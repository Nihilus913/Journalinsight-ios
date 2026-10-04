import Foundation
import JICore
import JIHealthKit
import JIPersistence

/// W-ONDEVICE O-10 (B-44 dual run): every on-device result is logged next to the hub's verdict for
/// the same morning in `DecisionLogStore` (`ondevice_shadow_log`). No hub (or no hub verdict for
/// the day yet) -> the hub column stays nil and the morning is not counted as a match.
nonisolated enum ShadowLogWriter {
    typealias Write = @Sendable (String, OnDeviceVerdictResult, Date) async -> Void

    static func make(hub: (any HealthDataProvider)?) -> Write? {
        guard let db = try? AppDatabase.onDisk() else { return nil }
        let store = DecisionLogStore(db: db)
        return { day, result, computedAt in
            let hubVerdict: String? = if let hub, let v = try? await hub.morningVerdict(date: day), v.date == day { v.verdict } else { nil }
            try? store.recordShadow(row(day: day, result: result, computedAt: computedAt, hubVerdict: hubVerdict))
        }
    }

    static func row(day: String, result: OnDeviceVerdictResult, computedAt: Date, hubVerdict: String?) -> ShadowVerdictRow {
        ShadowVerdictRow(
            day: day, onDeviceVerdict: result.verdict, hubVerdict: hubVerdict,
            inputsDigest: result.inputsDigest ?? "-", computedAt: computedAt.ISO8601Format(),
            latencyFromWakeSec: result.wakeAt.map { computedAt.timeIntervalSince($0) }
        )
    }
}
