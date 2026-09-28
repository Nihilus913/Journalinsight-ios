# Apple workouts payload — frozen contract (W-B81 day 0)

`workouts_payload.json` is the frozen shape of the `workouts` list that JournalInsight's
`HealthKitUploader` adds to the existing `POST /api/v1/ingest/apple-health` body. It sits
**next to** `metrics` inside `data` (as `hae_bridge.py`'s module doc already shows):
`{"data": {"metrics": [...], "workouts": [...]}}`. Either list may be absent or empty; an
empty/absent `workouts` list never deletes or changes stored workouts (X-1).

All values are fixture values, not user data. The three workouts are the L1 fixture run:
indoor run 2026-09-21, indoor cycle 2026-09-25 (no user effort rating — estimate only), and
outdoor run 2026-09-28 (parent workout with 3 activities, HR series, route, zone times).

## Conventions
- **Keys are snake_case**, exact wire names. Swift types need explicit `CodingKeys`
  (`HubClient.post` encodes without `.convertToSnakeCase`).
- **Dates** use the existing `HAEDate.format` shape `"yyyy-MM-dd HH:mm:ss Z"` in the
  device's local offset (never UTC). The hub derives start_utc from the offset.
- **Units are fixed by the key** (`_s`, `_m`, `_mps`, `_bpm`, kcal) — no per-field units object.
  The uploader converts from HealthKit units before sending.
- Optional fields may be sent as `null` or omitted; the hub treats both the same.
  Lists (`activities`, `hr_samples`, `route`) are sent as `[]` when empty.

## Workout fields
| key | type | req | meaning |
|---|---|---|---|
| `uuid` | string | yes | `HKWorkout.uuid` (uppercase UUID). Idempotency key: re-send = update. |
| `sport` | string | yes | `HKWorkoutActivityType` as lower snake_case (`running`, `cycling`, `walking`, `traditional_strength_training`, ...). |
| `name` | string | no | Display name (app-provided title or derived: "Outdoor Run"). |
| `is_indoor` | bool | no | `HKMetadataKeyIndoorWorkout`; null if not set. |
| `source` | string | no | Source/device name (`sourceRevision.source.name`). |
| `start` / `end` | date | yes | Workout start/end, local offset. |
| `duration_s` | int | yes | `HKWorkout.duration`, seconds (excludes pauses). |
| `distance_m` | number | no | Total distance, metres; null for non-distance sports. |
| `kcal` | number | no | Active energy burned, kcal. |
| `avg_hr_bpm` / `max_hr_bpm` | int | no | From workout statistics for heart rate. |
| `effort_user` | number | no | `workoutEffortScore`, 1–10, user rating; null if not rated. |
| `effort_estimated` | number | no | `estimatedWorkoutEffortScore`, 1–10; null if unavailable. Hub load = (user ?? estimated) × minutes. |
| `is_parent` | bool | yes | True when the workout has >1 `HKWorkoutActivity` (custom/multisport). |
| `segment_count` | int | yes | Number of entries in `activities` (0 for a simple workout). |
| `activities` | list | yes | Child activities, see below; `[]` for a simple workout. |
| `hr_samples` | list | yes | HR series `{ts, bpm}`; `[]` if none. |
| `route` | list | yes | `HKWorkoutRoute` locations, see below; `[]` for indoor/no GPS. |
| `zone_time` | list | no | iOS 27 `HKWorkoutZoneGroup` time-in-zone; omitted if not present. |

## `activities[]`
`uuid` (string, req), `sport` (string, req), `name` (string, opt), `start`/`end` (date, req),
`duration_s` (int, req), `distance_m` (number, opt).

## `hr_samples[]`
`ts` (date, req), `bpm` (number, req). Sampled as recorded (typ. every 5 s on Watch; the fixture is
thinned).

## `route[]`
`ts` (date, req), `lat` / `lon` (decimal degrees WGS-84, req), `elevation_m` (metres, opt),
`speed_mps` (m/s, opt), `h_accuracy_m` (horizontal accuracy, metres, opt).

## `zone_time[]`
`zone` (int 1–5, req), `lower_bpm` (int, opt), `upper_bpm` (int, opt; null = open top),
`seconds` (int, req).

## Column map (A-1)
- `import.apple_workout`: uuid, sport, name, start (local + UTC), duration_s, distance_m, kcal,
  avg/max HR, effort_user, effort_estimated, is_parent, segment_count (activity_id from the sequence).
- `import.apple_workout_sample`: hr_samples + route merged on `ts` → ts, hr_bpm, lat, lon,
  elevation_m, speed_mps.
- `import.apple_workout_detail`: sample_count, has_gps (`route` non-empty), has_hr
  (`hr_samples` non-empty), ascent_m (sum of positive `elevation_m` deltas).
