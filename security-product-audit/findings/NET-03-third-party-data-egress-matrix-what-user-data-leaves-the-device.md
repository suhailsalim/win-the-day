# NET-03 — Third-party data-egress matrix: what user data leaves the device per endpoint

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Location(s)** | _See Details below._ |

## Summary

Consolidated transport-layer inventory of every outbound HTTPS endpoint and the specific user data (health-sensitive LLM content, precise coordinates, food search terms/barcodes) it receives. All egress is HTTPS and by-design/disclosed; no health data is exposed via any query string.

## Details

This is a reference/consolidation record, not a new defect — the actionable transport issues are itemized in separate findings (Gemini key in URL, cleartext Ollama, no cert pinning, precise coordinates). Every claim below was re-read against source.

**LLM providers (only the single user-selected one is contacted per call).** Two entry points route to providers:

- `AIEstimator.complete(prompt:imageBase64:settings:jsonOnly:)` — `WinTheDay/AI/AIEstimator.swift:647`. The `switch settings.provider` (lines 649-676) dispatches to: `anthropic` → `api.anthropic.com`; `openai` → `https://api.openai.com/v1`; `gemini` → `generativelanguage.googleapis.com`; `deepseek` → `https://api.deepseek.com/v1` with **`image: nil`** (text-only, confirmed line 655: `prompt: prompt, image: nil, model: apiModel)  // text only`); `ollamacloud` → `https://ollama.com/v1`; `openrouter` → `https://openrouter.ai/api/v1`; `ollama` → user-set `settings.ollamaHost + "/v1"` (line ~672).
- `AIEstimator.chatWithTools(...)` — `WinTheDay/AI/AIEstimator.swift:301`. Routes the tool-calling coach loop to `anthropicToolChat` / `openAICompatToolChat` (openai/openrouter/deepseek/ollamacloud/ollama) / `geminiToolChat`, falling back to flattened `chat()` for `apple` or on any transport error (lines 314-324).

**Health-sensitive payloads reaching the selected provider** (all via `complete()` POST bodies, confirmed in `AIEstimator.swift`):
- Meal photos as base64 JPEG + caption — `estimateMealPhoto(imageBase64:...)` line 126, `complete(prompt: prompt, imageBase64: imageBase64, ...)` line 130.
- Body-composition (InBody) report text + photo — `parseBodyComp` line 47, `complete(... imageBase64: imageBase64 ...)` line 55.
- Full lab/health-checkup report text + photo — `parseLabs` line 70, line 84.
- Catalog/food item text + photo — `parseItem` line 163.
- Occasion/booking pasted text, week-plan context — text-only `complete` calls (lines 196, 224, 257, 287).
- Via the coach tool loop: real health data including **conditions, meds, injuries**, day logs and prayer records — `CoachTools.swift:43` `getHealthIndex` description confirms it returns "health notes (conditions/meds/injuries/goals)" plus imported lab analytes; these tool results are serialized into message content sent to the provider inside `chatWithTools`.

**Non-LLM endpoints:**
- `WeatherManager.fetch()` — `WinTheDay/Managers/WeatherManager.swift:48` builds `https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)...` — **precise lat/lon in the query string**, HTTPS.
- `FoodLookup.off(_:)` — `WinTheDay/Food/FoodLookup.swift:57` sends raw food **search terms** to `https://world.openfoodfacts.org/cgi/search.pl?search_terms=...` (percent-encoded, HTTPS, only on explicit "search online", not as-you-type per the comment at line 51-53).
- `AppStore.lookupBarcode(_:kind:)` — `WinTheDay/Core/AppStore.swift:1666` sends scanned **barcodes** to `https://world.openfoodfacts.org/api/v2/product/\(code).json?...`, HTTPS.

**Query-string exposure summary:** only the open-meteo coordinates and (per the separate Gemini finding) the Gemini API key ride in URLs. All LLM prompt/photo content and coach health data are POST request bodies, not URLs. No health data was found in any query string.

## Failure / exploit scenario

**Threat model (d) network attacker + (e) privacy-compliance.** No exploitable transport weakness is introduced by this consolidation itself. Under threat model (e), the concrete consequence is compliance accuracy: an App Store privacy manifest / policy must enumerate every third party listed here — up to seven LLM providers (Anthropic, OpenAI, Google/Gemini, OpenRouter, DeepSeek, Ollama Cloud, and any user-configured Ollama host), Open-Meteo, and Open Food Facts — and correctly declare the data categories they receive: **Health & Fitness** and **Sensitive Info** (labs, conditions, meds, injuries, body-comp, meal photos) to the LLM provider, and **Precise Location** to Open-Meteo. Under threat model (d), a Wi-Fi attacker sees only TLS-encrypted destinations for these HTTPS endpoints; the residual cleartext risk exists solely for a user-configured `http://` Ollama host, which is captured in its own finding.

## Impact

By design and disclosed in-app, health-sensitive content (labs, meds, conditions, injuries, body-composition, meal photos) egresses to whichever single cloud LLM the user selects, and precise coordinates egress to Open-Meteo. All egress is HTTPS. The material residual transport concerns are the ones tracked as separate findings (Gemini API key in URL query string; user-configurable cleartext `http://` Ollama host with no ATS restriction; absence of certificate pinning). This record's own impact is limited to ensuring privacy-compliance artifacts are complete and accurate.

## Recommendation

No transport code fix is warranted for this consolidation beyond the separately-itemized findings; retain the existing in-app disclosure that selected-provider egress occurs.

For App Store / privacy compliance (threat model e):
- Ensure the privacy policy and `PrivacyInfo.xcprivacy` (currently absent — see the privacy-manifest finding) enumerate all third parties: the LLM providers, `api.open-meteo.com`, and `world.openfoodfacts.org`.
- Declare the correct NSPrivacyCollectedDataTypes categories: **Health & Fitness / Sensitive Info** for LLM providers and **Precise Location** for Open-Meteo.
- Note that the set of possible LLM recipients is user-selectable across up to seven providers plus an arbitrary user-supplied Ollama host, so the disclosure should describe the category of recipient rather than imply a single fixed vendor.


---

_Finding NET-03. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._