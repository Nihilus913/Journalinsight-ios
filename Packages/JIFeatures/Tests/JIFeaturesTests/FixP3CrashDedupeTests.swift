import Foundation
import Testing
@testable import JIFeatures

// W-FIX-P3 RG-75 (B-18): the same crash must land once in "Last crash" — an identical record
// written twice, or an NSException the handler stored and MetricKit re-delivers ~24 h later.
// Swift traps only arrive via MetricKit, so the section says so (pending note).

private let p3Info = VersionInfo(appName: "JournalInsight", appVersion: "2.2.1", build: "2610060900", bundleId: "toby913.JournalInsight")

private func p3Store() -> CrashLogStore {
    CrashLogStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("crashdedupe-tests-\(UUID().uuidString)", isDirectory: true))
}

@Suite struct FixP3CrashDedupeTests {
    @Test func sameCrashTwiceIsOneEntry() throws {
        let store = p3Store()
        let t = Date(timeIntervalSince1970: 1_000_000)
        let a = CrashMapping.record(exceptionName: "NSRangeException", reason: "index 3 beyond bounds", callStack: ["f"], info: p3Info, date: t)
        let b = CrashMapping.record(exceptionName: "NSRangeException", reason: "index 3 beyond bounds", callStack: ["f"], info: p3Info, date: t)
        try store.write(a)
        try store.write(b)
        #expect(store.list().count == 1)
    }

    @Test func metricKitRedeliveryOfStoredExceptionIsOneEntry() throws {
        let store = p3Store()
        let crashAt = Date(timeIntervalSince1970: 2_000_000)
        try store.write(CrashMapping.record(exceptionName: "NSInvalidArgumentException", reason: "bad", callStack: [], info: p3Info, date: crashAt))
        let snap = CrashDiagnosticSnapshot(date: crashAt.addingTimeInterval(20 * 3600), appVersion: "2.2.1", build: "2610060900",
                                           signal: 6, exceptionType: 10, objcExceptionName: "NSInvalidArgumentException", objcExceptionMessage: "bad")
        CrashReporter.ingest([snap], store: store, info: p3Info)
        CrashReporter.ingest([snap], store: store, info: p3Info)   // MetricKit can redeliver a payload
        #expect(store.list().count == 1)
        #expect(store.latest?.source == .exception)
    }

    @Test func differentCrashesStillBothKept() throws {
        let store = p3Store()
        let t = Date(timeIntervalSince1970: 3_000_000)
        try store.write(CrashMapping.record(exceptionName: "NSRangeException", reason: "x", callStack: [], info: p3Info, date: t))
        // A Swift trap (no ObjC name) the next day is a different crash.
        CrashReporter.ingest([CrashDiagnosticSnapshot(date: t.addingTimeInterval(3600), build: "2610060900", signal: 5, exceptionType: 6)],
                             store: store, info: p3Info)
        // The same exception type in an older build than a MetricKit window allows is also kept.
        CrashReporter.ingest([CrashDiagnosticSnapshot(date: t.addingTimeInterval(4 * 86_400), build: "2610060900", objcExceptionName: "NSRangeException")],
                             store: store, info: p3Info)
        #expect(store.list().count == 3)
    }

    @Test func lastCrashSaysSwiftTrapsArriveLater() {
        let note = VersionViewModel.crashPendingNote
        #expect(note.contains("Swift"))
        #expect(note.contains("24 h"))
    }
}
