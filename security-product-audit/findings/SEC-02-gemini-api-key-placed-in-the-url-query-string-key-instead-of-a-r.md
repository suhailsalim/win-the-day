# SEC-02 — Gemini API key placed in the URL query string (?key=...) instead of a request header

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Secrets & credentials |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | AI / networking (Gemini provider) |
| **Location(s)** | `WinTheDay/AI/AIEstimator.swift:458`, `WinTheDay/AI/AIEstimator.swift:751` |

## Summary

Both Gemini request paths embed the user's Gemini API key in the request URL's query string (`?key=<key>`), whereas every other provider passes its key in a request header. URL-borne secrets leak into more sinks (URLSession task metrics, os_log traces, crash logs, TLS-terminating proxies) than header values.

## Details

Both Gemini code paths build the endpoint with the key interpolated directly into the query string:

- `WinTheDay/AI/AIEstimator.swift:458` (tool-calling loop, `geminiToolSend`):
  ```swift
  let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")!
  ```
- `WinTheDay/AI/AIEstimator.swift:751` (completion/vision, `gemini`):
  ```swift
  let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")!
  ```

In both cases `key` is the real Gemini secret pulled from the Keychain (`let key = Keychain.get("gemini")` at lines 473 and 749), so this is a live credential, not a placeholder.

By contrast, every other provider passes its key in a header, confirmed in the same file:
- Anthropic: `req.setValue(key, forHTTPHeaderField: "x-api-key")` at lines 332 and 691.
- OpenAI-compatible family (OpenAI, OpenRouter, DeepSeek, Ollama Cloud): `req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")` at lines 391 and 724.

So Gemini is the sole outlier. The request is dispatched via `URLSession.shared.data(for: req)` in `send()` (line 675). On a non-2xx response `send()` throws `AIError.http(statusCode, body)` where `body` is the Gemini response body (line 677-678) — that error text does not contain the URL, so there is no direct key echo into error strings; the exposure is purely that the secret rides in the URL rather than a header. Gemini accepts the `x-goog-api-key` header as a drop-in alternative, so the header form is available with no functional change.

The report's factual claims all check out; severity Low is appropriate for this local-only iOS app (no server logs, HTTPS in transit).

## Failure / exploit scenario

Threat models (d)/(e). Traffic is HTTPS, so a passive Wi-Fi sniffer (threat d) cannot read the key on the wire — the report correctly concedes this. The realistic path is a TLS-terminating egress point or on-device diagnostic sink: a user on a corporate/MDM network with an installed root CA whose proxy logs full request URLs, or an on-device network-debugging/console capture, records `...generateContent?key=<the-actual-Gemini-secret>` verbatim. The Anthropic and OpenAI keys, carried in `x-api-key`/`Authorization` headers, are far less likely to be captured by URL-oriented logging. Anyone reading that proxy/diagnostic log can lift the Gemini key and run up API charges on the user's account.

## Impact

Elevated exposure of one specific credential (the Gemini key) relative to the app's other provider keys. Query-string secrets are captured by sinks that header values escape: URLSession task descriptions/metrics, `os_log` network traces, crash reports, on-device diagnostic captures, and any TLS-terminating proxy the user's network forces. Blast radius is a single third-party API key (billing abuse, quota exhaustion), not the user's health data. HTTPS still protects the value from passive network observers, which caps this at Low.

## Recommendation

Move the key out of the query string into the `x-goog-api-key` request header in both Gemini paths, matching the other providers:

```swift
let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
var req = URLRequest(url: url)
req.httpMethod = "POST"
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
```

Apply to both `geminiToolSend` (AIEstimator.swift:458) and `gemini` (AIEstimator.swift:751). This is behavior-preserving for the Gemini API and brings Gemini in line with the header-based key passing already used for Anthropic (x-api-key) and the OpenAI-compatible providers (Authorization: Bearer).

## References

- CWE-598: Use of GET Request Method With Sensitive Query Strings
- Google Generative Language API — x-goog-api-key header authentication


---

_Finding SEC-02. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._