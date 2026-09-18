import SwiftUI
import JIPersistence
import JIDesign

/// E9 — the Mind tab's descriptive-tone snapshot card (oracle `MindSnapshotCard.tsx`). Always
/// renders plain, muted-tone text — structural, not a documentation convention — so it can never
/// pick up the athletic gate's prescriptive (GO/RED-colored, imperative) styling. `mindSnapshot()`
/// derives the headline/description purely from today's check-in and never emits a verdict word.
public struct MindSnapshotCard: View {
    let checkin: CheckIn?

    public init(checkin: CheckIn?) { self.checkin = checkin }

    public var body: some View {
        let snap = mindSnapshot(checkin)
        Surface(level: 1, padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MIND · TODAY").font(.caption.bold()).foregroundStyle(JIColor.muted)
                Text(snap.headline).jiFont(.title, weight: .heavy).foregroundStyle(JIColor.text)
                Text(snap.description).font(.subheadline).foregroundStyle(JIColor.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's mind snapshot")
    }
}
