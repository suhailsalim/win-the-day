# PLAN: Full backup & restore (export/import a single archive)

## Goal
All data lives in UserDefaults + `Documents/photos/`; the only safety net is the iOS device backup.
Ship an explicit **Export backup** (one shareable archive) and **Import backup** (restore/merge) so
users can move devices, recover, or just feel safe. This also unblocks a future Android/web story.
Note: iCloud sync is NOT an option here — free Apple signing has no CloudKit (AGENTS.md); this is
file-based via the share sheet / Files app.

## Files to touch
- `WinTheDay/Core/BackupBundle.swift` — NEW (auto-joins target).
- `WinTheDay/Settings/SettingsView.swift` — Export/Import rows in a "Data" section.
- `WinTheDay/Core/Models.swift` — only if a version stamp struct is needed.

## Steps, in order
1. Inventory every persisted key by grepping `UserDefaults` reads in AppStore + managers (the
   docs list them: `suhail_health_v2`, `suhail_ios_settings_v1`, `targets_v1`, `modules_v1`,
   `personalize_v1`, `prayer_*`, `hyd_*`, `fast_*`, `coach_threads*`/`coach_chat_v1`,
   `week_outlook*`, `weekly_review*`, `score_baselines_v1` — verify by grep, don't trust this list).
2. `BackupBundle`: a Codable envelope `{ formatVersion: 1, createdEpoch, appVersion,
   blobs: [String: Data] }` where each blob is the raw JSON already stored under that key. Raw
   passthrough (not re-typed) means old backups restore into newer app versions through the same
   tolerant decoders the app already uses.
3. Export: write the envelope + a `photos/` folder (copy from PhotoStore) into a temp directory,
   zip it as `WinTheDay-backup-YYYY-MM-DD.wtd.zip` (use `NSFileCoordinator`-free simple
   `Process`? No — use Apple's `Archive`/`AppleArchive` or write an uncompressed folder and share
   it as a directory package; simplest reliable path: `Foundation`'s `FileManager` +
   `NSFileCoordinator` zip via `UIDocumentInteraction` is messy — use `Compression`'s
   `AppleArchive` on iOS 17, or fall back to sharing the JSON file alone and photos separately if
   zipping proves fragile — the JSON is the critical asset). Share via the existing share-sheet
   helper in `PDFReport.swift`.
4. Import: `.fileImporter` in Settings → parse envelope → show a summary sheet ("Backup from
   <date>: N days, M photos — Replace current data?") → on confirm, write each blob back to its
   key, copy photos in, then force a full reload (`AppStore` re-init path or a "restart required"
   alert). **Never partial-write:** stage all blobs, validate the main blob decodes as `AppData`
   first, then commit all keys.
5. Exclude API keys (Keychain) — state that in the UI ("keys are not included in backups").
6. Build, test: export on device → delete a habit → import → habit is back; photos visible.
7. Commit.

## Edge cases a weaker model would miss
- Restoring **newer-format backups into older apps** is out of scope, but stamp `formatVersion`
  now so it's detectable later; refuse import when `formatVersion` is unknown.
- The main blob can be ~hundreds of KB; the share sheet handles it, but **do not** route the
  backup through UserDefaults or the App Group snapshot.
- After restore, managers (`PrayerManager` etc.) hold stale in-memory state — the cleanest v1 is
  an alert "Restored — please relaunch the app" rather than a fragile live re-init of every
  manager.
- Photos referenced by entries but missing from the archive must not crash the History timeline —
  PhotoStore lookups already fail soft; verify once.
- Chat threads may contain provider names/models — fine to include; they contain no keys.

## Acceptance criteria
- [ ] Export produces a file openable in Files; re-importing it on a wiped install reproduces
      entries, habits, settings, threads, and photos.
- [ ] Import of a corrupted/truncated file shows an error and changes nothing (staged commit).
- [ ] API keys demonstrably absent from the archive (inspect the JSON).
- [ ] Build green; old data untouched when export is used without import.
