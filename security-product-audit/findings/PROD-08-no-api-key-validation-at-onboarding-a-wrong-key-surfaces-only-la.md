# PROD-08 — No API-key validation at onboarding; a wrong key surfaces only later as a raw provider error

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Product & UX |
| **Status** | CONFIRMED |
| **Location(s)** | _See Details below._ |

## Summary

The onboarding Intelligence step writes a pasted API key straight to Keychain with no "Test connection" affordance, so a wrong or truncated key is not detected until a later meal estimate or coach message fails with a raw provider error string. Real UX/activation gap, but no security impact.

## Details

All four cited locations reproduce exactly as reported.

**Onboarding writes the key with no validation** (`WinTheDay/App/OnboardingView.swift:227-233`):
```swift
if Providers.provider(store.settings.provider).needsKey {
    SecureField("Paste API key", text: $apiKey)
        .font(.system(size: 15)).textInputAutocapitalization(.never).autocorrectionDisabled()
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceOverlay))
        .onChange(of: apiKey) { _, v in Keychain.set(v, for: store.settings.provider) }
}
```
The key is persisted to Keychain character-by-character via `.onChange`; there is no "Test connection" control anywhere in the onboarding step.

**The test affordance exists only in Settings** (`WinTheDay/Settings/SettingsPages.swift:234-301`). `testConnectionCard` renders a "Test connection" button whose `runTest()` (line 291-301) calls `store.testAIConnection()` and surfaces `.ok` / `.failed` states. This card is not present in the onboarding flow — note the key field in Settings at line 228 uses the same `.onChange { Keychain.set(...) }` pattern but is accompanied by the test card, whereas onboarding is not.

**First feedback is a raw error string.** In the coach path (`WinTheDay/Core/AppStore.swift:3071-3073`):
```swift
} catch {
    threads[i].messages.append(ChatMessage(role: "assistant",
        text: "Couldn\u{2019}t reach the AI: \(error.localizedDescription)"))
}
```
And the underlying error for a rejected key (`WinTheDay/AI/AIEstimator.swift:16`):
```swift
case .http(let code, let msg): return "Provider error \(code): \(msg)"
```
Only the *missing*-key case is actionable (`AIEstimator.swift:14`: `case .noKey: return "No API key set for this provider. Add one in Settings → Intelligence."`). A *wrong* key produces `AIError.http(401, …)`, which renders as "Provider error 401: …" with no pointer back to the key field.

This is a genuine product/activation defect, but it carries no security or privacy consequence under any of the stated threat models — the key stays in the Keychain, nothing is leaked, and no attacker capability is created. It is Informational for a security audit.

## Failure / exploit scenario

A new user reaches the onboarding Intelligence step, selects a cloud provider (e.g. Anthropic/OpenAI), and pastes an API key that is slightly wrong or truncated on copy. Nothing signals a problem; setup completes. Days later they scan a meal label or message the coach and receive "Provider error 401: …" or "Couldn't reach the AI: …" with no indication the cause is the key or where to fix it. They must independently discover Settings → Intelligence → Test connection. This is an activation/onboarding failure, not a security exposure.

## Impact

Degraded onboarding for the app's core AI value proposition: a setup-time typo in the key is not caught at entry and later manifests as an opaque HTTP/error string rather than an actionable "that key was rejected — re-check it in Settings → Intelligence." No confidentiality, integrity, or availability impact; no attacker benefit. Product-quality only.

## Recommendation

Reuse the existing `store.testAIConnection()` in the onboarding Intelligence step: add a lightweight "Test key" button next to the `SecureField` (mirror `SettingsPages.testConnectionCard` / `runTest()`), so a bad key is caught during setup. Separately, map common provider auth codes (401/403) in `AIError.http` — or at the `AppStore` catch site (`AppStore.swift:3072`) — to an actionable message pointing back to Settings → Intelligence rather than echoing the raw provider string. Neither change is security-motivated; prioritize as UX polish.


---

_Finding PROD-08. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._