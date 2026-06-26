# Data, persistence & backup

## Storage map
| Data | Where |
|---|---|
| `AppData` (entries, catalog, habits, sessions, occasions, …) | `UserDefaults` key `suhail_health_v2` (JSON) |
| `AppSettings` | `suhail_ios_settings_v1` |
| `Targets` / `ModulePrefs` / `Personalization` | `targets_v1` / `modules_v1` / `personalize_v1` |
| Manager settings (prayer/hydration/fasting) | own `prayer_*` / `hyd_*` / `fast_*` keys |
| Coach chat / week outlook / weekly review | `coach_chat_v1` / `week_outlook*` / `weekly_review*` |
| API keys | Keychain (per provider) |
| Progress photos | `Documents/photos/` (`PhotoStore`) |
| Widget/watch snapshot | App Groups (`SharedStore`) |

## The tolerant-Codable rule (do not skip)
Every persisted struct hand-writes `init(from:)` with `(try? c.decode(...)) ?? default`. This is the
fix for the historical **data-loss-on-update** bug: synthesized Codable would reject old saves missing
a newly added key and wipe everything. **When adding a stored property, add its tolerant decode line.**

Representative inits: `Entry`, `AppData`, `AppSettings`, `ModulePrefs`, `Targets`, `CatalogItem`,
`LoggedItem`, `Micro`, `Occasion`, `ScheduledSession`, `RoutineBlock`, `SleepBreakdown`, `HealthNote`.

## Backup / export / reset
- **Auto-backup**: full bundle (`BackupBundle` = data + base64 photos) written to
  `Documents/Win the Day - latest backup.json` on background; visible in Files (UIFileSharingEnabled).
- **Manual**: Settings → Your data → export/import JSON (fileExporter/fileImporter), or reset (with
  confirmation). `exportHealthPDF` produces the doctor report.
- True iCloud sync is **not** available (free signing); the JSON backup rides in the device's iCloud
  backup.

## Key files
`AppStore.swift` (`load`/`persistData`/`persistSettings`/backup/export), `Models.swift` (all inits),
`PhotoStore.swift`, `Shared/SharedSnapshot.swift`, `Keychain.swift`.
