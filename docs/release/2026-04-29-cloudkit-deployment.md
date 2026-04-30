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
