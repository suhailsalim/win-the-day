# PRIV-01 — In-app cloud-transmission disclosure is scoped to "Meals are sent" while the coach also transmits conditions, meds, injuries, and lab values

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Location(s)** | `WinTheDay/Core/Models.swift`, `WinTheDay/AI/CoachTools.swift`, `WinTheDay/Core/AppStore.swift`, `WinTheDay/Coach/CoachChatView.swift`, `WinTheDay/Today/TodayView.swift`, `WinTheDay/Coach/CoachChatListView.swift`, `WinTheDay/Settings/SettingsPages.swift`, `docs/features/coach-ai.md` |

## Summary

The only in-app disclosure of third-party transmission (the provider footer) is worded "Meals are sent to <vendor> for estimation," but the coach's getHealthIndex tool sends the user's conditions, medications (with doses), injuries, goals, and every imported lab analyte to the same cloud provider — an under-scoped disclosure for the most sensitive data class the app holds.

## Details

The single in-app disclosure of cloud transmission is `AIProvider.foot`, rendered only in AI provider settings:

- `WinTheDay/Settings/SettingsPages.swift:118` — `Text(provider.foot)`
- For every cloud vendor the string is scoped to meals, e.g. `Models.swift:1898` `foot: "Meals are sent to OpenAI for estimation. Standard API privacy applies."`; identical pattern for Anthropic (`:1906`), Google (`:1914`), DeepSeek (`:1932`), and Ollama Cloud (`:1948`). None mentions health notes, medications, or labs.

The coach, however, has a read tool that emits exactly that clinical data to the selected provider:

- `WinTheDay/AI/CoachTools.swift:43` — `getHealthIndex` description: "health notes (conditions/meds/injuries/goals)… every lab analyte they have imported."
- `WinTheDay/Core/AppStore.swift:3144-3162` `toolGetHealthIndex()` confirms the payload: health notes (`healthIndex()`), a `SCHEDULED MEDS/SUPPLEMENTS (user's own record...)` section built from `activeRegimens` including `r.dose` (`:3148-3158`), and a lab `biologyDigest()` (`:3159`). Whatever this returns is fed back into the provider's chat/tool-calling loop, i.e. sent to the cloud vendor.

The coach's own entry points reinforce a local mental model rather than disclosing transmission:

- `WinTheDay/Coach/CoachChatView.swift:92` — "Ask me anything… I can see your logs."
- `WinTheDay/Today/TodayView.swift:1132` — "Your AI coach can see your logs — ask it anything."
- `WinTheDay/Coach/CoachChatListView.swift:66` — "Start a conversation — Coach can see your logs."

"Can see your logs" reads as on-device inspection, never third-party transmission of medical records. The project's own docs already flag the gap: `docs/features/coach-ai.md:27` — "the health index (notes + lab values) is sent to the selected AI provider, same as meal[s]." The UI has not been updated to match.

## Failure / exploit scenario

Threat model (c)/(e): A user imports lab reports and a medication list, then selects a cloud provider and enters an API key. At that setup step the footer says only "Meals are sent to <vendor> for estimation," and the coach surfaces ("can see your logs") imply local inspection. Believing clinical data stays on-device, the user asks the coach a health question; the model calls `getHealthIndex`, and their diagnoses, medication names + doses, injuries, and lab values are transmitted to the third-party vendor — a disclosure the user was never shown in-app.

## Impact

The most sensitive data class the app holds (diagnoses, medications with doses, injuries, lab values) leaves the device to a third party while the only in-app disclosure names only "meals." This is a material disclosure-accuracy gap affecting informed consent and user trust, and a weak point for App Store privacy-label accuracy. It is not a covert exfiltration: transmission is intended behavior, requires deliberate cloud-provider setup where a (narrower) disclosure is shown, and the on-device Apple Intelligence and local Ollama options carry accurate "nothing leaves" footers — which is why this is Medium rather than High.

## Recommendation

Broaden the cloud-provider `foot` strings in `Models.swift` from "Meals are sent…" to name the full surface, e.g. "Your meals, health notes, and imported labs are sent to <vendor> when you use estimation or the coach." Add a one-line disclosure inside the coach itself — in the empty state (`CoachChatView.swift:92`) and/or on first send to a cloud provider — stating that the conversation and the logs/health data it reads are sent to <vendor>. Replace or supplement the "can see your logs" copy at `CoachChatView.swift:92`, `TodayView.swift:1132`, and `CoachChatListView.swift:66` so it does not imply purely local inspection. The behavior is already documented at `docs/features/coach-ai.md:27`; align the UI to it.

## References

- Apple App Store Review Guidelines 5.1.1 (Data Collection and Storage — accurate disclosure)
- Apple Privacy Nutrition Labels (Health & Fitness data type)


---

_Finding PRIV-01. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._