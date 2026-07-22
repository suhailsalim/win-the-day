# SEC-01 — Provider API keys stored with kSecAttrAccessibleAfterFirstUnlock (not …ThisDeviceOnly) — they ride encrypted device backups off the original device

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Secrets & credentials |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | secrets |
| **Location(s)** | `WinTheDay/Core/Keychain.swift`, `WinTheDay/Settings/SettingsPages.swift`, `WinTheDay/Core/BackupBundle.swift` |

## Summary

The Keychain wrapper stores per-provider API keys with kSecAttrAccessibleAfterFirstUnlock rather than the …ThisDeviceOnly variant, so the paid third-party keys are eligible for inclusion in an encrypted iTunes/Finder/iCloud device backup and are re-materialized when that backup is restored onto a different device.

## Details

`Keychain.set` in `WinTheDay/Core/Keychain.swift` writes the item with the plain `AfterFirstUnlock` accessibility class:

```swift
// WinTheDay/Core/Keychain.swift:8-20
static func set(_ value: String, for account: String) {
    let data = Data(value.utf8)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,          // "com.suhail.WinTheDay.apikeys"
        kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
    if value.isEmpty { return }
    var add = query
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock   // line 19
    SecItemAdd(add as CFDictionary, nil)
}
```

This is the only accessibility assignment in the app (grep for `kSecAttrAccessible` across `WinTheDay/` and `Shared/` returns just line 19). The account key is the provider id and the value is the API key — set from the Settings key field at `WinTheDay/Settings/SettingsPages.swift:228` (`Keychain.set(v, for: store.settings.provider)`) and read back at lines 129/208.

Two facts confirmed by re-reading the code:

1. **iCloud Keychain sync does not apply.** `kSecAttrSynchronizable` is never set (absent from the whole file), so the keys are not the cross-device-syncing kind. The only propagation channel is the OS-level *encrypted* backup.

2. **The keys are genuinely excluded from the app's own JSON archive**, so this is *not* a backup-file leak. `WinTheDay/Core/BackupBundle.swift:19` states "API keys are in the Keychain and are never part of an archive," and grepping the backup code confirms no key material is serialized. The gap is purely the Keychain accessibility class.

The behavior contradicts the app's own UX copy, which tells the user keys are device-bound and must be re-entered after a restore:

- `WinTheDay/Settings/SettingsPages.swift:1271`: "Your API keys are not included: they stay in the Keychain, so you'll re-enter them after a restore."
- `WinTheDay/Settings/SettingsPages.swift:1362`: "API keys aren't in backups — they stay in the Keychain, so re-enter yours in Settings afterwards."
- `WinTheDay/Settings/SettingsPages.swift:218`: field subtitle "Stored in your device Keychain."

That promise is accurate for the app's JSON archive but not for an OS-level encrypted device backup: non-`ThisDeviceOnly` generic-password items are carried in encrypted iTunes/Finder backups and iCloud device backups and restored on the target device. So a key the UI implies is device-bound can silently reappear on a second device. Note line 1271 itself says the auto-backup "rides along in your iCloud device backup," which makes the mismatch more pointed — the user is told the backup travels, yet also told the keys stay put.

## Failure / exploit scenario

Threat model (b), encrypted-backup migration. The user upgrades or repairs their phone and restores from an encrypted iTunes/Finder backup (or an iCloud device backup) onto a different device — or hands an old, encrypted-backed-up phone to someone during a trade-in. Because the keychain items use `AfterFirstUnlock` rather than `…ThisDeviceOnly`, the paid provider API keys (Anthropic/OpenAI/Gemini/OpenRouter/DeepSeek/Ollama Cloud) are restored on the target device even though the app's own restore copy told the user they would have to re-enter them. The keys are usable there for billed API calls until the user rotates them. (Requires possession of, and the passphrase for, an *encrypted* backup; plain unencrypted backups do not carry keychain items.)

## Impact

Billing-sensitive third-party credentials can leave the original device via an encrypted OS backup and be re-materialized on another device, widening the blast radius beyond what the UX describes. This is a defense-in-depth / UX-accuracy gap rather than a direct compromise: it requires an encrypted backup and its passphrase, no key material sits in any plaintext file, and there is no iCloud Keychain sync. For a single-user local app the practical exposure is narrow, but the propagation of a paid credential is genuinely unexpected given the app's explicit "stays in the Keychain / re-enter after restore" messaging.

## Recommendation

Change line 19 to the device-bound variant:

```swift
add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
```

`…ThisDeviceOnly` items are excluded from encrypted backups and device transfers, so the keys never migrate off the device — which is exactly what the Settings copy at `SettingsPages.swift:1271/1362` already promises. This aligns behavior with the UX and is a one-line, backward-compatible change (existing items are rewritten on next `set`; users who never re-save simply keep the old item until they re-enter a key, matching the documented "re-enter after restore" flow). No functional downside for a local-only app that already expects keys to be re-entered per device.

## References

- Apple: Keychain item accessibility constants — kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
- CWE-522: Insufficiently Protected Credentials


---

_Finding SEC-01. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._