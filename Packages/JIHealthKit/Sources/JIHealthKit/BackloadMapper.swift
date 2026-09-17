import Foundation
import JIHub

/// Pure DTO → HK sample-spec mapping (HK-free — no `import HealthKit` in this file or its
/// dependency `BackloadSampleSpec.swift` — so it runs under plain `swift test` on any host).
/// Entries with unparseable dates are dropped rather than thrown: the hub is the source of truth
/// for shape (pydantic-validated), so a bad date here would be a hub bug, not a caller error, and
/// one bad row should not sink the whole month's write.
public enum BackloadMapper {
    public static func map(_ dto: BackloadResponseDTO) -> [BackloadWriteSpec] {
        var specs: [BackloadWriteSpec] = []
        specs.append(contentsOf: dto.sleep.compactMap(mapSleep))
        specs.append(contentsOf: dto.rhr.compactMap(mapRHR))
        specs.append(contentsOf: dto.steps.compactMap(mapSteps))
        specs.append(contentsOf: dto.energy.flatMap(mapEnergy))
        specs.append(contentsOf: dto.vo2max.compactMap(mapVo2Max))
        specs.append(contentsOf: dto.workouts.compactMap(mapWorkout))
        return specs
    }

    static func mapSleep(_ e: BackloadSleepEntryDTO) -> BackloadWriteSpec? {
        guard let start = BackloadDateParsing.timestamp(e.start), let end = BackloadDateParsing.timestamp(e.end) else { return nil }
        let asleepEnd = end.addingTimeInterval(-e.awakeSec)
        guard asleepEnd > start else { return nil }
        return .sleep(BackloadSleepSampleSpec(syncId: e.syncId, inBedStart: start, inBedEnd: end, asleepStart: start, asleepEnd: asleepEnd))
    }

    static func mapRHR(_ e: BackloadRHREntryDTO) -> BackloadWriteSpec? {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .restingHeartRate, start: start, end: end, value: e.bpm))
    }

    static func mapSteps(_ e: BackloadStepsEntryDTO) -> BackloadWriteSpec? {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .stepCount, start: start, end: end, value: e.count))
    }

    /// One `energy` row yields two samples (active + basal) sharing the row's `sync_id` prefix,
    /// distinguished by an `:active`/`:basal` suffix so each has its own stable `HKMetadataKeySyncIdentifier`.
    static func mapEnergy(_ e: BackloadEnergyEntryDTO) -> [BackloadWriteSpec] {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return [] }
        return [
            .quantity(BackloadQuantitySampleSpec(syncId: "\(e.syncId):active", kind: .activeEnergyBurned, start: start, end: end, value: e.activeKcal)),
            .quantity(BackloadQuantitySampleSpec(syncId: "\(e.syncId):basal", kind: .basalEnergyBurned, start: start, end: end, value: e.basalKcal)),
        ]
    }

    static func mapVo2Max(_ e: BackloadVo2MaxEntryDTO) -> BackloadWriteSpec? {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .vo2Max, start: start, end: end, value: e.value))
    }

    static func mapWorkout(_ e: BackloadWorkoutEntryDTO) -> BackloadWriteSpec? {
        guard let start = BackloadDateParsing.timestamp(e.start), let end = BackloadDateParsing.timestamp(e.end) else { return nil }
        let kind = BackloadWorkoutKind(rawValue: e.kind.rawValue) ?? .other
        return .workout(BackloadWorkoutSampleSpec(syncId: e.syncId, start: start, end: end, kind: kind, name: e.name, kcal: e.kcal, distanceM: e.distanceM, avgHr: e.avgHr))
    }
}
