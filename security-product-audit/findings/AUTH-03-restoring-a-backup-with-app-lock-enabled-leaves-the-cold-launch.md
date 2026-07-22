# AUTH-03 — Restoring a backup with app lock enabled leaves the cold-launch mirror stale, so the app relaunches unlocked for one session despite appLockEnabled=true

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | App lock & auth |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | App lock lifecycle |
| **Location(s)** | `WinTheDay/Managers/AppLock.swift`, `WinTheDay/Core/BackupBundle.swift`, `WinTheDay/Core/AppStore.swift`, `WinTheDay/App/WinTheDayApp.swift`, `WinTheDay/Settings/SettingsPages.swift` |

## Summary

The AppLock cold-launch gate is driven solely by the `applock_enabled` UserDefaults mirror, which a backup restore never updates (only the AppSettings blob is restored). After restoring a backup that had app lock on, the first cold launch comes up fully unlocked; the mirror self-heals on the *next* launch, leaving a single unlocked session.

## Details

The whole-app lock gate decides its cold-launch state from a single UserDefaults mirror, and that mirror is the one piece of lock state a backup restore does not touch.

**init reads only the mirror** (`WinTheDay/Managers/AppLock.swift:31-33`):
```swift
init() {
    locked = d.object(forKey: enabledKey) as? Bool ?? false   // enabledKey = "applock_enabled"
}
```

**`start(enabled:)` never arms the lock itself** (`AppLock.swift:39-42`):
```swift
func start(enabled: Bool) {
    syncEnabled(enabled)
    if locked { promptOnce() }
}
```

**`syncEnabled` writes the mirror but only ever *clears* `locked`** (`AppLock.swift:45-51`):
```swift
func syncEnabled(_ enabled: Bool) {
    d.set(enabled, forKey: enabledKey)
    if !enabled {
        locked = false; covered = false; backgroundedAt = nil
        failureNote = ""; unavailableNote = ""
    }
}
```
So on a cold launch, `locked` equals whatever the mirror held at `init`; `start(enabled: true)` writes `mirror = true` for *next* time but does not lock the current session.

The mirror is kept in step with `AppSettings.appLockEnabled` only by the Settings toggle (`WinTheDay/Settings/SettingsPages.swift:1152` / `1162`, via `lock.syncEnabled(...)`). A restore bypasses that path:

- `BackupKeys.all` (`WinTheDay/Core/BackupBundle.swift:19-47`) restores `"suhail_ios_settings_v1"` — the AppSettings blob that carries `appLockEnabled` — but **contains no `applock_enabled` entry**. Restore commit at `BackupBundle.swift:218-224` writes the staged keys and, for full archives, removes only keys listed in `BackupKeys.all`; the mirror is neither written nor removed, so it retains the target device's prior value.
- `AppStore.reloadFromDefaults()` (`WinTheDay/Core/AppStore.swift:3610-3629`) rebuilds `settings` in memory via `load()` but never references the lock (there is no `AppLock` handle in `AppStore` at all).
- `WinTheDayApp`'s `.onChange(of: store.settings)` (`WinTheDay/App/WinTheDayApp.swift:54-55`) re-applies only the theme (`theme.apply(...)`). The one place `lock` is armed at launch is `.task { lock.start(enabled: store.settings.appLockEnabled) }` (`WinTheDayApp.swift:47`).

Net effect on a device whose mirror is `false` (fresh install, or app lock previously off) restoring a backup with `appLockEnabled = true`: the first post-restore cold launch reads `mirror = false → locked = false`; `start(enabled: true)` writes `mirror = true` but leaves the session unlocked; the app shows Today with the full restored health history and never prompts for Face ID. The subsequent launch reads `mirror = true` and locks correctly, so the fail-open window is exactly one session.

This is a genuine fail-open of a control the user deliberately enabled, but it is bounded and self-healing, and AppLock is by design only a UI shield over `RootView` — the header comment states it plainly (`AppLock.swift:4-6`): the lock "is purely a UI shield" and "widgets, the watch app and notifications are governed by iOS, not by this." It does not protect data at rest.

## Failure / exploit scenario

Threat model (a)+(b): a user migrates to a new phone (or reinstalls), opens Win the Day, and restores their backup (app lock had been enabled). The app tells them to relaunch (`restoreNeedsRelaunch = true`). They force-quit and reopen. Because the restored `applock_enabled` mirror is still `false` from the fresh install, `init` sets `locked = false` and `start(enabled: true)` does not re-arm it — the app opens straight to Today, showing the just-restored health history (conditions, medications, labs, meal/InBody photos) with no Face ID prompt. Anyone with the unlocked/unattended device in that one session sees everything the user expected the lock to hide. The next launch locks normally.

## Impact

A user-enabled privacy lock silently fails open for exactly one launch — the first launch after restoring a backup — which is precisely the moment the freshly restored full health history is present on the device. The exposure is limited because (1) it is a single session and self-heals on the next launch, and (2) AppLock is explicitly a UI-only shield: the same data is already reachable via `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace` and the plaintext backup regardless of the lock, so no data is exposed that a file-access adversary could not already reach. The practical impact is a fail-open of a convenience/privacy shield under brief-physical-access (threat model a), hence Low rather than Medium.

## Recommendation

Make start(enabled:) authoritative: when enabled is true and this is a cold launch, set locked=true regardless of the mirror. Call lock.syncEnabled(settings.appLockEnabled) from reloadFromDefaults (or from WinTheDayApp's onChange(of: store.settings)) so restores and any programmatic settings change re-arm the lock.


---

_Finding AUTH-03. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._