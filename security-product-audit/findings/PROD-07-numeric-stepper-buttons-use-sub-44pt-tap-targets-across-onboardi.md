# PROD-07 — Numeric stepper +/- buttons use sub-44pt tap targets across onboarding and settings

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Product & UX |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Area** | product-ux |
| **Location(s)** | `WinTheDay/App/OnboardingView.swift`, `WinTheDay/Settings/SettingsPages.swift` |

## Summary

The +/- stepper controls that are the primary way to set every numeric target and profile value use hit areas of 36x30pt (onboarding) and 38x32pt (settings), below Apple's 44x44pt HIG minimum, with the two adjacent buttons separated only by a hairline divider.

## Details

Both cited controls are real and reachable.

**Onboarding stepper** (`WinTheDay/App/OnboardingView.swift:304-318`):
```swift
HStack(spacing: 0) {
    Button(action: dec) { Image(systemName: "minus").frame(width: 36, height: 30) }
    Button(action: inc) { Image(systemName: "plus").frame(width: 36, height: 30) }
}
```
The button's tappable region is its label frame, so each target is 36x30pt. `spacing: 0` places minus and plus immediately adjacent with no separator at all in onboarding. This `stepper(...)` helper drives Calories, Protein, Steps, Water, work/study hours, and prize Target (`OnboardingView.swift:166-200`).

**Shared StepperRow** (`WinTheDay/Settings/SettingsPages.swift:39-66`):
```swift
Button(action: dec) { stepIcon("minus") }
Divider().frame(height: 22)
Button(action: inc) { stepIcon("plus") }
...
private func stepIcon(_ symbol: String) -> some View {
    Image(systemName: symbol)
        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentDark)
        .frame(width: 38, height: 32)
}
```
Each button is 38x32pt. The `.padding(.vertical, 10)` at line 58 is applied to the outer row HStack, not to the buttons, so it does not enlarge the individual tap targets. A 0.5pt `Divider` sits between the two adjacent buttons.

`StepperRow` is the single control for the entire numeric-settings surface — grep confirms ~20 instances: Calories, Protein, Steps, Age, Height, prize Start/Now/Target, water Daily target/Glass size/reminder Every/From/Until, evening check hour, notification Fires-at, fasting Target hours, Ramadan month/Suhoor warning (`SettingsPages.swift:580-1018`). The IntelligencePage and other settings pages reuse the same row.

The width (36-38pt) is close to the guideline, but the 30-32pt height is meaningfully short, and because the two buttons are directly adjacent (0 spacing / hairline divider) the effective separation between increment and decrement is small.

## Failure / exploit scenario

Under threat model (e) accessibility: a user with a motor-control limitation or larger fingers, or one adjusting a target one-handed while on the move, taps the calorie or prize stepper and repeatedly hits plus when aiming for minus, because the two 30-32pt-tall buttons sit adjacent with only a hairline between them. There is no data-loss or security consequence — the values are user-editable and reversible — but the interaction is error-prone for the app's primary numeric-entry pattern.

## Impact

Degraded usability and accessibility for the most-used input control in the app. Every numeric target and profile value is edited exclusively through these steppers, so the sub-guideline hit area compounds across the whole configuration flow. No security or data-integrity impact; this is a polish/accessibility defect, which is why the reported Medium is downgraded to Low for this local single-user app.

## Recommendation

Raise each button's tappable region to at least 44x44pt while keeping the small glyph. Simplest fix: increase the frame in `stepIcon` (SettingsPages.swift:64) and the onboarding buttons (OnboardingView.swift:310-311) to `height: 44` (and width toward 44), or keep the visual glyph size and add `.contentShape(Rectangle())` with padding to expand the hit area. Optionally add slight spacing between the minus and plus buttons so adjacent mistaps are less likely, and add `.accessibilityLabel`s so VoiceOver announces increment/decrement.

## References

- Apple Human Interface Guidelines — Layout: minimum 44x44pt tap target
- WCAG 2.1 SC 2.5.5 Target Size


---

_Finding PROD-07. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._