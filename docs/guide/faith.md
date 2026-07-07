# Faith — prayer, Qibla & fasting

The spirituality pillar is optional and flexible: choose Islam for the full experience below,
define another faith's practices as custom habits, or turn the pillar off entirely.

## Prayer times

Prayer times are **computed on your device** — no server, works offline once located:

- Calculation method (MWL default and other standard methods), **branch** (Sunni/Shia — Shia uses
  the Jafari method), and **madhab** (Hanafi/Shafi'i/Maliki/Hanbali) — the madhab drives the Asr
  time.
- Location comes from iOS location services; times update as you travel.
- **Notifications** at each prayer (Fajr's is skipped by design), and a **Live Activity** appears
  on your Lock Screen in the window after the adhan.

## Marking prayers & on-time scoring

Tap a prayer when you've prayed it. The app records *when* you marked it and classifies it against
that prayer's actual window:

| Band | Meaning |
|---|---|
| Prompt | Prayed early in the window |
| On time | Within the valid window |
| Late but valid | e.g. Asr in the last stretch before sunset, Isha after midnight |
| Made up (qadha) | Marked after the window fully passed |

The classification follows fiqh carefully — Maghrib stays valid until Isha, Isha's preferred window
ends at *Islamic* midnight (halfway between sunset and Fajr, not 12:00 AM), and your madhab setting
shifts the Dhuhr/Asr boundary consistently with the displayed times. Timing feedback is neutral by
design — a made-up prayer is recorded, never shamed — and timing penalties can be turned off so any
marked prayer simply counts.

The **Prayer ring** fills as the day's prayers are completed, judged only against prayers that are
actually due so far — you're never shown a failing score at breakfast for prayers that haven't
happened yet.

## Qibla

A live compass pointing to the Kaaba from your location, with distance. Hold the phone flat and
follow the needle.

## Fasting

A fasting window tracker for intermittent fasting or religious fasts: start/end your fast, see
elapsed and remaining time on Today, in widgets, and on the watch. Ramadan-aware reminders use
their own notification channel.

## High latitudes & travel

Where Fajr or Isha can't be computed astronomically (extreme latitudes, white nights), the app
degrades gracefully — affected prayers are treated as valid-but-untimed rather than mis-scored.
