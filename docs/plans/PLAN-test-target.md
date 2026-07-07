# PLAN: Unit tests for tolerant Codable + the pure score engines (currently ZERO tests)

## Goal
The repo has no test target at all (`grep -c XCTest project.pbxproj` → 0), yet its #1 stated risk is
"a missing tolerant-decode line wipes user data" (AGENTS.md convention 1), and it now ships five
pure deterministic engines (`ScoreEngine`, `EatingScorer`, `PrayerClassifier`, `RingEngine`,
`ReadinessScorer` shim) that are explicitly designed to be unit-testable. Add a test suite that
locks in (a) decode round-trips for every persisted struct and (b) engine determinism, runnable
headlessly from the CLI.

## Approach — SwiftPM test package, NOT a pbxproj test target
All engine files and `Models.swift` import **only Foundation** (verified). Editing `project.pbxproj`
by hand to add a test target is error-prone; instead create a standalone SwiftPM package at the repo
root that compiles the app's source files directly via `sources:` paths. No pbxproj changes at all.

## Files to create
- `EngineTests/Package.swift`
- `EngineTests/Tests/EngineTests/CodableToleranceTests.swift`
- `EngineTests/Tests/EngineTests/ScoreEngineTests.swift`
- `EngineTests/Tests/EngineTests/PrayerClassifierTests.swift`
- `EngineTests/Tests/EngineTests/EatingScorerTests.swift`
- Append `EngineTests/.build/` to `.gitignore`.

## Steps, in order
1. Create `EngineTests/Package.swift`:
   ```swift
   // swift-tools-version: 5.9
   import PackageDescription
   let package = Package(
       name: "EngineTests",
       platforms: [.macOS(.v14), .iOS(.v17)],
       targets: [
           .target(
               name: "AppCore",
               path: "../WinTheDay",
               sources: ["Core/Models.swift", "Engines/ScoreEngine.swift",
                         "Engines/EatingScorer.swift", "Engines/PrayerClassifier.swift",
                         "Engines/RingEngine.swift", "Engines/ReadinessScorer.swift",
                         "Engines/PrayerTimes.swift"]),
           .testTarget(name: "EngineTests", dependencies: ["AppCore"],
                       path: "Tests/EngineTests")
       ]
   )
   ```
2. `cd EngineTests && swift build` — expect missing-type errors. Resolution rules:
   - If a listed file references a type defined in another `WinTheDay/*.swift` file, add THAT file
     to `sources` **only if it is also Foundation-only** (check its imports first).
   - If a file drags in SwiftUI/UIKit/HealthKit types, do NOT add it; instead exclude the one
     referencing file if it isn't essential, or (last resort) note the type and stub nothing — stop
     and reconsider which files are needed. `Core/Models.swift` + the five engines + `PrayerTimes.swift`
     should close over themselves; expect at most 1–2 additions (e.g. `Theme` references would be a
     blocker — they should not appear in these files; if one does, that line likely belongs in a
     view file and moving it is out of scope — drop that source file from the package instead).
   - App sources have no `import AppCore` obviously; in test files use `@testable import AppCore`.
3. Write `CodableToleranceTests.swift` — the data-loss guards. For each persisted struct
   (`Entry`, `AppData`, `AppSettings`, `ModulePrefs`, `Occasion`, `RingDef`, `DayCheckIn`,
   `PrayerLog`, plus any other struct in Models.swift with a hand-written `init(from:)`):
   - **Round-trip:** encode a fully-populated instance with JSONEncoder, decode it, assert every
     field survives. This catches the classic "decode line added, CodingKeys/encode not updated"
     bug and the reverse.
   - **Empty-object tolerance:** decode from `"{}".data(using: .utf8)!` and assert it succeeds with
     defaults (this is the tolerant-decode contract).
   - **Unknown-enum tolerance:** decode a `RingDef` whose JSON has `"source": "somethingNew"` and
     assert it falls back rather than throwing.
   - **Zero-survival:** an `Entry` with `readiness = 0` must round-trip to 0, not nil/default.
4. Write `ScoreEngineTests.swift`:
   - Determinism: same `Inputs` twice → identical `Result`.
   - Calibration gate: `baselines.sampleNights < 7` → score reported as unavailable/calibrating
     (read the actual API in `ScoreEngine.swift` first; assert whatever "not available" looks like,
     e.g. an `available` flag or nil — do not guess field names, open the file).
   - Strain monotonicity: higher activeKcal → strain S non-decreasing, clamped to [0, 21].
   - Missing sub-inputs renormalize: readiness with no HRV baseline ≠ crash, ≠ 0-by-default.
   - `selfReportMultiplier`: floor at 0.85 even with all penalties maxed (alcohol 3, illness,
     lateCaffeine, soreness 3, stress 3).
5. Write `PrayerClassifierTests.swift` (open `PrayerClassifier.swift` first for exact API):
   - Maghrib marked between +20min and Isha onset → late-valid, never qadha.
   - Isha before Islamic midnight → on-time band; after next Fajr → qadha.
   - A `nil` prayer time (high latitude) → `.unknown`, no crash.
   - +90s grace: a mark 60s after the qadha boundary still classifies pre-qadha.
6. Write `EatingScorerTests.swift`:
   - TDEE floor: activeKcal = 0 → TDEE == 1.15 × BMR (not bare BMR).
   - Quality gating: fewer than 3 of its 5 inputs present → result marked partial and Quality
     omitted (not scored 0).
   - Weights renormalize: score with only CalorieFit+Protein available is still in 0…100.
7. Run: `cd EngineTests && swift test`. All green.
8. Add a one-liner to `AGENTS.md` under "Verify before you're done":
   `4. cd EngineTests && swift test (pure-engine + codable-tolerance suite).`
9. Commit: `test: SwiftPM engine test package — codable tolerance + score determinism`.

## Edge cases a weaker model would miss
- **Do not** add the package to the Xcode project or `project.pbxproj` — it is intentionally
  standalone; the app never depends on it.
- `sources:` paths in Package.swift are relative to `path:` (`../WinTheDay`), not the package root.
- Tests run on **macOS** — anything gated `#if os(iOS)` inside the compiled files silently drops
  out; if a needed API is iOS-gated, run tests via
  `xcodebuild test -scheme EngineTests -destination 'platform=iOS Simulator,name=iPhone 16'`
  from inside `EngineTests/` instead (SwiftPM packages are xcodebuild-testable). Try `swift test`
  first; only fall back if compilation genuinely differs.
- Encode-side asymmetry is the whole point of the round-trip test: hand-written `init(from:)` with
  synthesized `encode(to:)` means a property missing from an explicit `CodingKeys` enum decodes
  fine but never persists. Populate EVERY field with a non-default value in round-trip tests or the
  test proves nothing.
- `Date()`/timezone: PrayerClassifier tests must construct fixed epochs with an explicit fixed
  `TimeZone` (e.g. build boundaries from literal epochs), never "now", or they'll flake by locale.
- Don't test `AppStore`/managers — they're `@MainActor` + UserDefaults-coupled; out of scope here.

## Acceptance criteria
- [ ] `cd EngineTests && swift test` exits 0 with ≥ 20 test methods across the 4 files.
- [ ] Deleting any one tolerant-decode line in `Models.swift` (try it, then revert) makes at least
      one test fail — proves the guard is live.
- [ ] No changes to `project.pbxproj`; app still builds exactly as before.
- [ ] `.gitignore` covers `EngineTests/.build/`.
