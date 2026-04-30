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
