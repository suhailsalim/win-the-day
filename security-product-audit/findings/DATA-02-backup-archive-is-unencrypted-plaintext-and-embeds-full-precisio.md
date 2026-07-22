# DATA-02 — Backup archive is unencrypted plaintext and embeds full-precision GPS location — with no user-facing encryption option

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | data-at-rest |
| **Location(s)** | `WinTheDay/Core/AppStore.swift:3527`, `WinTheDay/Core/AppStore.swift:3531`, `WinTheDay/Core/AppStore.swift:3548`, `WinTheDay/Core/AppStore.swift:3550`, `WinTheDay/Core/BackupBundle.swift:131`, `WinTheDay/Managers/PrayerManager.swift:146`, `WinTheDay/App/WinTheDayApp.swift:72`, `Info.plist:29` |

## Summary

Both the user-initiated export and the silent on-background auto-backup serialize the entire health dataset — including full-precision latitude/longitude and base64 meal/lab/InBody photos — to a plaintext JSON file with no encryption and no passphrase option, so every downstream copy is a fully readable health + precise-home-location dump.

## Details

Re-read from source and confirmed every claim; the reachable surface is actually **broader** than the report captured.

**1. The serializer is plaintext JSON, no encryption path exists.** `AppStore.makeBackupData()`:

```swift
// WinTheDay/Core/AppStore.swift:3521-3528
private func makeBackupData() -> Data? {
    persistData()
    persistSettings()
    var names: Set<String> = []
    for entry in data.entries.values { names.formUnion(entry.photos) }
    let archive = BackupService.makeArchive(photoNames: names)
    return try? JSONEncoder().encode(archive)   // :3527 — plaintext, no cipher
}
```

There is no CryptoKit call, no key derivation, no `SymmetricKey`, nowhere in the backup path.

**2. TWO write sinks, both plaintext, one requiring zero user action.**
- User-initiated share: `exportJSON()` (`AppStore.swift:3531-3537`) writes to `temporaryDirectory/win-the-day-backup-<date>.json` and hands the URL to the share sheet (`SettingsPages.swift:1234 exportURL = store.exportJSON()`).
- **Silent auto-backup**: `writeAutoBackup()` (`AppStore.swift:3550-3556`) writes the *same* `makeBackupData()` blob to `autoBackupURL` = `Documents/"Win the Day - latest backup.json"` (`AppStore.swift:3548`), invoked on **every** background transition (`WinTheDayApp.swift:72`, `if phase == .background { store.writeAutoBackup() }`). Because `Info.plist:29 UIFileSharingEnabled=true` and `:31 LSSupportsOpeningDocumentsInPlace=true`, that Documents file is continuously exposed to Files.app and to any paired/trusted computer — no export tap, no share sheet, no user intent required. This is the more serious sink and the report omitted it.

**3. The archive contents include full-precision coordinates + all photos.** `BackupKeys.all` enumerates the persisted keys copied verbatim, including:

```swift
// WinTheDay/Core/BackupBundle.swift (BackupKeys.all)
"prayer_method", "prayer_lat", "prayer_lon", "prayer_place",
```

Those doubles are stored raw by `PrayerManager.persist()`:

```swift
// WinTheDay/Managers/PrayerManager.swift:145-148
if let c = coordinate {
    defaults.set(c.latitude, forKey: "prayer_lat")
    defaults.set(c.longitude, forKey: "prayer_lon")
}
```

`makeArchive` (`BackupBundle.swift:131-142`) copies each key's UserDefaults value into `archive.blobs` and base64-encodes every referenced photo into `archive.photos` (`:140 archive.photos[name] = raw.base64EncodedString()`). So the plaintext file contains the full AppData blob (`suhail_health_v2` — entries, labs, rings, plans), coach transcripts, and every meal/lab/InBody JPEG, alongside exact home coordinates.

**4. One report claim corrected in the app's favor:** API keys are genuinely excluded — confirmed by the `BackupKeys` doc comment ("API keys are in the Keychain and are never part of an archive") and by the absence of any keychain read in `makeArchive`. The finding does not depend on that.

## Failure / exploit scenario

**Threat model (b) — exported/synced file, no encryption at rest.** Two concrete paths:

1. *Silent, no user action:* the user pairs the phone to a laptop (iTunes/Finder file sharing) or opens Files.app. `Documents/"Win the Day - latest backup.json"`, rewritten on every backgrounding, is a plaintext dump of all health data + exact `prayer_lat`/`prayer_lon`. Anyone with the trusted-computer pairing or brief Files.app access copies it and reads the user's home coordinates and labs — the Face ID app-lock is a UI shield only and does not gate the Documents directory.

2. *Deliberate export:* the user taps Export to back up to iCloud Drive / email / AirDrop. The plaintext JSON with exact home coordinates, all labs, and base64 photos now sits unencrypted in cloud storage and on every synced device, recoverable by anyone who later obtains that account or device. There is no option to protect it with a passphrase.

## Impact

Every copy of the backup — the always-present Documents auto-backup, or any shared/synced export — is a fully readable personal health record (meals, weight, labs, InBody/meal photos, coach chats) plus the user's precise home/prayer location, with no at-rest protection and no way for the user to encrypt it. The location doubles are full CoreLocation precision, sufficient to identify a residence. Because the auto-backup requires no user action and is exposed via file sharing, the exposure exists by default, not only when a user chooses to export.

## Recommendation

1. **Offer an encrypted export** as the default for the share sheet: derive a key from a user passphrase (e.g. CryptoKit `HKDF` + `AES.GCM.seal` over the archive Data) so shared/synced copies are ciphertext. Keep an explicit "unencrypted" opt-out if interop with old imports is needed.
2. **Address the silent Documents auto-backup**, which is the larger exposure: either encrypt it the same way, or move it out of the file-sharing-visible Documents directory (e.g. Application Support, which is not surfaced by `UIFileSharingEnabled`), or protect the file with `FileProtectionType.complete`. Today it is plaintext in a directory reachable by Files.app and paired computers on every backgrounding.
3. **Coarsen the persisted/exported location**: prayer-time math tolerates rounding, so store/export latitude/longitude truncated to ~2 decimal places (~1 km) rather than raw full-precision coordinates that pinpoint a home. Apply at the `PrayerManager.persist()` write (`PrayerManager.swift:145-147`).

## References

- CWE-311: Missing Encryption of Sensitive Data
- CWE-312: Cleartext Storage of Sensitive Information
- CWE-359: Exposure of Private Personal Information to an Unauthorized Actor


---

_Finding DATA-02. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._