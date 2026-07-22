# PRIV-05 — Privacy policy's absolute "never transmits your Apple Health data anywhere" is contradicted by HealthKit-derived readiness/sleep/active scores the coach auto-fetches and sends to cloud providers

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | privacy-policy-accuracy / AI coach data flow |
| **Location(s)** | `website/privacy/index.html`, `WinTheDay/Core/AppStore.swift`, `WinTheDay/Engines/ScoreEngine.swift`, `WinTheDay/AI/CoachTools.swift` |

## Summary

The Apple Health section of the privacy policy states the app "never transmits your Apple Health data anywhere" with the "only exception" being "health text you deliberately submit," and the summary table marks Apple Health as not leaving the device. But the coach tool getReadiness returns Sleep/Readiness/Active scores computed directly from HealthKit reads (HRV, resting HR, respiratory rate, sleep, active energy); the model can auto-invoke this tool mid-chat, sending those derived Health values to whichever cloud provider is selected — not "text you deliberately submit."

## Details

The policy makes an absolute promise in `website/privacy/index.html`:

- Line 87–88: **"The app never transmits your Apple Health data anywhere.** The only exception is health text *you* deliberately submit to an AI feature, covered below."
- Line 144 (summary table): `Apple Health data | Apple Health, under iOS permissions | No` (does it leave the device? — No).

The shipping code contradicts the absolute framing. `toolGetReadiness` (`WinTheDay/Core/AppStore.swift:3121-3132`) returns the readiness bundle:

```swift
lines.append("Sleep \(e.sleepScore)/100, Readiness \(e.readiness)/100" +
             (e.activeScore.map { ", Active \($0)/100" } ?? ", Active: not computed") +
             (e.eatingScore.map { ", Eating \($0)/100" } ?? ", Eating: not enough data"))
```

Those scores are computed **from raw HealthKit samples**. `computeReadiness(for:health:)` (`AppStore.swift:2432` onward) reads them live from `HealthManager`:

```swift
let sleep = await health.fetchSleepDetail(nightEnding: day)          // AppStore.swift:2435
async let hrvMedian = health.fetchHRVOvernightMedian(nightEnding: day) // :2442
async let rhr       = health.fetchRestingHR(asOf: endOfDay)           // :2443
async let resp      = health.fetchRespiratoryRateOvernightMedian(...)  // :2444
```

These feed `ScoreEngine.Inputs` (`AppStore.swift:2485-2488`) → `ScoreEngine.compute` (`ScoreEngine.swift:54`), whose factors are explicitly HealthKit-derived: `hrvOvernightMedian` SDNN, `restingHR`, `respiratoryRate`, sleep duration, and active energy (`ScoreEngine.swift:27-34`, `98-135`). The results are written back to the entry as `sleepScore` / `readiness` / `activeScore` (`AppStore.swift:2511-2515`), which is exactly what `toolGetReadiness` echoes.

`getReadiness` is a registered coach tool the model can call on its own initiative during a chat — `CoachTools.swift:31-33`:

```swift
CoachTool(name: "getReadiness", description: "Get a day's Sleep/Readiness/Active/Eating scores and the factors behind them.",
          ... run: { store, args in store.toolGetReadiness(dateArg(args)) })
```

Per the audit charter, coach read tools return real user data to whichever provider is selected. When a cloud provider (Anthropic/OpenAI/Gemini/OpenRouter/DeepSeek/Ollama Cloud) is active, a tool call to `getReadiness` puts these HealthKit-derived scores into the request body sent off-device.

Mitigating nuance (why this is Low, not higher): the "What leaves your device" section does disclose that "the questions and **context in a coach conversation**" are sent to the provider (`index.html:98`), and these are aggregated 0–100 scores, not raw HealthKit samples. So the transmission itself is broadly disclosed and by-design. The defect is a **contradiction between two parts of the same policy**: the Apple Health section's unqualified "never transmits … anywhere" and its narrow carve-out for "health text *you* deliberately submit" do not cover values a tool auto-fetches, and the summary-table "No" row is flatly wrong for Health-derived data reaching a cloud coach.

## Failure / exploit scenario

Threat model (e), App Store review / privacy-compliance accuracy. A privacy-conscious user reads the Apple Health section, sees "The app never transmits your Apple Health data anywhere" and a summary table row that says Apple Health does not leave the device, and concludes they can freely use the AI coach with a third-party cloud provider (e.g. OpenAI) without any Health-derived data reaching it — because the only stated exception is *text they type themselves*. They open a coach chat and ask "how should I train today?"; the model autonomously calls `getReadiness`, and the response body sent to OpenAI now contains their HealthKit-derived Sleep 62/100, Readiness 48/100, Active 71/100 scores — data the user was told stays on device. There is no code exploit here; the harm is a materially misleading privacy representation that a reviewer or regulator could flag as inaccurate.

## Impact

The policy's absolute phrasing overstates the on-device guarantee for Apple Health. The leaked values are aggregated/derived scores (0–100), not raw samples, so the sensitivity is limited and the flow is disclosed elsewhere in the policy. But the internal inconsistency is real: a user relying specifically on the Apple Health section's "never leaves the device" + "only exception is text you deliberately submit" would not expect readiness/sleep numbers to reach a cloud provider from an auto-fired tool call. Policy-vs-code consistency is an explicit maintenance requirement for this file, and inaccurate privacy claims are an App Store review and compliance risk.

## Recommendation

Reconcile the Apple Health section with actual coach behavior. Concretely:

1. `index.html:87-88`: soften the absolute claim, e.g. "The app never uploads your raw Apple Health samples. Values **derived** from Health data — such as your Sleep, Readiness and Active scores — may be included when you use the AI coach with a cloud provider, as part of the coach conversation's context."
2. Broaden the "only exception" wording so it covers data a coach tool fetches automatically, not just text the user types.
3. `index.html:144` (summary table): change the Apple Health row's "No" to reflect the derived-score path, e.g. "Raw samples: No. Derived scores (sleep/readiness/active) may be sent to your chosen AI provider when you use the coach."

No code change is required; alternatively, if the intent is to keep the guarantee absolute, exclude HealthKit-derived fields from `toolGetReadiness`/coach tool output when a cloud provider is selected — but a policy edit is the proportionate fix.

## References

- App Store Review Guideline 5.1.1 (Data Collection and Storage — privacy policy accuracy)
- Apple HealthKit terms — disclosure of Health data use and sharing


---

_Finding PRIV-05. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._