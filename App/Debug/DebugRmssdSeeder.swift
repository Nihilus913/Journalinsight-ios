#if DEBUG
import Foundation
import HealthKit
import JIHealthKit

/// W-FIX3 fixer C-h (live record, /wave rule 8): `-JISeedRMSSD <ms>` on a DEBUG launch writes ONE
/// native-RMSSD sample, dated to last night (03:00 local, today's wake-up night), into this
/// device's HealthKit — the simulator has no Watch to produce one. It asks share access for that
/// one type only; the sample carries `JIDebugSeed` metadata so it is never mistaken for a reading.
/// Never compiled into Release.
enum DebugRmssdSeeder {
    static let flag = "-JISeedRMSSD"

    /// The requested value in ms, or nil (no flag, missing/unparseable value, or ≤ 0 — never a
    /// 0 ms reading).
    static func requestedValue(_ arguments: [String] = CommandLine.arguments) -> Double? {
        guard let i = arguments.firstIndex(of: flag), arguments.index(after: i) < arguments.endIndex,
              let v = Double(arguments[arguments.index(after: i)]), v > 0 else { return nil }
        return v
    }

    /// 03:00 local today — before `HKRecoveryAssembler.nightStartHour`, so the assembler dates it
    /// to today's night.
    static func sampleDate(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(bySettingHour: 3, minute: 0, second: 0, of: now) ?? now
    }

    static func seedIfRequested() async {
        guard let ms = requestedValue(), HKHealthStore.isHealthDataAvailable(),
              let type = HKReadKind.hrvRMSSD.sampleType as? HKQuantityType else { return }
        let store = HKHealthStore()
        do {
            try await store.requestAuthorization(toShare: [type], read: [type])
            let at = sampleDate()
            let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: ms),
                                          start: at, end: at, metadata: ["JIDebugSeed": true])
            try await store.save(sample)
            print("[JIDebugSeed] RMSSD \(ms) ms saved at \(at)")
        } catch {
            print("[JIDebugSeed] RMSSD seed failed: \(error)")
        }
    }
}
#endif
