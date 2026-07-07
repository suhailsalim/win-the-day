# Win the Day

**Win the Day** is a native iOS app (iOS 17+, SwiftUI, with an Apple Watch companion) for people
who want one place to run their whole day: nutrition, training, sleep, prayer, study, and planning
— scored honestly, coached by AI, and stored **entirely on your device**.

## Why it's different

- **Local-first, private by design.** No backend, no account, no analytics. Your data is JSON on
  your phone; AI keys live in the iOS Keychain. The only network calls are to the AI provider *you*
  choose and free public data services (weather, food lookups).
- **Deterministic scores, not vibes.** Sleep, Readiness, Active, Eating, and Prayer-timing scores
  are pure on-device formulas over your HealthKit data and logs — the same inputs always produce
  the same number. The AI explains scores; it never invents them.
- **Bring your own AI.** Anthropic, OpenAI, Gemini, OpenRouter, DeepSeek, Ollama (local or cloud),
  or Apple Intelligence — switchable any time, with graceful fallbacks when a provider can't do
  tools or JSON.
- **Faith as a first-class pillar.** Astronomical prayer times computed on-device (madhab-aware),
  on-time prayer tracking, Qibla compass, and fasting windows — all optional and customizable.

## The feature map

| Area | What you get |
|---|---|
| [Today & rings](guide/today.md) | Configurable ring row (3–4 rings), habit checklist, quick logging, day score & streak |
| [Food](guide/food.md) | Free-text meals + AI estimate, structured food log, barcode scan, personal food library, Eating score |
| [Faith](guide/faith.md) | Prayer times & notifications, on-time bands, Qibla, fasting tracker, Live Activities |
| [Sleep](guide/sleep.md) | HealthKit sleep stages, WHOOP-style Sleep & Readiness scores, tonight's plan |
| [Study & focus](guide/study-focus.md) | Study timer with Live Activity, distraction-free focus screen |
| [Planning](guide/planning.md) | Week outlook, routines → sessions, occasions & trips with AI plans, calendar sync |
| [AI coach](guide/coach.md) | Multi-thread chat that reads your live data through tools |
| [Trends](guide/trends.md) | Charts, history browser, progress photos, PDF report, lab/InBody imports |
| [Widgets & Watch](guide/widgets.md) | Home & Lock Screen widgets, watch app + complications |

## Start here

New to the app? Read [Getting started](guide/getting-started.md) — it covers onboarding,
connecting Apple Health, and setting up an AI provider in about five minutes.

!!! note "Developers"
    Building or contributing? Start with the [Developer Docs](architecture.md) and the repo's
    `AGENTS.md`.
