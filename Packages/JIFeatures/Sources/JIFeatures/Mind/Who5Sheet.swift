import SwiftUI
import JIPersistence
import JIDesign

/// Weekly WHO-5 check-in sheet — oracle `Who5Sheet.tsx`.
///
/// Safety note: the below-threshold message (`who5Message`) is computed and shown only once all
/// 5 items are answered. Before that, unanswered items would otherwise default toward 0 in a
/// running total, which could surface the doctor-referral message prematurely/incorrectly off a
/// partial score. Since this instrument's RAILS call for extra care around that exact string, we
/// intentionally wait for the real, complete raw score rather than showing a "running" score that
/// could misfire.
public struct Who5Sheet: View {
    @Bindable var model: MindViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var answers: [Int?] = [nil, nil, nil, nil, nil]
    @State private var saving = false

    public init(model: MindViewModel) { self.model = model }

    private var allAnswered: Bool { answers.allSatisfy { $0 != nil } }
    private var raw: Int? { allAnswered ? who5Raw(answers.compactMap { $0 }) : nil }
    private var pct: Int? { raw.map(who5Percent) }
    private var message: String? { raw.flatMap(who5Message) }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Over the last two weeks…") {
                    ForEach(Array(WHO5_ITEMS.enumerated()), id: \.offset) { idx, item in
                        Picker(item, selection: $answers[idx]) {
                            Text("—").tag(Int?.none)
                            ForEach(WHO5_RESPONSES, id: \.value) { r in
                                Text(r.label).tag(Int?.some(r.value))
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Score").foregroundStyle(JIColor.muted)
                        Spacer()
                        Text(pct.map { "\($0)/100" } ?? "—/100").font(.title3.bold())
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(JIColor.reduced)
                    }
                }
            }
            .navigationTitle("Weekly well-being check-in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(!allAnswered || saving)
                }
            }
        }
    }

    private func save() async {
        guard allAnswered else { return }
        saving = true
        let ok = await model.addWho5(NewWho5(date: todayISOString(), items: answers.compactMap { $0 }))
        saving = false
        if ok { dismiss() }
    }
}
