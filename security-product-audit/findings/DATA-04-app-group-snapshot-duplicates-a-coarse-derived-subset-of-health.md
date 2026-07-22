# DATA-04 — App Group snapshot duplicates a coarse, derived subset of health/location data into a second default-protection store

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Data at rest |
| **Status** | CONFIRMED |
| **Location(s)** | `Shared/SharedSnapshot.swift`, `WinTheDay/WinTheDay.entitlements`, `PrayerWidgetExt.entitlements`, `WinTheDay/Managers/PrayerManager.swift` |

## Summary

The widget snapshot (a strict, minimized subset of already-stored health data plus a coarse place label) is written to the App Group UserDefaults suite, which uses the platform-default file-protection class rather than an explicit stronger one. Real but negligible incremental exposure; the prior Low rating overstates it.

## Details

The mechanical claims in the report are accurate:

- `SharedStore.save` encodes the snapshot and writes it to the App Group suite:
```swift
// Shared/SharedSnapshot.swift
78  static let appGroup = "group.com.suhail.WinTheDay"
80  private static let key = "snapshot"
82  static func save(_ snapshot: SharedSnapshot, suite: String = appGroup) {
83      guard let data = try? JSONEncoder().encode(snapshot) else { return }
84      UserDefaults(suiteName: suite)?.set(data, forKey: key)
85  }
```
- The payload carries `placeName` (`SharedSnapshot.swift:19`) plus derived metrics — `score` (:23), `caloriesText`/`proteinText` (:26-27), `readiness`/`sleepScore`/`eatingScore`/`activeScore` (:49-52), `projectedWeeklyKg` (:53), and weekly counts (:37-40).
- The group entitlement is held by both `WinTheDay.entitlements:7-10` and `PrayerWidgetExt.entitlements:5-8` (and the watch targets via a separate `group.com.suhail.WinTheDay.watch` suite, `SharedSnapshot.swift:79`).

However, three facts materially reduce the severity below the reported Low:

1. **`placeName` is coarse, not precise.** It is a city/area label, not coordinates: `PrayerManager.swift:357` sets it to `[p.locality, p.administrativeArea].compactMap { $0 }.first ?? ""`. The precise `prayer_lat`/`prayer_lon` are written only to the main app's UserDefaults (`PrayerManager.swift:146-147`) and are **not** included in `SharedSnapshot`. The report's own text acknowledges this ("coarse location text"), so the "location" exposure is a city name the widget must render anyway.

2. **No new data class is created.** Every field in the snapshot is a derived/rendered value that already exists in the main app's own UserDefaults, which itself uses the same platform-default protection. The snapshot contains no raw notes, labs, meds, conditions, or photos. So the App Group store is not a weaker copy of a stronger store — it is a minimized subset at parity with the primary store.

3. **"Any group member" is first-party only.** iOS App Groups are scoped to the same developer team; the only readers are this app's own widget/watch extensions. There is no third-party app access.

4. **Not reachable via this app's concrete file-exposure vector.** The `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` exposure (the credible threat-(b) surface elsewhere in this audit) exposes only the main app's `Documents/` directory, not the App Group container. The group plist is only reachable by full-filesystem backup extraction or a jailbreak — the same posture as literally all UserDefaults-backed data in the app.

The absence of an explicit `NSFileProtection*` class on the group container is not a defect specific to this store; iOS UserDefaults does not offer per-key protection-class control, and the container inherits the default (roughly "until first unlock"), identical to the main app.

## Failure / exploit scenario

Under threat model (a)/(b): an attacker with brief access to an unlocked device cannot browse the App Group container through Files.app (only `Documents/` is file-shared), so this store is not reached by the vector that makes threat (b) concrete for this app. Reaching the group plist requires a full-device backup extraction or a jailbroken/forensic image — at which point the attacker equally obtains the main app's UserDefaults (containing the same scores plus precise `prayer_lat`/`prayer_lon`) and the far more sensitive `Documents/photos` and plaintext backup archives. The snapshot yields only a coarse city label and a handful of health scores already available from those richer sources, so it adds no net exposure.

## Impact

Negligible incremental data-at-rest exposure. In the only scenarios where the App Group plist is readable (backup extraction / device compromise), the same or strictly richer data is already available from the main app's store, `Documents/photos`, and the plaintext backup export. The snapshot is a well-minimized, coarse subset and represents good design rather than a meaningful leak.

## Recommendation

No urgent action required; the current design (a tiny, derived, coarse subset) is the correct pattern. Defensive hygiene going forward:

- Keep the snapshot restricted to render-only values; never add raw health notes, lab text, conditions/meds, or precise coordinates to `SharedSnapshot`. A brief code comment on the struct stating this invariant would help future contributors (the `add-snapshot-field` workflow is the place to enforce it).
- Continue storing only the coarse `placeName` label, never lat/lon, in the group container (already the case).
- If the team later wants defense-in-depth for the primary at-rest posture, the higher-leverage work is on the exposed `Documents/`/backup surfaces (Keychain accessibility class, `UIFileSharingEnabled`, plaintext backup) rather than on this minimized group snapshot.

## References

- CWE-359: Exposure of Private Personal Information to an Unauthorized Actor
- CWE-311: Missing Encryption of Sensitive Data


---

_Finding DATA-04. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._