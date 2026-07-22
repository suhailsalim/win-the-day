# PRIV-02 — HealthKit purpose strings understate read/write scope (heart, HRV, sleep, body composition read; blood glucose & blood-oxygen written) — "steps/weight" and "calories/protein" only

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | Privacy / HealthKit disclosure |
| **Location(s)** | `WinTheDay.xcodeproj/project.pbxproj`, `WinTheDay/Managers/HealthManager.swift` |

## Summary

The two HealthKit usage strings baked into the build settings claim the app only reads "steps and weight" and only writes "calories and protein," but the code requests read access to heart rate, HRV, resting HR, respiratory rate, sleep, and full body composition, and write access to blood glucose, oxygen saturation, body temperature, and resting heart rate.

## Details

Verified directly against source.

**Purpose strings** (`WinTheDay.xcodeproj/project.pbxproj`, present identically in both the Debug config at lines 516–517 and the Release config at lines 547–548):

```
INFOPLIST_KEY_NSHealthShareUsageDescription  = "Win the Day reads your steps and weight to show them alongside your daily log.";
INFOPLIST_KEY_NSHealthUpdateUsageDescription = "Win the Day writes the calories and protein you log back to the Health app.";
```

**Actual READ request** (`WinTheDay/Managers/HealthManager.swift:64-68`):

```swift
let read: Set<HKObjectType> = [
    stepType, weightType, activeEnergyType, restingHRType, hrvType, respiratoryRateType, sleepType,
    energyType, proteinType, bodyFatType, leanMassType, bmiType, HKObjectType.workoutType(),
    HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)
]
```

Resolving the type properties (lines 40-52): the share string names 2 of 16 requested read types. Undisclosed: `activeEnergyBurned`, `restingHeartRate`, `heartRateVariabilitySDNN`, `respiratoryRate`, `sleepAnalysis`, `dietaryEnergyConsumed`, `dietaryProtein`, `bodyFatPercentage`, `leanBodyMass`, `bodyMassIndex`, `workoutType`, `heartRate`, `distanceWalkingRunning`, `distanceCycling`.

**Actual WRITE request** (`HealthManager.swift:69-73`):

```swift
var write: Set<HKSampleType> = [
    energyType, proteinType, weightType, bodyFatType, leanMassType, bmiType,
    HKObjectType.workoutType()
]
for t in Self.labWritableTypes.values { write.insert(t) }
```

with (`HealthManager.swift:572-578`):

```swift
static let labWritableTypes: [String: HKQuantityType] = [
    "glucose": HKQuantityType(.bloodGlucose),
    "oxygen": HKQuantityType(.oxygenSaturation),
    "respiratory": HKQuantityType(.respiratoryRate),
    "temperature": HKQuantityType(.bodyTemperature),
    "resting heart": HKQuantityType(.restingHeartRate)
]
```

So the update string names 2 of 12 writable types. Undisclosed writes include the two most sensitive analytes the app touches — `bloodGlucose` and `oxygenSaturation` — plus body composition, body temperature, and resting heart rate (written by `writeLabs`, lines 581-595, when the user imports lab values). Even the class doc comment at line 21 ("Reads steps + body mass and writes dietary energy + protein") is stale relative to the real Sets.

The prior auditor's read/write enumerations and evidence are accurate; nothing was overstated.

## Failure / exploit scenario

**Threat model (e), App Store review / privacy accuracy — the dominant real risk.** Guideline 5.1.1(i) requires the HealthKit purpose string to explain the app's use of the data. A reviewer testing the HealthKit consent flow sees the sheet request write access to Blood Glucose and Blood Oxygen while the accompanying `NSHealthUpdateUsageDescription` says only "writes the calories and protein you log back to the Health app." That mismatch — sensitive clinical analytes granted under a string that mentions neither — is a well-documented rejection trigger for health apps.

**Consent-accuracy angle (secondary, and partly mitigated):** iOS itemizes every requested data type with per-type on/off toggles in the consent sheet regardless of the purpose string, so a user is not blind to *which* types are requested — the string supplies the *why*. The residual harm is a user who reads the reassuring "steps and weight / calories and protein" context, under-reads the itemized toggle list, and grants blood-glucose/blood-oxygen write access believing the app only handles food macros.

## Impact

Primary impact is App Store compliance: an inaccurate HealthKit purpose string on an app that writes blood glucose and oxygen saturation is a realistic Guideline 5.1.1 rejection. Secondary impact is weakened informed consent — the string fails to disclose that the app reads heart rate, HRV, resting HR, respiratory rate, and sleep, and can write clinical analytes (glucose, SpO2, body temperature) — though iOS's itemized consent sheet limits how much the user is actually misled. No data exfiltration or local-attacker exposure results from this issue itself; it is a disclosure/policy defect, which is why it sits at Medium rather than higher.

## Recommendation

Rewrite both `INFOPLIST_KEY_NSHealth*UsageDescription` values in **both** build configs (`project.pbxproj:516/547` and `:517/548`) to match the real Sets, and keep them in sync whenever `read`/`write`/`labWritableTypes` change. Suggested:

- Share: `"Win the Day reads your steps, weight, body composition, heart rate, resting heart rate, HRV, respiratory rate, sleep and workouts to compute your readiness, eating and activity scores and show them alongside your daily log."`
- Update: `"Win the Day writes what you log back to Health: calories, protein, weight, body composition and workouts, plus lab values you import (e.g. blood glucose, blood oxygen, body temperature, resting heart rate)."`

To prevent drift, consider deriving the human-readable list from the same type Sets, or add a code comment at `HealthManager.swift:64` and `:572` noting that the Info.plist strings must be updated alongside. Also fix the stale class doc comment at line 21.

## References

- Apple App Store Review Guideline 5.1.1(i) — Data Collection and Storage (purpose strings)
- Apple HealthKit: NSHealthShareUsageDescription / NSHealthUpdateUsageDescription requirements


---

_Finding PRIV-02. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._