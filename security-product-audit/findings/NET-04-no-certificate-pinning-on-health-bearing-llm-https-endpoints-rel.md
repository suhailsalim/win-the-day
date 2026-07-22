# NET-04 — No certificate pinning on health-bearing LLM HTTPS endpoints (relies on system trust store)

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Network & transport |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Location(s)** | `WinTheDay/AI/AIEstimator.swift` |

## Summary

All outbound requests carrying sensitive health data (labs, meds, meal/InBody photos) to the selected LLM provider go through `URLSession.shared` with default TLS validation and no pinning delegate, so a compromised device trust store can transparently MITM the plaintext-over-TLS payloads.

## Details

The code fact is accurate. Every network call in the app funnels through the shared session with default trust evaluation, and there is no `URLSessionDelegate`, `URLAuthenticationChallenge` handler, `SecTrust`/`serverTrust` evaluation, or custom `URLSessionConfiguration` anywhere in the repo.

- `WinTheDay/AI/AIEstimator.swift:674-681` — the single send path for all LLM providers:
  ```swift
  private func send(_ req: URLRequest) async throws -> Data {
      let (data, resp) = try await URLSession.shared.data(for: req)
      if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { ... }
      return data
  }
  ```
- A repo-wide grep for `URLSessionDelegate`, `serverTrust`, `SecTrust`, `didReceive challenge`, `pinning`, and `URLSession(configuration:` returns **zero** matches — confirming no pinning is implemented anywhere.
- `URLSession.shared` is used identically in the other three network sites: `WinTheDay/Core/AppStore.swift:1670`, `WinTheDay/Managers/WeatherManager.swift:55`, `WinTheDay/Food/FoodLookup.swift:62`.
- The most sensitive payloads travel this path. Provider routing (`AIEstimator.swift:647-671`) sends prompts + base64 JPEG images to `https://api.anthropic.com/v1/messages` (`anthropic()`, line 688), OpenAI, Gemini, DeepSeek, OpenRouter, and `ollama.com`. All endpoints are `https://` literals, so transport is TLS-encrypted; the gap is purely the absence of pinning on top of that.

This is a genuine hardening gap, correctly rated **Informational**: it is not a live vulnerability. Standard system TLS already defeats an ordinary on-path Wi-Fi attacker (threat model (d)), and the app is local-only with user-supplied keys. Pinning only matters once the device trust store itself is subverted (attacker-installed or MDM/corporate root CA), which is a high bar and largely under the device owner's own control.

## Failure / exploit scenario

Under a modified threat model (d) where the network attacker can also get a root CA into the device trust store — e.g. a managed/MDM device with a corporate TLS-inspection root, or a user socially engineered into installing and trusting a configuration profile — the attacker terminates TLS at a proxy for `api.anthropic.com` (or any selected provider). Because `send()` performs only default trust evaluation and does no pinning, the proxy's cert chains to the injected trusted root and validation passes. The attacker then reads (and could alter) the plaintext request bodies, which per `anthropic()` (AIEstimator.swift:685-699) include the user's prompt and base64 JPEGs — meal photos, lab-report/InBody captures, and the health context assembled by the coach tools. On a device with an untampered trust store this is not reachable.

## Impact

Confidentiality (and integrity) of the most sensitive data the app transmits — health notes, lab values, meds/conditions, and meal/body photos sent to the cloud LLM. Exposure is conditional on a compromised device trust store, so it does not affect a normally-configured device and is a defensible hardening opportunity rather than an exploitable flaw in the app's own code.

## Recommendation

Optional hardening, not required for release:

- If pinning is desired, add a `URLSessionDelegate` that validates the server public key/SPKI against a pinned set for the fixed cloud endpoints (`api.anthropic.com`, `api.openai.com`, `generativelanguage.googleapis.com`, `api.deepseek.com`, `openrouter.ai`, `ollama.com`), and route `send()` through a session configured with that delegate. Budget for provider key rotation (pin to the CA or to multiple backup SPKIs to avoid outages).
- Do **not** pin the user-configured Ollama host (`AIEstimator.swift:664-669`) — it is arbitrary/self-hosted and often plain `http://` on LAN.
- Lower-effort alternative: document the trust-store assumption and rely on system TLS, which is appropriate for this local app's threat model. The separately-tracked issues (Gemini key in URL query string, Ollama cleartext HTTP, missing ATS config) are the higher-value transport items; pinning is secondary to those.

## References

- CWE-295: Improper Certificate Validation (here: absence of pinning, not misvalidation)
- OWASP MASVS-NETWORK-2: certificate/public-key pinning for sensitive endpoints


---

_Finding NET-04. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._