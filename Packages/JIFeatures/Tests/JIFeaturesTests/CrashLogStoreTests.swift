import Foundation
import Testing
@testable import JIFeatures

// B-18 p1: CrashLogStore (write/list order, cap 5, clear, Codable round-trip) + the two capture
// mappings (simulated NSException; MXCrashDiagnostic via the `CrashDiagnosticSnapshot` seam).

private let info = VersionInfo(appName: "JournalInsight", appVersion: "2.3", build: "41", bundleId: "toby913.JournalInsight")

private func tempStore() -> CrashLogStore {
    CrashLogStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("crashlog-tests-\(UUID().uuidString)", isDirectory: true))
}

private func rec(_ t: TimeInterval, type: String = "T") -> CrashRecord {
    CrashRecord(date: Date(timeIntervalSince1970: t), source: .exception, appVersion: "1", build: "1", type: type, summary: "s")
}

@Suite struct CrashLogStoreTests {
    @Test func emptyStoreListsNothing() {
        let store = tempStore()
        #expect(store.list().isEmpty)
        #expect(store.latest == nil)
        #expect(throws: Never.self) { try store.clear() }   // clearing a never-created dir is a no-op
    }

    @Test func listIsNewestFirstRegardlessOfWriteOrder() throws {
        let store = tempStore()
        try store.write(rec(2_000, type: "b"))
        try store.write(rec(1_000, type: "a"))
        try store.write(rec(3_000, type: "c"))
        #expect(store.list().map(\.type) == ["c", "b", "a"])
        #expect(store.latest?.type == "c")
    }

    @Test func capKeepsNewestFive() throws {
        let store = tempStore()
        for i in 1...7 { try store.write(rec(TimeInterval(i * 100), type: "r\(i)")) }
        let list = store.list()
        #expect(list.count == CrashLogStore.cap)
        #expect(list.map(\.type) == ["r7", "r6", "r5", "r4", "r3"])
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.count == 5)
    }

    @Test func clearRemovesEverything() throws {
        let store = tempStore()
        try store.write(rec(1)); try store.write(rec(2))
        try store.clear()
        #expect(store.list().isEmpty)
        try store.write(rec(3))   // still writable after clear
        #expect(store.list().count == 1)
    }

    @Test func unreadableFileIsSkipped() throws {
        let store = tempStore()
        try store.write(rec(5))
        try Data("not json".utf8).write(to: store.directory.appendingPathComponent("0000000000000-bad.json"))
        #expect(store.list().count == 1)
    }

    @Test func codableRoundTripIsLossless() throws {
        let r = CrashRecord(id: "abc", date: Date(timeIntervalSince1970: 1_790_000_000.123), source: .metricKit,
                            appVersion: "2.3", build: "41", type: "SIGSEGV", summary: "EXC_BAD_ACCESS", callStack: ["0 a", "1 b"])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .millisecondsSince1970
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .millisecondsSince1970
        #expect(try dec.decode(CrashRecord.self, from: enc.encode(r)) == r)
        let store = tempStore()
        try store.write(r)
        #expect(store.list() == [r])
    }

    @Test func recordTruncatesStackAndSummary() {
        let r = CrashRecord(date: .now, source: .exception, appVersion: "1", build: "1", type: "t",
                            summary: String(repeating: "x", count: 2_000), callStack: (0..<100).map { "\($0)" })
        #expect(r.callStack.count == CrashRecord.maxCallStackFrames)
        #expect(r.summary.count == CrashRecord.maxSummaryLength)
    }

    @Test func simulatedNSExceptionMapsToRecord() throws {
        let ex = NSException(name: .invalidArgumentException, reason: "forced debug crash", userInfo: nil)
        let date = Date(timeIntervalSince1970: 1_000)
        let r = CrashMapping.record(ex, info: info, date: date)
        #expect(r.source == .exception)
        #expect(r.type == "NSInvalidArgumentException")
        #expect(r.summary == "forced debug crash")
        #expect(r.appVersion == "2.3" && r.build == "41")
        #expect(r.date == date)
        #expect(r.reportText.contains("Type: NSInvalidArgumentException"))
        #expect(r.reportText.contains("Version: 2.3 (41)"))

        let withStack = CrashMapping.record(exceptionName: "X", reason: nil, callStack: ["0 JournalInsight main"], info: info)
        #expect(withStack.summary == "No reason given")
        #expect(withStack.reportText.contains("Call stack:\n0 JournalInsight main"))
    }

    @Test func metricKitSignalDiagnosticMaps() {
        let d = CrashDiagnosticSnapshot(date: Date(timeIntervalSince1970: 5_000), appVersion: "2.2", build: "39",
                                        signal: 11, exceptionType: 1, exceptionCode: 0,
                                        terminationReason: "Namespace SIGNAL, Code 11")
        let r = CrashMapping.record(d, fallback: info)
        #expect(r.source == .metricKit)
        #expect(r.type == "SIGSEGV")
        #expect(r.summary == "EXC_BAD_ACCESS (code 0) · Namespace SIGNAL, Code 11")
        #expect(r.appVersion == "2.2" && r.build == "39")   // crashed build, not the running one
        #expect(r.callStack.isEmpty)
    }

    @Test func metricKitObjCExceptionAndFallbacksMap() {
        let objc = CrashDiagnosticSnapshot(date: .now, signal: 6, objcExceptionName: "NSRangeException",
                                           objcExceptionMessage: "index 3 beyond bounds")
        let r = CrashMapping.record(objc, fallback: info)
        #expect(r.type == "NSRangeException")
        #expect(r.summary == "index 3 beyond bounds · SIGABRT")
        #expect(r.appVersion == "2.3" && r.build == "41")   // payload lacked identity → running app

        let bare = CrashMapping.record(CrashDiagnosticSnapshot(date: .now), fallback: info)
        #expect(bare.type == "Crash" && bare.summary == "No details in diagnostic")
        #expect(CrashMapping.signalName(99) == "Signal 99")
        #expect(CrashMapping.machExceptionName(10) == "EXC_CRASH")
    }

    @Test func ingestWritesEveryDiagnosticCapped() {
        let store = tempStore()
        let snaps = (1...6).map { CrashDiagnosticSnapshot(date: Date(timeIntervalSince1970: TimeInterval($0)), signal: 11) }
        CrashReporter.ingest(snaps, store: store, info: info)
        #expect(store.list().count == 5)
        #expect(store.latest?.date == Date(timeIntervalSince1970: 6))
    }
}
