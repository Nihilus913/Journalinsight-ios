# JournalInsight (Swift) — CLAUDE.md

Native SwiftUI JournalInsight, iOS 27 + watchOS 27. Replaces the React Native app (`HealthTraining/mobile/`, frozen at v1.18.2 as the behavioral oracle). Spec + wave plans live in the HealthTraining repo:
- `/Users/nihilus/Documents/HealthTraining/docs/superpowers/specs/2026-09-12-ji-swift-native-migration-design.md`
- `/Users/nihilus/Documents/HealthTraining/docs/superpowers/plans/2026-09-12-swift-w0-w1-foundation.md`
- HealthTraining `CLAUDE.md`, `REFS.md`, and its memory dir do NOT auto-load here — read them first for any decision; this repo's own memory dir is separate.

## Build / test
- `xcodegen generate` after editing `project.yml` (the generated .xcodeproj is committed).
- `DEVELOPER_DIR=/Users/nihilus/Downloads/Xcode-beta.app/Contents/Developer xcodebuild -project JournalInsight.xcodeproj -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build|test` (Xcode 27 RC until Toby installs GA + runs xcode-select)
- New Swift files under App/ or AppTests/ are NOT in the target until you run `xcodegen generate` and commit the regenerated JournalInsight.xcodeproj/project.pbxproj — a build can "succeed" while silently excluding them (SwiftPM globs `Packages/*/Sources`, but run it anyway).
- `App/Info.plist` is GENERATED from `project.yml` `info.properties` — never hand-edit it.
- Read `CONTEXT-IOS-FOUNDATION.md` (frozen W1 APIs + rulings) before any W2+ code; renaming/changing a signature needs a note there in the same commit.
- Package tests without Xcode: `swift test --package-path Packages/<Name>`.
- Fixtures: `Fixtures/{hub-contract,golden}` are COPIES synced by `HealthTraining/scripts/parity/sync_fixtures.py`; never edit here (FixtureManifestTests fails on drift).

## Rules
1. Branch `swift-migration`; never commit to `main` directly.
2. Bundle id `toby913.JournalInsight`. Token only in the Keychain. `NSAllowsLocalNetworking` stays.
3. Swift 6 language mode, strict concurrency. MainActor default isolation in JIDesign/JIFeatures/App; JICore/JIHub/JIPersistence stay nonisolated (CONTEXT §3). No `@unchecked Sendable` without a comment naming why.
4. Named hub errors (`.unauthorized`, `.duplicate`, `.yazioAuthExpired`) are load-bearing UI contracts.
5. Never render a zero for missing data: skeleton / "No data yet" / neutral error + retry / staleness banner.
6. Green (`#4ade80`) is reserved for verdict, band, 0–100 score, status. Selection + CTA = info blue `#38bdf8`.
7. Press-in scale 0.92 within 100 ms; every screen wave closes with `docs/DEVICE_RECORDING_PROTOCOL_IOS.md` recordings.
8. `JICompute` (W6): no `Calendar.current`, `TimeZone.current`, `Date()`; Int128 is NOT enough for `PythonRound`.
9. `legacy/` is a read-only donor (see legacy/README.md).
