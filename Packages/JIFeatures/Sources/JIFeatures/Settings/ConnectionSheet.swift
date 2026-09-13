import SwiftUI
import Observation
import JICore
import JIDesign
import JIHub

@Observable @MainActor
public final class ConnectionSheetModel {
    public var baseURL: String
    public var token: String
    public var status: ConnectionTestResult?
    public var testing = false
    public var saveError: String?
    private let store: ConnectionConfigStore

    public init(store: ConnectionConfigStore) {
        self.store = store
        let existing = try? store.load()
        baseURL = existing?.baseURL.absoluteString ?? "http://"
        token = existing?.token ?? ""
    }

    // Rule 2 (CLAUDE.md): the token lives only here and in the SecureField below — never in
    // `status`, a log, or an accessibility label. `candidate` and `statusText` must stay that way.
    private var candidate: ConnectionConfig? {
        // `.whitespacesAndNewlines`: a token pasted from a terminal carries a trailing "\n" that
        // would otherwise land verbatim in the Bearer header. `host()` is "" (not nil) for
        // "https://:8000", so emptiness is checked explicitly.
        let cleanURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanURL), let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty, !cleanToken.isEmpty else { return nil }
        return ConnectionConfig(baseURL: url, token: cleanToken)
    }
    public func test() async {
        guard let c = candidate else { status = .other("Enter a valid http(s) URL and a token."); return }
        testing = true; defer { testing = false }
        status = await ConnectionTest.run(c)
    }
    // CODE-3: Save must never be a silent no-op — an invalid candidate or a Keychain write failure
    // is surfaced via `saveError` for the sheet to display, instead of quietly doing nothing.
    public func save() -> ConnectionConfig? {
        saveError = nil
        guard let c = candidate else {
            saveError = "Enter a valid http(s) URL and a token before saving."
            return nil
        }
        do {
            try store.save(c)
            return c
        } catch {
            saveError = "Could not save to the keychain: \(error.localizedDescription)"
            return nil
        }
    }
}

public struct ConnectionSheet: View {
    @State private var model: ConnectionSheetModel
    private let onSaved: (ConnectionConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(store: ConnectionConfigStore, onSaved: @escaping (ConnectionConfig) -> Void) {
        _model = State(initialValue: ConnectionSheetModel(store: store)); self.onSaved = onSaved
    }
    public var body: some View {
        NavigationStack {
            Form {
                Section("HealthTraining hub") {
                    TextField("Base URL", text: $model.baseURL).iosURLField().autocorrectionDisabled()
                    SecureField("API token", text: $model.token)
                }
                Section {
                    Button { Task { await model.test() } } label: { HStack { Text("Test connection"); if model.testing { Spacer(); ProgressView() } } }
                        .disabled(model.testing)
                    if let s = model.status { Text(statusText(s)).font(.footnote).foregroundStyle(JIColor.muted) }
                    if let e = model.saveError { Text(e).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Connection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let c = model.save() { onSaved(c); dismiss() } }.tint(JIColor.info)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
    // Never interpolate `model` or the config here — only the fixed, tokenless strings below (rule 2).
    private func statusText(_ s: ConnectionTestResult) -> String {
        switch s {
        case .ok(let last): "Connected. Last sync: \(last ?? "never")."
        case .unauthorized: "Reachable, but the token was rejected."
        case .unreachable(let m): "Unreachable: \(m)"
        case .other(let m): m
        }
    }
}

// Controller ruling 2: `.keyboardType` and `.textInputAutocapitalization` are iOS-only APIs and
// fail to compile for the macOS host that `swift test` builds against. No-op on other platforms.
private extension View {
    @ViewBuilder func iosURLField() -> some View {
        #if os(iOS)
        self.keyboardType(.URL).textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
