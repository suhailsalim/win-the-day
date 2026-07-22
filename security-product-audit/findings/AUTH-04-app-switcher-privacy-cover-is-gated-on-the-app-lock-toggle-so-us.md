# AUTH-04 — App-switcher privacy cover is gated on the app-lock toggle, so users without app lock (the default) get their health/labs/prayer screen thumbnailed in the iOS app switcher

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | App-switcher redaction |
| **Location(s)** | `WinTheDay/Managers/AppLock.swift`, `WinTheDay/App/WinTheDayApp.swift`, `WinTheDay/Core/Models.swift` |

## Summary

The redaction overlay that hides screen content in the iOS app switcher only engages when Face ID app lock is enabled. Since app lock defaults to off, most users' sensitive screens (Health conditions/meds, lab photos, prayer data) are captured in the multitasking snapshot with no cover.

## Details

The app-switcher cover and the biometric lock are welded to the same toggle.

- `AppLock.shielded` (the thing drawn over the app) is `locked || covered` — `WinTheDay/Managers/AppLock.swift:22`:
  ```swift
  var shielded: Bool { locked || covered }
  ```
- On `.inactive` (which fires right before iOS snapshots the screen for the app switcher), `covered` is set to the app-lock flag, not unconditionally — `WinTheDay/Managers/AppLock.swift:56-58`:
  ```swift
  func willResignActive(enabled: Bool) {
      covered = enabled
  }
  ```
- The caller passes `store.settings.appLockEnabled` as `enabled` — `WinTheDay/App/WinTheDayApp.swift:83-85`:
  ```swift
  let on = store.settings.appLockEnabled
  switch phase {
  case .inactive:   lock.willResignActive(enabled: on)
  ```
- The overlay only renders when `shielded` is true — `WinTheDay/App/WinTheDayApp.swift:43-45`:
  ```swift
  .overlay {
      if lock.shielded { LockScreenView().environmentObject(lock) }
  }
  ```
- App lock is off by default — `WinTheDay/Core/Models.swift:1446` `var appLockEnabled = false`.

So for any user who has not turned on app lock (the default state), `enabled` is `false` ⇒ `covered` stays `false` ⇒ `shielded` is `false` ⇒ no overlay is drawn when the app goes inactive, and iOS captures and retains a full-fidelity thumbnail of whatever screen was open. The class doc-comment itself frames the cover as "the privacy cover the app switcher screenshots" (AppLock.swift:4-6), i.e. it was intended as a privacy control, but it is conditioned on an unrelated feature toggle. Note also that `.inactive` on a fresh launch never runs `willResignActive` with `on == true` unless lock is on, so there is no path that covers the switcher independently of the lock.

## Failure / exploit scenario

Threat model (a) — brief physical access to an unlocked/unattended device. The user opens the Health tab showing conditions, medications and injuries, or taps into a lab/InBody photo, then swipes up to the app switcher or hands the phone over. Because app lock is off (the default), no cover was drawn on `.inactive`, so the app-switcher card shows a legible thumbnail of the medical screen to anyone glancing at the phone. The snapshot is retained by iOS on disk (unencrypted while the device is unlocked) and re-displayed every time the switcher is invoked until the app is next foregrounded and re-snapshotted.

## Impact

Unintended disclosure of sensitive health information (medical conditions, medications, injuries, lab values, body-composition photos, and prayer/location-adjacent data) via the iOS app-switcher thumbnail and its on-disk retention, for the majority of users who never enable app lock. The exposure is limited: it requires local physical access to the specific device and only reveals the last-viewed screen, and the app-lock cover fully mitigates it when enabled — hence Low, not Medium. This is a privacy-hygiene gap rather than an authentication bypass; the biometric gate itself is intact.

## Recommendation

Decouple the app-switcher redaction from the biometric-lock toggle. The cover is cheap, has no authentication semantics, and should always be applied on `.inactive`/`.background`:

- In `WinTheDay/Managers/AppLock.swift`, make `willResignActive` and `didEnterBackground` always set `covered = true` regardless of the `enabled` argument (keep `enabled` only for the grace-clock / lock-arming logic). On `.active`, continue clearing `covered = false`.
- Keep `shielded = locked || covered` unchanged; when lock is off, `LockScreenView` will show its non-authenticating cover state (verify `LockScreenView` renders a plain redaction panel when `!locked` and does not prompt for Face ID in that case). If a distinct lightweight cover is preferred over the full lock screen, branch the overlay in `WinTheDayApp.swift` on `lock.locked` vs `lock.covered`.
- Confirm `syncEnabled` still clears `covered` when the user is actively foregrounded so toggling the lock off does not leave a stuck cover (AppLock.swift:45-51).

This mirrors standard banking-app behavior (which the code comment at AppLock.swift:53-55 already cites) and removes the false coupling between "I want a Face ID gate" and "I don't want my medical data thumbnailed."

## References

- CWE-200: Exposure of Sensitive Information to an Unauthorized Actor
- Apple: Prepare a UI snapshot before your app enters the background (Human Interface / applicationDidEnterBackground privacy screen guidance)


---

_Finding AUTH-04. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._