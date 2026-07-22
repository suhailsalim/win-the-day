# PROD-04 — Custom Settings toggles expose no VoiceOver value or toggle trait — the switch announces only "button" with no on/off state

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Product & UX |
| **Status** | CONFIRMED |
| **Location(s)** | _See Details below._ |

## Summary

IOSToggle and ToggleRow are hand-built from a Capsule + Circle inside a plain Button with zero accessibility modifiers, so VoiceOver reads the control as a bare "button" — no name, no on/off value, and no toggle trait — across App Lock, HealthKit sync, module toggles, reminders, coach-writes, and more.

## Details

Re-read `WinTheDay/UI/Components.swift` and `WinTheDay/Settings/SettingsPages.swift`, grepped both for `accessibility` (zero matches), and mapped every call site.

`IOSToggle` (Components.swift:4-25) and `ToggleRow` (Components.swift:28-48) are each a `Button { … } label: { ZStack { Capsule(); Circle() } }` closed with `.buttonStyle(.plain)`. Neither carries any `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityAddTraits(.isToggle)`, nor `.accessibilityRepresentation`:

```swift
struct ToggleRow: View {          // Components.swift:28
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? onColor : Theme.tertiaryInk.opacity(0.18)) …
                Circle().fill(.white) …
            }
        }
        .buttonStyle(.plain)      // no accessibility* modifier anywhere
    }
}
```

Because the label is drawn from shapes only, SwiftUI synthesizes an accessibility element with the Button trait and **no** text and **no** value — VoiceOver announces just "button".

`ToggleTextRow` (SettingsPages.swift:78-98) does render the descriptive name, but as a **sibling** `Text` in the same `HStack`, not associated with the control, and the `ToggleRow` beside it remains a separate, stateless element:

```swift
HStack {
    VStack(alignment: .leading) { Text(label) …; if !sub.isEmpty { Text(sub) … } }
    Spacer()
    ToggleRow(on: on, action: action)   // separate a11y element, still bare "button"
}
```

So VoiceOver reads the label as one element, then reaches the control and announces "button" with no on/off state and no "switch/toggle" role. For the bare `ToggleRow`/`IOSToggle` used **without** any adjacent label — e.g. the favorite toggle in `CatalogView.swift:253` and the HealthKit metric rows the doc comment references (`Components.swift:27` "used for HealthKit metric rows") — there is no spoken text at all: just "button".

Confirmed reach across security- and privacy-relevant Settings controls: App Lock (`SettingsPages.swift:1122` `ToggleRow(on: store.settings.appLockEnabled)`), HealthKit sync (`:690` `ToggleRow(on: store.settings.healthkit)`), coach-can-propose-writes (`:281`), every Today module toggle (`:515`), prayer enable (`:897`), fasting/Ramadan (`:963`, `:998`), calendar/reminders sync (`:1081`, `:1085`), hydration & smart reminders (`:744`, `:807`, `:812`). These are the primary interaction surface of the entire Settings area, and none of them is a real SwiftUI `Toggle` (which would supply the label/value/`.isToggle` trait automatically).

## Failure / exploit scenario

A VoiceOver user opens Settings to confirm App Lock is on. They swipe to the control at `SettingsPages.swift:1122`; because `ToggleRow` has no `accessibilityValue` and no `.isToggle` trait, VoiceOver speaks only "button" — no name, no "on/off". The user cannot tell the current state, and after a double-tap gets no spoken confirmation of the new state. The same failure hides whether HealthKit sync (`:690`) is sending health data and whether the coach is allowed to propose writes (`:281`) — states a privacy-conscious user specifically needs to verify. For bare toggles with no adjacent Text (favorite row, HealthKit metric rows), even the control's name is unspoken.

## Impact

VoiceOver users cannot perceive or confidently change the state of essentially every switch in the app — including privacy/security-sensitive ones (App Lock, HealthKit sync, coach write permission). This is a genuine, pervasive accessibility defect (not a security vuln): it degrades usability for blind/low-vision users and is an App Store accessibility-guideline concern. Scope is broad (20+ call sites) but non-destructive and recoverable, so Medium is the correct rating; it is not a data-loss or exploit issue.

## Recommendation

Prefer replacing `IOSToggle`/`ToggleRow` with SwiftUI's native `Toggle` (which auto-provides the label, on/off value, and `.isToggle` trait) styled to match, e.g. `Toggle(label, isOn: $isOn).toggleStyle(SwitchToggleStyle(tint: onColor)).labelsHidden()` where a custom label row is needed. If the bespoke look must stay, add on each control: `.accessibilityAddTraits(.isToggle)`, `.accessibilityValue(on ? "On" : "Off")`, and an `.accessibilityLabel(name)` (threaded through as a parameter, since `ToggleRow` currently takes none). For `ToggleTextRow`, wrap the `HStack` in `.accessibilityElement(children: .combine)` (or `.ignore` + explicit label/value) so the name and state are announced as one switch element rather than a separate Text and a bare button.


---

_Finding PROD-04. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._