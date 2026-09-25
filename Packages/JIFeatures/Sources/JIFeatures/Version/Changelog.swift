import Foundation

// W5a-L4 (P-version). Verbatim port of `mobile/src/version/changelog.ts` (`APP_NAME`,
// `APP_VERSION`, `CHANGELOG` — every entry, every item, unchanged), plus ONE leading "Swift
// native" entry for this app. `rnEntries` is frozen at the RN oracle's v1.18.2 and is checked
// byte-exact by `VersionViewModelTests` (node-computed digest); new Swift releases prepend to
// `swiftEntries`, never edit the RN block. The crash-log section of RN's screen is descoped
// (Android Kotlin module — BACKLOG B-row).

/// One release note. `id` is the version string (unique per entry, RN keys the list by it).
public nonisolated struct ChangelogEntry: Sendable, Equatable, Identifiable, Codable {
    public var id: String { version }
    public let version: String
    /// YYYY-MM-DD
    public let date: String
    public let title: String
    public let items: [String]
    public init(version: String, date: String, title: String, items: [String]) {
        self.version = version; self.date = date; self.title = title; self.items = items
    }
}

public nonisolated enum Changelog {
    /// RN `APP_NAME`.
    public static let appName = "JournalInsight"
    /// RN `APP_VERSION` = `CHANGELOG[0].version` — the frozen oracle build this port mirrors.
    public static let rnAppVersion: String = rnEntries[0].version
    /// `PrefStore` key of the "last version the About & version screen was opened for" marker
    /// (RN `versionSeen.ts` `STORAGE_KEY`, kept verbatim so the semantics are recognisable).
    public static let seenPrefKey = "ht.version.lastSeen.v1"

    /// The one entry this port adds. Its version is the Swift app line, not an RN build number.
    public static let swiftNativeEntry = ChangelogEntry(
        version: "2.0.0-beta.1",
        date: "2026-09-17",
        title: "Swift native (Waves W0–W5a)",
        items: [
            "JournalInsight is now a native SwiftUI app for iPhone (iOS 27) and Apple Watch — the React Native build is frozen at 1.18.2 as the behavioral reference every screen is checked against",
            "Today, Recovery, Energy, Nutrition, Training, Mind, Journal, Goals, KPIs, backup & restore, and the morning gate carried over module by module, with the same numbers and the same copy",
            "Apple Health is a data source: HRV, resting heart rate, sleep and steps read on-device, with a one-time Garmin history backload",
            "Settings is a real screen: Connection, Preferences, Data and Advanced groups, with Appearance, Reminders, Edit Today and this version screen",
        ]
    )

    // W-FIX3 BUG-43: the changelog stopped at 17 Sep. One entry per Swift milestone since, newest
    // first. The installed release is `2.0.0` (the About screen marks the entry whose version
    // equals `CFBundleShortVersionString` "Installed"); the earlier Swift milestones are its
    // pre-releases, so every id stays unique.
    public static let fixesEntry = ChangelogEntry(
        version: "2.0.0",
        date: "2026-09-25",
        title: "Regression fixes",
        items: [
            "Appearance works everywhere: System, Light and Dark follow your choice across the app and in open sheets, and your accent colour tints every screen",
            "Goals, KPIs, Today and More agree with each other — the same numbers and the same KPI set on every screen that shows them",
            "Export starts with Journal, Mind and WHO-5 ticked, and the goal date is picked from a calendar",
            "Large text sizes: long titles and subtitles wrap instead of being cut off, and Settings icons no longer run into their labels",
        ]
    )

    public static let morningFlowEntry = ChangelogEntry(
        version: "2.0.0-beta.3",
        date: "2026-09-23",
        title: "Morning flow and the Apple gate",
        items: [
            "Today leads with the morning decision: why the gate says what it says, and a way to override it",
            "The readiness gate can run on Apple Watch data alone",
            "Last night's Apple Health data reaches your hub when you open the app",
        ]
    )

    public static let nativeLookEntry = ChangelogEntry(
        version: "2.0.0-beta.2",
        date: "2026-09-22",
        title: "Native look, widgets and a Settings menu",
        items: [
            "Every screen uses the iOS look: system lists, controls and typography",
            "Home Screen widgets",
            "Settings is a menu of smaller screens instead of one long page",
            "Workouts can be sent to Apple Watch, and backloaded workouts carry their route and heart rate",
        ]
    )

    public static let swiftEntries: [ChangelogEntry] = [fixesEntry, morningFlowEntry, nativeLookEntry, swiftNativeEntry]

    /// What the screen renders: Swift entries first, then every RN entry (newest first).
    public static let entries: [ChangelogEntry] = swiftEntries + rnEntries

    /// Verbatim `CHANGELOG` from `mobile/src/version/changelog.ts` @ v1.18.2. Do not edit.
    public static let rnEntries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "1.18.2",
            date: "2026-09-08",
            title: "Scroll crash fix",
            items: [
                "Fixed a force-close (\"JournalInsight keeps closing\") that happened when you scrolled to the top or bottom of a screen — the rubber-band edge effect crashed the app on the phone",
            ]
        ),
        ChangelogEntry(
            version: "1.18.1",
            date: "2026-09-08",
            title: "Snow-leopard fixes",
            items: [
                "Today's stat chips and the home-screen KPI widget showed the oldest day of the week instead of today — fixed",
                "The four KPI tiles on Today are the same height again (the Sleep score label no longer wraps)",
                "The weekly nutrition-gate note (\"not enough tracked days\") moved to its own card on the readiness rationale — it never described the daily verdict",
                "Recovery: the Garmin sleep score leads again (the computed score is a shadow line), the readiness gauge card hugs the arc with its detail link inside, and trend arrows point the right way",
                "The \"Mock data\" banner no longer swallows every tap while it is visible",
                "Deep links and widget taps from a cold start open the right screen instead of \"Unmatched Route\"",
                "Backup export no longer crashes on a fresh install",
                "Animations follow Android's animator duration scale (Developer options), so a faster system setting speeds up the app too",
                "Version screen: a \"Last crash\" section appears after a force-close, with Share and Clear",
            ]
        ),
        ChangelogEntry(
            version: "1.18.0",
            date: "2026-09-08",
            title: "Your KPIs",
            items: [
                "You can now choose which KPIs show up on Today and Recovery, and put them in the order you care about — a new \"My KPIs\" screen in Settings",
                "Today's stat-chip row now shows your top 4 chosen KPIs instead of a fixed HRV/RHR/Sleep/Steps set",
                "Recovery's cards now show only the KPIs you've kept selected, in Recovery's own fixed order",
                "\"Reset to defaults\" in My KPIs restores the original Today and Recovery selections in one tap",
                "A new home-screen widget shows your #1 KPI — its current value, a trend arrow, and when it last updated — right on your Android home screen",
                "Tapping the KPI widget opens that metric's full detail screen, with a working back button, even from a cold start",
                "Your KPI choices and order are included in local backups, same as your other on-device preferences",
            ]
        ),
        ChangelogEntry(
            version: "1.17.0",
            date: "2026-09-08",
            title: "Gate challenges",
            items: [
                "Gate challenges can now be edited after creation — fix the title, hypothesis, target, start date, or session filter without having to delete and start over",
                "Completing a challenge now goes through a confirm dialog instead of a silent tap, with room to leave a closing note",
                "Every challenge now shows a live execution score (percent of sessions completed) plus an \"ahead of pace / on pace / behind pace\" read against a weekly cadence",
                "Closing notes now save to the hub and sync across devices, instead of staying stuck on the one phone that wrote them — your old on-device-only notes still show up, labelled as such, until you write a new one",
                "Challenges with zero recorded sessions and never completed can now be deleted outright; anything with real history is archived instead, never erased",
                "Today's gate-challenge banner now shows the live score and offers a one-tap \"Mark complete\" once you've hit the target",
                "A confirmed bug is fixed: a completed or archived challenge's session count could keep silently climbing from activity logged after it closed — it's frozen at close-out now",
            ]
        ),
        ChangelogEntry(
            version: "1.16.0",
            date: "2026-09-07",
            title: "Haptics",
            items: [
                "Every vibration in the app — button presses, save confirmations, verdict reveals, drag-and-drop, gate-status changes — now fires through your phone's richer vibration hardware where it's available, instead of one generic buzz for everything",
                "A press and a save now feel distinctly different from each other, instead of the identical tap they used to share",
                "A new Haptics intensity slider in Settings lets you dial every vibration from a faint tap up to full strength, with a felt preview and click-stops at 20/40/60/80/100%",
                "Older phones without that richer vibration hardware automatically fall back to the same vibration style the app already used — nothing is lost on basic devices",
                "The existing Haptics Off switch still silences every vibration outright, independent of the new slider",
                "The gate status \"changed\" vibration is now one smooth two-pulse effect instead of two separate taps that could drift apart in timing",
                "Intensity starts at 100% by default, so upgrading doesn't change how anything feels until you move the new slider yourself",
            ]
        ),
        ChangelogEntry(
            version: "1.15.0",
            date: "2026-09-07",
            title: "Redesign",
            items: [
                "Sub-screens that could open blank (a KPI drill-down among them) now consistently show their content — a wrapper on the screen body was collapsing to zero size",
                "Every card now sits on a visibly separated surface — a soft shadow and a tint step between page, card, and nested content, instead of a flat panel with a thin outline",
                "On Android 12+, the app's accent color can now follow your wallpaper (Material You / dynamic color), with a Color source toggle in Appearance to switch back to a fixed accent",
                "Light mode has been redesigned across the app rather than left as an afterthought of dark mode",
                "The tab bar and screen headers are now real frosted glass — content blurs and scrolls behind them instead of hiding under a solid bar",
                "Today's tiles, Settings, Training, Recovery and Energy got a composition pass — clearer section grouping, a page title on Training, tighter grouping between the readiness gauge and its detail link, and hairlines separating Energy's Raw/Adj/Deficit chips",
                "Goals, KPIs, challenges and the decision log now read and write to a local-first store first, syncing to the server in the background instead of blocking on it",
                "A home-screen widget now shows today's verdict without opening the app",
            ]
        ),
        ChangelogEntry(
            version: "1.14.0",
            date: "2026-09-06",
            title: "Feel fix",
            items: [
                "The verdict card (and every Yes/Skip, tile, row and stepper press app-wide) now visibly holds its pressed look for a beat instead of sometimes showing nothing at all — a real Fold recording had caught the verdict card changing 0 pixels on a tap",
                "Cold start now shows a loading glyph on both startup gates instead of two back-to-back blank screens — the app no longer looks stuck between launch and first content",
                "Energy, Recovery, Training and Nutrition now paint your last-known numbers immediately on a cold start instead of sitting on a loading state while the network catches up",
                "That loading glyph only appears after a short delay, so a fast reopen never flashes it for no reason",
                "Nutrition's first scroll of the session no longer stalls — its rubber-band edge gesture was staying armed on every other tab and its meal list/chart were recomputing on renders that didn't touch them",
                "Fixed a regression from the Nutrition fling fix where switching away and back reset your scroll position and remounted the whole screen every time",
                "The tab cross-fade transition (Today / Journal / Energy / etc.) now does a genuine cross-dissolve instead of a hard flash to black mid-switch",
            ]
        ),
        ChangelogEntry(
            version: "1.13.0",
            date: "2026-09-05",
            title: "Smooth",
            items: [
                "Journal and Nutrition now push back with a real rubber-band spring when you scroll past the top or bottom, instead of stopping dead",
                "Nutrition's meal list and chart no longer do the heavy lifting during your first scroll — rows and the intake/TDEE chart are memoized so the initial fling doesn't stall",
                "Reopening the app or switching tabs no longer sits on stale numbers in the background — the app now tells its data layer when it's actually in the foreground, with a 30-60s freshness floor and the next likely tab's data prefetched on focus",
                "Tile drag-and-drop now runs entirely on the shared motion tokens and springs siblings out of the way as you drop, instead of snapping into place",
                "Every animation duration and spring in the app now comes from one token table — nothing is hand-picked per component anymore, including the tab cross-fade and tile physics",
                "Journal search now caps its results list and windows the Calendar/Insights views instead of re-rendering your whole history on every keystroke",
                "The mock-data banner no longer sits on top of the tab title on the unfolded display",
                "Production builds no longer ship console logging",
                "A YAZIO sync that hits an expired token now re-authenticates once and retries instead of failing the whole sync",
            ]
        ),
        ChangelogEntry(
            version: "1.12.1",
            date: "2026-09-05",
            title: "Energy reads the right way round",
            items: [
                "Energy now shows your balance the way you read it: a deficit as a negative number, a surplus as a positive one — the hero, the daily log and the chart markers all agree",
                "Deficit days are coloured by how deep they are (mild and moderate, aggressive, dangerous); surplus days are neutral, never green",
                "The percent chip says Deficit % or Surplus % instead of a bare signed number",
                "Mock data uses the same sign convention as the hub, so switching modes no longer flips the meaning of the numbers",
            ]
        ),
        ChangelogEntry(
            version: "1.12.0",
            date: "2026-09-05",
            title: "Composition",
            items: [
                "Energy now leads with one big number (your 7-day adjusted deficit) and a bar chart of intake vs. TDEE per day, with the raw/×0.85/percent figures as secondary chips — instead of a stack of uppercase labels with nothing to look at",
                "On the unfolded (tablet-width) screen, Energy and Nutrition now use the full width as two real columns (chart + list, or week strip/macro card + meal timeline) instead of one narrow stretched column with empty space on the side",
                "The Nutrition macro card's protein and fat values no longer go missing or float loose in the middle of the card — carbs, protein and fat now sit in one aligned grid with the ring",
                "Every tab now tells you plainly when you're looking at sample data instead of your real numbers, with a tap-through straight to the hub connection settings",
                "Sample data now always starts from today and counts back a week, instead of showing a fixed date range that drifted further into the past the longer you'd had the app installed",
                "App startup no longer waits on the security vault before it starts loading your cached screen — the two now run at the same time, so a cold reopen reaches your last screen sooner",
                "Switching into Today from Energy or Journal is smoother — the incoming screen no longer replaces most of the display in a single frame",
            ]
        ),
        ChangelogEntry(
            version: "1.11.0",
            date: "2026-09-05",
            title: "Device truth",
            items: [
                "Tapping the verdict card, Yes/Skip, tiles, tab buttons and rows now shows a real press-in the instant your thumb lands, instead of nothing happening until the screen changes",
                "Switching tabs now genuinely cross-fades over the configured ~300ms — measured device recordings showed this used to render as a hard cut",
                "Killing the app and reopening it shows your last screen instantly from a persisted cache instead of a blank reload while it re-fetches everything",
                "After clearing app data, sections now appear progressively as each one's data arrives instead of one long skeleton followed by everything popping in at once",
                "Today and Nutrition no longer flash 0 kcal / 0 g when cached or the previous day's data exists — a cached value is now labelled as such instead of zeroed",
                "The staleness banner only says \"Offline\" when the hub truly can't be reached; otherwise it correctly reads \"Stale · synced HH:MM · tap to sync\"",
                "The gate-rationale \"What's moving the verdict\" contributor breakdown now loads from the live 28-day payload and offers a Retry instead of failing permanently, and logging a meal that fails now says whether it was a network problem or something the hub rejected",
                "Cards now sit on a visible depth ramp (background → card → nested → control) and Today's readiness ring is a single open ring with a gap-and-dot reveal that sweeps clockwise as your score builds",
            ]
        ),
        ChangelogEntry(
            version: "1.10.1",
            date: "2026-09-05",
            title: "Hotfix: collapsed tab bar, week strip and readiness chips",
            items: [
                "The bottom tab bar had quietly collapsed into a tiny cluster of icons crammed in one corner of the pill instead of spanning it evenly — fixed at the root, so it and every other row-style button lay out correctly again",
                "Today and Training's day-of-week strip had shrunk to a tight column of cells instead of spanning the card — back to filling it properly",
                "The readiness score's HRV / RHR / Sleep / Steps chips had stopped showing any label or value, rendering as empty outlines — they're back, and tapping HRV opens its drill-down again",
                "A whole-app sweep for the same layout bug across every button and row confirmed nothing else was silently affected",
            ]
        ),
        ChangelogEntry(
            version: "1.10.0",
            date: "2026-09-04",
            title: "Every tap responds (Wave H1)",
            items: [
                "Press feedback now reaches every remaining button and row that was still invisible under your thumb — steppers, chevrons, drill-in rows and the last holdout controls across the whole app all scale and tap back now",
                "Tabs, drag-and-drop, and gate changes each get their own distinct haptic pattern instead of sharing one generic buzz — a soft tick for routine updates, a genuine double pulse when a verdict changes, one strong pulse on a fail",
                "Reduce-motion (in system settings) now actually switches off the spring animation on every button press and animated number in the app, not just a handful of screens",
                "Undoing a gate response, backing off a logged set, or removing a food you just logged no longer happens on a single accidental tap — each now needs a deliberate second confirm, matching how easy it stays to log something in the first place",
                "Touch targets across the app grew to a full 48pt, so small buttons are easier to hit without your thumb catching a neighbour",
                "The status-bar clock no longer overlaps content on Journal, Recovery, or Nutrition — the same fix Today already had now covers all three",
            ]
        ),
        ChangelogEntry(
            version: "1.9.0",
            date: "2026-09-04",
            title: "Fixing what was visibly broken (Wave G0)",
            items: [
                "Today no longer flashes a stale, wrong-day readiness verdict for several seconds after a cold start — it now holds its loading state until the real verdict for today is ready",
                "Training's readiness card was stuck showing a verdict from over a week ago even while Today had already moved on; it now reads the exact same up-to-date verdict as Today",
                "Today's cards no longer scroll up underneath the status bar clock — the top of the screen is reserved space at every scroll position, not just on first paint",
                "Nutrition's floating + Log button no longer covers the last meal row's calorie figure when you land on the screen fresh — it's docked below your food list instead of floating over it",
                "Tapping into the Weight KPI drill-down used to show a bare \"--\" with no chart and no way back; it now shows the same weight and trend as the Today tile, with a working back control",
                "The Energy tab finally has a title — every other tab already opened with one, Energy was the odd one out",
            ]
        ),
        ChangelogEntry(
            version: "1.8.1",
            date: "2026-09-03",
            title: "Feel follow-ups & vault-key portability (Wave F2.1)",
            items: [
                "The tab bar now has its own quiet haptic tick when you switch tabs, matching the feel language the rest of the app already speaks",
                "Press feedback reaches the buttons and rows that were still dead under your thumb — backup/restore, sync, verdict and header controls, day and entry rows across Energy, Journal, Nutrition and Recovery — every one now scales and taps back",
                "Backups now carry your encrypted journal key itself, wrapped under a passphrase you set — a fresh install can restore your encrypted rows instead of leaving them locked out forever",
                "The encrypted check-in fields migration lands and runs once on upgrade, unnoticed unless something goes wrong",
            ]
        ),
        ChangelogEntry(
            version: "1.8.0",
            date: "2026-09-01",
            title: "Choreography, haptics & identity (Wave F2)",
            items: [
                "KPI charts are finally touchable: drag across any trend line to scrub a value tooltip point by point, with real date and unit axis labels — and if a fetch fails you now see an honest error state instead of a silently missing trend arrow",
                "The app got a sense of touch: verdict reveals, goal and PR moments, saves, steppers and the day strip each speak their own haptic language (and it's all switchable off in Settings → Feel)",
                "Scores and rings no longer just appear — they count up and sweep in together as one deliberate reveal, then hold still; celebrations ride a proper overshoot spring",
                "Tapping a KPI tile now morphs into its drill-down instead of hard-cutting, two-pane swaps cross-fade, and skeletons shimmer while they load (Journal, Mind and the Health Connect screens got real loading states at all)",
                "Light theme now actually reaches every screen, sheet and the tab bar — previously ~150 hardcoded dark colors ignored your Appearance setting",
                "A new visual identity layer: material blur depth on the hero and tiles, a visible data-freshness dot per tile, an insight voice setting (terse / encouraging / analytical), a numeric streak with an ignition animation, a weekly weight-trend recap card, and a shareable milestone export",
                "Journal's first screen is now a clean capture view (streak, behavior cards, prompts, new entry) — search and your entry library begin one scroll below, so nothing hides behind the floating tab bar anymore",
            ]
        ),
        ChangelogEntry(
            version: "1.7.1",
            date: "2026-09-01",
            title: "Fixing what F1 broke on Today",
            items: [
                "The 1.7.0 release (Wave F1) broke Today's layout on-device: a duplicate native header left a dead gap above the screen, the gate's Yes button went invisible (near-black text on a near-black background), and the streak widget's row bled over into the tile dock below it — all three traced back to one animation bug shared by every tappable card and button in that release",
                "Fixed at the root and re-verified on-device: headers, button contrast and row layouts are back to how they were before F1, with new tests in place so this class of bug gets caught before it ships next time",
            ]
        ),
        ChangelogEntry(
            version: "1.7.0",
            date: "2026-09-01",
            title: "Starting to feel alive (Wave F1)",
            items: [
                "Reorder Today yourself: long-press any tile to jiggle it loose, drag it where you want, release to save — no more arrow-tapping in a separate edit screen",
                "KPI drill-down screens were quietly ignoring the date range you picked — 7, 28, 90 and 365 days all showed the same week's numbers. Fixed at the root, plus a small 'MOCK DATA' / 'HUB CONNECTED' badge so it's never ambiguous which one you're looking at",
                "Buttons, tiles and cards finally push back when you touch them — a quick scale-and-fade instead of feeling dead under your thumb",
                "Fixed: swiping a Journal behavior card no longer fights with the screen's vertical scroll — a stray touch used to get grabbed the wrong way",
            ]
        ),
        ChangelogEntry(
            version: "1.6.0",
            date: "2026-09-01",
            title: "Health Connect groundwork & your safety net (Wave R6a)",
            items: [
                "Back up everything, restore it anytime: a new Settings screen exports your full local data — journal, mood check-ins, goals, gate overrides, weekly plan and more — into one file, and restores it with a before/after row-count preview and a corruption check before anything gets overwritten",
                "A new Health Connect screen in Settings lays the groundwork for pulling in Android health data — see exactly what it would read and grant permission ahead of time; nothing changes in your numbers yet, this is the foundation the next wave builds on",
                "Your encrypted journal stays encrypted even inside a backup file — verified, not just assumed",
            ]
        ),
        ChangelogEntry(
            version: "1.5.0",
            date: "2026-09-01",
            title: "Made for the fold (Wave R5)",
            items: [
                "Unfold your Z Fold 8 and Recovery goes two-pane — the metric list stays on one side while its detail opens beside it, so you're never pushed to a new screen and back",
                "A new Session Coach screen for training days: live heart rate tracked against the 175 safety cap, with a load bar and a plain-language cue the moment you're approaching, at, or past it (shows a clear 'not available' state for now — live heart-rate streaming has no real data source wired up yet)",
                "Swipeable behavior cards on Journal surface the day's two standing habits — no pre-workout fueling, reflux-safe carbs — swipe or tap Yes/No to log either in seconds",
                "Reduced-motion support throughout: the swipe gesture steps aside and the Yes/No buttons take over",
            ]
        ),
        ChangelogEntry(
            version: "1.4.0",
            date: "2026-09-01",
            title: "Your journal, locked to your phone (Wave R4-lite)",
            items: [
                "Journal entries and check-in notes are now encrypted at rest in a personal vault — unlocked automatically on this phone, with no cloud key involved",
                "Search your journal by text, mood or tag, and browse entries on a calendar you can scope to a week, two weeks, month or year",
                "Journaling insights go deeper: your preferred time of day, your longest session, weekly trends — plus a small celebration the first time you cross a new streak milestone",
                "Light mode has arrived, alongside a personal accent color, adjustable text size, and a name for your greeting on Today",
                "Goals now show overdue vs. on-track at a glance with a real calendar date picker; export is a pick-what-you-want checklist (check-ins, events, WHO-5, goals) as CSV or JSON",
                "Workout reminders are per-weekday now — a different time for Monday than for Thursday, set independently",
                "The Mind tab's check-in summary reads as an observation, never a verdict — GO/REDUCED/RED language stays where it belongs, on the readiness card",
            ]
        ),
        ChangelogEntry(
            version: "1.3.1",
            date: "2026-08-31",
            title: "Food logging & a Today that's yours (Wave R3.5)",
            items: [
                "'+ Log' is live: log food from the app via meal templates or manual entry, plus weigh-in — with honest error states when the hub declines (no fake success)",
                "The readiness arc now shows its quality bands, and tapping it breaks the score into its contributors",
                "Day-strip navigation on Nutrition and Training, macro mini-rings, and per-item macros finally rendered",
                "A small celebration moment when a goal milestone lands, and the Overview trend projection is now honest about gaining phases",
                "Customizable Today: pick and order your own zero-tap tile set (the verdict hero stays fixed)",
                "One ACWR everywhere: the pipeline's analyze step now reads the restored training-load history instead of computing its own",
            ]
        ),
        ChangelogEntry(
            version: "1.3.0",
            date: "2026-08-31",
            title: "Self-sufficient compute (Wave R3b)",
            items: [
                "The morning gate now computes on your phone — verdicts work offline, honor your threshold overrides, and carry a small 'computed on device' marker when local",
                "Every metric is a door: tap any tile or chip for its drill-down — full-year history, 7/28/90/365-day ranges, personal-baseline band, and the cited threshold behind it",
                "Gate challenges are yours to define: create, track and archive experiments in-app (the HR ≤175 safety floor is fixed and not configurable, by design)",
                "Energy and weekly-recommendation numbers compute client-side from raw data, parity-checked against the server in dev builds",
                "Dose-aware notifications: day-3+ warning when the interval gate closes, plus an optional daily dose-log reminder",
                "The backfilled year of history is finally visible — the drill-downs are its first reader",
            ]
        ),
        ChangelogEntry(
            version: "1.2.1",
            date: "2026-08-30",
            title: "Your feedback round (R2.3 + R3a)",
            items: [
                "Readiness is back: a fetch bug silently discarded Garmin's score for months — fixed, 90 days backfilled, Recovery now shows real readiness",
                "Numbers no longer clip vertically (the new numeral font needed matching line metrics)",
                "The rationale screen speaks human — no more raw rule names — and always offers a concrete action",
                "Nutrition: neutral 'kcal remaining' instead of a celebratory green shortfall; week strip counts strict tracked days only",
                "Training: no more NaN reps, one card per lift instead of four duplicates",
                "Goals are real now: a Goals editor backed by a new goals API (weight target corrected to 75 kg — the old 68.5 was a wrong hardcode), every hardcoded target removed",
                "Gate-config editor with live verdict preview, editable KPI thresholds, and the weekly plan finally persists — with separate training-day and rest-day targets",
            ]
        ),
        ChangelogEntry(
            version: "1.2.0",
            date: "2026-08-30",
            title: "Feel, fit & flow (Waves R2.1 + R2.2)",
            items: [
                "Verdict-first Today: the readiness word is the hero, with one insight line naming the day's single biggest lever — a REDUCED day always comes with a concrete action",
                "Everything is tappable now: verdict → full rationale (the gate's rules, suggestions and 3-day trail), tiles → their tabs, day strips → that date, offline banner → sync",
                "Mind check-in one tap from Today, with its own daily reminder; the Journal tab's navigation grid is gone",
                "New design foundation: shared design tokens, reserved verdict colors, tabular numeral typeface",
                "Weight and other big numbers no longer clip on the cover display (deterministic sizing)",
                "Training-load/ACWR restored after 5 months dark, and the recovery screen now carries a real 7-day HRV average",
                "Override reason is a dropdown; sparse trends say how many days they still need instead of drawing misleading charts",
                "Smoother everywhere: no skeleton flashes on tab switches, stable layouts, memoized heavy cards",
                "A small dot on the gear marks a new version until you've seen this screen",
            ]
        ),
        ChangelogEntry(
            version: "1.1.0",
            date: "2026-08-30",
            title: "Control surface (Wave R2)",
            items: [
                "Sync button — trigger a Garmin + YAZIO sync from the phone and watch it through to done",
                "History backfill — pulls up to a year of recovery, energy, nutrition and training history for offline trends",
                "Respond to the morning gate (y / N / override) and rate session feel 1–5 from the phone",
                "Nutrition tab — macro rings, meal timeline, day drill-down, week tracking strip",
                "Training tab — gate detail, week plan, per-lift progression steppers that write back to the hub",
                "Weigh-ins can be pushed to Garmin via the hub (API)",
                "Settings now one tap from Today (gear, top right) — including on error screens",
                "Fixed: system bar overlaying tab buttons, clipped weight numeral, widgets not refreshing after sync, interval count stuck at 1, backfill missing nutrition/training rows",
                "New app identity: name, icon, and this version screen",
            ]
        ),
        ChangelogEntry(
            version: "1.0.0",
            date: "2026-08-29",
            title: "First installable release (Wave R1)",
            items: [
                "Live data from the Mac hub over home Wi-Fi (bearer-token secured)",
                "Offline-first: last-good data cached on the phone, shown when the hub is unreachable",
                "Connection settings with a two-stage connection test (reachability, then auth)",
                "Journal, mood check-ins, goals, reminders and export — the JournalInsight heritage",
            ]
        ),
    ]
}
