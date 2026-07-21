# Win the Day — iOS

A native **SwiftUI** personal health & discipline tracker. Log your day, let AI estimate
calories/macros, track configurable habits, plan your week, and watch the trends that actually
matter — with an Apple Watch app, widgets, and an AI coach that knows your data.

> **Local-first.** No accounts, no backend. Your data lives on your device (and optionally Apple
> Health). API keys are stored in the Keychain. AI requests go directly from your device to the
> provider you choose.

Built with Xcode 26, iOS 17+, Swift 6 (strict concurrency). Originally generated from a Claude Design
prototype (`design/`).

## Features

- **Today** — meals + AI "Estimate my day", per-meal times, quick-log catalog with multi-dose
  servings, micronutrients, hydration, configurable habits & 0–N daily score, day status
  (sick/travel/rest).
- **Plan** — AI week outlook, weekly routine → scheduled sessions, an **AI week-plan generator**
  (workouts, focus blocks, stretch/wind-down, walk & meal reminders), events & travel planning, all
  syncing to Apple Calendar/Reminders.
- **Sleep & readiness** — richer HealthKit sleep + a 0–100 readiness score (sleep + HRV + resting HR
  + load + late meals).
- **Faith** — Islamic prayer times, Qibla compass, fasting & Ramadan mode (fully optional/customizable).
- **Coach** — data-aware AI chat, daily nudges, weekly review, across 8 providers
  (Anthropic/OpenAI/Gemini/OpenRouter/DeepSeek/Ollama/Ollama Cloud/Apple).
- **Health** — InBody & lab report import (photo/PDF/text → AI parse → Apple Health), health notes,
  doctor-ready PDF export, structured workout logging.
- **Weather** — Open-Meteo forecast with walk/run-vs-indoor advice.
- **Trends** — weekly review, insights, the personal "prize" metric, charts, micronutrient RDA.
- **Apple Watch app, home/lock widgets, complications, Live Activities, Siri shortcuts.**

Full feature docs: [`docs/`](docs/). Architecture: [`docs/architecture.md`](docs/architecture.md).

## Website

**<https://suhailaka.github.io/win-the-day/>** — landing page, hosted user guide
(`/docs/`), [privacy policy](https://suhailaka.github.io/win-the-day/privacy/) and
[support](https://suhailaka.github.io/win-the-day/support/).

The site is static and free to run: `website/` holds hand-written HTML/CSS (no framework, no JS,
no analytics) and `.github/workflows/site.yml` builds MkDocs into `_site/docs`, lays `website/`
over the root, and deploys to GitHub Pages on every push to `main` touching `docs/`, `website/`
or `mkdocs.yml`.

- Preview the landing page by opening `website/index.html` in a browser — every link is
  relative, so it works from `file://` too (the `docs/` links need the built site).
- Preview the docs with `pip install 'mkdocs<2' 'mkdocs-material>=9.7,<10' && mkdocs serve`.
- Screenshots are grey placeholders until real captures are dropped in — see
  [`website/assets/README.md`](website/assets/README.md).
- **One-time repo setting:** Settings → Pages → Build and deployment → Source =
  **GitHub Actions** (a workflow can't set this itself).

## Build & run

1. Open `WinTheDay.xcodeproj` in **Xcode 26+**.
2. Set your **Signing team** on each target (Signing & Capabilities). Free Apple ID works (App Groups
   are fine; iCloud/WeatherKit are not — see notes).
3. Select the **WinTheDay** scheme + an iOS 17 simulator or your iPhone, and **Run** (⌘R).

From the CLI (used by the build/install loop):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project WinTheDay.xcodeproj -scheme WinTheDay -configuration Debug \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath build/dd build
```

Files are organised in Xcode **file-system-synchronized groups** — drop a `.swift` file in a target's
folder and it compiles (except `Shared/`, which is wired in `project.pbxproj`).

## Configure AI

**Settings → Intelligence**: pick a provider, paste its API key (stored in the Keychain), optionally
**Test connection**. Then on **Today**, fill meals and tap **Estimate my day**. Ollama (local) and
Apple Intelligence need no key.

## Apple Health, Calendar & Reminders

Grant permissions when prompted (or from the Health / Settings screens). The app reads steps, weight,
energy, HR/HRV, sleep and workouts, and writes calories, protein, body comp and workouts back. With
Calendar/Reminders connected it plans around your real commitments and writes sessions/events to a
"Win the Day" calendar.

## Notes & limits

- iPhone, portrait, iOS 17+. Newsreader font is the SIL OFL build.
- **Free signing**: App Groups work; **iCloud/CloudKit and WeatherKit do not** (paid membership only)
  — weather uses [Open-Meteo](https://open-meteo.com) (no key). Watch wireless installs can hit error
  4000 — reinstall from the iPhone Watch app.
- Bundle ids/team are personal placeholders; change them for your own build.

## Contributing & agents

- **[AGENTS.md](AGENTS.md)** is the single source of truth for building, conventions and gotchas —
  read it before changing code. **[CLAUDE.md](CLAUDE.md)** points there.
- The repo is set up for **[OpenWolf](https://openwolf.com)** (Claude Code project intelligence +
  token savings): `npm i -g openwolf && openwolf init`. The `.wolf/` dir is per-developer (git-ignored).
- Non-negotiable convention: every persisted struct uses a **tolerant `init(from:)`** so updates never
  wipe user data. See [docs/features/data-persistence.md](docs/features/data-persistence.md).

## License

[MIT](LICENSE).
