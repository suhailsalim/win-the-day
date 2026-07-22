# Appendix — Win the Day Security & Product Audit

Supporting material for the [README](README.md) and the per-finding files in [`findings/`](findings/).

## Contents

1. [Scope](#scope)
2. [Methodology](#methodology)
3. [Threat models](#threat-models-considered)
4. [Severity rubric](#severity-rubric)
5. [Third-party data-flow matrix](#third-party-data-flow-matrix)
6. [Categories treated as not-applicable](#categories-deliberately-treated-as-na)
7. [Rejected & merged findings](#rejected--merged-findings)
8. [References](#references)
9. [Limitations](#limitations)
10. [Audit run statistics](#audit-run-statistics)

## Scope

**In scope.** The full Win the Day repository at branch `win-day-security-audit-8972ca` (commit `f2e504d`), ~32.6k LOC across all four targets and shared code:
- **WinTheDay** (iOS app) — `App/`, `Core/` (AppStore, BackupBundle, Keychain, PhotoStore, Models), `Managers/` (AppLock, PrayerManager, WeatherManager, HealthManager), `AI/` (AIEstimator, CoachTools), `Food/`, `Health/`, `Settings/`, `Trends/`, `Today/`, `UI/`, `Engines/`.
- **PrayerWidgetExt** (widgets, Live Activities, lock/home widgets, widget action intents).
- **WinTheDayWatch** (watchOS) and **WatchWidgetExt** (complications).
- **Shared/** cross-target types (notably `SharedSnapshot.swift`).
- Configuration and compliance surfaces: `Info.plist`, `*.entitlements`, `WinTheDay.xcodeproj/project.pbxproj` (HealthKit purpose strings), and the public `website/privacy/index.html`.

Focus areas: secret handling, data at rest (UserDefaults blobs, Documents files, photos, App-Group snapshot), transport/egress to third-party endpoints, the AI coach tool-calling trust boundary, app-lock coverage, backup/restore integrity, and privacy-disclosure/compliance accuracy — plus a product-UX/accessibility pass.

**Not in scope.** Server-side security (there is no server), multi-user/tenant isolation (single user by design), third-party provider internal security, and dynamic/runtime testing on physical hardware (this was a static source audit with cited `file:line` evidence).

## Methodology

The audit ran as a **fan-out / verify / synthesize** pipeline over the repository at commit `f2e504d` on branch `win-day-security-audit-8972ca` (~32.6k LOC across four targets).

1. **Parallel dimension finders.** Independent Opus finders were each scoped to one dimension — `secrets`, `data-at-rest`, `transport`, `ai-trust`, `auth` (app lock), `integrity` (backup/restore), `privacy` (disclosure/compliance), and `product-ux` — and were seeded with the concrete leads from the charter but explicitly instructed to confirm or refute each lead against real code and to find more. Every claim was required to cite `file:line`.
2. **Adversarial verification.** Each candidate finding was re-read by an independent verifier that re-opened the cited code, reproduced the reasoning, and either confirmed it, downgraded/upgraded severity, or rejected it. Several charter leads were sharpened in this pass — e.g., the Ollama cleartext lead was reframed as *also* a functional break under default ATS, the lock-screen-widget claim's "calories/protein/water" detail was corrected as inaccurate, and the "restored blobs unvalidated" and "no size cap" items were down-rated to Informational once it was shown they grant an attacker nothing beyond a well-formed hostile backup.
3. **Synthesis (this document).** Verified findings were deduplicated (four exact-duplicate pairs merged, keeping the stronger write-up), normalized to a single cross-dimension severity scale (Critical/High/Medium/Low/Informational), assigned stable `PREFIX-NN` IDs, and ordered most-severe-and-important first. Severity was calibrated to the local, single-user iOS threat models below rather than to a generic server-app rubric.

Findings were only reported when grounded in specific, cited code; generic checklist items with no code basis were excluded.

## Threat models considered

This is a local-only, single-user iOS app with no backend, so severity is weighted against on-device and disclosure threats rather than network-service threats.

- **(a) Brief physical access to an unlocked or briefly-unattended device.** The relevant question is what an opportunistic person can read or do in seconds. The app's Face ID lock is a UI shield only, and the Siri/Shortcuts surface sits outside it (AUTH-01, AUTH-02) — health/prayer data can be voiced or Spotlight-searched, and the day log can be mutated, on an unlocked-but-app-locked device.
- **(b) Possession of the exported backup file, or Files.app / Finder / iTunes file-sharing access, or a trusted-computer pairing.** The app deliberately exposes its `Documents` directory, which holds a plaintext-JSON health dump (with precise home GPS) and raw lab/body/meal photos (DATA-01, DATA-02), and a crafted archive can path-traverse on restore (INTG-01). This is the highest-impact model for this app.
- **(c) A malicious content author.** Text the user pastes or photographs (booking confirmations, OCR'd lab reports, meal captions, food names) flows into the LLM and back into the tool-calling loop. The realistic harm is prompt injection steering suggestions, unwanted Confirm cards, or over-sharing to the user's own provider (AI-01…04) — bounded by the Confirm-gate.
- **(d) A network attacker on shared/hostile Wi-Fi.** Nearly all egress is HTTPS; the only cleartext exposure is a user-configured non-loopback Ollama host (NET-02), and there is no certificate pinning (NET-04), so a compromised device trust store could MITM health-bearing TLS payloads.
- **(e) App Store review / privacy compliance.** The missing privacy manifest (PRIV-03), the understated HealthKit and camera purpose strings (PRIV-02, PRIV-04), and the inaccurate public privacy policy (PRIV-05, PRIV-06) are treated as first-class findings because they block or endanger submission and mislead users.

**Explicitly out of scope:** server-side authz/injection/SSRF (no server exists) and multi-user isolation (single user).

## Severity rubric

Severity is calibrated to a **local-only, single-user iOS app** — there is no server, so ratings weight on-device exposure, disclosure accuracy, and App Store compliance rather than remote exploitability.

| Severity | Meaning in this audit |
|---|---|
| 🔴 **Critical** | Trivially exploitable exposure or compromise of sensitive data with no meaningful precondition; or a guaranteed data-loss defect. (None found.) |
| 🔴 **High** | Full or near-full disclosure of the sensitive health record, or a serious integrity defect, reachable under a realistic threat model with a modest precondition (e.g. file-sharing / paired-computer access). |
| 🟠 **Medium** | Meaningful security, privacy, disclosure-accuracy, or accessibility defect requiring user action, physical access, a crafted input file, or an App-Store-blocking compliance gap. |
| 🟡 **Low** | Real weakness with a narrow precondition or bounded impact; defense-in-depth and UX-accuracy gaps. |
| ⚪ **Informational** | Hardening opportunities, transparency notes, and documented-for-completeness observations with no direct exploit path. |

## Third-party data-flow matrix

Every outbound destination and the specific user data that leaves the device to reach it. All cloud egress is by-design and disclosed in Settings; the concern is scope, precision, and (for one path) cleartext — not covert exfiltration.

| Endpoint | Data that leaves the device | Notes |
|---|---|---|
| `api.anthropic.com` (Anthropic) | Meal photos; and via coach tools: health notes, imported lab values, conditions, meds+doses, injuries, goals, HealthKit-derived readiness/sleep/active scores | HTTPS; key in `x-api-key` header. Only on user turns + model-invoked read tools. |
| `api.openai.com` (OpenAI) | Same class as above | HTTPS; `Authorization: Bearer`. |
| `generativelanguage.googleapis.com` (Gemini) | Same class as above | HTTPS, but **API key is in the URL query string** `?key=…` (SEC-02) — more log/proxy sinks than a header. |
| `openrouter.ai` (OpenRouter) | Same class as above | HTTPS; `Authorization: Bearer`; static non-identifying `HTTP-Referer`/`X-Title`. |
| `api.deepseek.com` (DeepSeek) | Same class as above | HTTPS; `Authorization: Bearer`. |
| `ollama.com` (Ollama Cloud) | Same class as above | HTTPS. |
| User self-hosted Ollama (`http://<LAN-IP>` or `localhost:11434`) | Same prompt bodies (health-bearing) | **Cleartext** if a non-loopback LAN IP is configured; also blocked by default ATS, so the documented setup silently fails (NET-02). |
| Apple Intelligence (on-device) | Nothing leaves the device | On-device inference. |
| `api.open-meteo.com` | **Full-precision** latitude/longitude | HTTPS; coordinates not rounded before egress (NET-05) — home-grade precision for a 7-day forecast. |
| `world.openfoodfacts.org` | Food search terms; scanned barcode payloads | HTTPS. Search term percent-encoded (good); scanned **barcode not percent-encoded** (NET-06). |
| iCloud Drive / Files / any paired computer (backup export + Files sharing) | **Entire plaintext health record**: all blobs, precise `prayer_lat`/`prayer_lon`, base64 lab/InBody/meal photos | Unencrypted JSON, no passphrase option; `Documents` also exposed via `UIFileSharingEnabled` (DATA-01/DATA-02). API keys correctly excluded. |

## Categories deliberately treated as N/A

Because the app is local-only, single-user, and backend-free, several standard audit categories do not apply and were intentionally excluded rather than reported as empty findings:

- **Server-side authorization / access control** — no server, no accounts, no sessions. There is nothing to authorize.
- **Injection into a backend (SQLi / NoSQLi / command injection / SSRF)** — no server-side query engine or request-forwarding component exists. (Client-side URL-building hygiene *is* covered, e.g. NET-06.)
- **Multi-user / multi-tenant data isolation** — a single device owner is the only principal; there is no cross-user boundary to breach.
- **Authentication server security (password storage, token issuance, session fixation, brute-force)** — there is no auth server; the only "auth" is a local biometric UI gate, assessed under AUTH-*.
- **Transport secrecy for provider-to-provider traffic** — once data reaches a chosen cloud LLM, its handling is the provider's responsibility and is disclosed to the user; the audit covers only what leaves the device and how (see NET-* and the data-flow matrix).
- **Rate limiting / DoS of a service** — no service is operated; the only availability concern is self-inflicted (INTG-03, import OOM), which is reported.
- **Secret rotation / server-side key management** — keys are user-supplied and stored in the device Keychain; there is no server vault to manage.

## Rejected & merged findings

Transparency on what did **not** make the report.

### Rejected after verification

- **Coach tool results lack a length cap (health data transmission is disclosed-by-design; per-iteration "re-send" is inherent to stateless LLM APIs, not a defect)** — I re-read AppStore.swift `toolGetFoodLog` (3134), `toolGetHealthIndex` (3144-3162), `exportDayText` (1940-1971), `healthIndex` (2539-2563), and `biologyDigest` (2367-2391), plus the Anthropic tool loop in AIEstimator.swift (321, 340-377) and the OpenAI-compatible send (381-399). This refuted the finding's two core claims: (1) `exportDayText` is a single-day, mostly-structured export and `healthIndex`/`biologyDigest` already cap labs at prefix(12) and analytes at prefix(24) — only `healthNotes` and single-day free text are uncapped, so "unbounded" is overstated; (2) the "re-sent every iteration" concern is inherent statelessness of the Messages/Chat-Completions APIs (messages appended once each at 356/363, resent because the endpoints hold no session), so it is not an app-introduced leak and the report's recommended remedy is not implementable. The underlying transmission is disclosed-by-design to a user-selected provider. This reduces the finding to a minor, optional hygiene note — Informational, not a Low-severity privacy defect.

### Merged as duplicates

Four candidate findings were merged into stronger write-ups of the same root issue during synthesis:

Four merges, all exact-duplicate root issues where two dimension-finders independently surfaced the same defect; kept the stronger write-up each time. (1) idx 9 "Gemini key in URL" dropped in favor of idx 1, which enumerates the concrete leak sinks (URLSession metrics, os_log, crash logs, TLS-terminating proxies). (2) idx 2 "provider error body echoed" dropped in favor of idx 10, which additionally establishes the body is persisted verbatim into coach chat history and rides plaintext backups and may quote back health/lab text. (3) idx 5 "path traversal on restore" (Low) dropped in favor of idx 25 (High) — same root cause, stronger analysis; final severity normalized to Medium (see below). (4) idx 8 "no privacy manifest" (Informational) dropped in favor of idx 29 (Low), which correctly frames it as a hard App Store upload blocker since 1 May 2024. Genuinely distinct-but-adjacent items were kept separate: the unencrypted-backup content (DATA-02), its file-sharing exposure surface (DATA-01), the in-app UI non-disclosure (PROD-06), and the privacy-policy omission (PRIV-06) each have different owners and remediations, so they remain four findings. Severity normalization: idx 25 path traversal reconciled from the Low/High split to Medium — it writes attacker-controlled bytes but only within the app's own sandbox and only after the user chooses to import a crafted archive (threat model (b)).

## References

- **Apple — Data Protection & File Protection classes** (`NSFileProtectionComplete`, `…CompleteUntilFirstUserAuthentication`, `…None`) — relevant to DATA-01/03/04.
- **Apple — Keychain item accessibility constants** (`kSecAttrAccessibleAfterFirstUnlock` vs `…ThisDeviceOnly`) — SEC-01.
- **Apple — App Transport Security (ATS)** and `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` guidance — NET-02.
- **Apple — Privacy manifest files (`PrivacyInfo.xcprivacy`) and required-reason APIs** (`NSPrivacyAccessedAPICategoryUserDefaults`), mandatory for uploads since 1 May 2024 — PRIV-03.
- **Apple — Protecting user privacy / purpose strings** (`NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`) — PRIV-02, PRIV-04.
- **Apple — App Store privacy "nutrition label" (data collection & use disclosure)** — PRIV-01, PRIV-05, PRIV-06.
- **Apple — File Sharing (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`)** — DATA-01.
- **Apple Human Interface Guidelines — 44×44pt minimum tap target; Accessibility (Dynamic Type, VoiceOver traits/values)** — PROD-03, PROD-04, PROD-07.
- **WCAG 2.1 SC 1.4.3 Contrast (Minimum)** — PROD-05.
- **CWE-22** Path Traversal (INTG-01); **CWE-312** Cleartext Storage of Sensitive Information (DATA-02); **CWE-319** Cleartext Transmission (NET-02); **CWE-598** Information Exposure Through Query Strings (SEC-02); **CWE-532** Insertion of Sensitive Information into Log/Error (NET-01); **CWE-400** Uncontrolled Resource Consumption (INTG-03).
- **OWASP MASVS / MSTG** — mobile storage, platform, and network verification standards.
- **OWASP Top 10 for LLM Applications — LLM01 Prompt Injection** — AI-01…04.

## Limitations

- This was a **static source audit** with cited `file:line` evidence; no dynamic/runtime testing, no on-device instrumentation, and no live traffic capture were performed. Exploit scenarios are reasoned from the code, not executed.
- Severity reflects the **local, single-user, backend-free** architecture. A future change that adds a server, sync, or accounts would require re-rating.
- Findings are pinned to commit `f2e504d`. Line numbers may drift as the code evolves; re-verify against the current tree before acting.
- The audit reviewed the four app targets, shared code, configuration, and the public privacy policy. It did not review third-party provider security, the Xcode project's full build settings beyond signing-relevant items, or the marketing website beyond the privacy page.

## Audit run statistics

| Metric | Value |
|---|---|
| Agents run | 52 (8 finders + per-finding verifiers + 1 synthesis) |
| Agent errors | 0 |
| Findings raised → verified → kept | 43 → 42 confirmed/plausible → 38 after merge |
| Rejected | 1 |
| Merged as duplicates | 4 |
| Model | Claude Opus (high reasoning effort) for every agent |
