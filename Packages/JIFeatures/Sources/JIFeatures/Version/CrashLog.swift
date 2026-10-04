import Foundation
#if canImport(MetricKit) && !os(watchOS)
import MetricKit
#endif

// B-18 p1 (P-version, BACKLOG row 24). On-device crash log for the Version screen's "Last crash"
// section (UI lands in p2). Two sources:
//   1. `NSSetUncaughtExceptionHandler` — an uncaught NSException is written SYNCHRONOUSLY to disk
//      from the handler (the process is about to die), then any previously installed handler runs.
//   2. MetricKit `MXCrashDiagnostic` — delivered on a later launch (~24 h lag); mapped through the
//      `CrashDiagnosticSnapshot` seam so the mapping is unit-testable without real payloads
//      (the simulator never produces them).
// Storage: small JSON files, newest 5 kept, in Application Support/CrashLogs. Local only — never
// uploaded to the hub (Toby 2026-10-04, binding). Everything here is `nonisolated`: the exception
// handler and the MetricKit subscriber callback run off the main actor.

/// One recorded crash. `type` is the NSException name or a signal/Mach exception name
/// (e.g. `SIGSEGV`, `EXC_BAD_ACCESS`); `summary` is the reason / termination reason.
public nonisolated struct CrashRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Source: String, Codable, Sendable { case exception, metricKit }

    public let id: String
    public let date: Date
    public let source: Source
    public let appVersion: String
    public let build: String
    public let type: String
    public let summary: String
    /// Top of the call stack (symbolicated frames for an NSException; empty for MetricKit,
    /// whose call-stack tree is unsymbolicated JSON and adds nothing on-device).
    public let callStack: [String]

    public static let maxCallStackFrames = 30
    public static let maxSummaryLength = 500

    public init(id: String = UUID().uuidString, date: Date, source: Source, appVersion: String, build: String,
                type: String, summary: String, callStack: [String] = []) {
        self.id = id; self.date = date; self.source = source
        self.appVersion = appVersion; self.build = build; self.type = type
        self.summary = String(summary.prefix(Self.maxSummaryLength))
        self.callStack = Array(callStack.prefix(Self.maxCallStackFrames))
    }

    /// Plain-text report for Copy / Share (p2).
    public var reportText: String {
        var lines = [
            "JournalInsight crash report",
            "Date: \(ISO8601DateFormatter().string(from: date))",
            "Version: \(appVersion) (\(build))",
            "Source: \(source == .exception ? "Uncaught exception" : "MetricKit")",
            "Type: \(type)",
            "Summary: \(summary)",
        ]
        if !callStack.isEmpty { lines.append("Call stack:"); lines += callStack }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Store

/// Newest-first, capped file store. Each record is one atomically written JSON file, so a crash
/// mid-write can never corrupt an earlier record; unreadable files are skipped, not fatal.
public nonisolated struct CrashLogStore: Sendable {
    public static let cap = 5
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// `Application Support/CrashLogs` (created on first write).
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CrashLogs", isDirectory: true)
    }

    public static var `default`: CrashLogStore { CrashLogStore(directory: defaultDirectory()) }

    /// Writes `record`, then prunes to the newest `cap`. Synchronous by design (crash handler).
    public func write(_ record: CrashRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(record)
        let ms = Int64((record.date.timeIntervalSince1970 * 1000).rounded())
        let name = String(format: "%013lld-%@.json", ms, record.id)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        try prune()
    }

    /// All readable records, newest first (by `date`, ties by id for a stable order).
    public func list() -> [CrashRecord] {
        entries().map(\.record)
    }

    public var latest: CrashRecord? { list().first }

    /// Removes every stored record (the directory itself stays).
    public func clear() throws {
        for url in files() { try FileManager.default.removeItem(at: url) }
    }

    private func files() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
    }

    private func entries() -> [(url: URL, record: CrashRecord)] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return files().compactMap { url in
            guard let data = try? Data(contentsOf: url), let rec = try? decoder.decode(CrashRecord.self, from: data) else { return nil }
            return (url, rec)
        }.sorted { a, b in a.record.date != b.record.date ? a.record.date > b.record.date : a.record.id > b.record.id }
    }

    private func prune() throws {
        for old in entries().dropFirst(Self.cap) { try FileManager.default.removeItem(at: old.url) }
    }
}

// MARK: - NSException mapping

public nonisolated enum CrashMapping {
    /// Record for an uncaught NSException (fields passed separately so tests need no real throw).
    public static func record(exceptionName: String, reason: String?, callStack: [String], info: VersionInfo, date: Date = Date()) -> CrashRecord {
        CrashRecord(date: date, source: .exception, appVersion: info.appVersion, build: info.build,
                    type: exceptionName, summary: reason?.isEmpty == false ? reason! : "No reason given", callStack: callStack)
    }

    public static func record(_ exception: NSException, info: VersionInfo, date: Date = Date()) -> CrashRecord {
        record(exceptionName: exception.name.rawValue, reason: exception.reason, callStack: exception.callStackSymbols, info: info, date: date)
    }

    /// Record for a MetricKit crash diagnostic (via the seam). Build/version come from the payload
    /// (the crashed build), falling back to the running app's identity.
    public static func record(_ d: CrashDiagnosticSnapshot, fallback info: VersionInfo) -> CrashRecord {
        let type: String
        if let name = d.objcExceptionName, !name.isEmpty { type = name }
        else if let sig = d.signal { type = signalName(sig) }
        else if let exc = d.exceptionType { type = machExceptionName(exc) }
        else { type = "Crash" }

        var parts: [String] = []
        if let msg = d.objcExceptionMessage, !msg.isEmpty { parts.append(msg) }
        if let sig = d.signal, type != signalName(sig) { parts.append(signalName(sig)) }
        if let exc = d.exceptionType { parts.append(machExceptionName(exc) + (d.exceptionCode.map { " (code \($0))" } ?? "")) }
        if let term = d.terminationReason, !term.isEmpty { parts.append(term) }
        let summary = parts.isEmpty ? "No details in diagnostic" : parts.joined(separator: " · ")

        return CrashRecord(date: d.date, source: .metricKit,
                           appVersion: d.appVersion?.isEmpty == false ? d.appVersion! : info.appVersion,
                           build: d.build?.isEmpty == false ? d.build! : info.build,
                           type: type, summary: summary)
    }

    public static func signalName(_ sig: Int) -> String {
        switch sig {
        case 4: "SIGILL"; case 5: "SIGTRAP"; case 6: "SIGABRT"; case 8: "SIGFPE"; case 9: "SIGKILL"
        case 10: "SIGBUS"; case 11: "SIGSEGV"; case 13: "SIGPIPE"; case 15: "SIGTERM"
        default: "Signal \(sig)"
        }
    }

    public static func machExceptionName(_ exc: Int) -> String {
        switch exc {
        case 1: "EXC_BAD_ACCESS"; case 2: "EXC_BAD_INSTRUCTION"; case 3: "EXC_ARITHMETIC"
        case 6: "EXC_BREAKPOINT"; case 10: "EXC_CRASH"; case 11: "EXC_RESOURCE"; case 12: "EXC_GUARD"
        default: "Exception \(exc)"
        }
    }
}

/// Protocol seam over `MXCrashDiagnostic` + its payload's `timeStampEnd`: the simulator cannot
/// produce MetricKit payloads, so tests build a snapshot directly.
public nonisolated struct CrashDiagnosticSnapshot: Sendable, Equatable {
    public var date: Date
    public var appVersion: String?
    public var build: String?
    public var signal: Int?
    public var exceptionType: Int?
    public var exceptionCode: Int?
    public var terminationReason: String?
    public var objcExceptionName: String?
    public var objcExceptionMessage: String?

    public init(date: Date, appVersion: String? = nil, build: String? = nil, signal: Int? = nil, exceptionType: Int? = nil,
                exceptionCode: Int? = nil, terminationReason: String? = nil, objcExceptionName: String? = nil, objcExceptionMessage: String? = nil) {
        self.date = date; self.appVersion = appVersion; self.build = build; self.signal = signal
        self.exceptionType = exceptionType; self.exceptionCode = exceptionCode; self.terminationReason = terminationReason
        self.objcExceptionName = objcExceptionName; self.objcExceptionMessage = objcExceptionMessage
    }
}

#if canImport(MetricKit) && !os(watchOS)
extension CrashDiagnosticSnapshot {
    public nonisolated init(_ d: MXCrashDiagnostic, payloadEnd: Date) {
        self.init(date: payloadEnd, appVersion: d.applicationVersion, build: d.metaData.applicationBuildVersion,
                  signal: d.signal?.intValue, exceptionType: d.exceptionType?.intValue, exceptionCode: d.exceptionCode?.intValue,
                  terminationReason: d.terminationReason,
                  objcExceptionName: d.exceptionReason?.exceptionName, objcExceptionMessage: d.exceptionReason?.composedMessage)
    }
}
#endif

// MARK: - Installer

/// Installs both capture paths once at launch (`AppDelegate.didFinishLaunching`).
public nonisolated enum CrashReporter {
    // unsafe: written once in `install()` on the main thread at launch before any handler can fire;
    // afterwards only read (from the crashing thread). A C handler cannot capture context.
    nonisolated(unsafe) private static var store: CrashLogStore?
    nonisolated(unsafe) private static var info: VersionInfo?
    nonisolated(unsafe) private static var previousHandler: (@convention(c) (NSException) -> Void)?
    nonisolated(unsafe) private static var installed = false
    #if canImport(MetricKit) && !os(watchOS)
    nonisolated(unsafe) private static var subscriber: MetricKitCrashSubscriber?
    #endif

    public static func install(store: CrashLogStore = .default, info: VersionInfo = VersionInfo()) {
        guard !installed else { return }
        installed = true
        Self.store = store
        Self.info = info
        previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.handle(exception)
        }
        #if canImport(MetricKit) && !os(watchOS)
        let sub = MetricKitCrashSubscriber(store: store, info: info)
        subscriber = sub
        MXMetricManager.shared.add(sub)
        #endif
    }

    /// The uncaught-exception path: synchronous write, then chain to the previous handler.
    static func handle(_ exception: NSException) {
        if let store, let info { try? store.write(CrashMapping.record(exception, info: info)) }
        previousHandler?(exception)
    }

    /// MetricKit path, factored out for tests: records every crash diagnostic of a delivery.
    public static func ingest(_ snapshots: [CrashDiagnosticSnapshot], store: CrashLogStore, info: VersionInfo) {
        for s in snapshots { try? store.write(CrashMapping.record(s, fallback: info)) }
    }
}

#if canImport(MetricKit) && !os(watchOS)
// @unchecked: immutable after init (`let` Sendable fields only); NSObject subclassing blocks the
// compiler from proving it. MetricKit calls `didReceive` on an arbitrary queue.
nonisolated final class MetricKitCrashSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    let store: CrashLogStore
    let info: VersionInfo
    init(store: CrashLogStore, info: VersionInfo) { self.store = store; self.info = info }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let snapshots = payloads.flatMap { p in
            (p.crashDiagnostics ?? []).map { CrashDiagnosticSnapshot($0, payloadEnd: p.timeStampEnd) }
        }
        CrashReporter.ingest(snapshots, store: store, info: info)
    }
}
#endif
