# Encrypted Vault v1.0 — Orchestration Plan

**Date:** 2026-04-29
**Spec:** `docs/superpowers/specs/2026-04-29-encrypted-vault-d-v1-design.md`
**Status:** Ready for execution

---

## Goal

Orchestrate the seven implementation plans that together deliver the v1.0 encrypted journal release. Identifies which plans can run in parallel, which must run sequentially, and how to monitor execution across all worktrees.

---

## Plan inventory

| # | Plan | Filename | Approx. tasks |
|---|---|---|---|
| 1 | Vault Foundations | `2026-04-29-vault-1-foundations.md` | 5 |
| 2 | VaultManager | `2026-04-29-vault-2-manager.md` | 5 |
| 3 | Migration Infrastructure | `2026-04-29-vault-3-migration.md` | 6 |
| 4 | Container Swap + App Boot | `2026-04-29-vault-4-app-boot.md` | 5 |
| 5 | Repository + View Rewiring | `2026-04-29-vault-5-views.md` | 7 |
| 6 | Settings + UI Floor | `2026-04-29-vault-6-settings.md` | 10 |
| 7 | Project Capabilities + Privacy Manifest | `2026-04-29-vault-7-project-config.md` | 5 |

---

## Dependency graph

```
                 ┌──────────────┐
                 │ Plan 1       │   foundations (no deps)
                 │ Foundations  │
                 └──────┬───────┘
                        │
                        ▼
                 ┌──────────────┐                ┌──────────────┐
                 │ Plan 2       │                │ Plan 7       │   project config
                 │ VaultManager │                │ Project cfg  │   (NO code deps,
                 └──────┬───────┘                └──────────────┘    can run from T0)
                        │
                        ▼
                 ┌──────────────┐
                 │ Plan 3       │
                 │ Migration    │
                 └──────┬───────┘
                        │
            ┌───────────┴────────────┐
            ▼                        ▼
     ┌──────────────┐         ┌──────────────┐
     │ Plan 4       │         │ Plan 5       │   parallel-eligible
     │ App boot     │         │ View rewire  │   after Plan 3
     └──────┬───────┘         └──────────────┘
            │
            ▼
     ┌──────────────┐
     │ Plan 6       │   needs Plan 4 (sync status surfaced from final container)
     │ Settings/UI  │   and Plan 5 (Lock-Now state observed by views)
     └──────────────┘
```

### Why these dependencies

| Plan | Depends on | Why |
|---|---|---|
| 1 | — | Pure additive code: `EnvelopeCodec`, `EntryBody`, `KeychainService`, `LockPolicy`, `Logger`. |
| 2 | 1 | `VaultManager` uses `KeychainService`, `LockPolicy`. |
| 3 | 1, 2 | `MigrationCoordinator.run` calls `vault.sessionKey()` and `EnvelopeCodec.encode`. |
| 4 | 2, 3 | `JournalInsightApp` wires up `VaultManager` and runs `MigrationCoordinator` before container swap. |
| 5 | 1, 2, 3 | `EntryRepository` uses `EnvelopeCodec` + `VaultManager`; views read `EntryBody`. Schema columns must exist. Does **not** require Plan 4 — code compiles and tests run against in-memory containers. |
| 6 | 2, 4 | Lock-Now button calls `vault.lockNow()`; sync-status icon reads from the CloudKit-enabled container built in Plan 4. |
| 7 | — | Pure project config: entitlements, `PrivacyInfo.xcprivacy`, capabilities, CloudKit Dashboard steps. Touches no Swift source files. |

### Execution waves (max parallelism)

```
Wave A (T0):   Plan 1   ║   Plan 7
Wave B:        Plan 2
Wave C:        Plan 3
Wave D:        Plan 4   ║   Plan 5
Wave E:        Plan 6
```

Maximum parallel width is **2**. Plans 1+7 run together at start; Plans 4+5 run together once Plan 3 finishes.

---

## Subagent dispatch model

### Worker subagents (one per plan)

For each plan, dispatch a fresh `general-purpose` subagent with this prompt template:

```
You are implementing Plan {N}: {Title} from the JournalInsight encrypted-vault v1.0 release.

Spec:  docs/superpowers/specs/2026-04-29-encrypted-vault-d-v1-design.md
Plan:  docs/superpowers/plans/2026-04-29-vault-{N}-{slug}.md

Use the superpowers:executing-plans skill. Implement every task in
the plan file in order, ticking the checkboxes as you go. Run the
test step for each task and only proceed when it passes.

Commit after each task. Use the commit message templates in the plan.

When all tasks are done, write a short report:
  - Which tasks completed
  - Any deviations from the plan and why
  - Any test failures still outstanding
  - Final commit SHA
```

### Monitor subagent

One `general-purpose` subagent runs in the background with this prompt:

```
You are the execution monitor for the JournalInsight encrypted-vault
v1.0 release. Your job: poll worker progress and report status.

Worker plans live in docs/superpowers/plans/2026-04-29-vault-*.md.
Each plan has tasks marked with `- [ ]` (pending) or `- [x]` (done).

Every 60 seconds:
  1. For each plan file, count pending vs done checkboxes.
  2. Run `git log --oneline -20 docs/superpowers/plans/` to see recent commits.
  3. Print a status table:
        Plan   Tasks   Done   Pending   Last Commit
  4. If any plan has been at the same checkbox count for >5 minutes, flag it.

Stop after 4 hours or when all plans show 100% done. Do not modify
any files. Read-only role.
```

The monitor uses the **plan file checkboxes themselves** as the source of truth — workers tick them as they complete tasks. Git commit messages give a secondary signal.

### Status polling table format

```
+--------+-------+------+---------+------------------------------+
| Plan   | Tasks | Done | Pending | Last commit                  |
+--------+-------+------+---------+------------------------------+
| 1      |   5   |  3   |    2    | feat(vault): add EnvelopeCodec |
| 2      |   5   |  0   |    5    | (queued)                     |
| 3      |   6   |  0   |    6    | (queued)                     |
| 4      |   5   |  0   |    5    | (queued)                     |
| 5      |   7   |  0   |    7    | (queued)                     |
| 6      |  10   |  0   |   10    | (queued)                     |
| 7      |   5   |  2   |    3    | chore: add PrivacyInfo.xcprivacy |
+--------+-------+------+---------+------------------------------+
```

---

## Worktree strategy

Two options for parallel execution:

### Option A — Single worktree, sequential parallel waves

Workers within a single wave run in the same worktree. They commit to the same branch. Conflicts are managed by the dependency graph: parallel-eligible plans never touch the same files.

**File-level conflict matrix:**

| Plans | Shared files | Conflict risk |
|---|---|---|
| 1 + 7 | None — Plan 7 only touches `*.entitlements`, `PrivacyInfo.xcprivacy`, `project.pbxproj` capabilities; Plan 1 only touches `Vault/*` | Zero |
| 4 + 5 | `MainScreenView.swift` (Plan 4: PrivacyOverlay attachment at root) vs (Plan 5: views switch to `EntryRepository`). Both edit the same file. | **Medium** — coordinate via line-range partitioning or sequence them |

If running 4+5 in the same worktree, sequence them: Plan 4 first (smaller file footprint), then Plan 5.

### Option B — Separate worktrees per parallel pair

Workers in a wave each get their own worktree (via `superpowers:using-git-worktrees`), each branched from the same base commit. After both workers in a wave complete, merge their branches sequentially. Higher isolation; one merge step per wave.

**Recommended:** Option A for waves A and D (the conflict surface is tiny and we can sequence Plan 4 → Plan 5 within the same worktree); the user's environment already runs in a worktree (`competent-joliot-80556e`).

---

## Acceptance — release readiness checklist

Once all 7 plans are complete, verify against the spec's pre-release security gate (Section 6 of the spec). Every row must be green:

- [ ] `.complete` file protection on SwiftData store *(Plan 4)*
- [ ] `.complete` + `isExcludedFromBackup` on wallpaper *(Plan 6)*
- [ ] `PrivacyInfo.xcprivacy` manifest declared *(Plan 7)*
- [ ] App Store Connect privacy labels filled *(Plan 7 — manual checklist)*
- [ ] Privacy policy URL hosted and reachable *(Plan 7 — manual checklist)*
- [ ] App-switcher privacy overlay on `scenePhase != .active` *(Plan 4)*
- [ ] CloudKit container created + schema deployed to production *(Plan 7 — manual checklist)*
- [ ] Container-swap integration test passes *(Plan 4)*
- [ ] Migration idempotency integration test passes *(Plan 3)*
- [ ] EnvelopeCodec AAD-tampering test passes *(Plan 1)*
- [ ] Lint rule `vault_log_privacy_required` enforced *(Plan 7)*
- [ ] CSV export sanitization (S-9) *(Plan 6)*
- [ ] Export-file cleanup on share-sheet dismiss (S-6) *(Plan 6)*
- [ ] Sync `notificationsEnabled` toggle with `notificationSettings()` (H-7) *(Plan 6)*
- [ ] DST-safe streak test (H-1) + midnight circular-mean test (H-2) *(Plan 5)*

---

## Execution kickoff

When the user is ready to execute:

```
1. Dispatch wave A:
   - Worker subagent → Plan 1
   - Worker subagent → Plan 7
   - Monitor subagent (background)

2. When both Plan 1 and Plan 7 are 100% done:
   - Dispatch wave B: Worker → Plan 2
3. When Plan 2 is 100% done:
   - Dispatch wave C: Worker → Plan 3
4. When Plan 3 is 100% done:
   - Dispatch wave D: Worker → Plan 4 (sequential, then Plan 5)
5. When Plan 4 + Plan 5 are 100% done:
   - Dispatch wave E: Worker → Plan 6
6. Final: run release readiness checklist above
```

---

*End of orchestration plan.*
