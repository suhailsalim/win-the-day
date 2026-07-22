# PROD-06 — Backup UI describes what the export contains but never discloses it is unencrypted plaintext, while the Settings footer reassures "your data, your device"

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Location(s)** | `WinTheDay/Settings/SettingsPages.swift`, `WinTheDay/Settings/SettingsView.swift`, `WinTheDay/Core/AppStore.swift`, `WinTheDay/Core/BackupBundle.swift` |

## Summary

The Backup & data page and Settings footer give the user a "private to my device" mental model and actively prompt exporting to iCloud Drive/Files, but never disclose that the exported/auto-backup file is unencrypted plaintext JSON containing the full health profile, base64 photos, and precise prayer_lat/prayer_lon, readable by anyone who obtains the file.

## Details

The reported copy exists verbatim and the underlying technical claim (plaintext, sensitive, location-bearing export) is confirmed from code.

**The disclosure copy (accurate about contents, silent on encryption):**
`WinTheDay/Settings/SettingsPages.swift:1270-1277`, `autoBackupNote`:
> "A backup holds everything on this device — entries, habits, targets, settings, coach chats, prayer/hydration/fasting setup, library, labs, body comp & photos. Your API keys are not included: they stay in the Keychain... Auto-backup writes to the Files app (On My iPhone → Win the Day) every time you leave the app, and it rides along in your iCloud device backup. **Tap Back up to also drop a copy in iCloud Drive.**"

The restore footnote (`SettingsPages.swift:1361-1367`) likewise itemizes contents and the Keychain exclusion but carries no encryption caveat.

The Settings footer reinforces the safe mental model — `WinTheDay/Settings/SettingsView.swift:86`:
> "Win the Day · v1.0\nNo accounts. No backend. **Your data, your device.**"

**The file really is unencrypted plaintext and really carries the sensitive data:**
- `WinTheDay/Core/AppStore.swift:3550-3556` `writeAutoBackup()` does `try? raw.write(to: autoBackupURL)` with no encryption and no explicit file-protection class, where `autoBackupURL` = `documentsDir.appendingPathComponent("Win the Day - latest backup.json")` (`AppStore.swift:3543-3548`). The Documents dir is Files-exposed (`UIFileSharingEnabled=true`), so this rolling plaintext copy is refreshed on every background transition.
- `AppStore.swift:3531-3537` `exportJSON()` and `3521-3527` `makeBackupData()` produce the same via `JSONEncoder().encode(archive)` — no encryption step anywhere.
- The archive is a plain `Codable` struct (`WinTheDay/Core/BackupBundle.swift:74-95`); `blobs: [String: Data]` and `photos: [String: String]` serialize to base64 inside human-readable JSON. `BackupCodec` (`BackupBundle.swift:57-67`) is a binary-plist *wrapper for type fidelity, not encryption*.
- The exported blob whitelist explicitly includes `"prayer_lat", "prayer_lon", "prayer_place"` (`BackupBundle.swift:41`) and photos are base64 JPEGs (`BackupBundle.swift:81`, `140`), so precise home coordinates, labs, conditions and meal/lab/InBody images all travel in the plaintext file. The "API keys are excluded" claim in the copy is truthful (keys are not in the whitelist and stay in Keychain).

So the finding is real: the copy is accurate about *what* is in the backup and correctly excludes API keys, but omits the one caveat that matters for threat model (b) — the file is unencrypted and readable by anyone who can open it — and pairs that omission with a "your data, your device" reassurance and an active nudge to copy it into iCloud Drive.

## Failure / exploit scenario

Threat model (b): a user reads "No accounts. No backend. Your data, your device." (`SettingsView.swift:86`) and, following the in-app prompt at `SettingsPages.swift:1271` ("Tap Back up to also drop a copy in iCloud Drive"), exports the backup. The resulting `win-the-day-backup-*.json` is unencrypted plaintext holding their labs, conditions/meds/injuries, coach chats and precise `prayer_lat`/`prayer_lon` home coordinates. Separately, on every app exit `writeAutoBackup()` refreshes an identical plaintext `Win the Day - latest backup.json` inside the Files-exposed Documents dir. Anyone who later obtains that file — via the shared iCloud Drive, the Files app on a briefly-unattended unlocked phone, or a paired/trusted computer's file-sharing access — reads the entire medical profile and home location in a text editor, with nothing in the UI having warned that the copy was unprotected.

## Impact

Users are given an incomplete-consent picture: the copy details what the backup contains and truthfully excludes API keys, but never says the file is unencrypted, so a privacy-conscious user cannot make an informed choice about where to store it. Combined with the reassuring "your data, your device" framing and the explicit nudge to place a copy in iCloud Drive, this can lead a user to drop an unprotected full medical profile plus precise home coordinates into locations reachable by others. Marginal harm attributable to the missing caveat alone is limited (the substantive exposure is the plaintext export and Files sharing themselves, tracked as separate findings), which is why this is Low rather than Medium — but it materially compounds those findings by removing the user's chance to self-protect.

## Recommendation

1. Add one explicit caveat to `autoBackupNote` (`SettingsPages.swift:1270-1277`) and the restore footnote (`1361-1367`): the backup file is **unencrypted** and anyone who can open it can read all health data and your home location; store it somewhere protected and avoid unprotected cloud folders. 2. Stop pairing the unqualified "Your data, your device." footer (`SettingsView.swift:86`) with an unwarned plaintext export — either soften the reassurance or link it to the caveat. 3. Consider offering a passphrase-encrypted export and setting `.completeFileProtection` (or at least not writing the rolling auto-backup into the Files-exposed Documents dir) so the default path is not an unprotected plaintext file. These are content/affordance changes; none alter the read-tool or restore logic.

## References

- CWE-311: Missing Encryption of Sensitive Data
- CWE-359: Exposure of Private Personal Information to an Unauthorized Actor
- Apple Data Protection / NSFileProtection file-protection classes


---

_Finding PROD-06. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._