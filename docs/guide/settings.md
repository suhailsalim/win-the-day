# Settings & privacy

## How Settings is organized

Settings is a simple grouped menu — every row opens its own page, so nothing competes for
attention.

**Coach & intelligence**

- **Intelligence** — AI provider and model, API key (Keychain), custom model IDs, Ollama host,
  test connection, and whether the coach may propose changes (always as a card you confirm first).

**Your day**

- **Today layout** — toggle and reorder Today's modules, set per-module accent colors, and rename
  your pillars.
- **Rings** — how many rings show on Today (3–6), their order, and your custom rings.
- **Targets & profile** — daily targets (calories, protein, steps), the eating-score profile
  (age, height, sex, goal), and **the prize** — your one priority metric, which headlines Trends.
- **Reminders** — smart nudges (streak at risk, dinner window, protein check…) and the evening
  wind-down. Rule-based, no AI, nothing leaves the phone.

**Trackers**

- **Hydration** — daily target, glass size, and the reminder schedule.
- **Prayer times** — branch, madhab, calculation method, and Friday Jumu'ah.
- **Fasting** — fasting window (16:8 and friends) and Ramadan mode.
- **Apple Health** — sync on/off, a doctor-ready PDF export, and **Auto notes from imports**
  (out-of-range results in an imported report become a finding note on the Health tab, computed
  on-device from general reference ranges).
- **Calendar & Reminders** — connect, then choose whether sessions go to Calendar and prep tasks
  to Reminders.

**App**

- **Appearance** — color theme and light/dark (see below).
- **Privacy** — Face ID / Touch ID app lock with a configurable grace period.
- **Backup & data** — export a backup, restore one, or reset (see below).
- **Run setup again** — replay the guided onboarding.

## Appearance

The **Color theme** picker offers six palettes — accents, background wash, and glass tints all
follow it:

| Palette | Look |
|---|---|
| **Indigo** (default) | Cool indigo on neutral glass |
| **Warm sand** | The original warm beige look |
| **Sage** | Calm greens |
| **Ocean** | Sea blues |
| **Rose** | Soft warm pinks |
| **Graphite** | Just greys — no color cast |

Below it, pick light, dark, or follow-the-system, plus a dark style: **Grey** (soft charcoal
surfaces) or **Black** (true black, saves power on OLED). Liquid-glass transparency follows iOS's
**Reduce Transparency** accessibility setting rather than an in-app switch.

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

Each concern has its own switch, on the page where the feature lives: smart nudges and the
wind-down under **Reminders**, hydration pings under **Hydration**, prayer notifications with
**Prayer times**, and suhoor/iftar alerts under **Fasting** when Ramadan mode is on.

## Backup

**Settings → Backup & data** exports a full backup to iCloud Drive / Files — entries, habits,
targets, settings, coach chats, prayer/hydration/fasting setup, library, labs, body comp, and
photos. An **auto-backup** is also written to the Files app (On My iPhone → Win the Day) every
time you leave the app, and rides along in your iCloud device backup. Restoring shows you what's
inside the file before anything is overwritten.

API keys are the one exception: they live in the Keychain and are never included in a backup, so
you'll re-enter them after restoring to a new device.
