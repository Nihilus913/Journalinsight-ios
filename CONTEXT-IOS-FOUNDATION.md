# CONTEXT-IOS-FOUNDATION.md
frozen-at: 7de66dd (W2a merge, tag swift-w2a-foundation) — refs_lint checks this is an ancestor of the wave branch

Frozen record of the W0/W1 native Swift JournalInsight foundation, verbatim from the code at commit `2f80086` (tag `swift-w1-foundation`, since merged to `main`). Read this before writing any W2+ code.

## 1. Purpose + change rule

The contract every W2+ coder reads first. **Adding** to these APIs (new methods, DTO fields, capability flags, design tokens) needs no update here. **Renaming or changing a signature** below needs a note in this file, in the same commit as the change. Don't let it drift.

## 2. Package graph

```
JICore → JIHub  ─┐
       → JIDesign ┴→ JIFeatures → App
       (JIPersistence → JIFeatures too)
```
`JIHub`, `JIDesign`, `JIPersistence` depend only on `JICore` (+GRDB for JIPersistence). `JIFeatures` depends on all four. `App` depends on all five. Nothing depends on `JIFeatures`/`App`.

All `Package.swift`: `// swift-tools-version: 6.4`, `platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)]`, `.swiftLanguageMode(.v6)`. `project.yml` (XcodeGen) pins the App target to `deploymentTarget.iOS: "27.0"`, `xcodeVersion: "27.0"`, `SWIFT_VERSION: "6.0"`, `SWIFT_STRICT_CONCURRENCY: complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`. Bundle id `toby913.JournalInsight` (Tests: `toby913.JournalInsightTests`).

## 3. Isolation split (ruling)

Data-layer packages **JICore / JIHub / JIPersistence**: `nonisolated` — no `.defaultIsolation` in `swiftSettings`. UI packages **JIDesign / JIFeatures**: `.defaultIsolation(MainActor.self)` in `swiftSettings`. **App** target: same default via `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` in `project.yml` (not a package setting).

Consequences from real compiler errors:
- In MainActor-default `JIDesign`, pure math/data is explicitly `nonisolated`: `readinessBand`, `gaugeAngle`, `ReadinessBand`, private `ArcSegment: Shape` (`Shape.path(in:)` is a `nonisolated` protocol requirement). In `JIFeatures`: `resolveTodayRow`, `TodayChip` likewise — a synthesized `Equatable` on a MainActor enum can't be used from a nonisolated test.
- `@Observable @MainActor` classes (`ProviderStore`, `TodayViewModel`, `ConnectionSheetModel`, `AppEnvironment`) spell out `@MainActor` explicitly even where it's already the default.
- No `@unchecked Sendable` without a comment naming why. Only `InMemorySecretStore` (`JIHub`) has one: `// @unchecked: lock-guarded dictionary` (NSLock-backed). Test-only `StubURLProtocol` carries the same pattern for its process-global state.

## 4. JICore (nonisolated)

`Capabilities.swift`: `public struct DataCapability: OptionSet, Sendable, Hashable { public let rawValue: UInt32 }`. Flags (bit→name): `0 gate`, `1 morning`, `2 morningVerdict`, `3 recovery`, `4 sleepSummary`, `5 exercises`, `6 energy`, `7 nutritionDay`, `8 nutritionWeek`, `9 foodLogWrite`, `10 weighinWrite`, `11 goals`, `12 kpiTargets`, `13 challenges`, `14 sync`, `15 dataQuality`, `20 bodyBattery`, `21 trainingReadiness`, `22 garminSleepScore`, `23 hrvRMSSD`, `24 hrvSDNN`. `public static let hubAll` = every flag **except `.hrvSDNN`** (Mac hub/Fenix supplies RMSSD, not SDNN — deliberate, see `hubAllCoversEveryDomainButNotSDNN`).

`Gate.swift`:
```swift
public enum GateRecommendation: String, Codable, Sendable, Equatable {
    case progress = "PROGRESS", maintain = "MAINTAIN", reduce = "REDUCE", insufficientData = "INSUFFICIENT_DATA"
}
public struct GateAverages: Codable, Sendable, Equatable {
    public var avgKcal7d, avgProtein7d, avgWeightKg, avgRhrBpm, sleepScore7d, acwr: Double?
    public var avgBodyBattery, avgKcalBurned7d, avgKcalDeficit7d, estWeeklyWeightChangeKg: Double?
    public var trends: [String: String]
}
public struct DailyKpiRow: Codable, Sendable, Equatable { public var date: String; public var values: [String: Double?] }
public struct GateResponse: Codable, Sendable, Equatable {
    public var averages: GateAverages
    public var daily: [DailyKpiRow]
    public var recommendation: GateRecommendation
    public var trackedDays, totalDays, minTrackedDays: Int
    public var triggeredRules, suggestions: [String]
}
```
`DailyKpiRow` hand-writes `Codable` (custom `Key: CodingKey`) so `values` keeps a wire `null` **present with `nil`**, never dropped (`Dictionary` subscript-assign-`nil` removes the key — uses `updateValue(nil, forKey:)` + explicit `c.decodeNil(forKey:)`). `values` is `public var` so tests can mutate it. Also reverses `JSON.decoder`'s `.convertFromSnakeCase` per-key (private `snakeCased(_:)`) since that strategy runs before `DailyKpiRow` sees a key (wire `kcal_consumed` arrives as `kcalConsumed`; the row's contract is raw snake_case).

`Morning.swift`:
```swift
public struct TodayActivity: Codable, Sendable, Equatable {
    public var name, type: String?
    public var durationSec, avgHr, maxHr: Int?
    public var teAerobic: Double?
}
public struct Experiment: Codable, Sendable, Equatable {
    public var count, target: Int
    public var executionScore: Double?
    public var wantsCompletePrompt: Bool?
}
public struct HrvPoint: Codable, Sendable, Equatable { public var date: String; public var hrvWeeklyAvg, rhrBpm: Double? }
public struct MorningResponse: Codable, Sendable, Equatable {
    public var todayActivities: [TodayActivity]
    public var verdict, verdictDate: String?
    public var experiment: Experiment?
    public var carbs3dAvg: Double?
    public var carbWatchFloor: Double
    public var hrvSeries: [HrvPoint]
}
public struct MorningVerdict: Codable, Sendable, Equatable {
    public var date, verdict: String
    public var reason, sessionPrescription: String?
    public var computedAt: String
}
public enum VerdictTone: Sendable, Equatable { case go, amber, red, muted }
public struct VerdictParts: Sendable, Equatable { public var word, session: String; public var tone: VerdictTone }
public func verdictParts(_ v: String?) -> VerdictParts
```
Port of `mobile/src/lib/verdict.ts`: splits on `"—"`; `word` keeps the parenthetical, tone strips it. Tone: `nil`/empty → `("—","No verdict yet",.muted)`; `GO*` → `.go`; **`REDUCED*` → `.amber`** (deliberate deviation — RN's `startsWith("RED")` also catches `"REDUCED"` and renders red; design wins, `mobile/src/theme/tokens.ts` `verdict.reduced` + plan L24, 2026-09-13 ruling); other `RED*` → `.red`; else `.amber`.

`Recovery.swift`: `public struct RecoveryDay: Codable, Sendable, Equatable { public var date: String; public var sleepScore, sleepDurationSec, rhrBpm, bodyBatteryAvg, readinessScore, acwr, hrvWeeklyAvg: Double? }`; `public struct RecoveryReport: Codable, Sendable, Equatable { public var days: [RecoveryDay] }`.

`Sync.swift`: `public struct SyncStatus: Codable, Sendable, Equatable { public var lastSync: String? }`; `public struct HealthResponse: Codable, Sendable, Equatable { public var status: String }`.

**HealthDataProvider ↔ hub routes** (confirmed against `HubDataProvider.swift`, §5):
```swift
public protocol HealthDataProvider: Sendable {
    var capabilities: DataCapability { get }
    func health() async throws -> HealthResponse                              // GET /health
    func gate(windowDays: Int) async throws -> GateResponse                    // GET /api/v1/planning/gate?window_days=
    func morning() async throws -> MorningResponse                            // GET /api/v1/planning/morning
    func morningVerdict(date: String) async throws -> MorningVerdict          // GET /api/v1/planning/morning-verdict?date=
    func recovery(windowDays: Int) async throws -> [RecoveryDay]              // GET /api/v1/vitals/recovery?window_days= (unwraps .days)
    func syncStatus() async throws -> SyncStatus                              // GET /api/v1/ingestion/status
}
```
The remaining 21 hub routes (exercises, energy, nutrition, food log, weigh-in, gate respond, feel, sync trigger/job, goals, kpi targets, challenges, data quality, sleep summary) are **not yet ported** — added in W3/W4 by the task that first needs each, each with its own contract decode test.

`HubError.swift`:
```swift
public enum HubError: Error, Equatable, Sendable {
    case unauthorized
    case duplicate(detail: String)
    case yazioAuthExpired(detail: String)
    case http(status: Int, detail: String?)
    case network(String)
    case decoding(String)
    public static func from(status: Int, detail: String?) -> HubError
}
```
`.from`: `401→.unauthorized`, `409→.duplicate`, `502→.yazioAuthExpired`, else `.http`. Named cases are load-bearing UI contracts (CLAUDE.md rule 4).

`JSON.decoder`/`JSON.encoder` are **computed `static var`s, not `static let`** (`JSONDecoder`/`Encoder` aren't `Sendable`; a stored constant is a Swift 6 strict-concurrency error). `decoder.keyDecodingStrategy = .convertFromSnakeCase`; `encoder.keyEncodingStrategy = .convertToSnakeCase`, `outputFormatting = [.sortedKeys]`. **Acronym rule**: `.convertFromSnakeCase` turns wire `base_url` into `baseUrl`, not `baseURL` — any acronym-cased property needs explicit `CodingKeys` (see `ConnectionConfig`, §5).

`MockDataProvider`: `public struct MockDataProvider: HealthDataProvider { public let capabilities: DataCapability = .hubAll; public static func fixtureURL(named name: String) -> URL? }` — previews/tests only, **never the app default** (`AppEnvironment.apply` always builds a `HubDataProvider`); serves `Bundle.module`'s own fixture copies.

`ProviderStore`: `@Observable @MainActor public final class ProviderStore { public var provider: any HealthDataProvider; public init(provider: any HealthDataProvider) }`.

**Fixtures**: `Fixtures/hub-contract/*.json` + `Fixtures/golden/*.json` (repo root) are **copies** synced by `HealthTraining/scripts/parity/sync_fixtures.py`; `Fixtures/MANIFEST.sha256` hashes all 17 hub-contract + golden files, `FixtureManifestTests` fails on drift. A **second** copy lives under `Packages/JICore/Sources/JICore/Fixtures/hub-contract/` as a real `Bundle.module` resource copy, **not a symlink** — SwiftPM won't resolve nested symlinks into a package resource bundle. `libraryFixtureCopiesMatchManifest` guards that copy too; both refresh from the same sync-script run.

## 5. JIHub (nonisolated)

```swift
public protocol SecretStore: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ key: String, _ data: Data) throws
    func delete(_ key: String) throws
}
public struct KeychainStore: SecretStore { public let service: String; public init(service: String = "toby913.JournalInsight.hub") }
public final class InMemorySecretStore: SecretStore, @unchecked Sendable
```
`KeychainStore`: device-only, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced. Token lives **only** in the Keychain — never fixtures, logs, error strings, or status text (`ConnectionSheet.statusText` interpolates only fixed strings/detail — never `model`/config).

```swift
public struct ConnectionConfig: Codable, Sendable, Equatable {
    public var baseURL: URL
    public var token: String
    private enum CodingKeys: String, CodingKey { case baseURL = "baseUrl"; case token }
}
public struct ConnectionConfigStore: Sendable {
    public static let key = "ht.connection.v1"
    public init(secrets: any SecretStore = KeychainStore())
    public func load() throws -> ConnectionConfig?
    public func save(_ c: ConnectionConfig) throws
    public func clear() throws
}
public struct HubClient: Sendable {
    public let config: ConnectionConfig
    public init(config: ConnectionConfig, session: URLSession = .shared)
    public func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T
}
```
`HubClient.get`: 15 s `timeoutInterval`, `Authorization: Bearer <token>`, `Accept: application/json`. Non-2xx decodes `{"detail":...}` and throws via `HubError.from`; decode failure throws `.decoding("\(path): \(error)")`.

```swift
public struct HubDataProvider: HealthDataProvider {
    public let capabilities: DataCapability = .hubAll
    public init(client: HubClient)
    public func gate(windowDays: Int = 28) async throws -> GateResponse
    public func recovery(windowDays: Int = 28) async throws -> [RecoveryDay]
}
public enum ConnectionTestResult: Equatable, Sendable { case ok(lastSync: String?), unauthorized, unreachable(String), other(String) }
public enum ConnectionTest { public static func run(_ config: ConnectionConfig, session: URLSession = .shared) async -> ConnectionTestResult }
```
Both windowed calls clamp `min(windowDays, 365)`. `ConnectionTest.run`: `/health` probes reachability (network error → `.unreachable`); `/api/v1/ingestion/status` probes the bearer (401 → `.unauthorized`, else `.ok(lastSync:)`).

**Test convention**: `StubURLProtocol` holds `nonisolated(unsafe) static var` state (process-global). Only **one** `@Suite(.serialized)` may be backed by it (`HubClientTests`) — two independent serialized suites still interleaved on this static state in practice (confirmed by a failing run), so `HubDataProviderTests.swift` adds tests via `extension HubClientTests { ... }`. New stub-backed tests go there too.

## 6. JIPersistence (nonisolated)

GRDB **7.11.1** (pinned by revision `b83108d...` in `Package.resolved` at both package level (`Packages/JIPersistence/`, `Packages/JIFeatures/`) and workspace level (`JournalInsight.xcodeproj/.../swiftpm/Package.resolved`) — all three move together on a bump.

```swift
public final class AppDatabase: Sendable {
    public let pool: DatabasePool
    public static func inMemory() throws -> AppDatabase
    public static func onDisk(name: String = "journalinsight.sqlite", excludedFromBackup: Bool = false) throws -> AppDatabase
    public static func cache() throws -> AppDatabase   // onDisk(name: "cache.sqlite", excludedFromBackup: true)
}
enum Migrations { static var migrator: DatabaseMigrator }
public struct CacheHit<T: Sendable>: Sendable { public let value: T; public let fetchedAt: Date }
public struct OfflineCache: Sendable {
    public init(db: AppDatabase)
    public func put<T: Encodable>(_ key: String, _ value: T) throws
    public func get<T: Decodable & Sendable>(_ key: String, as: T.Type) throws -> CacheHit<T>?
    public func fetchedAt(_ key: String) throws -> Date?
}
public struct PrefStore: Sendable {
    public init(db: AppDatabase)
    public func set<T: Encodable>(_ key: String, _ value: T) throws
    public func get<T: Decodable>(_ key: String, as: T.Type) throws -> T?
    public func remove(_ key: String) throws
}
```
`inMemory()` — despite the name — opens a `DatabasePool` on a **unique temp file** (`journalinsight-test-<UUID>.sqlite`): `DatabasePool` can't open `":memory:"` (needs a real file for WAL). Two calls never share state. `cache()` → `cache.sqlite`, excluded from backup (+ `-wal`/`-shm` siblings via `URLResourceValues.isExcludedFromBackup`). Plain `onDisk()` default `journalinsight.sqlite` **is backed up** (user prefs). One migrator shared by both files; migration `"v1_foundation"` creates **both** `cache` and `pref` tables in **both** files (each store touches only its own table) — never edit a shipped migration, append new ones. Timestamps use `Date().ISO8601Format()` / `Date(_:strategy: .iso8601)` — **`Date.ISO8601FormatStyle`, not `ISO8601DateFormatter`**. Cache keys used by Today: `"today.morning"`, `"today.gate"`, `"today.recovery"`.

## 7. JIDesign (`.defaultIsolation(MainActor.self)`)

`JIColor` (hex, `mobile/src/theme/tokens.ts` dark scheme, verbatim): `bg 0x0b0f14`, `surface 0x141a22`, `surface2 0x1c242e`, `surface3 0x273040`, `nested 0x333e4d`, `control 0x3f4b5c`, `text 0xe6edf3`, `muted 0x8b98a5`, `mutedNested 0xb0bcca`, `go 0x4ade80`, `reduced 0xfbbf24`, `danger 0xf87171`, `info 0x38bdf8`, `sleep 0xa78bfa`. **`go` (`#4ade80`) reserved** for verdict/band/0–100 score/status only (rule 6); selection+CTA use `info` (`#38bdf8`). `JIColor.color(for tone: VerdictTone) -> Color` maps go/amber/red/muted → go/reduced/danger/muted.

`JIRadius`: `card: CGFloat = 16`, `hero: CGFloat = 24`.

`JIMotion` (perceptual durations, `mobile/src/theme/tokens.ts` MOTION): `press = .spring(duration: 0.10, bounce: 0)`, `standard = .spring(duration: 0.50, bounce: 0)`, `overshoot = .spring(duration: 0.50, bounce: 0.4)`, `reveal = .spring(duration: 2.8, bounce: 0)`, `micro: Duration = .milliseconds(200)`, `card: Duration = .milliseconds(400)`, `staggerXs: Duration = .milliseconds(70)`. RN mapping: SwiftUI `bounce` and RN spring `dampingRatio` are complementary on `[0,1]` (`dampingRatio = 1 − bounce`), so `overshoot` bounce `0.4` ≙ RN `dampingRatio 0.6`.

```swift
public struct PressableScaleStyle: ButtonStyle { public static let pressedScale: CGFloat = 0.92; public static let pressedOpacity: Double = 0.85 }
public extension ButtonStyle where Self == PressableScaleStyle { static var pressableScale: PressableScaleStyle { .init() } }
```
0.92 scale / 0.85 opacity while pressed; press-in uses `JIMotion.press` (100 ms), release uses `JIMotion.overshoot` (the bounce). `reduceMotion` suppresses `scaleEffect` (opacity-only fallback). `.sensoryFeedback(.selection, trigger: isPressed) { old,new in new && !old }` — haptic fires **only on press-in**, not release.

`Surface`: `public struct Surface<Content: View>: View { public init(level: Int = 1, radius: CGFloat = JIRadius.card, padding: CGFloat = 16, @ViewBuilder content: () -> Content) }`. `level` 1/2/3 → surface/surface2/surface3; **`default:` in the switch falls back to `surface`**, silently absorbing an invalid level.

`SkeletonBlock`: `public init(width: CGFloat? = nil, height: CGFloat = 16)`. `StalenessBanner`: `public init(fetchedAt: Date?, hubReachable: Bool)` — renders only when `!hubReachable && fetchedAt != nil`; copy `"Showing data from HH:mm — hub unreachable"`.

```swift
public nonisolated enum ReadinessBand: Sendable, Equatable { case danger, warn, go }
public nonisolated let readinessGoMin = 70.0
public nonisolated let readinessWarnMin = 40.0
public nonisolated func readinessBand(for value: Double) -> ReadinessBand
public nonisolated func gaugeAngle(for value: Double) -> Angle
public struct ReadinessArcGauge: View { public init(score: Double?, sourceMissing: Bool = false, size: CGFloat = 180) }
```
Thresholds: `<40 danger`, `40..<70 warn`, `>=70 go`. Clock convention (RN-matched): `270°=9 o'clock(0)`, `360°=12 o'clock(50)`, `450°=3 o'clock(100)` — `gaugeAngle = 270 + (clamp(value,0,100)/100)*180`. Private `ArcSegment: Shape` subtracts 90° to convert to SwiftUI's 0°=3-o'clock convention. Needle = filled `Circle` (`JIColor.text`) with band-colored stroke overlay, positioned via `cos/sin` of the gauge angle, animated with `JIMotion.reveal`.

`StatChip`: `public init(label: String, value: Double?, unit: String? = nil, points: [Double?] = [], sourceMissing: Bool = false, action: (() -> Void)? = nil)`. `Sparkline`: `public init(points: [Double?])` — **always neutral gray** (`mutedNested`), never the reserved green. A11y mirrors what's drawn: `numeral` is the same rounded string shown visually; `unit` announced only when `showsUnit` (`value != nil && !sourceMissing`) — never a bare unit with no number.

## 8. JIFeatures (`.defaultIsolation(MainActor.self)`)

```swift
nonisolated public struct TodayChip: Identifiable, Equatable, Sendable {
    public let id: String, label: String, value: Double?, unit: String?, points: [Double?], sourceMissing: Bool
}
nonisolated public struct ResolvedTodayRow: Sendable { public let row: DailyKpiRow?; public let stale: Bool }
nonisolated public func resolveTodayRow(_ daily: [DailyKpiRow]) -> ResolvedTodayRow
```
Port of `mobile/src/data/cache/todayFallback.ts`: `daily[0]` is "today"; a row is "real" when `kcal_consumed > 0` or `protein_g > 0`. Falls back to the first real row after `daily[0]` (`stale: true`); if none real, returns `daily.first` with `stale: false`.

```swift
@Observable @MainActor
public final class TodayViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, empty, error(String) }
    public private(set) var phase: Phase = .idle
    public private(set) var morning: MorningResponse?
    public private(set) var gate: GateResponse?
    public private(set) var recovery: [RecoveryDay] = []
    public private(set) var fetchedAt: Date?
    public private(set) var hubReachable = true
    public init(provider: any HealthDataProvider, cache: OfflineCache)
    public var verdict: VerdictParts { get }
    public var readiness: Double? { get }        // latest recovery day's readinessScore
    public var chips: [TodayChip] { get }
    public func load() async
    public func refresh() async
}
```
Phase machine: `load()` restores from cache (`phase = .loaded` if cached `morning` exists), then always calls live fetch. On live success: `phase = .empty` **iff** `verdict == nil && recovery.isEmpty`, else `.loaded`. On live failure: `hubReachable = false`; if `morning` is still `nil` → `.error(message)`; else the cached `.loaded` state is kept — **a live failure never regresses a populated screen**. `refresh()` skips the cache-restore step. A cancelled fetch (`Task.isCancelled`, e.g. a tab switch mid-load) is **not** a failure: `hubReachable` is left untouched and `phase` returns to `.idle` (if it was `.loading`) so `TodayView.task` reloads on the next appearance. Chip ids/order (fixed): **`hrv, rhr, sleep, steps`**, from `latestRecovery` (max by date) for hrv/rhr/sleep and `resolveTodayRow(gate.daily)` for steps; `hrv.sourceMissing = !caps.contains(.hrvRMSSD)`, `sleep.sourceMissing = !caps.contains(.garminSleepScore)`, rhr/steps never source-missing on the hub provider.

`TodayView`: `public init(model: TodayViewModel, onOpenConnection: @escaping () -> Void)`. `VerdictHeroView`: `public init(verdict: VerdictParts, readiness: Double?, readinessMissing: Bool)` — reveals on **every** `onAppear`, resets on `onDisappear` (fires on every open/return, not just first load — feel diagnosis 2026-09-03). Ruling: `readiness.map { revealed ? $0 : 0 }` — a genuinely `nil` score stays `nil` through the whole reveal (never coerced to a literal `0`, which would flash "0" before "No data yet" settles); only a real score counts up from 0.

```swift
@Observable @MainActor
public final class ConnectionSheetModel {
    public var baseURL: String
    public var token: String
    public var status: ConnectionTestResult?
    public var testing = false
    public init(store: ConnectionConfigStore)
    public func test() async
    public func save() throws -> ConnectionConfig?
}
public struct ConnectionSheet: View { public init(store: ConnectionConfigStore, onSaved: @escaping (ConnectionConfig) -> Void) }
```
Validation (`candidate`): trims `baseURL`/`token` with `.whitespacesAndNewlines` (a terminal-pasted token often carries a trailing `\n`), requires scheme `http`/`https`, **non-empty** `host()` (bare `"https://:8000"` has `host() == ""`, not `nil` — checked explicitly), non-empty token. `test()` short-circuits to `.other(...)` synchronously, **no network call**, when `candidate == nil`. iOS-only modifiers (`.keyboardType`, `.textInputAutocapitalization`) wrapped `#if os(iOS) ... #else self #endif` since `swift test` builds against the macOS host.

## 9. App

```swift
@Observable @MainActor
final class AppEnvironment {
    let secrets: any SecretStore
    let cache: OfflineCache
    let prefs: PrefStore
    var providerStore: ProviderStore?
    var needsConnection = false
    init(secrets: any SecretStore = KeychainStore(), inMemory: Bool = false) throws
    func boot() throws
    func apply(_ config: ConnectionConfig)
}
```
Hub-only bootstrap: `apply` always constructs `HubDataProvider` — `MockDataProvider` never appears here. `inMemory: true` routes `cache`/`prefs` through `AppDatabase.inMemory()` for tests.

`RootTabView` (`@Bindable var env: AppEnvironment`): `TodayViewModel` created inside a SwiftUI `.task { todayModel = TodayViewModel(...) }`, **never** `DispatchQueue.main.async`. "Recovery" tab is a W2 placeholder.

`AppDelegate` (DEBUG-only): on `UIScene.didActivateNotification`, creates a `TouchIndicatorWindow` (passthrough — `hitTest` always `nil`, never owns a touch) and attaches `TouchObserverRecognizer` to the scene's key window to mirror touches into it. Why: a `hitTest`-`nil` window never receives `sendEvent`, and **iOS 27 SwiftUI ignores `NSPrincipalClass`** (`UIApplication.shared` is `SwiftUIApplication`, proven by a hosted test), so a custom `UIApplication` subclass isn't an option. Runtime wiring checked by `touchOverlayIsWiredToTheKeyWindow` (`AppTests/AppSmokeTests.swift`), not by reading code.

## 10. Build / test / tooling

- `xcodegen generate` after **any** new file under `App/`/`AppTests/`; commit the regenerated `project.pbxproj`. SwiftPM sources are globbed automatically, but run it anyway — a build can "succeed" while silently excluding a new file.
- **`App/Info.plist` is GENERATED from `project.yml`'s `targets.JournalInsight.info.properties` — never hand-edit it.** `UIUserInterfaceStyle`, ATS local networking, URL schemes all live in `project.yml`.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` prefix on every `xcodebuild`/`xcodegen` call until Xcode 27 GA is installed and selected.
- Package tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/<Name>`.
- App/simulator: `DEVELOPER_DIR=.../Xcode.app/Contents/Developer xcodebuild -project JournalInsight.xcodeproj -scheme JournalInsight -destination 'platform=iOS Simulator, name=iPhone 17 Pro' build|test`.
- Device: `xcodebuild ... -destination 'platform=iOS,name=<device>' -allowProvisioningUpdates build`, then `xcrun devicectl device install app --device <udid> <path>.app` + `devicectl device process launch` (or Xcode ▶ Run).
- Xcode 16+ ships app code in a separate debug dylib — `strings`/`nm` on `JournalInsight.app` show nothing useful; code lives in `JournalInsight.debug.dylib`.
- `JournalInsightTests` (`bundle.unit-test`) currently reports target platform ios17.0 in build output — this is the Swift Testing library's own triple, not the app's/project's `27.0` deployment target, and needs no W2+ follow-up.

## 11. CLAUDE.md §Rules (verbatim)

Rules live only in `CLAUDE.md` at the repo root (injected in every worktree). Do not copy them here.

## 12. W1 gate results

**PENDING — Toby's device gate (Task 17 Steps 1–4).** Link once written: `HealthTraining/output/feel/ios/w1/REPORT.md`. Simulator smoke: app boots to the Connection gate, screenshot at `HealthTraining/output/feel/ios/w1/simulator-today.png`. Live-hub Today round trip + feel recordings land in the same directory (untracked; `REPORT.md` lists paths).

Toby's checklist (device **"Toby's iPhone"**, iPhone 17 Pro Max):

**Step 1 — one-time manual (agent cannot do these):** (1) Install Xcode 27 GA to `/Applications` first (today `/Applications/Xcode.app` is still 26.6); until then use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, which builds+tests fine. Once GA is installed, `sudo xcode-select -s /Applications/Xcode.app`. (2) Xcode → Settings → Accounts: paid Apple ID signed in; set the Team in Signing & Capabilities (XcodeGen leaves `DEVELOPMENT_TEAM` empty — after choosing it once, copy the team id into `project.yml` so regeneration keeps it). (3) iPhone: Developer Mode on (Settings → Privacy & Security), connected by cable or Wi-Fi pairing. (4) Hub reachable on the LAN: `start_api.sh` binds `0.0.0.0` (plan of record R0); note the Mac's LAN IP via `ipconfig getifaddr en0`.

**Step 2 — install and connect:** build+run on device; on the phone: Connection sheet → `http://<mac-ip>:8000` + token → Test → "Connected. Last sync: …" → Save. Expected: Today renders the same numbers as the RN app on the Fold (verdict word, readiness, HRV/RHR/sleep/steps). Screenshot both phones side by side into `output/feel/ios/w1/`.

**Step 3 — offline fallback:** Wi-Fi off → pull to refresh → expected staleness banner "Showing data from HH:mm — hub unreachable", numbers stay. Wi-Fi on → pull → banner disappears. Note the result in REPORT.md.

**Step 4 — feel recording (protocol Task 4):** record (a) press-and-hold + release on the HRV chip, (b) pull-to-refresh, (c) leave the tab and return (reveal), (d) tab switch Today ↔ Recovery. AirDrop into `output/feel/ios/w1/`; extract frames at 120 fps; press-in must be ≤ 12 frames after the touch ring appears (≥8% pixel change inside the chip's crop). Write `REPORT.md` with the interaction→file→frames→pass/fail table, leaving "Toby's verdict" for him. Expected: press-in PASS; tab switch EXPECTED to FAIL (hard cut — W2 story).

## 13. Deferred minors (pick up in W2+)

- Route strings (`/health`, `/api/v1/ingestion/status`, etc.) duplicated as literals across `HubDataProvider` and `ConnectionTest` in JIHub — no shared constant.
- `HubDataProviderTests.fixtureData` builds its path via `#filePath`-relative traversal instead of a bundle resource.
- `AppDatabase.open`'s `PRAGMA journal_mode = WAL` is redundant — `DatabasePool` already opens in WAL mode by default.
- `AppDatabase.inMemory()`'s temp files are never cleaned up after a test run.
- `readinessBand`/`gaugeAngle`/`readinessGoMin`/`readinessWarnMin` are bare top-level symbols in JIDesign, not namespaced.
- `SkeletonBlock`'s pulse animation resets to `false` then `true` on every re-mount instead of preserving phase.
- `Surface`'s level switch `default:` silently absorbs any invalid `level` int by falling back to `surface` — no assertion.
- `JIFeatures` now genuinely uses its `JIHub`/`JIDesign` package deps (previously flagged as possibly unused).
- `TodayViewModel.fetchLive()` has no generation/token guard against overlapping `load()`/`refresh()` calls racing each other.
- `TodayViewModel.describe(_:)`'s fallback case produces a generic `"Hub error: \(e)"` string for any unmatched `HubError`.
- `TodayView` declares `@Bindable private var model` but never uses a `$model` binding.
- `JIFeaturesTests` (`ConnectionSheetModelTests`) relies on JIHub's `InMemorySecretStore` reaching it transitively rather than a JIFeatures-local double.
- `AppDelegate` stores the overlay window in a single scalar `var window: UIWindow?` — multi-scene would overwrite it.
- The `UIScene.didActivateNotification` observer registered in `AppDelegate` is never removed.
- `AppSmokeTests.appTargetTestsRun` is a trivial `1 + 1 == 2` placeholder assertion.
- Running the app test bundle prints XCTest's "Executed 0 tests" next to the real Swift Testing summary — cosmetic noise from the two frameworks coexisting.
- Commit `2f83d64` has its `Co-Authored-By` trailer on the subject line instead of the body (verified via `git show --stat 2f83d64`).

