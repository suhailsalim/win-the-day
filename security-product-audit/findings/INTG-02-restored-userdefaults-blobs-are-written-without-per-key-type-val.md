# INTG-02 — Restored UserDefaults blobs are written without per-key type validation (defense-in-depth gap, no added attacker power)

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Integrity & restore |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | Backup/restore |
| **Location(s)** | `WinTheDay/Core/BackupBundle.swift:62`, `WinTheDay/Core/BackupBundle.swift:209`, `WinTheDay/Core/BackupBundle.swift:220`, `WinTheDay/Core/BackupBundle.swift:235`, `WinTheDay/Managers/PrayerManager.swift:125` |

## Summary

BackupService.restore writes each decoded archive value straight into UserDefaults with no check that its plist type matches what the key is supposed to hold. The behavior is real, but every downstream reader is type-tolerant and reverts to defaults on mismatch, and a malicious archive already has full, correctly-typed write power — so the missing validation grants an attacker nothing beyond what a well-formed hostile backup already does.

## Details

The factual claim in the report is accurate. Re-reading `WinTheDay/Core/BackupBundle.swift`:

- `BackupCodec.decode` (lines 62-66) unwraps a single-element binary plist and returns `list.first` as `Any` — any plist type (Data/String/Bool/Int/Double/Array/Dictionary) round-trips.
- In `restore` (lines 202-226), each blob is decoded and staged as an untyped `(key, value)` pair (lines 207-210), then committed with `for item in staged { d.set(item.value, forKey: item.key) }` (line 220). There is **no** per-key type assertion.
- The **only** blob that is type-validated is the main `suhail_health_v2` / `AppData` blob, via `appData(in:)` at line 235-238 (`try? JSONDecoder().decode(AppData.self, …)`), gated at line 212. Every other key (`prayer_lat`, `prayer_lon`, `onboarding_done_v1`, `suhail_ios_settings_v1`, `coach_threads_v1`, etc.) is written verbatim.

So far the report is correct. Where it over-reaches is impact. I verified every reader of these keys, and all are type-tolerant with a default fallback — a mistyped restored value simply evaporates:

- `WinTheDay/Managers/PrayerManager.swift:125-126` — `defaults.object(forKey: "prayer_lat") as? Double` (a String → `nil` → coordinates ignored).
- `WinTheDay/Managers/WeatherManager.swift:29` — same `as? Double` guard.
- `WinTheDay/App/AppIntentsSupport.swift:77-78` — same `as? Double` guard.
- `WinTheDay/Core/AppStore.swift:21` / `:3617` — `d.bool(forKey: "onboarding_done_v1")` (a Dictionary → `false`).
- `WinTheDay/Core/AppStore.swift:382-398`, `:2982` — `d.data(forKey:)` (a non-Data → `nil` → tolerant `init(from:)` keeps defaults).
- `WinTheDay/Managers/HydrationManager.swift:23-24` — `as? Int ?? 8/22`; `WinTheDay/Managers/FastingManager.swift:26` — `as? Double ?? 0`; `WinTheDay/Core/AppStore.swift:340` — `stringArray(forKey:) ?? []`; `PrayerManager.swift:129` — `string(forKey:) ?? ""`.

There is no unguarded force-cast (`as!`) on any restored key, so there is no crash path either. The decoded value is a Foundation plist object, so `d.set` itself cannot throw on a valid plist type.

Critically, the restore path is **already** a full trusted-write primitive by design: an accepted archive overwrites every listed key, and for a full (v1) archive it even `removeObject`s every key the archive omits (lines 223-225), and it plants an attacker-chosen `AppData` blob (which *does* pass validation). A crafted backup can therefore already set `prayer_lat`/`prayer_lon` to any **valid** Double (real coordinates of the attacker's choosing), wipe all settings, or replace the entire day history — all with correct types. The type-confusion variant the report describes achieves strictly *less* (values revert to defaults) than what a correctly-typed hostile archive already achieves. The missing validation adds no attacker capability; it is a code-hygiene / defense-in-depth gap, not a distinct vulnerability.

## Failure / exploit scenario

Threat model (b): the attacker gets the user to import a `.wtd` backup file they crafted (AirDrop, email attachment, shared iCloud file). For the file to be accepted at all it must already carry a valid `AppData` blob (`parse`/`restore` reject otherwise, `RestoreError.noEntries`). Having cleared that bar, the attacker could set `prayer_lat` to the string `"pwned"` — but `PrayerManager.load()` reads `object(forKey:) as? Double`, gets `nil`, and falls back to the default location. Net effect: the user's prayer coordinates reset to default, identical to what happens if the attacker simply omits the key. No crash, no code execution, no data exfiltration, no privilege change. The same attacker could instead ship a valid Double and point the user's Qibla/prayer times at an arbitrary location — but that requires no type-confusion trick and is the inherent risk of importing an untrusted backup, which the confirm sheet (`BackupSummary`) and the whole restore design already treat as an explicit user-consented overwrite.

## Impact

Negligible. A mistyped restored value uniformly reverts to a compile-time default via the tolerant getters; there is no crash, corruption, or escalation. The realistic worst case (skewed prayer coordinates, reset settings) is fully achievable by a correctly-typed hostile archive, so the missing per-key type check does not widen the attack surface. The genuine trust boundary — "importing a backup is a full-state overwrite" — is inherent to the feature and already surfaced to the user before commit.

## Recommendation

Optional hardening only; not a security fix. If desired for robustness, add a per-key expected-type map and skip (rather than write) any blob whose decoded value doesn't match — e.g. the JSON-blob keys (`suhail_health_v2`, `suhail_ios_settings_v1`, `targets_v1`, `modules_v1`, `personalize_v1`, `coach_threads_v1`, …) must be `Data`; `prayer_lat`/`prayer_lon`/`fast_start` must be `Double`; `*_done`/`prayer_enabled`/`hyd_on`/`fast_on` must be `Bool` — validated in the staging loop at `BackupBundle.swift:207-210` before `d.set` at line 220. This costs a few lines and keeps restored state schema-clean, but changes nothing about the app's actual risk posture. The higher-value control (already implicitly present) is that restore requires an explicit user confirm and rejects any file lacking a parseable `AppData` blob.


---

_Finding INTG-02. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._