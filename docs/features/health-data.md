# Health data: HealthKit, imports & reports

## HealthKit (`HealthManager`)
- **Reads**: steps (today + history), body mass, active energy, resting HR, HRV, sleep (+ detail),
  workouts this week. **Writes**: dietary energy + protein, body composition, supported lab values,
  and **workouts** (`HKWorkoutBuilder`).
- Placeholder values on Simulator (empty HealthKit) so the UI isn't blank.
- Per-day loading (`loadForDay`) + steps history (`loadStepsHistory`) for past-date viewing and Trends.

## Imports (`ImportReportView`)
- **InBody / body composition**: photo/PDF/text → `AIEstimator.parseBodyComp` → `BodyComp` (saved to
  `AppData.bodyComps`, mirrored to weight + the prize metric, written to Health).
- **Lab / checkup**: photo/PDF/text → `AIEstimator.parseLabs` → `LabRecord`/`LabItem` (saved to
  `AppData.labs`; supported values written to Health and marked).

## Health profile & notes
Free-text `HealthNote`s (condition/medication/injury/goal/note) added in `HealthView` via
`HealthNoteEditor`. Together with the latest body comp + recent labs they form the
[health index](coach-ai.md) fed to the coach.

## Doctor-ready PDF
`PDFReport.swift` (`AppStore.exportHealthPDF`) renders prize metric, weekly stats, body-comp timeline
and the latest labs into a PDF; shared via the share sheet from Settings → Apple Health.

## Workouts
Structured logging (`Workout`/`Exercise`/`StrengthSet`) in `WorkoutView`, written to Apple Health and
surfaced in the [training](habits-scoring.md) Trends card.

## Key files
`HealthManager.swift`, `ImportReportView.swift`, `PDFReport.swift`, `WorkoutView.swift`,
`HealthView.swift`, `HealthNoteEditor.swift`, `Models.swift` (`BodyComp`, `LabRecord`, `LabItem`,
`HealthNote`, `Workout`).
