# AUTH-01 — Face ID lock promises "health notes, labs, prayer records and photos stay private," but it is a UI-only shield with zero at-rest protection

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | App lock & authentication |
| **Location(s)** | `Info.plist`, `WinTheDay/Managers/AppLock.swift`, `WinTheDay/App/LockScreenView.swift`, `WinTheDay/App/WinTheDayApp.swift`, `WinTheDay/Core/PhotoStore.swift` |

## Summary

The NSFaceIDUsageDescription and lock-screen copy tell the user the Face ID lock keeps their health notes, labs, prayer records and photos private, but AppLock is by its own documentation "purely a UI shield over RootView" — it provides no data-at-rest protection, and the photos it names are readable via file sharing while the app is locked.

## Details

Every cited line is confirmed verbatim in source:

- `Info.plist:25-26`:
  ```xml
  <key>NSFaceIDUsageDescription</key>
  <string>Win the Day uses Face ID to unlock the app so your health notes, labs, prayer records and photos stay private.</string>
  ```
- `WinTheDay/App/LockScreenView.swift:17`:
  ```swift
  Text("Locked to keep your health, faith and photos private.")
  ```
- `WinTheDay/Managers/AppLock.swift:4-6` (the feature's own doc comment):
  ```swift
  /// Local-only: nothing leaves the device, the lock is purely a UI shield over
  /// `RootView` (widgets, the watch app and notifications are governed by iOS, not by this).
  ```
- `WinTheDay/App/WinTheDayApp.swift:44` confirms the mechanism is a SwiftUI overlay only:
  ```swift
  if lock.shielded { LockScreenView().environmentObject(lock) }
  ```
  `shielded` is just `locked || covered` (`AppLock.swift:22`). Unlock flips a `@Published` bool (`AppLock.swift:104-118`); nothing is encrypted, sealed, or file-protected.

The specific data the copy names is genuinely reachable while the app shows its lock screen:

- **Photos** — `WinTheDay/Core/PhotoStore.swift:3-7` stores meal/lab/InBody JPEGs in `Documents/photos`:
  ```swift
  /// Stores day photos as JPEGs in Documents/photos, referenced by filename from each Entry.
  let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("photos", isDirectory: true)
  ```
  and `Info.plist:29-32` exposes the app's whole `Documents` tree to Files.app and any paired computer:
  ```xml
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  ```
  The overlay in `WinTheDayApp.swift` cannot intercept file-sharing access — that path never touches the app's UI.

The report's claim is accurate: the lock only hides pixels of `RootView` on the unlocked device. It does not gate the App-Group snapshot read by widgets/watch, notification banners, App Intents, or — most concretely — the on-disk photos. `AppLock.swift:4-6` even admits widgets/watch/notifications are out of scope, but the user-facing copy does not.

This is a copy-accuracy / privacy-design finding. The heavier data-extraction vector (UIFileSharingEnabled exposing `Documents/photos`) is its own separate finding; the incremental issue confirmed here is that the app actively markets the lock as delivering privacy for photos/labs it does not protect, which is also an App Store privacy-accuracy concern.

## Failure / exploit scenario

Threat model (b): the user enables Face ID app lock, reassured by the on-screen promise that their labs and photos "stay private." The device is later connected to a trusted/paired computer (or opened in Files.app on the device itself). Because `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are true, the browser sees the app's `Documents` folder and opens `Documents/photos`, reading every meal/lab/InBody JPEG — while the app is displaying its Face ID lock screen. The exact data the copy says will "stay private" is extracted, and the lock never participates.

## Impact

The privacy value proposition the lock is sold on is false. A user who turns on Face ID believing their labs and photos are protected gets no at-rest protection: the sensitive photos are extractable over USB/Files.app regardless of lock state, and the App-Group snapshot, notification banners, and App Intents readouts are likewise ungated. Beyond the direct exposure, the mismatch between the stated purpose string and the feature's actual capability is an App Store privacy-accuracy risk (threat model e).

## Recommendation

Two-part fix:

1. **Make the copy honest.** Reword `NSFaceIDUsageDescription` (`Info.plist:26`) and `LockScreenView.swift:17` to describe what the lock actually does — obscures the app's own screens on this device — and stop asserting that photos/labs "stay private." e.g. "Win the Day uses Face ID to hide the app's screens on this device when you step away."

2. **Deliver the protection the copy implied, or remove the exposure.** For real at-rest protection of the named photos: drop `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace` (`Info.plist:29-32`) or relocate `Documents/photos` (`PhotoStore.swift:6-7`) into a non-shared container (e.g. Application Support), and apply `.completeUnlessOpen`/`.complete` file protection to the photo directory and JSON blobs. Explicitly document in-code and in the privacy copy that widgets, the watch app, notifications, and App Intents are outside the lock — matching the honest note already in `AppLock.swift:4-6`.

## References

- Apple: Encrypting Your App's Files (Data Protection / NSFileProtection)
- App Store Review Guideline 5.1.1 (accurate privacy disclosures)
- CWE-522: Insufficiently Protected Credentials/Data at Rest (analogous)


---

_Finding AUTH-01. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._