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
        specs.append(contentsOf: dto.sleep.flatMap(mapSleep))
        specs.append(contentsOf: dto.rhr.compactMap(mapRHR))
        specs.append(contentsOf: mapSteps(dto.steps, stepBuckets: dto.stepBuckets))
        specs.append(contentsOf: dto.energy.flatMap(mapEnergy))
        specs.append(contentsOf: dto.vo2max.compactMap(mapVo2Max))
        specs.append(contentsOf: dto.workouts.compactMap(mapWorkout))
        specs.append(contentsOf: dto.heartRate.compactMap(mapHeartRate))
        specs.append(contentsOf: dto.respiration.compactMap(mapRespiration))
        specs.append(contentsOf: dto.spo2.compactMap(mapSpo2))
        specs.append(contentsOf: dto.hrv.flatMap(mapHrv))
        specs.append(contentsOf: dto.stepBuckets.compactMap(mapStepBucket))
        specs.append(contentsOf: dto.floors.compactMap(mapFloors))
        specs.append(contentsOf: dto.distance.compactMap(mapDistance))

        // daily_resp/daily_spo2 fallback: only for days with no dense samples of that kind, per
        // the frozen contract note — placed at the night's sleep midpoint.
        let midpoints = sleepMidpoints(dto.sleep)
        let denseRespDates = Set(dto.respiration.compactMap { dateOnly($0.ts) })
        let denseSpo2Dates = Set(dto.spo2.compactMap { dateOnly($0.ts) })
        specs.append(contentsOf: dto.dailyResp.compactMap { mapDailyResp($0, denseDates: denseRespDates, midpoints: midpoints) })
        specs.append(contentsOf: dto.dailySpo2.compactMap { mapDailySpo2($0, denseDates: denseSpo2Dates, midpoints: midpoints) })
        return specs
    }

    // MARK: - Sleep (v1 generic-asleep + v2 staged)

    static func mapSleep(_ e: BackloadSleepEntryDTO) -> [BackloadWriteSpec] {
        guard let start = BackloadDateParsing.timestamp(e.start), let end = BackloadDateParsing.timestamp(e.end) else { return [] }

        if e.stages.isEmpty {
            let asleepEnd = end.addingTimeInterval(-e.awakeSec)
            guard asleepEnd > start else { return [] }
            return [.sleep(BackloadSleepSampleSpec(syncId: e.syncId, inBedStart: start, inBedEnd: end, asleepStart: start, asleepEnd: asleepEnd, version: e.version))]
        }

        let stageSpecs: [BackloadSleepStageSampleSpec] = e.stages.enumerated().compactMap { index, stage in
            guard let stStart = BackloadDateParsing.timestamp(stage.start), let stEnd = BackloadDateParsing.timestamp(stage.end), stEnd > stStart else { return nil }
            return BackloadSleepStageSampleSpec(syncId: "\(e.syncId):st\(index)", stage: mapStageKind(stage.stage), start: stStart, end: stEnd)
        }
        guard !stageSpecs.isEmpty else { return [] }
        return [
            .delete(kind: .sleepCategory, syncId: "\(e.syncId):asleep"),
            .sleepStaged(BackloadSleepStagedSampleSpec(baseSyncId: e.syncId, inBedStart: start, inBedEnd: end, stages: stageSpecs, version: e.version)),
        ]
    }

    static func mapStageKind(_ kind: BackloadSleepStageKindDTO) -> BackloadSleepStageKind {
        switch kind {
        case .deep: return .deep
        case .light: return .light
        case .rem: return .rem
        case .awake: return .awake
        }
    }

    static func sleepMidpoints(_ entries: [BackloadSleepEntryDTO]) -> [String: Date] {
        var out: [String: Date] = [:]
        for e in entries {
            guard let start = BackloadDateParsing.timestamp(e.start), let end = BackloadDateParsing.timestamp(e.end) else { continue }
            guard let date = dateOnly(e.start) else { continue }
            out[date] = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        }
        return out
    }

    // MARK: - Simple daily kinds (unchanged since v1)

    static func mapRHR(_ e: BackloadRHREntryDTO) -> BackloadWriteSpec? {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .restingHeartRate, start: start, end: end, value: e.bpm, version: e.version))
    }

    /// v2: a date with 15-min step buckets gets the v1 daily `steps:<date>` sample deleted
    /// (buckets replace it, per the frozen contract) instead of written.
    static func mapSteps(_ entries: [BackloadStepsEntryDTO], stepBuckets: [BackloadStepBucketEntryDTO]) -> [BackloadWriteSpec] {
        let bucketDates = Set(stepBuckets.compactMap { dateOnly($0.start) })
        return entries.compactMap { e in
            if bucketDates.contains(e.date) {
                return .delete(kind: .stepQuantity, syncId: e.syncId)
            }
            guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return nil }
            return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .stepCount, start: start, end: end, value: e.count, version: e.version))
        }
    }

    /// One `energy` row yields two samples (active + basal) sharing the row's `sync_id` prefix,
    /// distinguished by an `:active`/`:basal` suffix so each has its own stable `HKMetadataKeySyncIdentifier`.
    static func mapEnergy(_ e: BackloadEnergyEntryDTO) -> [BackloadWriteSpec] {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return [] }
        return [
            .quantity(BackloadQuantitySampleSpec(syncId: "\(e.syncId):active", kind: .activeEnergyBurned, start: start, end: end, value: e.activeKcal, version: e.version)),
            .quantity(BackloadQuantitySampleSpec(syncId: "\(e.syncId):basal", kind: .basalEnergyBurned, start: start, end: end, value: e.basalKcal, version: e.version)),
        ]
    }

    static func mapVo2Max(_ e: BackloadVo2MaxEntryDTO) -> BackloadWriteSpec? {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .vo2Max, start: start, end: end, value: e.value, version: e.version))
    }

    // MARK: - W9 daily kinds (B-30 P5)

    static func mapFloors(_ e: BackloadFloorsEntryDTO) -> BackloadWriteSpec? {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .flightsClimbed, start: start, end: end, value: e.count, version: e.version))
    }

    /// `meters` is already net of that day's workout distance on the hub (`DistanceItem`); the
    /// workout's own distance sample is attached separately, so the two never double-count.
    static func mapDistance(_ e: BackloadDistanceEntryDTO) -> BackloadWriteSpec? {
        guard let (start, end) = BackloadDateParsing.dayBounds(e.date) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .distanceWalkingRunning, start: start, end: end, value: e.meters, version: e.version))
    }

    static func mapWorkout(_ e: BackloadWorkoutEntryDTO) -> BackloadWriteSpec? {
        guard let start = BackloadDateParsing.timestamp(e.start), let end = BackloadDateParsing.timestamp(e.end) else { return nil }
        let kind = BackloadWorkoutKind(rawValue: e.kind.rawValue) ?? .other
        return .workout(BackloadWorkoutSampleSpec(syncId: e.syncId, start: start, end: end, kind: kind, name: e.name, kcal: e.kcal, distanceM: e.distanceM, avgHr: e.avgHr, startEstimated: e.startEstimated ?? false, version: e.version))
    }

    // MARK: - v2 dense series (no sync_id on the wire — derived from `ts`)

    static func mapHeartRate(_ e: BackloadHeartRateEntryDTO) -> BackloadWriteSpec? {
        guard let ts = BackloadDateParsing.timestamp(e.ts) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: "hr:\(e.ts)", kind: .heartRate, start: ts, end: ts, value: e.bpm))
    }

    static func mapRespiration(_ e: BackloadRespirationEntryDTO) -> BackloadWriteSpec? {
        guard let ts = BackloadDateParsing.timestamp(e.ts) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: "resp:\(e.ts)", kind: .respiratoryRate, start: ts, end: ts, value: e.brpm))
    }

    static func mapSpo2(_ e: BackloadSpo2EntryDTO) -> BackloadWriteSpec? {
        guard let ts = BackloadDateParsing.timestamp(e.ts) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: "spo2:\(e.ts)", kind: .oxygenSaturation, start: ts, end: ts, value: e.pct / 100.0))
    }

    static func mapStepBucket(_ e: BackloadStepBucketEntryDTO) -> BackloadWriteSpec? {
        guard let start = BackloadDateParsing.timestamp(e.start), let end = BackloadDateParsing.timestamp(e.end) else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .stepCount, start: start, end: end, value: e.count))
    }

    /// HRV readings map 1:1 to samples when present; when `readings` is empty the entry falls
    /// back to a single nightly-average sample at that night's sleep midpoint (or day-start + 12h
    /// when there's no matching sleep entry — an approximation, not a claimed sleep time).
    /// v4: written under Apple's native `heartRateVariabilityRMSSD` type (no toggle) — see
    /// `BackloadQuantityKind.hrvRMSSD`. No hub `version` (the HRV item is not a versioned daily row).
    static func mapHrv(_ e: BackloadHrvEntryDTO) -> [BackloadWriteSpec] {
        if !e.readings.isEmpty {
            return e.readings.compactMap { reading in
                guard let ts = BackloadDateParsing.timestamp(reading.ts) else { return nil }
                return .quantity(BackloadQuantitySampleSpec(syncId: "\(e.syncId):\(reading.ts)", kind: .hrvRMSSD, start: ts, end: ts, value: reading.rmssdMs))
            }
        }
        guard let avg = e.nightlyRmssdMs, let (dayStart, _) = BackloadDateParsing.dayBounds(e.date) else { return [] }
        let at = dayStart.addingTimeInterval(12 * 3600)
        return [.quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .hrvRMSSD, start: at, end: at, value: avg))]
    }

    // MARK: - Daily fallback (only when no dense samples exist for that date)

    static func mapDailyResp(_ e: BackloadDailyRespEntryDTO, denseDates: Set<String>, midpoints: [String: Date]) -> BackloadWriteSpec? {
        guard !denseDates.contains(e.date) else { return nil }
        guard let value = e.sleepAvg ?? e.wakingAvg else { return nil }
        guard let at = midpoints[e.date] else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .respiratoryRate, start: at, end: at, value: value, version: e.version))
    }

    static func mapDailySpo2(_ e: BackloadDailySpo2EntryDTO, denseDates: Set<String>, midpoints: [String: Date]) -> BackloadWriteSpec? {
        guard !denseDates.contains(e.date) else { return nil }
        guard let value = e.sleepAvg else { return nil }
        guard let at = midpoints[e.date] else { return nil }
        return .quantity(BackloadQuantitySampleSpec(syncId: e.syncId, kind: .oxygenSaturation, start: at, end: at, value: value / 100.0, version: e.version))
    }

    // MARK: - Helpers

    /// The `YYYY-MM-DD` prefix of a full timestamp string, e.g. `"2026-06-01T22:31:00+02:00"` ->
    /// `"2026-06-01"` — used only to correlate dense-series timestamps with daily/sleep dates
    /// (all wire dates are already hub-local, per the contract note in `BackloadDateParsing`).
    static func dateOnly(_ ts: String) -> String? {
        guard ts.count >= 10 else { return nil }
        return String(ts.prefix(10))
    }
}
