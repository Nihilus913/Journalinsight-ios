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
nonisolated func workoutTypeTitle(_ type: String) -> String {
    let words = type.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    guard let first = words.first else { return "Workout" }
    return first.uppercased() + words.dropFirst()
}

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
    return local.filter { w in !hubStarts.contains { abs($0.timeIntervalSince(w.start)) <= 5 * 60 } }
}

/// At accessibility sizes the metrics go one per line (no truncated "6.02 k…").
public nonisolated func completedWorkoutMetricsStacked(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

/// A completed workout: symbol well, title + source, then duration · distance · avg HR, then the
/// time-in-zone line when the hub has it. Reads only.
public struct CompletedWorkoutRow: View {
    let text: CompletedWorkoutText
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(activity: DayActivity) { self.text = completedWorkoutRowText(activity) }

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
                if !text.zones.isEmpty {
                    Text("Time in zone · " + text.zones.joined(separator: " · ")).jiFont(.caption)
                        .foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("completed-workout-zones")
                }
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
