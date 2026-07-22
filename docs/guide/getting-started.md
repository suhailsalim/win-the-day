# Getting started

## First launch

Onboarding adapts to what you care about. Pick your **life areas** (health, spirituality,
work/study, custom) and the app seeds sensible starter habits and Today modules for each — you can
change all of it later.

You'll be asked for:

1. **Basics** — name, targets (calories, protein, steps, water, study hours). Skip anything; every
   target has a sane default.
2. **Apple Health access** — grant read access for steps, weight, sleep, heart data, and workouts.
   This powers the Sleep/Readiness/Active scores and step-linked habits. You can decline and log
   manually; scores that need sensors will show as unavailable rather than fake numbers.
3. **Faith setup (optional)** — choose Islam (rich preset: prayer times, Qibla, fasting), another
   faith, or none. For Islam, pick your calculation method, branch, and madhab; prayer times are
   computed on-device from your location.

## Connect an AI provider (optional but recommended)

The coach, meal estimates, plan generation, and tips all use the AI provider you choose.

1. Open **Settings → Intelligence**.
2. Pick a provider: Anthropic, OpenAI, Google Gemini, OpenRouter, DeepSeek, Ollama (a model running
   on your own machine), Ollama Cloud, or Apple Intelligence (no key needed, on-device).
3. Paste your API key and tap **Test connection**. Keys are stored in the iOS Keychain, never in
   the app's data or any backup.

!!! tip "No key? No problem."
    Apple Intelligence works with no key on supported devices, and Ollama lets you run a model
    locally for free. Everything that isn't AI (scores, prayer times, logging, trends) works with
    no provider at all.

## Your first day

- Open **Today** and type what you ate into the meal boxes, then tap **Estimate my day** to get
  calories, protein, and macros.
- Tap habits as you complete them. Winning the day = completing at least ~60% of your active habits.
- Mark prayers as you pray them — the app records *when*, and scores on-time performance.
- Log water with the bottle, start a study session, and check your rings.

By tomorrow morning you'll have your first Sleep and Readiness scores (they calibrate over your
first week of data — the app labels them "calibrating" until baselines are solid).

## What gets stored where

Everything lives on your device: logs in app storage, photos in the app's Documents folder, API
keys in the Keychain. Nothing is uploaded anywhere except the text you explicitly send to your
chosen AI provider. See [Settings & privacy](settings.md).
