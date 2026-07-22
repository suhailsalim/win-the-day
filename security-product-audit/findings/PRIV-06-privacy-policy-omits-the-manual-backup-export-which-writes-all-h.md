# PRIV-06 — Privacy policy omits the manual backup export, which writes all health data and precise prayer coordinates to a user-shareable plaintext JSON file

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Location(s)** | `website/privacy/index.html`, `WinTheDay/Core/AppStore.swift`, `WinTheDay/Core/BackupBundle.swift`, `WinTheDay/Settings/SettingsPages.swift` |

## Summary

The app ships a user-facing "Back up to iCloud Drive / Files" feature that serializes every health blob plus precise prayer coordinates (prayer_lat/prayer_lon) and base64 photos into an unencrypted JSON file the user can share off-device, but the privacy policy only mentions the passive iCloud/Finder device backup and never discloses this manual export path, its lack of encryption, or that it contains precise location.

## Details

The privacy policy's page header comment asserts it must be "literally true of the shipping code," yet its account of backups is incomplete.

**What the policy says (`website/privacy/index.html`):**
- Line 78: *"There is no cloud sync, so your device backup (iCloud device backup or Finder) is the app's backup."* — only the passive OS-level backup is acknowledged.
- The "What stays on your device" section and the summary table (lines ~140-147) mark *"Daily logs, habits, plans, chat threads"* and *"Progress photos, imported reports"* as leaving the device: **No**.
- The "Your control" section (lines ~156-160) lists revoking Health/location/etc., removing an API key, and deleting the app — but never mentions exporting a backup.

**What the code actually does:**
- `WinTheDay/Settings/SettingsPages.swift:1233-1234` renders a button labelled *"Back up to iCloud Drive / Files"* whose action is `exportURL = store.exportJSON()`, then presents a file exporter / share sheet.
- `WinTheDay/Core/AppStore.swift:3531-3535` — `exportJSON()` writes the archive to `win-the-day-backup-<date>.json` in the temp directory and returns the URL for the share sheet.
- `WinTheDay/Core/AppStore.swift:3521-3528` — `makeBackupData()` builds the archive and encodes it with `try? JSONEncoder().encode(archive)` — **plaintext JSON, no encryption**.
- `WinTheDay/Core/BackupBundle.swift:20-49` — `BackupKeys.all` includes `"prayer_lat", "prayer_lon"` (line 41), the main `AppData` blob (`suhail_health_v2`, entries/labs/rings/plans), settings, coach threads, and AI-written text. Line 140 base64-encodes every referenced photo (meal/lab/InBody images) into `archive.photos`.

API keys are correctly excluded from the archive (they live in the Keychain; `BackupBundle.swift:19` documents this), so the concern is scoped to health data, location, and photos.

This is a completeness gap, not a false statement: the policy is silent on a real, user-reachable off-device data path.

## Failure / exploit scenario

Under threat model (e), App Store privacy-compliance / policy accuracy: a reviewer or privacy-conscious user reads the policy, sees "your device backup ... is the app's backup" and a summary table asserting daily logs and photos do **not** leave the device, and reasonably concludes no in-app export exists. In reality, Settings offers "Back up to iCloud Drive / Files" which produces `win-the-day-backup-<date>.json` — an unencrypted file containing labs, health notes, coach transcripts, base64 meal/lab photos, and `prayer_lat`/`prayer_lon` (a person's home coordinates, since prayer times are computed for where they sleep). A user could save this to a shared iCloud Drive folder, email it, or drop it in a cloud service believing the policy's "stays on your device" framing still applied, unaware the file is plaintext and carries precise location.

## Impact

Low direct impact: the export is entirely user-initiated and user-controlled, and no data reaches any party the user did not choose. The harm is a disclosure/accuracy gap — the policy's "What leaves your device", summary table, and "Your control" sections give an incomplete picture, which is an App Store privacy-label consistency risk and could mislead a user into mishandling a plaintext file that contains precise location and sensitive health data. The at-rest encryption of the exported file itself is a separate (backup-dimension) concern.

## Recommendation

Add the export path to the policy so it stays "literally true of the shipping code":

1. In "Your control", add a bullet: *"Export a full backup via Settings → Back up to iCloud Drive / Files. This produces an unencrypted JSON file containing your logged data, imported reports and photos, and the coordinates used for prayer times — store or share it carefully."*
2. Adjust the "What leaves your device" section / summary table so the "does it leave the device?" answers for logs and photos note the manual-export exception, rather than a flat "No".
3. Keep the note that API keys are excluded from the archive (accurate per `BackupBundle.swift:19`).

Encrypting the export file itself is a data-at-rest hardening item owned by the backup dimension, not this privacy finding.

## References

- Apple App Store Review Guideline 5.1.1 (Data Collection and Storage) — privacy policy accuracy
- CWE-359: Exposure of Private Personal Information to an Unauthorized Actor


---

_Finding PRIV-06. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._