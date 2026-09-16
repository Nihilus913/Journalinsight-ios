# INVARIANTS — never break these (checked by verifier lanes; spec §12 A4)
1. JIDesign/JIFeatures default to MainActor isolation: new non-UI declarations need explicit `nonisolated`.
2. Hub errors are named cases (`HubError.<case>`), never `Error` strings.
3. Never render zero: a missing metric shows the placeholder glyph, not `0`.
4. Reserved green `#4ade80` is the GO verdict only.
5. Press feedback: scale 0.92, 100 ms, on every tappable.
6. The API token lives only in Keychain (JIHub's `KeychainStore`); never in UserDefaults, logs or snapshots.
