import SwiftUI
import JIDesign

/// B-57 W4 — the "Change" sheet for the heart-rate cap (spec §3.3). The limit is optional
/// (Toby 2026-09-24): the toggle off saves "no cap"; on, only a whole number is accepted, with no
/// range — the number is the user's.
struct HrCapChangeSheet: View {
    let current: Int?
    let onSave: (String?) async -> Bool
    @State private var useLimit: Bool
    @State private var text: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private let theme = JITheme.native

    init(current: Int?, onSave: @escaping (String?) async -> Bool) {
        self.current = current
        self.onSave = onSave
        _useLimit = State(initialValue: current != nil)
        _text = State(initialValue: current.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use a heart-rate limit", isOn: $useLimit)
                        .tint(theme.color(.info))
                        .accessibilityIdentifier("hrCapChange.toggle")
                    if useLimit {
                        HStack {
                            Text("Heart-rate cap")
                            Spacer()
                            TextField("bpm", text: $text)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 64, maxWidth: 96)
                                .numberPadKeyboard()
                                .accessibilityLabel("Heart-rate cap in bpm")
                                .accessibilityIdentifier("hrCapChange.field")
                            Text("bpm").foregroundStyle(theme.color(.muted))
                        }
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(theme.color(.danger))
                            .accessibilityIdentifier("hrCapChange.error")
                    }
                } footer: {
                    Text("Have a heart condition? Use the limit your doctor gave you. The app never changes this for you.")
                }
            }
            .navigationTitle(current == nil ? "Add a limit" : "Change your cap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await onSave(useLimit ? text : nil) { dismiss() } else { error = hrCapParseError }
                        }
                    }
                    .accessibilityIdentifier("hrCapChange.save")
                }
            }
        }
        .jiTheme(.native)
    }
}

extension View {
    /// `.keyboardType` is iOS-only; `swift test` builds for the macOS host. `.numbersAndPunctuation`
    /// lets the user type a minus sign — the number is theirs.
    @ViewBuilder func numberPadKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}
