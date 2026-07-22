# DATA-01 — Plaintext health backup and raw health photos are exposed via iTunes/Files file sharing

| Field | Value |
|---|---|
| **Severity** | High |
| **Category** | Data at rest |
| **Status** | CONFIRMED |
| **Location(s)** | `Info.plist:29`, `Info.plist:31`, `WinTheDay/Core/AppStore.swift:3547`, `WinTheDay/Core/AppStore.swift:3548`, `WinTheDay/App/WinTheDayApp.swift:72`, `WinTheDay/Core/PhotoStore.swift:5`, `WinTheDay/Core/BackupBundle.swift:41`, `WinTheDay/Core/BackupBundle.swift:81` |

## Summary

The app enables Files/Finder file sharing on its Documents directory, which holds a rolling plaintext JSON backup of the entire health record (including precise GPS) plus a folder of raw health-photo JPEGs — all copyable without unlocking the app.

## Details

Both file-sharing flags are enabled in the top-level `Info.plist`, exposing the app's entire Documents directory to the Files app and to a paired computer (Finder/iTunes file sharing):

```
Info.plist:29  <key>UIFileSharingEnabled</key>
Info.plist:30  <true/>
Info.plist:31  <key>LSSupportsOpeningDocumentsInPlace</key>
Info.plist:32  <true/>
```

Two high-value assets sit directly under Documents:

**1. A rolling plaintext backup at the Documents root**, refreshed on every backgrounding. The code names it in its own comment as "The visible-in-Files rolling backup":

```
AppStore.swift:3547  /// The visible-in-Files rolling backup the app refreshes whenever it goes to the background.
AppStore.swift:3548  var autoBackupURL: URL { documentsDir.appendingPathComponent("Win the Day - latest backup.json") }
```

`documentsDir` is `.documentDirectory` (AppStore.swift:3543), and `writeAutoBackup()` (3549) writes the archive there. It is triggered on every background transition:

```
WinTheDayApp.swift:71  if phase == .background {
WinTheDay/App/WinTheDayApp.swift:72      store.writeAutoBackup()
```

The archive is `makeBackupData()` (AppStore.swift:3521) → `BackupService.makeArchive`, a `BackupArchive` (BackupBundle.swift:74) with `blobs: [String: Data]` (every persisted UserDefaults key of real user data, verbatim) and `photos: [String: String]` (filename → base64 JPEG). `BackupKeys.all` (BackupBundle.swift:20-49) enumerates the contents: the `suhail_health_v2` AppData blob (entries, habits, catalog, labs, rings, plans), settings, coach chat transcripts, weekly AI reviews, fasting/hydration state, and — confirming the precise-location claim — `"prayer_lat", "prayer_lon"` (BackupBundle.swift:41). The file is plain `JSONEncoder().encode(archive)` output — no encryption.

**2. Raw health-photo JPEGs** in `Documents/photos`:

```
PhotoStore.swift:5   let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
PhotoStore.swift:6       .appendingPathComponent("photos", isDirectory: true)
```

These are the meal, nutrition-label, lab-report and InBody photos referenced by each Entry.

One correction to the report's framing: **API keys are NOT exposed** — they live in the Keychain and are deliberately excluded from every archive (BackupBundle.swift:16-19: "API keys are in the Keychain and are never part of an archive"). The rest of the report is accurate.

The documented AppLock (Face ID, `NSFaceIDUsageDescription` at Info.plist:25-26) is a SwiftUI-layer shield and does nothing to gate filesystem access to these files.

## Failure / exploit scenario

Threat model (a)/(b): The unlocked phone is briefly unattended, or a paired/trusted computer is available. Because `writeAutoBackup()` runs on every background transition (WinTheDayApp.swift:72), `Win the Day - latest backup.json` is always present and current at the Documents root. The observer opens Files → On My iPhone → Win the Day (or connects the phone in Finder → Files), and copies/AirDrops that single JSON plus the `photos` folder. They now hold the complete unencrypted health dossier — labs, conditions, medications, meal history, prayer records, sleep, coach chat, and home GPS (`prayer_lat`/`prayer_lon`) — plus every health photo, with no app unlock and no credential. On a paired-computer or backup-file path this needs no on-device interaction at all.

## Impact

Total, credential-free disclosure of the app's most sensitive data-at-rest. The Face ID app lock the app advertises for exactly this data ("so your health notes, labs, prayer records and photos stay private", Info.plist:26) is fully bypassed at the filesystem layer. This is the highest-value data-at-rest exposure in the app: an entire longitudinal medical/behavioral record plus precise home location, in cleartext, extractable in seconds. API keys are the one thing spared (Keychain-only).

## Recommendation

If in-place document sharing of these files is not an actual product requirement, remove `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` from `Info.plist` (lines 29-32). Independently, move standing data out of the user-exposed Documents directory: relocate the auto-backup and `Documents/photos` into Application Support (`.applicationSupportDirectory`) or Caches, which are not surfaced by Files/Finder — change `documentsDir` (AppStore.swift:3542-3544) and `PhotoStore.dir` (PhotoStore.swift:5-6) accordingly, with a one-time migration of existing files. If file sharing must stay on for user-initiated export, keep Documents empty of standing data and write exports only to `temporaryDirectory` (as `exportJSON()` at AppStore.swift:3531-3536 already does) consumed by the share sheet. Consider setting `FileProtectionType.complete` on the backup and photo files so they are also encrypted at rest when the device is locked.

## References

- CWE-538: Insertion of Sensitive Information into Externally-Accessible File or Directory
- CWE-311: Missing Encryption of Sensitive Data
- Apple: Enabling iTunes and iCloud file sharing (UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace)
- Apple: FileProtectionType


---

_Finding DATA-01. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._