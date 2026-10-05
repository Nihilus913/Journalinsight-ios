import SwiftUI
import JICore
import JIDesign

// MARK: - W-B91 S3 b91p2: the Strain detail sheet (tap the Strain card on Decide)
//
// One sheet with what sits behind the card: the strain value and the usual range, the
// Exercise-minutes Load figure (Q4: the minutes stay reachable after the Strain card replaced the
// minutes Load tile), and the ACWR's three fact tiles — acute (7 d), chronic (28 d), ratio — with
// the hub's named status word ("Overreaching", "Paused", ...) next to the ratio, never a bare number.

/// One fact tile ("Acute", "0.86", "7-day avg / day").
public nonisolated struct StrainLoadTile: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let valueText: String
    public let caption: String
}

public nonisolated struct StrainDetailModel: Equatable, Sendable {
    /// "Yesterday" before the call, "Today so far" after it.
    public let strainLabel: String
    /// The strain number (0 dp) or "—" while calibrating / not sent.
    public let strainText: String
    /// "Your usual 30–55" · "Calibrating · 12 of 19 loaded days" · "No data".
    public let usualText: String
    /// The Exercise-minutes Load figure: "245 min", or "—" without a reading.
    public let minutesText: String
    /// "Exercise minutes · 7 d · normal 180–320".
    public let minutesCaption: String
    /// Always three: acute, chronic, ratio ("—" when the hub sent none).
    public let tiles: [StrainLoadTile]
    /// The named ACWR status (`decideLoadStatus`); `.missing(.noData)` without a Load row.
    public let status: JISignalStatus
    /// The hub's caption for the Load row ("7 d vs 28 d · 6 sessions in 28 d · ..."), if any.
    public let statusCaption: String?

    public var statusWord: String { status.word }
}

/// Builds the sheet from the card's state, the morning strain (for the usual range after the call),
/// the hub's `load` gate row and the gate-input minutes Load (`RecoveryInsightService.loadReading`).
public nonisolated func strainDetailModel(state: DecideStrainState, strain: MorningStrain?,
                                          load: GateSignal?, minutes: RecoveryLoadReading?) -> StrainDetailModel {
    let usualFromStrain: String? = {
        guard let lo = strain?.usualLow, let hi = strain?.usualHigh, lo <= hi else { return nil }
        return "Your usual \(jiNumber(lo, 0))–\(jiNumber(hi, 0))"
    }()
    let label: String, value: String, usual: String
    switch state {
    case let .before(v, range, _, _):
        label = "Yesterday"; value = jiNumber(v, 0)
        usual = "Your usual \(jiNumber(range.lowerBound, 0))–\(jiNumber(range.upperBound, 0))"
    case let .after(v, _, _, _):
        label = "Today so far"; value = jiNumber(v, 0)
        usual = usualFromStrain ?? JIMissingReason.calibrating.rawValue
    case let .calibrating(loaded, needed, max):
        label = max == nil ? "Yesterday" : "Today so far"; value = "—"
        usual = "\(JIMissingReason.calibrating.rawValue) · \(loaded) of \(needed) loaded days"
    case .unavailable:
        label = "Yesterday"; value = "—"; usual = JIMissingReason.noData.rawValue
    }
    let minutesText = minutes?.valueText ?? "—"
    let minutesCaption = "Exercise minutes · " + (minutes?.caption ?? JIMissingReason.noData.rawValue)
    let tiles = [
        StrainLoadTile(id: "acute", label: "Acute", valueText: jiValueText(load?.acuteLoad, decimals: 2),
                       caption: "7-day avg / day"),
        StrainLoadTile(id: "chronic", label: "Chronic", valueText: jiValueText(load?.chronicLoad, decimals: 2),
                       caption: "28-day avg / day"),
        StrainLoadTile(id: "ratio", label: "Ratio", valueText: jiValueText(load?.value, decimals: 2),
                       caption: "acute ÷ chronic"),
    ]
    let status = load.map(decideLoadStatus) ?? .missing(.noData)
    let caption = load?.note.flatMap { $0.isEmpty ? nil : $0 }
    return StrainDetailModel(strainLabel: label, strainText: value, usualText: usual,
                             minutesText: minutesText, minutesCaption: minutesCaption,
                             tiles: tiles, status: status, statusCaption: caption)
}

/// The `load` row among the gate signals (the Strain sheet's ratio + status source).
public nonisolated func strainDetailLoadSignal(_ gateSignals: [GateSignal]?) -> GateSignal? {
    gateSignals?.first { $0.key == "load" }
}

// MARK: - View

struct StrainDetailSheet: View {
    let model: StrainDetailModel
    let onClose: () -> Void
    @Environment(\.jiTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    strainSection
                    minutesSection
                    loadSection
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .jiPageGround()
            .background(theme.color(.bg))
            .navigationTitle("Strain")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("today.decide.strainDetail.done")
                }
            }
        }
        .jiTheme(theme)
        .presentationDetents([.medium, .large])
    }

    private var strainSection: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.strainLabel).jiFont(.caption).foregroundStyle(theme.color(.muted))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(model.strainText).jiNumeral(.numeralLarge, weight: .heavy, tint: .text)
                        .accessibilityIdentifier("today.decide.strainDetail.value")
                    Text("of 100").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                }
                Text(model.usualText).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("today.decide.strainDetail.usual")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var minutesSection: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Load").jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                Text(model.minutesText).jiNumeral(.numeralLarge, weight: .heavy, tint: .text)
                    .accessibilityIdentifier("today.decide.strainDetail.minutes")
                Text(model.minutesCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var loadSection: some View {
        Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Training load (ACWR)").jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Image(systemName: model.status.symbolName)
                        Text(model.statusWord)
                    }
                    .jiFont(.footnote, weight: .semibold)
                    .foregroundStyle(theme.color(model.status.role))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.decide.strainDetail.status")
                }
                HStack(spacing: 8) {
                    ForEach(model.tiles) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.label).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                            Text(tile.valueText).jiNumeral(.numeralSmall, weight: .heavy, tint: .text)
                            Text(tile.caption).jiFont(.micro).foregroundStyle(theme.color(.muted))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(theme.color(.nested), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("today.decide.strainDetail.tile.\(tile.id)")
                    }
                }
                if let caption = model.statusCaption {
                    Text(caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
