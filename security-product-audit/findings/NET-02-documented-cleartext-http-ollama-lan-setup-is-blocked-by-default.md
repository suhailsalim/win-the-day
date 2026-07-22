# NET-02 — Documented cleartext-HTTP Ollama LAN setup is blocked by default ATS (functional break) and steers users toward an unencrypted path for health-bearing prompts

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Network & transport |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | AI / Transport (Ollama local-model integration) |
| **Location(s)** | `WinTheDay/Core/Models.swift:1422`, `WinTheDay/Core/Models.swift:1476`, `WinTheDay/AI/AIEstimator.swift:416`, `WinTheDay/AI/AIEstimator.swift:668`, `WinTheDay/Settings/SettingsPages.swift:339`, `WinTheDay/Settings/SettingsPages.swift:346`, `Info.plist` |

## Summary

The Ollama integration defaults to and documents a cleartext `http://` LAN address for the local model server, but Info.plist declares no NSAppTransportSecurity exception. Under default ATS, cleartext to the documented non-loopback LAN IP is blocked, so the in-app setup instructions produce a silent functional failure, and they normalize sending the same health-bearing prompt bodies over an unencrypted channel.

## Details

All cited lines confirmed against source:

- `WinTheDay/Core/Models.swift:1422` — `var ollamaHost = "http://localhost:11434"` (cleartext default), and the tolerant decoder at `:1476` re-defaults to the same cleartext string.
- `WinTheDay/AI/AIEstimator.swift:665-668` — the completion path builds the request base directly from the user string: `let host = settings.ollamaHost.trimmingCharacters(...)` then `return try await openAICompatible(base: host + "/v1", keyName: nil, ...)`. The tool-calling loop does the identical thing at `:413-416`. So whatever scheme the user types (`http://…`) is used verbatim as the request base.
- `WinTheDay/Settings/SettingsPages.swift:339` — the settings field placeholder is literally `TextField("http://192.168.1.10:11434", …)`, i.e. a cleartext non-loopback LAN IP.
- `WinTheDay/Settings/SettingsPages.swift:346` — the help text: ``Run `OLLAMA_HOST=0.0.0.0 ollama serve` so your phone can reach it. localhost only works in the simulator.`` This explicitly tells the user that the safe default (localhost) does NOT work on a real device and that they must point the phone at the machine's LAN address — which the placeholder shows as `http://`.
- `Info.plist` (full file read) — contains no `NSAppTransportSecurity` dictionary at all; no `NSAllowsArbitraryLoads`, no `NSAllowsLocalNetworking`, no per-domain exception. A repo-wide grep for ATS keys across all `.plist` files returns nothing.

ATS behavior with these defaults:
- Loopback (`localhost`/`127.0.0.1`) is exempt from ATS, so the *default* config technically loads — but only reaches an Ollama server on the device itself, which is why the help text (correctly) says it "only works in the simulator."
- A numeric non-loopback LAN IP such as `192.168.1.10` is **not** ATS-exempt. Without `NSAllowsLocalNetworking` (or arbitrary-loads), a cleartext load to it is blocked by ATS. So the exact address the UI tells the user to enter will fail.

Net: the two real, code-grounded defects are (1) a functional break — the documented on-device setup cannot connect because ATS blocks it — and (2) the app normalizes an unencrypted transport for prompts that carry the same health content as the cloud providers.

## Failure / exploit scenario

Threat model (d), hostile/shared Wi-Fi, plus a plain functional-correctness failure:

1. Functional break (the reachable, shipped behavior): A user selects Ollama, follows the in-app instruction, and enters `http://192.168.1.10:11434`. Every completion (`AIEstimator.swift:668`) and every coach tool-call round trip (`:416`) issues a cleartext request to a non-loopback host. Default ATS blocks the load; the call fails with a transport error and the feature simply does not work, with no in-app explanation. This is the state of the shipped binary.

2. Latent confidentiality trap (contingent, not end-user reachable): The natural "fix" for the broken feature — by the developer, or a user rebuilding from source — is to add `NSAllowsArbitraryLoads`/`NSAllowsLocalNetworking` to Info.plist. Once that is done, the prompt bodies (meal descriptions, and coach chat that CoachTools surfaces: conditions, meds, injuries, lab/body-comp text) traverse the LAN in cleartext, readable by anyone sniffing the shared/hostile Wi-Fi. Note this leak is **not** reachable by an ordinary user of the App Store binary — Info.plist is baked at build time and there is no user setting that relaxes ATS — so the cleartext exposure only materializes for a maintainer who adds the exception.

## Impact

As shipped, the concrete impact is a broken on-device Ollama path (misleading UX: the app instructs a setup that ATS rejects). The health-data cleartext-leak impact is real but latent and not reachable by end users of the shipped app, because no ATS exception exists and Info.plist is not user-modifiable at runtime — it becomes live only if a maintainer relaxes ATS to make the feature work. Loopback/simulator use is safe. This bounds the security severity to Low: the transport-confidentiality exposure is contingent on a future code change, and the immediately reachable defect is functional rather than a data leak.

## Recommendation

Pick a coherent transport story rather than shipping instructions that ATS blocks:

1. Preferred: validate the `ollamaHost` field. Reject non-loopback `http://` hosts in `SettingsPages.swift` with an inline message ("Ollama over the local network must use https, or connect through a tunnel"), and fix the help text at `:346` so it no longer tells users to enter a cleartext LAN IP that cannot connect.
2. If cleartext LAN is genuinely intended for a self-hosted model, add a **scoped** `NSAllowsLocalNetworking` exception to `Info.plist` (not `NSAllowsArbitraryLoads`), and surface a one-time warning in the Ollama settings card that prompts — including coach chat containing conditions/meds/injuries — leave the device unencrypted on the local network.
3. At minimum, correct the misleading placeholder (`:339`) and help text (`:346`) so the documented setup matches actual ATS behavior, avoiding a silent functional failure.

## References

- Apple: App Transport Security (NSAppTransportSecurity, NSAllowsLocalNetworking, loopback exemption)
- CWE-319: Cleartext Transmission of Sensitive Information


---

_Finding NET-02. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._