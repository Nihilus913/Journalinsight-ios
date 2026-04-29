# Plan 7 — Project Capabilities + Privacy Manifest

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Apple-side artefacts that are required to ship: the iCloud / CloudKit container, the Push Notifications + Background Modes capabilities, the entitlements file, the `PrivacyInfo.xcprivacy` manifest with required-reason API codes, the `vault_log_privacy_required` SwiftLint rule, and a documented checklist for App Store Connect privacy labels and the privacy-policy URL.

**Architecture:** This plan does not modify Swift code. It changes project configuration files and adds a privacy manifest. Several steps are *manual Xcode UI actions* — described as imperative bullet points so a worker (human or agent) can follow them. Steps that *can* be done programmatically use `plutil` and `git apply` patches against `*.entitlements` and `PrivacyInfo.xcprivacy`. CloudKit Dashboard deployment is also a manual checklist item.

**Tech Stack:** Xcode project config, Apple `PrivacyInfo.xcprivacy` schema, App Store Connect privacy labels, SwiftLint custom rules.

**Spec section reference:** §5 (Project capabilities + iOS hardening floor; pre-release security gate items 3, 4, 5, 7, 11).

**Depends on:** No code dependencies. Can run from T0 in parallel with Plan 1.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `JournalInsight/PrivacyInfo.xcprivacy` | Privacy manifest declaring `UserDefaults` (CA92.1) and `FileTimestamp` (C617.1) reasons |
| Create | `JournalInsight/JournalInsight.entitlements` | iCloud (CloudKit), Push Notifications, Background Modes (remote-notifications), aps-environment |
| Modify | `JournalInsight.xcodeproj/project.pbxproj` | Wire `JournalInsight.entitlements` into target build settings |
| Create | `.swiftlint.yml` | Custom rule `vault_log_privacy_required` |
| Create | `docs/release/2026-04-29-cloudkit-deployment.md` | Manual CloudKit Dashboard steps |
| Create | `docs/release/2026-04-29-app-store-privacy-labels.md` | Manual App Store Connect privacy-label checklist |
| Create | `docs/release/2026-04-29-privacy-policy.md` | Privacy policy text (host as static page e.g. GitHub Pages) |

---

## Task 1: PrivacyInfo.xcprivacy

**Files:**
- Create: `JournalInsight/PrivacyInfo.xcprivacy`

- [ ] **Step 1.1: Create the manifest**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 1.2: Add to Xcode target (manual)**

In Xcode:
1. File → Add Files to "JournalInsight"…
2. Select `JournalInsight/PrivacyInfo.xcprivacy`.
3. In the dialog: ensure "JournalInsight" target is checked under "Add to targets".
4. Click Add.

- [ ] **Step 1.3: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED. Xcode validates the manifest at build time — any syntax error surfaces here.

- [ ] **Step 1.4: Commit**

```bash
git add JournalInsight/PrivacyInfo.xcprivacy
git commit -m "feat(privacy): add PrivacyInfo.xcprivacy with UserDefaults and FileTimestamp reasons"
```

---

## Task 2: Entitlements file

**Files:**
- Create: `JournalInsight/JournalInsight.entitlements`

- [ ] **Step 2.1: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.tobias.JournalInsight</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.ubiquity-container-identifiers</key>
    <array/>
    <key>aps-environment</key>
    <string>development</string>
</dict>
</plist>
```

> When preparing a release build: switch `aps-environment` to `production`. The standard pattern is two entitlements files (`JournalInsight.entitlements` for Debug, `JournalInsight.Release.entitlements` for Release) wired through the build settings — but for v1.0 we keep one file and document the swap in the deployment checklist (Task 5).

- [ ] **Step 2.2: Wire entitlements into the target (manual)**

In Xcode:
1. Select the `JournalInsight` project.
2. Select the `JournalInsight` target.
3. Go to "Signing & Capabilities".
4. Click "+ Capability" and add:
   - **iCloud** — check "CloudKit". Click "+" under Containers and create `iCloud.com.tobias.JournalInsight` (or pick the existing one if it was already created in your team).
   - **Push Notifications**.
   - **Background Modes** — check "Remote notifications".
5. Verify the entitlements file at "Build Settings" → "Code Signing Entitlements" is set to `JournalInsight/JournalInsight.entitlements`.

If Xcode created its own entitlements file with a different name, replace its contents with the file from Step 2.1 and delete any duplicates.

- [ ] **Step 2.3: Build succeeds**

```
xcodebuild build -scheme JournalInsight -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: BUILD SUCCEEDED. The simulator build does not actually exercise iCloud (no signed-in account), but capability validation runs at build time.

- [ ] **Step 2.4: Commit**

```bash
git add JournalInsight/JournalInsight.entitlements
git commit -m "feat(capabilities): add iCloud (CloudKit), Push Notifications, Background Modes entitlements"
```

> Note: the `JournalInsight.xcodeproj/project.pbxproj` file will also be modified by Xcode when capabilities are added. Stage and commit it together if it has uncommitted changes after the manual Xcode steps.

---

## Task 3: SwiftLint custom rule for vault logging

**Files:**
- Create: `.swiftlint.yml`

- [ ] **Step 3.1: Create SwiftLint config**

```yaml
# .swiftlint.yml
included:
  - JournalInsight
  - JournalInsightTests
  - JournalInsightUITests

excluded:
  - .claude
  - docs

opt_in_rules:
  - empty_count
  - first_where
  - sorted_first_last

custom_rules:
  vault_log_privacy_required:
    name: "Vault log must include privacy: parameter"
    regex: 'Logger\.(vault|migration|sync|crypto|storage)\s*\.\s*(error|warning|notice|info|debug)\s*\(\s*"[^"]*\\\([^,)]*\)[^"]*"\s*\)'
    message: "Logger calls in vault/migration/sync/crypto/storage paths must use 'privacy: .public' or 'privacy: .private(...)'. Hard CI failure."
    severity: error

  no_try_question_in_vault:
    name: "try? forbidden in vault paths"
    regex: '\btry\?'
    included:
      - JournalInsight/Vault
      - JournalInsight/Migration
      - JournalInsight/Repositories
      - JournalInsight/Storage
    message: "Use try with explicit catch in security-critical paths."
    severity: error

line_length: 200
```

> **Note:** SwiftLint is not currently in the project. Installing it is a separate developer-environment concern; the `.swiftlint.yml` file is checked in regardless so any developer who runs `swiftlint` (or any CI that adds it) gets the enforcement automatically.

- [ ] **Step 3.2: Verify SwiftLint runs locally if installed (optional)**

```
which swiftlint && swiftlint --quiet || echo "(swiftlint not installed — skip)"
```
Expected: either zero violations on the current code base, or "swiftlint not installed".

If installed and any violations are reported, fix them before continuing.

- [ ] **Step 3.3: Commit**

```bash
git add .swiftlint.yml
git commit -m "feat(ci): add SwiftLint config with vault_log_privacy_required and no_try_question_in_vault custom rules"
```

---

## Task 4: CloudKit Dashboard deployment checklist (documentation)

**Files:**
- Create: `docs/release/2026-04-29-cloudkit-deployment.md`

This task does not deploy CloudKit — it documents the manual steps so the release engineer follows the same recipe every release.

- [ ] **Step 4.1: Create checklist**

```markdown
# CloudKit Production Deployment — Release Checklist

**Container:** `iCloud.com.tobias.JournalInsight`
**Owner:** Toby (or the Apple Developer account holder)

## Pre-flight

- [ ] Xcode build of `JournalInsight` against the development environment has run successfully on a device signed into iCloud, AND the dev container shows expected record types in CloudKit Dashboard.
- [ ] All v1.0 SwiftData @Model classes (`JournalEntry`, `Goal`) have appeared as record types in the development environment.

## CloudKit Dashboard steps

1. Visit https://icloud.developer.apple.com/dashboard/.
2. Choose the team / Apple ID associated with this app.
3. Select container `iCloud.com.tobias.JournalInsight`.
4. Open the **Schema** tab.
5. Confirm record types: `CD_JournalEntry`, `CD_Goal` (SwiftData prefixes record types with `CD_`).
6. Confirm fields per record type. `CD_JournalEntry` should include:
   - `CD_id` (String)
   - `CD_date` (Date)
   - `CD_duration` (Double)
   - `CD_bodyCipher` (Bytes)
   - `CD_nonce` (Bytes)
   - `CD_schemaVersion` (Int64)
7. Click **Deploy Schema to Production**. Confirm in the dialog.
8. Wait for deployment to complete (~1–2 minutes).

## Post-deployment

- [ ] Switch `aps-environment` in `JournalInsight.entitlements` from `development` to `production`.
- [ ] Archive a release build in Xcode → Product → Archive.
- [ ] Validate the archive (Organizer → Distribute App → Validate). Validation will reject the build if the schema is not deployed.
- [ ] Upload to App Store Connect.

## Rollback

If a schema field needs to change after deployment, CloudKit treats the production schema as immutable for *removal* of fields. Always *add* new fields (with defaults) — never remove. To rename, add a new field and migrate data via app code.
```

- [ ] **Step 4.2: Commit**

```bash
mkdir -p docs/release
git add docs/release/2026-04-29-cloudkit-deployment.md
git commit -m "docs(release): CloudKit Dashboard production deployment checklist"
```

---

## Task 5: App Store Connect privacy labels

**Files:**
- Create: `docs/release/2026-04-29-app-store-privacy-labels.md`

- [ ] **Step 5.1: Create checklist**

```markdown
# App Store Connect Privacy Labels — v1.0

Submit these answers in App Store Connect → JournalInsight → App Privacy.

## Data Collection

**Question:** Do you or your third-party partners collect data from this app?

→ **Yes** (we collect data via iCloud sync, even though it's encrypted client-side).

## Data Types

| Category | Type | Used for | Linked to user | Used to track |
|---|---|---|---|---|
| User Content | Other User Content (journal entries) | App Functionality | **Yes** (Apple ID) | No |
| User Content | Other User Content (mood, tags) | App Functionality | **Yes** (Apple ID) | No |

> Notes:
> - "Linked to user" = Yes because iCloud sync is keyed to the Apple ID even though the content is end-to-end encrypted from Apple's perspective.
> - "Used to track" = No — we have no analytics, no advertising SDKs, no third-party services.
> - Mood is *not* "Health & Fitness" data type — Apple's category descriptions reserve that for clinical health records. Mood as part of personal journaling is "Other User Content."

## Tracking

**Question:** Do you or your partners use the data described above to track users?

→ **No.**

## Statement

In the "Privacy Practices" public string, declare: *"Your journal is encrypted end-to-end on your device with a key stored in iCloud Keychain. Apple sees only ciphertext; we have no access to your entries."*
```

- [ ] **Step 5.2: Commit**

```bash
git add docs/release/2026-04-29-app-store-privacy-labels.md
git commit -m "docs(release): App Store Connect privacy labels checklist"
```

---

## Task 6: Privacy Policy text + hosting plan

**Files:**
- Create: `docs/release/2026-04-29-privacy-policy.md`

The privacy policy URL is a hard App Store gate. Even though Plan 6 dropped the in-app About link, App Store Connect requires a publicly reachable URL.

- [ ] **Step 6.1: Create policy text**

```markdown
# JournalInsight Privacy Policy

**Effective:** 2026-04-29

## What we collect

JournalInsight stores your journal entries — text, mood, tags, dates, and durations — on your device using SwiftData.

## What we share

Nothing.

JournalInsight has no servers, no analytics, no advertising, and no third-party SDKs. We never see your data.

## iCloud Sync

If you are signed into iCloud, JournalInsight uses Apple's CloudKit private database to sync your encrypted journal between your devices. The encryption key is stored in iCloud Keychain on your devices. **Apple sees only encrypted data.** This is sometimes called "end-to-end encryption."

If you sign out of iCloud, sync stops and your data stays only on the current device.

## Backups

If you back up your iPhone or iPad to a Mac, your encrypted journal store is included in the backup. The encryption applies to backup as well — anyone who gains access to a backup file cannot read your entries without your device biometrics or passcode.

## Exports

If you use the in-app Export feature to save a CSV or JSON file, those exports are **not encrypted**. They contain your journal in plain text. Save them to a place you trust.

## Data retention

Your data lives on your device and in your iCloud account for as long as you keep them. Deleting the app removes the local copy. Removing the app from iCloud (Settings → Apple ID → iCloud → Manage Storage → JournalInsight) removes the cloud copy.

## Contact

For questions about this policy: <ADD AN EMAIL ADDRESS HERE BEFORE PUBLISHING>.

## Changes

We will update this page if our practices change.
```

- [ ] **Step 6.2: Hosting decision (manual checklist)**

```markdown
# Hosting checklist (do before App Store submission)

- [ ] Decide where this policy is hosted: GitHub Pages on `journalinsight.github.io`, or a custom domain.
- [ ] Replace `<ADD AN EMAIL ADDRESS HERE BEFORE PUBLISHING>` with a real contact email.
- [ ] Publish the page; verify it loads over HTTPS without redirects.
- [ ] Submit the URL in App Store Connect → App Privacy → Privacy Policy URL.
- [ ] Submit again as the "Support URL" if no separate support page exists.
```

Append the hosting checklist to the same file. Then:

- [ ] **Step 6.3: Commit**

```bash
git add docs/release/2026-04-29-privacy-policy.md
git commit -m "docs(release): privacy policy text + hosting checklist for App Store submission"
```

---

## Plan-7 acceptance

- [ ] `JournalInsight/PrivacyInfo.xcprivacy` exists, validates, and is in the app target.
- [ ] `JournalInsight/JournalInsight.entitlements` declares iCloud (CloudKit), aps-environment, container `iCloud.com.tobias.JournalInsight`.
- [ ] Xcode project capabilities show iCloud + Push Notifications + Background Modes (Remote notifications) for the JournalInsight target.
- [ ] `.swiftlint.yml` exists and (if SwiftLint is installed) reports zero violations.
- [ ] `docs/release/2026-04-29-cloudkit-deployment.md`, `docs/release/2026-04-29-app-store-privacy-labels.md`, `docs/release/2026-04-29-privacy-policy.md` are committed.
- [ ] `xcodebuild build` succeeds.
- [ ] No Swift source file under `JournalInsight/` has been modified by this plan.

When all six tasks are checked, this plan is complete.

> Important: Tasks 4, 5, and 6 are *manual operational checklists*, not code changes. Their "completion" inside this plan means the documents exist; their actual *execution* (CloudKit Dashboard, App Store Connect, hosting) happens immediately before App Store submission and is **not blocking for the v1.0 implementation work** — only for shipping.
