# Food & nutrition

There are three ways to get food into the app, from fastest to most detailed:

## 1. Free-text meals + AI estimate

Type what you ate into the five meal boxes (breakfast, snacks, lunch, dinner, drinks) in your own
words — "2 idli with sambar, filter coffee" is fine. Tap **Estimate my day** and the AI returns
per-meal and day totals: calories, protein, carbs, fat, fiber, and micronutrients.

The estimator is given your **personal food library** first, so foods you've verified are reused
with *your* values instead of being re-guessed.

Meal **times** are stamped automatically the first time a meal gets content (editable via the clock
chip) — timing feeds the Eating score and the dinner-to-bed advice.

## 2. Structured food log

The food log records individual items per meal with quantities and per-item macros. Add items by:

- **Search** — instant, offline search over your library and the bundled food database (including
  a curated South-Indian/Kerala set). An explicit "search online" reaches Open Food Facts.
- **Barcode scan** — point the camera at a package; the product's nutrition arrives from
  Open Food Facts.
- **AI parse** — describe food in natural language and get editable structured rows you approve
  before anything is saved.

Verified lookups are saved **up** into your library, so the app keeps getting faster and less
AI-dependent the longer you use it.

## 3. Your food library

**Catalog** (the **Library** button on Today's Quick log section) is your trusted list: name,
serving, calories, macros,
micros. Anything you log often belongs here — library values always win over database or AI
guesses. Every item carries a source tag (yours / database / Open Food Facts / AI estimate) so you
know where a number came from.

## The Eating score

A daily 0–100 score built from weighted sub-scores:

| Sub-score | Measures |
|---|---|
| Calorie fit | Intake vs. your goal band (maintain / cut / bulk) around your calculated TDEE |
| Protein | Intake vs. bodyweight-scaled target |
| Macro balance | Carb/protein/fat within healthy ranges |
| Micros | Coverage of logged micronutrients vs. RDA |
| Timing | Dinner-to-bed gap (3+ hours is ideal) |
| Quality | Fiber/veg vs. added sugar, saturated fat, sodium — only scored on days with enough detail |

Sub-scores that can't be computed are **omitted and the rest re-weighted** — the day is marked
*partial*, never silently penalized. The weekly view projects weight change from your energy
balance and flags aggressive deficits, and warns when a scale jump after a salty day is water,
not fat.

!!! tip "Protein & calories flow to Apple Health"
    Dietary energy and protein you log are written to Apple Health, so other apps see them too.
