import SwiftUI
import JICore
import JIDesign

// MARK: - W-B81 A-5: completed workouts from the hub (Apple dso 4 + Garmin)
//
// A *completed* workout (`core.activity` via `/training/day/{date}`) — a separate type from B-40's
// `WorkoutTemplate` (a plan for a workout). The hub is the one source of truth: the phone-local
// Health rows (W-FIX7) only bridge the minutes before the uploader delivered the workout.

/// What a completed-workout row says. Missing values are omitted, never shown as zero (rule 5).
public nonisolated struct CompletedWorkoutText: Equatable, Sendable {
    public var title: String
    /// "Apple Health" / "Garmin"; nil when the hub did not say (an older hub).
    public var sourceLabel: String?
    public var systemImage: String
    /// Duration, distance, average heart rate — in that order, only the ones present.
    public var metrics: [String]
    /// iOS 27 time-in-zone ("Z1 4 min"), zones with time only; empty when the hub has none.
    public var zones: [String]
    public var accessibilityLabel: String
}

public nonisolated func completedWorkoutRowText(_ a: DayActivity) -> CompletedWorkoutText {
    let title = a.name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? workoutTypeTitle(a.type)
    let source: String? = switch a.source { case "apple": "Apple Health"; case "garmin": "Garmin"; default: nil }
    var metrics: [String] = [], spoken: [String] = [title]
    if let source { spoken.append(source) }
    if let seconds = a.durationSec, seconds.isFinite, seconds >= 60 {
        let minutes = Int(seconds / 60)
        metrics.append(minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min" : "\(minutes) min")
        spoken.append(minutes >= 60 ? "\(minutes / 60) hours \(minutes % 60) minutes" : "\(minutes) minutes")
    }
    if let metres = a.distanceM, metres.isFinite, metres > 0 {
        let km = jiNumber(metres / 1000, 2)
        metrics.append("\(km) km"); spoken.append("\(km) kilometres")
    }
    if let hr = a.avgHr, hr > 0 {
        metrics.append("avg \(hr) bpm"); spoken.append("average heart rate \(hr) beats per minute")
    }
    let zones = (a.zoneTime ?? []).sorted { $0.zone < $1.zone }.compactMap { z -> String? in
        guard z.seconds.isFinite, z.seconds >= 60 else { return nil }
        return "Z\(z.zone) \(Int(z.seconds / 60)) min"
    }
    if !zones.isEmpty { spoken.append("time in zone " + zones.joined(separator: ", ")) }
    return CompletedWorkoutText(title: title, sourceLabel: source, systemImage: workoutTypeSymbol(a.type),
                                metrics: metrics, zones: zones, accessibilityLabel: spoken.joined(separator: ", "))
}

/// "traditional_strength_training" → "Traditional strength training".
nonisolated func workoutTypeTitle(_ type: String) -> String { TodayWorkout.title(ofHubType: type) }

nonisolated func workoutTypeSymbol(_ type: String) -> String {
    let t = type.lowercased()
    if t.contains("strength") || t.contains("functional") { return "dumbbell" }
    if t.contains("run") { return "figure.run" }
    if t.contains("cycl") || t.contains("bik") { return "figure.outdoor.cycle" }
    if t.contains("walk") { return "figure.walk" }
    if t.contains("hik") { return "figure.hiking" }
    if t.contains("swim") { return "figure.pool.swim" }
    if t.contains("row") { return "figure.rower" }
    if t.contains("yoga") { return "figure.yoga" }
    return "figure.mixed.cardio"
}

/// One source of truth: a phone-local Health workout is listed only until the hub holds it — an
/// Apple row (dso 4) starting within ± 5 min (the hub's own overlap window). Garmin rows never hide
/// a Health workout; the hub's overlap rule already decides between those two.
public nonisolated func healthWorkoutsNotOnHub(_ local: [TodayWorkout], hub: [DayActivity]) -> [TodayWorkout] {
    let hubStarts = hub.filter(\.isAppleHealth).compactMap(\.startDate)
    return local.filter { w in !hubStarts.contains(where: w.isSameWorkout(startingAt:)) }
}

// MARK: - W-FIX9 C-4: time in zone as a bar, labelled with the Watch's own bounds (audit F8)

/// One segment of the time-in-zone bar.
public nonisolated struct WorkoutZoneSegment: Equatable, Sendable, Identifiable {
    public let zone: Int
    /// Share of the workout's zoned time, 0…1.
    public let fraction: Double
    /// "Z2 118–135 · 12 min" — the bounds the Watch binned with (it recorded them), not the
    /// user's zones; "<118" / "170+" for the open ends; no bounds when the hub sent none.
    public let label: String
    public var id: Int { zone }
}

/// The zones with time, Z1 → Z5; empty when the hub has none (rule 5: no empty bar).
public nonisolated func workoutZoneBar(_ zones: [WorkoutZoneTime]?) -> [WorkoutZoneSegment] {
    let timed = (zones ?? []).filter { $0.seconds.isFinite && $0.seconds > 0 }.sorted { $0.zone < $1.zone }
    let total = timed.reduce(0) { $0 + $1.seconds }
    guard total > 0 else { return [] }
    return timed.map { z in
        let bounds: String? = switch (z.lowerBpm, z.upperBpm) {
        case let (lo?, hi?): "\(lo)–\(hi)"
        case let (lo?, nil): "\(lo)+"
        case let (nil, hi?): "<\(hi)"
        case (nil, nil): nil
        }
        let minutes = z.seconds < 60 ? "<1 min" : "\(Int(z.seconds / 60)) min"
        let label = [["Z\(z.zone)", bounds].compactMap { $0 }.joined(separator: " "), minutes].joined(separator: " · ")
        return WorkoutZoneSegment(zone: z.zone, fraction: z.seconds / total, label: label)
    }
}

/// Audit F8: the Watch's zone bounds are more than 3 bpm off the user's own zones (Settings ›
/// HR zones) — the row then says so instead of implying they are the same zones.
public nonisolated func workoutZonesDiffer(_ zones: [WorkoutZoneTime]?, from mine: HrZones?) -> Bool {
    guard let mine, mine.isValid else { return false }
    return (zones ?? []).contains { z in
        guard (1...5).contains(z.zone) else { return false }
        let lo = mine.floorsBpm[z.zone - 1]
        let hi: Int? = z.zone < 5 ? mine.floorsBpm[z.zone] : nil
        if let l = z.lowerBpm, abs(l - lo) > 3 { return true }
        if let u = z.upperBpm, let hi, abs(u - hi) > 3 { return true }
        return false
    }
}

/// Zone tints Z1 → Z5 — calm to hot, metric colours only (never the verdict's go/amber/red, rule 6;
/// never `info`, which is the accent).
nonisolated func workoutZoneRole(_ zone: Int) -> JIColorRole {
    switch zone {
    case 1: .muted
    case 2: .hrv
    case 3: .carbs
    case 4: .kcal
    default: .rhr
    }
}

/// The bar and its labels (one per line at accessibility sizes).
public struct WorkoutZoneBarView: View {
    let segments: [WorkoutZoneSegment]
    let differs: Bool
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(zones: [WorkoutZoneTime]?, userZones: HrZones? = nil) {
        self.segments = workoutZoneBar(zones); self.differs = workoutZonesDiffer(zones, from: userZones)
    }

    public var body: some View {
        if !segments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time in zone").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(segments) { s in
                            Capsule().fill(theme.color(workoutZoneRole(s.zone)))
                                .frame(width: max(4, s.fraction * (g.size.width - CGFloat(segments.count - 1) * 2)))
                        }
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                if typeSize.isAccessibilitySize {
                    ForEach(segments) { s in Text(s.label).jiFont(.caption).foregroundStyle(theme.color(.muted)) }
                } else {
                    Text(segments.map(\.label).joined(separator: " · ")).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if differs {
                    Text("Watch zones — differ from yours").jiFont(.micro, weight: .semibold)
                        .foregroundStyle(theme.color(.muted))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().strokeBorder(theme.color(.hairlineNested)))
                        .accessibilityIdentifier("completed-workout-zones-differ")
                }
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("completed-workout-zones")
        }
    }
}

/// At accessibility sizes the metrics go one per line (no truncated "6.02 k…").
public nonisolated func completedWorkoutMetricsStacked(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

/// A completed workout: symbol well, title + source, then duration · distance · avg HR, then the
/// time-in-zone line when the hub has it. Reads only.
public struct CompletedWorkoutRow: View {
    let text: CompletedWorkoutText
    let zoneTime: [WorkoutZoneTime]?
    let userZones: HrZones?
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(activity: DayActivity, userZones: HrZones? = nil) {
        self.text = completedWorkoutRowText(activity); self.zoneTime = activity.zoneTime; self.userZones = userZones
    }

    public var body: some View {
        let stacked = completedWorkoutMetricsStacked(typeSize)
        HStack(alignment: .top, spacing: JISpacing.s3) {
            if !stacked {
                Image(systemName: text.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.color(.info))
                    .frame(width: JIRowMetrics.iconWell, height: JIRowMetrics.iconWell)
                    .background(theme.color(.info).opacity(0.16), in: RoundedRectangle(cornerRadius: JIRowMetrics.iconWellRadius, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).jiFont(.body).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                if let source = text.sourceLabel {
                    Text(source).jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                if !text.metrics.isEmpty {
                    if stacked {
                        ForEach(text.metrics, id: \.self) { m in
                            Text(m).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
                        }
                    } else {
                        Text(text.metrics.joined(separator: " · ")).jiFont(.subheadline, weight: .semibold)
                            .foregroundStyle(theme.color(.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // W-FIX9 C-4: the zone bar with the Watch's bounds (the spoken label keeps text.zones).
                WorkoutZoneBarView(zones: zoneTime, userZones: userZones)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, JIRowMetrics.verticalPadding)
        .frame(minHeight: JIRowMetrics.minHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
        .accessibilityIdentifier("completed-workout-row")
    }
}
