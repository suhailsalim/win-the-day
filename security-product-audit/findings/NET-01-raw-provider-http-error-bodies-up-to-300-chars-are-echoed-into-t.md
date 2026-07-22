# NET-01 — Raw provider HTTP error bodies (up to 300 chars) are echoed into the user-visible AI error and persisted verbatim in coach chat history

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Network & transport |
| **Status** | CONFIRMED |
| **Location(s)** | _See Details below._ |

## Summary

On any non-2xx provider response, send() throws AIError.http(status, first 300 chars of the raw response body); that string is rendered verbatim in the UI and, in the coach path, appended as a persisted chat message that ships in plaintext backups. The provider body may quote back fragments of the offending request, which can include health-note / lab text.

## Details

Re-read confirms the reported code exactly.

`WinTheDay/AI/AIEstimator.swift:674-681` — the shared HTTP sender:
```swift
private func send(_ req: URLRequest) async throws -> Data {
    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw AIError.http(http.statusCode, String(body.prefix(300)))
    }
    return data
}
```
`send()` is the common path for every cloud provider request (anthropic, openAICompatible for openai/deepseek/ollamacloud/openrouter/ollama, and gemini all route their `URLRequest`s through it), so the echo is reachable on any provider error.

`WinTheDay/AI/AIEstimator.swift:12-22` renders it verbatim:
```swift
case .http(let code, let msg): return "Provider error \(code): \(msg)"
```

Confirmed two sinks for that string:
1. **Transient UI** — `WinTheDay/Core/AppStore.swift:1601` sets `aiErrorMessage = error.localizedDescription` (an `@Published` property, line 62) shown on-screen for estimator failures.
2. **Persistent, exportable** — `WinTheDay/Core/AppStore.swift:3071-3073` (coach chat) catches the error and appends it into the thread transcript:
```swift
} catch {
    threads[i].messages.append(ChatMessage(role: "assistant",
                                            text: "Couldn\u{2019}t reach the AI: \(error.localizedDescription)"))
}
```
This second sink is the meaningful amplifier the original report under-weighted: the error text is not merely a transient toast — it becomes a stored `ChatMessage` in the coach thread, which is part of the app data serialized into the plaintext backup export. So a fragment of the request body echoed back by the provider (which in the coach/estimator flows can contain the user's health notes, lab OCR text, or meal captions) can be written into durable, exportable storage.

I did not find any `print`/`os_log`/`NSLog` of the AI error, so the "loggable" claim is limited to the on-screen render plus the persisted chat message — no evidence of it reaching a system log or Console. The 300-char cap holds, bounding the leaked fragment.

Note the "attacker-controlled" framing is weak here: the provider is user-selected and a trusted TLS endpoint, and the data being echoed is the user's own health data shown back to the user on the user's own device. There is no cross-user or cross-boundary disclosure at the point of display. The real (small) hygiene concern is the durable persistence of an opaque provider string into the exportable transcript.

## Failure / exploit scenario

Under threat model (b) — someone holding the plaintext backup file or with Files.app / trusted-pairing access to the app's exposed Documents: the user pastes a health note / lab value into the coach and the selected provider (e.g. an OpenAI-compatible endpoint) rejects the request with a 400 whose body quotes the offending input back (several providers echo the rejected message). `send()` captures the first 300 chars of that body and `AppStore.swift:3073` writes `"Couldn't reach the AI: Provider error 400: …<echoed health-note fragment>…"` into the coach thread. That thread is serialized into the plaintext backup export, so the fragment now sits in a durable artifact rather than a transient toast. This is an information-hygiene leak, not a transport break — no interception or downgrade is involved, and at display time nothing crosses a trust boundary (it is the user's own data on the user's own screen).

## Impact

Minor. A bounded (≤300 char) fragment of a provider error body — which some APIs populate with an echo of the rejected request, potentially containing health-note / lab / meal text — can be surfaced in the UI and, more durably, stored verbatim in the coach chat transcript that is included in the plaintext backup export. No credentials leak (the key is a request header, not part of the response body). No network-transport weakness. Blast radius is capped by the 300-char prefix and by the fact that the exposed content is the user's own data.

## Recommendation

Do not propagate raw provider bodies to user-facing or persisted surfaces. In `AIError.errorDescription`, map `http(code, _)` to a friendly, body-free message (e.g. status-class based: "The AI provider rejected the request (400)." / "Rate limited (429) — try again shortly."). If the raw body is useful for debugging, keep it in a separate non-persisted, redacted debug field rather than in `errorDescription`. Independently, at `AppStore.swift:3071-3073`, avoid appending `error.localizedDescription` into the durable coach transcript — store a generic failure message in the thread and keep any detail in the transient `aiErrorMessage` only.


---

_Finding NET-01. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._