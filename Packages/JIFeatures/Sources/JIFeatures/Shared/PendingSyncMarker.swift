import Foundation
import Observation
import SwiftUI
import JICore
import JIDesign
import JIHub
import JIPersistence

// B-52 p5: the ONE global offline / "N pending" marker plus the per-kind pending rows behind it.
// Every outbox kind the app enqueues gets a human label here; a kind this table does not know
// (a newer build's row, or a p4 kind such as `training_break` / `garmin_push`) still counts and
// still lists — under its raw tag — so nothing queued is ever invisible.

/// Human label for one outbox `kind`. Unknown kinds fall back to the raw tag (never hidden).
public nonisolated func pendingSyncKindLabel(_ kind: String) -> String {
    switch kind {
    case "weighin": "Weigh-in"
    case "gateRespond": "Morning check-in"
    case "sessionFeel": "Session feel"
    case "plan_weekday": "Planned weekday"
    case "verdictOverride": "Verdict override"
    case "verdictOverrideClear": "Verdict override undo"
    case "goals_put", "targets": "Goals & targets"
    case "exercise_patch": "Lift edit"
    case "ondevice_verdict": "Morning verdict"
    case "strength": "Strength session"
    case "workout_template": "Workout template"
    case "training_break": "Training break"   // B-52 p4
    case "garmin_push": "Push to Garmin"      // B-52 p4
    default: kind
    }
}

/// One line of the marker's breakdown: a kind and how many of its rows are still queued.
public nonisolated struct PendingSyncLine: Sendable, Equatable, Identifiable {
    public var kind: String
    public var count: Int
    public var lastError: String?
    public var id: String { kind }
    public var label: String { pendingSyncKindLabel(kind) }
}

/// Pending rows grouped by kind in first-queued order (oldest kind first).
public nonisolated func pendingSyncLines(_ rows: [OutboxRow]) -> [PendingSyncLine] {
    var order: [String] = []
    var byKind: [String: PendingSyncLine] = [:]
    for row in rows {
        if byKind[row.kind] == nil {
            order.append(row.kind)
            byKind[row.kind] = PendingSyncLine(kind: row.kind, count: 0, lastError: nil)
        }
        byKind[row.kind]?.count += 1
        if let err = row.lastError { byKind[row.kind]?.lastError = err }
    }
    return order.compactMap { byKind[$0] }
}

/// The marker's face, or `nil` when there is nothing to say (hub up, queue empty).
public nonisolated func pendingSyncMarkerText(pending: Int, offline: Bool) -> String? {
    switch (offline, pending) {
    case (false, 0): nil
    case (true, 0): "Offline"
    case (true, let n): "Offline · \(n) pending"
    case (false, let n): "\(n) waiting to sync"
    }
}

/// Observable state behind the marker: the outbox queue and the watchdog's reachability, polled
/// while the app is in the foreground (the outbox has no change feed; a 2 s read of one small
/// table is cheap and keeps the count honest the moment a drain retires rows).
@MainActor
@Observable
public final class PendingSyncModel {
    public private(set) var lines: [PendingSyncLine] = []
    public private(set) var offline = false
    public var pendingCount: Int { lines.reduce(0) { $0 + $1.count } }
    public var markerText: String? { pendingSyncMarkerText(pending: pendingCount, offline: offline) }

    /// The current watchdog (rebuilt by the app on every foreground); weak — never keeps it alive.
    public weak var watchdog: HubWatchdog?
    private let outboxSource: () -> Outbox?
    private var outbox: Outbox?
    private let interval: Duration
    private var loop: Task<Void, Never>?

    /// The app's one instance: the scene-phase hook starts/stops it and hands it the watchdog,
    /// `RootTabView` draws it. Tests build their own over an in-memory outbox.
    public static let shared = PendingSyncModel()

    public init(interval: Duration = .seconds(2), outboxSource: @escaping () -> Outbox? = { try? Outbox(db: .onDisk()) }) {
        self.interval = interval
        self.outboxSource = outboxSource
    }

    /// One read: queue + reachability. Public so tests (and a drain caller) can force it.
    public func refresh() {
        // Opened once, then reused: a fresh DatabasePool every 2 s tick would churn file handles.
        if outbox == nil { outbox = outboxSource() }
        let rows = (try? outbox?.pending()) ?? []
        let fresh = pendingSyncLines(rows)
        if fresh != lines { lines = fresh }
        let isOffline = !(watchdog?.reachable ?? true)
        if isOffline != offline { offline = isOffline }
    }

    public func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                do { try await Task.sleep(for: self.interval) } catch { return }
            }
        }
    }

    public func stop() { loop?.cancel(); loop = nil }
}

/// The per-row "waiting to sync" glyph — the same symbol the Training rows already use
/// (`TrainingDaySheet`, `TrainingWeekStrip`, `LiftSteppers`), so every kind reads alike.
public struct PendingSyncGlyph: View {
    @Environment(\.jiTheme) private var theme
    public init() {}
    public var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .jiFont(.caption, weight: .semibold)
            .foregroundStyle(theme.color(.reduced))
            .accessibilityLabel("Waiting to sync")
    }
}

/// The global marker: a pill (hidden when the hub is up and nothing is queued) that expands into
/// one pending row per kind, each with the waiting-to-sync glyph.
public struct PendingSyncMarker: View {
    let model: PendingSyncModel
    @State private var expanded = false
    @Environment(\.jiTheme) private var theme

    public init(model: PendingSyncModel) { self.model = model }

    public var body: some View {
        if let text = model.markerText {
            let shape = RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
            VStack(alignment: .leading, spacing: 6) {
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    Label(text, systemImage: model.offline ? "wifi.exclamationmark" : "arrow.triangle.2.circlepath")
                        .jiFont(.footnote, weight: .semibold)
                        .foregroundStyle(theme.color(.reduced))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(model.lines.isEmpty)
                .accessibilityIdentifier("pending-sync-marker")
                if expanded {
                    ForEach(model.lines) { line in
                        HStack(spacing: 6) {
                            PendingSyncGlyph()
                            Text(line.count > 1 ? "\(line.label) ×\(line.count)" : line.label)
                                .jiFont(.caption)
                                .foregroundStyle(theme.color(.text))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pending-sync-row-\(line.kind)")
                    }
                }
            }
            .padding(.horizontal, JISpacing.s3).padding(.vertical, 6)
            .background(theme.color(.control), in: shape)
            .overlay(shape.strokeBorder(theme.color(.hairlineOuter), lineWidth: 1))
            .transition(.opacity)
        }
    }
}
