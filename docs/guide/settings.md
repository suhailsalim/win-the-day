# Settings & privacy

## What you can configure

- **Targets** — calories, protein, steps, water, study hours, weight goal, and your priority metric.
- **Modules** — reorder Today's modules, toggle optional ones, and set per-module accent colors.
- **Rings** — which rings show (3 or 4), their order, and custom rings.
- **Habits** — add/edit habits, pillars, and auto-links.
- **Faith** — calculation method, branch, madhab, notifications, fasting preferences.
- **AI provider** — provider, model, API key (Keychain), custom model IDs, Ollama host, test
  connection.
- **Food library** — your verified foods.
- **Health** — HealthKit connection status and what's synced.

## Privacy model, plainly

| Data | Where it lives | Ever leaves the device? |
|---|---|---|
| Daily logs, habits, plans, chat threads | On-device app storage | No |
| Progress photos | App's Documents folder | No |
| API keys | iOS Keychain | No |
| Health data (via HealthKit) | Apple Health | No (governed by iOS permissions) |
| Meal text, questions to the coach, health notes/labs you submit for parsing | — | **Yes — to the AI provider you chose**, when you use an AI feature |
| Location | Used on-device for prayer times, Qibla, weather | Coordinates go only to the free weather service |

There is no account, no analytics, no tracking, and no backend operated by the app.

!!! warning "One honest caveat"
    AI features work by sending the relevant text to your chosen provider. If that's unacceptable
    for something sensitive, use a local Ollama model or Apple Intelligence, or simply don't run AI
    on that item — everything deterministic works without AI.

## Notifications

Per-concern channels you can enable independently: prayer times, hydration reminders, session
reminders, fasting/Ramadan, and the weekly review.

## Backup

Data is local, so treat your **iPhone backup** (iCloud device backup or Finder) as the app's
backup — it captures app storage and photos. Keychain items (API keys) restore with encrypted
backups.
