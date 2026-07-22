# PROD-01 — Onboarding AI-provider picker frames cloud choice as a key/cost hurdle and never discloses that health data leaves the device

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | AI / LLM trust boundary |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | product-ux |
| **Location(s)** | `WinTheDay/App/OnboardingView.swift`, `WinTheDay/Core/Models.swift`, `WinTheDay/Settings/SettingsPages.swift` |

## Summary

The first-run "Pick your AI" step lets the user select (and defaults to) a cloud provider that transmits meal photos, labs and health notes off-device, but shows no egress disclosure at the point of choice — the "Meals are sent to <vendor>" footer exists only on the Settings page.

## Details

The onboarding Intelligence step's subtitle frames the cloud-vs-on-device decision purely as cost/key friction:

- `WinTheDay/App/OnboardingView.swift:211` — `page("✨", "Pick your AI", "Powers meal estimates, label scanning and your coach. Apple Intelligence is on-device & free; cloud providers need a key.")`. The only differentiator mentioned for cloud providers is that they "need a key."

Each provider row renders only the name and marketing tag, never the privacy footer:

- `WinTheDay/App/OnboardingView.swift:217-218` — `Text(p.name)…` and `Text(p.tag)…` (e.g. "GPT family", "Claude family"). The `AIProvider.foot` field is not referenced anywhere in `OnboardingView.swift`.

The disclosure text that would inform consent does exist in the model but is only surfaced on the Settings screen:

- `WinTheDay/Core/Models.swift:1898` — OpenAI's `foot`: `"Meals are sent to OpenAI for estimation. Standard API privacy applies."` (Anthropic/Gemini analogous at 1906+).
- `WinTheDay/Settings/SettingsPages.swift:118` — `Text(provider.foot)` is rendered on `IntelligencePage`, confirming the egress statement lives only in Settings, not in onboarding.

Two facts sharpen this beyond the original report:

1. **The default provider is cloud, not on-device.** `WinTheDay/Core/Models.swift:1419` — `var provider = "anthropic"` (and the tolerant decode at `1473` falls back to `"anthropic"`). So a user arriving at the Intelligence step finds a cloud provider (Anthropic) already selected/checkmarked and the `SecureField("Paste API key")` at `OnboardingView.swift:228` already visible — with no statement that pasting a key will cause their health data to be sent to Anthropic.

2. The `isCloud` flag the report cites for a fix genuinely exists and is ready to reuse — `WinTheDay/Core/Models.swift:1884` — `var isCloud: Bool { id != "apple" && !isLocal }`, documented as driving "the privacy footer & key prompt", yet it drives neither in the onboarding view.

Severity is Medium rather than High: this is an informed-consent/UX gap, not a technical vulnerability or a total absence of disclosure. The egress statement is present in Settings, and actual transmission still requires the user to deliberately obtain and paste an API key (with no key, the cloud call cannot fire). The gap is specifically that the most consequential privacy decision is presented at first run with the disclosure omitted at the point of choice.

## Failure / exploit scenario

Threat model (c)/(e). A privacy-conscious user installs the app for its "your data, your device" positioning. On the onboarding "Pick your AI" step they see Anthropic pre-selected (the default per `Models.swift:1419`) and a subtitle telling them only that "cloud providers need a key." Wanting meal scanning, they paste an API key. Nothing in the flow states that their meal photos, lab report OCR, and health notes will now be transmitted to a third-party cloud vendor — that sentence ("Meals are sent to Anthropic…") lives only on a Settings page they may never open. The single most consequential privacy decision in a health app is made without disclosure at the decision point, undermining the App Store privacy-nutrition/consent expectations for sensitive health data.

## Impact

Informed consent for off-device transmission of sensitive health data (meal photos, labs, conditions/meds via coach tools) is not obtained at the point where the user actually makes the choice. Because the default is already a cloud provider, the "on-device & free" framing nudges toward Apple while the pre-selected option is the opposite. This weakens the app's privacy positioning and its alignment with App Store health-data consent expectations, though real data egress still requires a deliberate key-paste, limiting blast radius.

## Recommendation

In the onboarding Intelligence step (`OnboardingView.swift:210-235`), surface the egress disclosure inline at the point of choice, gated on the already-existing `AIProvider.isCloud` flag (`Models.swift:1884`):

- When the selected provider `isCloud`, render `Text(Providers.provider(store.settings.provider).foot)` (and ideally an explicit "Your meal photos, labels and health notes will be sent to <vendor>." line) directly above the `SecureField("Paste API key")` at `OnboardingView.swift:228`, mirroring `SettingsPages.swift:118`.
- Consider showing each row's `p.foot` (or at least a one-line cloud/on-device tag distinction) so the choice isn't framed solely as "needs a key."
- Optionally reconsider defaulting `provider` to `"anthropic"` (`Models.swift:1419`); a privacy-first default of `"apple"` would make the on-device path the path of least resistance.

## References

- App Store Review Guideline 5.1.1 (data collection and disclosure/consent)
- Apple Privacy Nutrition Labels — health data category


---

_Finding PROD-01. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._