# Win the Day — Security & Product Audit

_Static source audit of the Win the Day iOS app (SwiftUI, iOS 17+, four targets, ~32,600 LOC)._

| | |
|---|---|
| **Target** | Win the Day — local-only health & discipline tracker |
| **Repository state** | branch `win-day-security-audit-8972ca`, commit `f2e504d` |
| **Audit date** | 22 July 2026 |
| **Scope** | iOS app, watchOS app, widgets, complications, shared code, Info.plist / entitlements, privacy policy |
| **Method** | Parallel multi-agent static review (8 dimension finders → adversarial per-finding verification → synthesis) |
| **Findings** | 38 confirmed (1 High · 11 Medium · 16 Low · 10 Informational) |

> **Headline:** The app's biggest gap is **data at rest**. A rolling, unencrypted plaintext JSON copy of the entire health record — labs, conditions, medications, meal history, prayer records, coach chat, and precise home GPS — plus a folder of raw lab/InBody/meal photos, sit in the app's `Documents` directory, which is exposed to the Files app and any paired computer via file sharing. None of it is protected by the app's Face ID lock, which is a UI shield only. See **[DATA-01](findings/DATA-01-plaintext-health-backup-and-raw-health-photos-are-exposed-via-it.md)**.

## Executive summary

Win the Day is a local-only, single-user iOS 17+ health and discipline tracker with no backend, no accounts, and no server-side attack surface. That architecture eliminates whole classes of risk up front — there is no authz to bypass, no multi-tenant data to cross, no injectable server. The team has also made several deliberately good calls: no app-wide ATS bypass, every cloud LLM endpoint forced to HTTPS, secrets kept in the Keychain and correctly excluded from backups, EXIF/GPS stripped from imported photos at capture, and a staged-then-committed restore that leaves the device untouched if an import fails. The AI coach's write tools only *stage* a proposal that the user must physically Confirm, which meaningfully caps the blast radius of prompt injection.

The residual risk therefore concentrates in three places: **data at rest**, **disclosure accuracy**, and **accessibility**. The single most consequential issue (DATA-01, High) is that `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` expose the app's `Documents` directory — which holds a rolling plaintext-JSON backup of the entire health record (including full-precision home GPS) plus a folder of raw lab/InBody/meal photo JPEGs — to Files.app and to any paired/trusted computer. None of this is protected by the app's Face ID lock, which by its own documentation is "purely a UI shield." The backup itself is unencrypted with no passphrase option (DATA-02), and a crafted archive can path-traverse out of the photos directory on restore (INTG-01).

A second cluster is **disclosure honesty**, which for a health app is both a trust and an App Store-compliance matter. The Face ID lock's copy promises that "health notes, labs, prayer records and photos stay private," yet the same photos are copyable while the app is locked, the lock does not cover the Siri/Shortcuts surface (AUTH-02), and the app-switcher cover is gated on a toggle that is off by default (AUTH-04). The HealthKit purpose strings claim "steps/weight" read and "calories/protein" write while the code touches heart rate, HRV, sleep, body composition, blood glucose and blood oxygen (PRIV-02). The in-app "Meals are sent to <vendor>" footer is the only transmission disclosure, but the coach also ships conditions, medications with doses, injuries and every lab analyte to the selected cloud provider (PRIV-01), and the onboarding provider picker discloses no egress at the point of choice (PROD-01). The public privacy policy's absolute "never transmits your Apple Health data anywhere" is contradicted by the coach's readiness/sleep tools (PRIV-05). Separately, the absence of any `PrivacyInfo.xcprivacy` manifest is a hard upload blocker (PRIV-03).

A third cluster is **accessibility and product safety**: app-wide hardcoded font sizes defeat Dynamic Type entirely (PROD-03), hand-built toggles are invisible to VoiceOver (PROD-04), secondary text falls below WCAG AA contrast on the transparent "liquid glass" surfaces (PROD-05), and "Run setup again" is an inescapable full-screen flow seeded from hardcoded defaults that silently deactivates the user's habits and modules (PROD-02). The AI-trust findings (AI-01…04) are all real but structurally bounded by the Confirm-gate and by the fact that any over-sharing goes only to the user's own chosen provider. Overall posture: a privacy-conscious local app whose biggest gaps are unencrypted at-rest data reachable without the app's own lock, and disclosures/consent that understate what the app actually reads and transmits.

## Severity summary

| Severity | Count |
|---|---:|
| 🔴 High | 1 |
| 🟠 Medium | 11 |
| 🟡 Low | 16 |
| ⚪ Informational | 10 |
| **Total** | **38** |

## Top risks

- **Plaintext health data + raw lab/body photos + precise home GPS are copyable off the device without ever unlocking the app** (DATA-01, DATA-02). File sharing exposes `Documents`, the backup is unencrypted JSON with no passphrase option, and Face ID does not protect files at rest — the app's central privacy promise does not hold against threat models (a) and (b).
- **The Face ID "App lock" is a UI shield that under-delivers on an explicit privacy promise** (AUTH-01, AUTH-02, AUTH-04): its copy names "health notes, labs, prayer records and photos," yet those photos are file-shareable while locked, the Siri/Shortcuts surface reads and *writes* day data with no lock check, and the app-switcher privacy cover is off by default.
- **Consent and disclosure understate what the app reads and sends** (PRIV-01, PRIV-02, PRIV-04, PRIV-05, PROD-01): HealthKit purpose strings, camera/photo strings, the in-app "Meals are sent" footer, the onboarding picker, and the public privacy policy all describe less scope and less off-device transmission than the code actually performs — a trust risk and an App Store review risk.
- **A crafted backup archive can path-traverse on restore** (INTG-01): unsanitized photo filenames from an untrusted archive are joined with `appendingPathComponent`, writing attacker-controlled bytes to an arbitrary path inside the sandbox.
- **App cannot ship as-is: no `PrivacyInfo.xcprivacy` manifest** (PRIV-03) despite pervasive required-reason UserDefaults use across all four targets — an automatic upload rejection since 1 May 2024.
- **Core accessibility is broken** (PROD-02…05): Dynamic Type has no effect anywhere, custom toggles are silent to VoiceOver, faint text fails WCAG AA contrast, and a destructive "Run setup again" flow can silently wipe the user's habit/module configuration.

## All findings

Ordered most-severe-and-important first. Each links to its own file under [`findings/`](findings/).

| ID | Severity | Area | Finding |
|---|---|---|---|
| [DATA-01](findings/DATA-01-plaintext-health-backup-and-raw-health-photos-are-exposed-via-it.md) | 🔴 High | Data at rest | Plaintext health backup and raw health photos are exposed via iTunes/Files file sharing |
| [DATA-02](findings/DATA-02-backup-archive-is-unencrypted-plaintext-and-embeds-full-precisio.md) | 🟠 Medium | Privacy & compliance | Backup archive is unencrypted plaintext and embeds full-precision GPS location — with no user-facing encryption option |
| [INTG-01](findings/INTG-01-path-traversal-arbitrary-sandbox-file-write-via-attacker-control.md) | 🟠 Medium | Integrity & restore | Path traversal / arbitrary sandbox file write via attacker-controlled photo filenames on backup restore |
| [AUTH-01](findings/AUTH-01-face-id-lock-promises-health-notes-labs-prayer-records-and-photo.md) | 🟠 Medium | Privacy & compliance | Face ID lock promises "health notes, labs, prayer records and photos stay private," but it is a UI-only shield with zero at-rest protection |
| [AUTH-02](findings/AUTH-02-app-s-face-id-app-lock-does-not-cover-the-siri-shortcuts-surface.md) | 🟠 Medium | App lock & auth | App's Face ID "App lock" does not cover the Siri/Shortcuts surface — score, prayers, water and location-derived next-prayer time are readable, and the day log is writable, on an unlocked-but-app-locked device |
| [PRIV-01](findings/PRIV-01-in-app-cloud-transmission-disclosure-is-scoped-to-meals-are-sent.md) | 🟠 Medium | Privacy & compliance | In-app cloud-transmission disclosure is scoped to "Meals are sent" while the coach also transmits conditions, meds, injuries, and lab values |
| [PRIV-02](findings/PRIV-02-healthkit-purpose-strings-understate-read-write-scope-heart-hrv.md) | 🟠 Medium | Privacy & compliance | HealthKit purpose strings understate read/write scope (heart, HRV, sleep, body composition read; blood glucose & blood-oxygen written) — "steps/weight" and "calories/protein" only |
| [PROD-01](findings/PROD-01-onboarding-ai-provider-picker-frames-cloud-choice-as-a-key-cost.md) | 🟠 Medium | AI / LLM trust | Onboarding AI-provider picker frames cloud choice as a key/cost hurdle and never discloses that health data leaves the device |
| [PROD-02](findings/PROD-02-run-setup-again-replays-onboarding-from-hardcoded-defaults-with.md) | 🟠 Medium | Product & UX | "Run setup again" replays onboarding from hardcoded defaults with no Cancel, silently deactivating habits/modules the user relies on |
| [PROD-03](findings/PROD-03-app-wide-fixed-font-sizes-dynamic-type-larger-text-accessibility.md) | 🟠 Medium | Product & UX | App-wide fixed font sizes — Dynamic Type / "Larger Text" accessibility setting has no effect anywhere |
| [PROD-04](findings/PROD-04-custom-settings-toggles-expose-no-voiceover-value-or-toggle-trai.md) | 🟠 Medium | Product & UX | Custom Settings toggles expose no VoiceOver value or toggle trait — the switch announces only "button" with no on/off state |
| [PROD-05](findings/PROD-05-secondary-ink-colors-tertiaryink-quaternaryink-fall-below-wcag-a.md) | 🟠 Medium | Product & UX | Secondary ink colors (tertiaryInk/quaternaryInk) fall below WCAG AA contrast for the 10–13px state-bearing text they render, worsened by the transparent "liquid glass" surfaces |
| [SEC-01](findings/SEC-01-provider-api-keys-stored-with-ksecattraccessibleafterfirstunlock.md) | 🟡 Low | Secrets & credentials | Provider API keys stored with kSecAttrAccessibleAfterFirstUnlock (not …ThisDeviceOnly) — they ride encrypted device backups off the original device |
| [SEC-02](findings/SEC-02-gemini-api-key-placed-in-the-url-query-string-key-instead-of-a-r.md) | 🟡 Low | Secrets & credentials | Gemini API key placed in the URL query string (?key=...) instead of a request header |
| [PRIV-03](findings/PRIV-03-no-privacyinfo-xcprivacy-manifest-required-reason-userdefaults-a.md) | 🟡 Low | Privacy & compliance | No PrivacyInfo.xcprivacy manifest — required-reason UserDefaults API undeclared (App Store upload/review blocker) |
| [PRIV-04](findings/PRIV-04-camera-photo-library-purpose-strings-claim-only-nutrition-label.md) | 🟡 Low | Privacy & compliance | Camera/Photo-Library purpose strings claim only "nutrition label" use, but the same pickers capture lab & body-composition reports and meal photos that are sent to a third-party cloud LLM |
| [PRIV-05](findings/PRIV-05-privacy-policy-s-absolute-never-transmits-your-apple-health-data.md) | 🟡 Low | Privacy & compliance | Privacy policy's absolute "never transmits your Apple Health data anywhere" is contradicted by HealthKit-derived readiness/sleep/active scores the coach auto-fetches and sends to cloud providers |
| [DATA-03](findings/DATA-03-health-photos-auto-backup-and-export-json-written-without-explic.md) | 🟡 Low | Data at rest | Health photos, auto-backup, and export JSON written without explicit NSFileProtection (default UntilFirstUserAuthentication only) |
| [NET-01](findings/NET-01-raw-provider-http-error-bodies-up-to-300-chars-are-echoed-into-t.md) | 🟡 Low | Network & transport | Raw provider HTTP error bodies (up to 300 chars) are echoed into the user-visible AI error and persisted verbatim in coach chat history |
| [NET-02](findings/NET-02-documented-cleartext-http-ollama-lan-setup-is-blocked-by-default.md) | 🟡 Low | Network & transport | Documented cleartext-HTTP Ollama LAN setup is blocked by default ATS (functional break) and steers users toward an unencrypted path for health-bearing prompts |
| [AI-01](findings/AI-01-coach-tool-loop-runs-every-model-requested-tool-with-no-relevanc.md) | 🟡 Low | AI / LLM trust | Coach tool-loop runs every model-requested tool with no relevance gate; poisoned stored content (food names, meal text, health notes, OCR'd lab names) re-enters as tool_result and can steer extra tool calls — bounded to over-sharing to the user's own provider and unwanted Confirm cards |
| [AI-02](findings/AI-02-planoccasion-and-mealphotoprompt-frame-untrusted-pasted-caption.md) | 🟡 Low | AI / LLM trust | planOccasion and mealPhotoPrompt frame untrusted pasted/caption text as instructions to "honor"/"trust", inviting prompt injection into AI suggestions |
| [AI-03](findings/AI-03-logfood-confirm-card-summary-embeds-the-model-supplied-food-name.md) | 🟡 Low | AI / LLM trust | logFood Confirm-card summary embeds the model-supplied food name with no length cap, unlike setMealText |
| [AI-04](findings/AI-04-flattened-fallback-chat-folds-history-into-one-prompt-with-user.md) | 🟡 Low | AI / LLM trust | Flattened fallback chat() folds history into one prompt with "User:"/"Coach:" role prefixes, enabling turn forgery on the non-tool path |
| [AUTH-03](findings/AUTH-03-restoring-a-backup-with-app-lock-enabled-leaves-the-cold-launch.md) | 🟡 Low | App lock & auth | Restoring a backup with app lock enabled leaves the cold-launch mirror stale, so the app relaunches unlocked for one session despite appLockEnabled=true |
| [AUTH-04](findings/AUTH-04-app-switcher-privacy-cover-is-gated-on-the-app-lock-toggle-so-us.md) | 🟡 Low | Privacy & compliance | App-switcher privacy cover is gated on the app-lock toggle, so users without app lock (the default) get their health/labs/prayer screen thumbnailed in the iOS app switcher |
| [PROD-06](findings/PROD-06-backup-ui-describes-what-the-export-contains-but-never-discloses.md) | 🟡 Low | Privacy & compliance | Backup UI describes what the export contains but never discloses it is unencrypted plaintext, while the Settings footer reassures "your data, your device" |
| [PROD-07](findings/PROD-07-numeric-stepper-buttons-use-sub-44pt-tap-targets-across-onboardi.md) | 🟡 Low | Product & UX | Numeric stepper +/- buttons use sub-44pt tap targets across onboarding and settings |
| [PRIV-06](findings/PRIV-06-privacy-policy-omits-the-manual-backup-export-which-writes-all-h.md) | ⚪ Informational | Privacy & compliance | Privacy policy omits the manual backup export, which writes all health data and precise prayer coordinates to a user-shareable plaintext JSON file |
| [NET-03](findings/NET-03-third-party-data-egress-matrix-what-user-data-leaves-the-device.md) | ⚪ Informational | Privacy & compliance | Third-party data-egress matrix: what user data leaves the device per endpoint |
| [NET-04](findings/NET-04-no-certificate-pinning-on-health-bearing-llm-https-endpoints-rel.md) | ⚪ Informational | Network & transport | No certificate pinning on health-bearing LLM HTTPS endpoints (relies on system trust store) |
| [NET-05](findings/NET-05-weather-forecast-query-sends-user-location-to-open-meteo-com-at.md) | ⚪ Informational | Privacy & compliance | Weather forecast query sends user location to open-meteo.com at full coordinate precision (no rounding) |
| [NET-06](findings/NET-06-scanned-barcode-interpolated-into-open-food-facts-url-path-witho.md) | ⚪ Informational | Network & transport | Scanned barcode interpolated into Open Food Facts URL path without percent-encoding |
| [DATA-04](findings/DATA-04-app-group-snapshot-duplicates-a-coarse-derived-subset-of-health.md) | ⚪ Informational | Data at rest | App Group snapshot duplicates a coarse, derived subset of health/location data into a second default-protection store |
| [INTG-02](findings/INTG-02-restored-userdefaults-blobs-are-written-without-per-key-type-val.md) | ⚪ Informational | Integrity & restore | Restored UserDefaults blobs are written without per-key type validation (defense-in-depth gap, no added attacker power) |
| [INTG-03](findings/INTG-03-backup-import-has-no-size-photo-count-or-plist-depth-cap-a-craft.md) | ⚪ Informational | Integrity & restore | Backup import has no size, photo-count, or plist-depth cap — a crafted or oversized archive can OOM-crash the app (self-inflicted, recoverable) |
| [AUTH-05](findings/AUTH-05-lock-screen-accessory-widgets-show-day-score-and-prayer-progress.md) | ⚪ Informational | Privacy & compliance | Lock-screen accessory widgets show day score and prayer progress on a locked device, outside app-lock control (by-design iOS behavior; report's calorie/protein/water claim is inaccurate) |
| [PROD-08](findings/PROD-08-no-api-key-validation-at-onboarding-a-wrong-key-surfaces-only-la.md) | ⚪ Informational | Product & UX | No API-key validation at onboarding; a wrong key surfaces only later as a raw provider error |

## What the app does well

A security review is not only a list of problems. These are genuine strengths observed in the code:

- **API keys are correctly kept out of backups.** `BackupKeys` documents that keys live in the Keychain and are never part of an archive, and `BackupKeys.all` contains no key-bearing entries (`WinTheDay/Core/BackupBundle.swift:18-20, 20-49`).
- **Imported photos are stripped of EXIF/GPS at capture.** Photos are re-rendered through `UIGraphicsImageRenderer` and re-encoded to JPEG on save (`WinTheDay/Core/PhotoStore.swift:15-25`), removing original camera/location metadata from nutrition-label and meal photos — a genuine privacy win.
- **The App-Group widget surface is intentionally minimal and derived** — short ring strings, scores, next-prayer time, with no raw notes, labs, or photo bytes (`Shared/SharedSnapshot.swift:11-13, 82-93`).
- **Derived/device-only state is deliberately excluded from backups.** The App-Group snapshot and `last_auto_backup` are treated as non-portable derived state and not archived (`WinTheDay/Core/BackupBundle.swift:18-20`).
- **Restore is staged-then-committed.** All blobs are decoded and the main `AppData` blob is proven to parse before any UserDefaults write, so a corrupt or truncated import leaves the device unchanged (`WinTheDay/Core/BackupBundle.swift:199-226`).
- **Backup import uses security-scoped resource access correctly** around the untrusted file read (`WinTheDay/Core/AppStore.swift:3569-3570`).
- **`formatVersion` is a required decode field**, so an unrelated or truncated JSON is rejected rather than silently importing as an empty archive (`WinTheDay/Core/BackupBundle.swift:87-95, 151-156`).
- **No global ATS bypass.** `Info.plist` contains no `NSAppTransportSecurity` dictionary and specifically no `NSAllowsArbitraryLoads=true`; all third-party endpoints (LLM providers, open-meteo, Open Food Facts) are forced to HTTPS.
- **Every cloud LLM endpoint is HTTPS** — api.anthropic.com, api.openai.com, generativelanguage.googleapis.com, openrouter.ai, api.deepseek.com, ollama.com (`AIEstimator.swift:329/407-410/458`). The only cleartext path is the user's self-hosted Ollama.
- **API secrets ride HTTP headers, not URLs, for every provider except Gemini** — Anthropic `x-api-key` (`AIEstimator.swift:691`), OpenAI-compatible `Authorization: Bearer` (`AIEstimator.swift:391/724`).
- **Untrusted food-search terms are percent-encoded** before entering the Open Food Facts query string, with a descriptive, non-identifying User-Agent (`FoodLookup.swift:57, 60`).
- **Requests carry sane timeouts** — 12s for OFF search, 120s for LLM POSTs, and a hard 30s `withTimeout` cap on meal-photo upload — so a stalled or hostile endpoint cannot hang indefinitely (`FoodLookup.swift:61`, `AIEstimator.swift:129/719`).
- **Meal photos are never persisted** and are only transmitted transiently for estimation (`AIEstimator.swift:26-27`), minimizing at-rest exposure of the most sensitive uploaded content.
- **OpenRouter attribution headers (`HTTP-Referer`/`X-Title`) carry only static, non-identifying app metadata** — no user data.
- **The coach's write tools are Confirm-gated.** `logFood`, `removeFood`, `setMealText`, `setMealTime`, and `togglePrayer` only stage a `PendingCoachWrite`; nothing mutates until the user taps Confirm (`AppStore.commitCoachWrite`), which structurally caps the impact of prompt injection.

## How this audit was run

Eight independent Opus agents each audited one dimension of the codebase in parallel (secrets, data-at-rest, transport, AI/LLM trust, app-lock, integrity/restore, privacy/compliance, product-UX). Every candidate finding was then handed to a separate adversarial Opus verifier that re-opened the cited code and either confirmed it, re-rated its severity, or rejected it. A final synthesis pass deduplicated, normalized severities, assigned IDs, and wrote this report. 52 agents ran end to end with zero errors. Full methodology, threat models, severity rubric, the third-party data-egress matrix, out-of-scope categories, and rejected findings are in the **[APPENDIX](APPENDIX.md)**.

## Contents

- **[README.md](README.md)** — this file: executive summary, severity summary, top risks, findings index, strengths.
- **[APPENDIX.md](APPENDIX.md)** — scope, methodology, threat models, severity rubric, data-flow matrix, out-of-scope categories, rejected findings, references, limitations.
- **[findings/](findings/)** — one Markdown file per finding, with code-cited evidence, an exploit/failure scenario, impact, and a concrete remediation.
