# PRIV-03 — No PrivacyInfo.xcprivacy manifest — required-reason UserDefaults API undeclared (App Store upload/review blocker)

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | App Store privacy compliance / privacy manifest |
| **Location(s)** | `WinTheDay/Core/AppStore.swift`, `WinTheDay/WinTheDay.entitlements`, `Shared/SharedSnapshot.swift`, `PrayerWidgetExt/WidgetActionIntents.swift`, `WinTheDay/App/AppIntentsSupport.swift` |

## Summary

The repository contains no PrivacyInfo.xcprivacy manifest for any target, yet the app and its extensions rely on UserDefaults (a required-reason API) pervasively. Since 1 May 2024 Apple rejects uploads that use required-reason APIs without a declared approved reason, so the app cannot ship as-is. It is a compliance/process gap under threat model (e), not a runtime data-exposure defect.

## Details

Verified independently from source:

- **No manifest exists anywhere.** `find . -name '*.xcprivacy'` returns nothing, and `rg -n "xcprivacy|PrivacyInfo"` across the entire repo (including the `.pbxproj`) returns nothing. There is no privacy manifest referenced by, or present in, any of the four targets.

- **UserDefaults is used pervasively across app + extension + shared + watch code — 13 Swift files.** The reported anchor is real: `WinTheDay/Core/AppStore.swift:3190-3194`, `loadCoachWriteLog()`, reads all coach-write history from the standard defaults:
  ```swift
  guard let raw = UserDefaults.standard.data(forKey: coachWriteLogKey),
        let list = try? JSONDecoder().decode([CoachWriteRecord].self, from: raw) else { return [] }
  ```
  and `persistCoachWriteLog()` writes it back with `UserDefaults.standard.set(...)`. Beyond the standard suite, the App-Group suite is used to feed widgets/watch, e.g. `Shared/SharedSnapshot.swift:84,88` (`UserDefaults(suiteName: suite)?.set/.data`), `AppStore.swift:902` (`UserDefaults(suiteName: SharedStore.appGroup)`), `PrayerWidgetExt/WidgetActionIntents.swift:36`, and `WinTheDay/App/AppIntentsSupport.swift:69`. So the extension targets, not just the main app, invoke the API.

- **`NSPrivacyAccessedAPICategoryUserDefaults` (reason CA92.1) is exactly the required-reason category this triggers.** With no manifest declaring it, Apple's upload processing emits **ITMS-91053 "Missing API declaration"** and, for App Store / TestFlight distribution of an app using this API, this is now an enforced rejection rather than a soft warning.

- **The entitlements file is genuinely thin** (`WinTheDay/WinTheDay.entitlements`): only `com.apple.developer.healthkit` and the `group.com.suhail.WinTheDay` App Group — it does not and cannot substitute for a privacy manifest.

- **Scoped the blast radius: no *other* required-reason APIs appear to be used.** I grepped for the other common categories and found no hits: file-timestamp APIs (`attributesOfItem`, `contentModificationDate`, `FileAttributeKey`, `resourceValues`), disk-space APIs (`volumeAvailableCapacity`, `systemFreeSize`), system-boot-time (`systemUptime`, `kern.boottime`, `mach_absolute_time`), and active-keyboard (`activeInputModes`). So the only required-reason declaration this codebase currently needs is UserDefaults (CA92.1) — the recommendation should not over-declare.

Correcting the prior rating: this is a real, confirmed gap, but it exposes no user data and creates no exploitable condition on-device. Its entire impact is App Store submission friction (threat model e). For a security/privacy audit weighted by user harm, **Low** is the honest severity; the earlier **Medium** overstates it.

## Failure / exploit scenario

Under threat model (e) — App Store review / privacy compliance: the developer archives the WinTheDay target and uploads the build to App Store Connect / TestFlight. Because the binary (and its widget/watch extensions) links and calls `UserDefaults` without any `PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults`, App Store Connect's upload processing returns an **ITMS-91053 "Missing API declaration"** email and the build is flagged; distribution is blocked until a manifest with an approved reason code is added and the build re-uploaded. There is no user-facing exploit or data leak — the failure is entirely in the submission/review pipeline.

## Impact

Ship-blocking for the developer: uploads that use a required-reason API without declaration are rejected during processing/review, delaying or preventing release. Secondary, product-relevant loss: the absence of a manifest means the app ships **no machine-readable statement of its actual privacy posture** — `NSPrivacyTracking=false`, empty `NSPrivacyTrackingDomains`, and empty `NSPrivacyCollectedDataTypes` — which is precisely the "no tracking, local-only, no data collection" story this app wants to advertise on its App Store privacy label. No on-device user data is exposed by this gap.

## Recommendation

Add a `PrivacyInfo.xcprivacy` resource to the app target (and to the widget and watch/complication targets, since they also call `UserDefaults`) declaring:

- `NSPrivacyTracking` = `false`
- `NSPrivacyTrackingDomains` = `[]`
- `NSPrivacyCollectedDataTypes` = `[]` (accurate: this app is local-only with no analytics/backend)
- `NSPrivacyAccessedAPITypes` = one entry with `NSPrivacyAccessedAPIType` = `NSPrivacyAccessedAPICategoryUserDefaults` and `NSPrivacyAccessedAPITypeReasons` = `["CA92.1"]` (app accesses UserDefaults to read/write values only the app itself can access, incl. the App-Group suite it shares with its own extensions).

Do **not** pre-declare file-timestamp / disk-space / boot-time / active-keyboard reasons — this audit found no usage of those APIs, so declaring them would be inaccurate. Re-audit only if such APIs are later introduced. Ensure the manifest file is added to each target's "Copy Bundle Resources" build phase (a manifest present in the repo but not bundled does not satisfy the check).

## References

- Apple: Describing use of required reason API (ITMS-91053)
- Apple: Privacy manifest files — NSPrivacyAccessedAPICategoryUserDefaults reason CA92.1


---

_Finding PRIV-03. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._