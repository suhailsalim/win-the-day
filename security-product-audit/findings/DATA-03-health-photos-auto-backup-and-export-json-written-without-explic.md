# DATA-03 — Health photos, auto-backup, and export JSON written without explicit NSFileProtection (default UntilFirstUserAuthentication only)

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Data at rest |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | data-at-rest |
| **Location(s)** | `WinTheDay/Core/PhotoStore.swift:23`, `WinTheDay/Core/PhotoStore.swift:38`, `WinTheDay/Core/AppStore.swift:3535`, `WinTheDay/Core/AppStore.swift:3552`, `WinTheDay/Core/AppStore.swift:3548` |

## Summary

Every file the app writes to disk — meal/lab/InBody photo JPEGs, the Files-visible auto-backup, and the share-sheet export — is written with a bare Data.write(to:) and no FileProtection option, so iOS applies only the default class (CompleteUntilFirstUserAuthentication). The plaintext health data stays decryptable while the device is locked, provided it has been unlocked once since boot.

## Details

All disk-write sites in the app omit an explicit protection class:

- `PhotoStore.swift:23` (save): `do { try data.write(to: dir.appendingPathComponent(name)); return name }` — resized meal/lab/InBody JPEGs into `Documents/photos`.
- `PhotoStore.swift:38` (restore): `try? data.write(to: dir.appendingPathComponent(name))`.
- `AppStore.swift:3535` (`exportJSON()`): `try? raw.write(to: url)` — full plaintext backup to a temp file for the share sheet.
- `AppStore.swift:3552` (`writeAutoBackup()`): `try? raw.write(to: autoBackupURL)` where `autoBackupURL` is `Documents/"Win the Day - latest backup.json"` (AppStore.swift:3548) — a rolling, Files.app-visible backup refreshed on backgrounding.

A repo-wide search confirms the gap — no `FileProtection`, `fileProtection`, `protectionKey`, `completeFileProtection`, or `setResourceValues` appears anywhere in `WinTheDay/` or `Shared/`:

```
WinTheDay/Core/AppStore.swift:3535:        try? raw.write(to: url)
WinTheDay/Core/AppStore.swift:3552:        try? raw.write(to: autoBackupURL)
WinTheDay/Core/PhotoStore.swift:23:        do { try data.write(to: dir.appendingPathComponent(name)); return name }
WinTheDay/Core/PhotoStore.swift:38:        try? data.write(to: dir.appendingPathComponent(name))
```

Since iOS 7, files with no explicit class default to `NSFileProtectionCompleteUntilFirstUserAuthentication`: encrypted at rest, but the decryption key stays resident from the first post-boot unlock onward, so the files remain readable while the device is subsequently locked. For medical photos, lab data, and a backup that also carries precise `prayer_lat`/`prayer_lon`, the appropriate class is `.complete` / `.completeUnlessOpen`, which re-locks the key whenever the screen locks.

The report's technical claims are accurate. The one small correction is to severity: this is a defense-in-depth hardening gap, not a directly reachable data leak (see scenario/impact), so it is downgraded from Medium to Low. Note the `Documents/` files (auto-backup at 3552, and the photos dir) are the higher-value targets because `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace` already expose that directory to a paired computer — but that separate exposure is an unlocked/trusted-pairing path, which file protection does not address; the two findings are orthogonal.

## Failure / exploit scenario

Threat model (a), refined: an attacker seizes the phone in the common locked-but-booted-and-once-unlocked state and applies forensic filesystem extraction (e.g. a device exploit or law-enforcement tooling such as Cellebrite/GrayKey). Because the files carry only default protection, `Documents/Win the Day - latest backup.json` (all health data + base64 photos + precise prayer coordinates) and every JPEG in `Documents/photos` decrypt without the passcode ever being re-entered, since the class key was released at first unlock and is not re-locked on screen lock. With `.completeUnlessOpen`/`.complete`, those same files would be cryptographically inaccessible in the locked state, forcing the attacker to defeat the passcode first.

## Impact

Loss of confidentiality for sensitive medical data (meal/lab/InBody photos) and a plaintext backup containing precise location, but only under a demanding precondition chain: physical seizure **and** forensic-grade filesystem access **and** a locked (not unlocked) device that was unlocked at least once since boot. On a normal unlocked device (threat a's simple case) file protection is moot — the data is already reachable through the app UI or Files.app. Default protection already provides at-rest encryption gated on first-unlock; the residual gap is only the lock-after-first-unlock window against a forensic adversary. That bounds real-world impact to Low for a single-user consumer health app, notwithstanding the genuine sensitivity of the data class.

## Recommendation

Add an explicit protection option at each write. It is a one-line change per site and safe here because nothing reads these files while the device is locked (widgets/watch read the App-Group snapshot, not `Documents/photos`):

- Photos (`PhotoStore.save` line 23 and `PhotoStore.write` line 38):
  `try data.write(to: url, options: [.completeFileProtection])` (or `.completeFileProtectionUnlessOpen` if any background access is later added).
- Export (`AppStore.swift:3535`) and auto-backup (`AppStore.swift:3552`):
  `try? raw.write(to: url, options: [.completeFileProtectionUnlessOpen])` — `UnlessOpen` avoids write failures if the app is backgrounded mid-write.

Also pin the `photos` directory itself: after creating it in `PhotoStore.dir` (line 9), call `try? base.setResourceValues(...)` with `URLResourceValues.fileProtection = .complete`, so files created there inherit the class even if a future write site forgets the option. These changes are transparent to Face ID app-lock and to the existing Files.app exposure — they harden the at-rest layer independently.

## References

- CWE-311: Missing Encryption of Sensitive Data
- CWE-312: Cleartext Storage of Sensitive Information
- Apple: Encrypting Your App's Files / NSFileProtectionComplete
- Apple: FileProtectionType and Data.WritingOptions


---

_Finding DATA-03. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._