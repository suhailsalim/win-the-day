# Sleep & readiness

## What the app reads

With Apple Health access, each morning the app pulls last night's sleep (total, in-bed, and stages
where recorded), overnight HRV, resting heart rate, and respiratory rate. A Watch gives the richest
data, but phone-only sleep tracking works — missing signals simply drop out of the formulas.

## Sleep score (0–100)

How well last night served *you*, not a generic 8-hour rule:

- **Sufficiency** — sleep vs. your personal **sleep need**: your own baseline duration, plus extra
  need after high-strain days, plus any recent sleep debt.
- **Efficiency** — time asleep vs. time in bed.
- **Consistency** — how stable your mid-sleep time has been across recent nights.
- **Stage quality** — deep + REM proportion, when stages are recorded.

## Readiness score (0–100)

A recovery score relative to **your own rolling baseline** — not population norms. Overnight HRV
leads, with resting heart rate, respiration, temperature deviation, and last night's sleep score.
Bands: green (ready to push), amber (moderate), red (take it easy).

- Scores are **calibrating** for your first week while baselines build; if you have existing Apple
  Health history the app imports the last 30 days on first launch so you're calibrated on day one.
- The optional **daily check-in** (soreness, stress, mood, alcohol, late caffeine, illness) sharpens
  Readiness within honest bounds — and the sensor-only number stays visible so you always see what
  the sensors said before your check-in adjusted it. Tap **How do you feel?** on the Sleep &
  readiness card to log it; you can also backfill a past day from History.

## Active score (0–100)

Daily activity strain from active calories — a saturating scale, so a rest day isn't a failure and
an all-out day doesn't need to be repeated to "keep a streak". Works without a Watch; per-minute
heart rate refines it when a Watch is paired. Auto-detected Apple Fitness workouts appear on Today
with duration, distance, calories, and heart-rate zone breakdown.

## Tonight's plan

From your sleep need, recent wake times, and today's strain, the app recommends **tonight's
bedtime** — and works backwards to a **dinner cutoff** (eating within ~3 hours of bed measurably
fragments sleep). The sleep module shows the plan; the meals section nudges you when dinner is
drifting late.

## Factor transparency

Every score expands into its factor list — exactly which inputs helped or hurt, with deltas. Past
days keep their factors, so you can tap any bar in the 14-day view and see *why* that day scored
the way it did.
