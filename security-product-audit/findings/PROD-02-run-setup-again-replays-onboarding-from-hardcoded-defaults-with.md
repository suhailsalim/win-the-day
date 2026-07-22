# PROD-02 — "Run setup again" replays onboarding from hardcoded defaults with no Cancel, silently deactivating habits/modules the user relies on

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Product & UX |
| **Status** | CONFIRMED |
| **Location(s)** | _See Details below._ |

## Summary

The Settings "Run setup again" entry re-presents onboarding as an inescapable full-screen cover whose selection state is hardcoded (areas=[.health,.spirituality], faith="islam") rather than preloaded from the user's real config; completing it — the only way out — deactivates habits and toggles modules based on those defaults.

## Details

Every cited location checks out.

**The entry point looks harmless.** `SettingsView.swift:81-82`:
```swift
row("wand.and.stars", tile: [...],
    title: "Run setup again", sub: "Replay the guided onboarding") { store.replayOnboarding() }
```

**`replayOnboarding()` only flips a flag** — `AppStore.swift:425-428`:
```swift
func replayOnboarding() {
    onboardingDone = false
    UserDefaults.standard.set(false, forKey: "onboarding_done_v1")
}
```

**The presentation is a dead end.** `RootView.swift:60-62`:
```swift
.fullScreenCover(isPresented: .constant(!store.onboardingDone)) {
    OnboardingView()
}
```
The binding is `.constant(...)`, and `fullScreenCover` has no interactive swipe-to-dismiss. `OnboardingView` offers only Continue/Back (lines 53-66) — no Cancel/Skip. The single exit is the last-page button "Start winning days", which calls `finish()` → `store.completeOnboarding()` (line 339, sets the flag true). Because `replayOnboarding()` already persisted `onboarding_done_v1=false`, **force-quitting does not escape** — on relaunch the cover returns. The user is compelled to complete and therefore apply the flow.

**Selection state is hardcoded, not preloaded** — `OnboardingView.swift:13-16`:
```swift
@State private var index = 0
@State private var areas: Set<Pillar> = [.health, .spirituality]
@State private var faith = "islam"            // islam / other / none
```
Since `OnboardingView` is a struct re-created each time the cover appears, these defaults apply on every replay regardless of the user's actual pillars/modules.

**`finish()` unconditionally applies those defaults** — `applyOnboarding()` at `AppStore.swift:431-465`:
```swift
for i in data.habits.indices {
    let p = data.habits[i].pillar
    if [.health, .spirituality, .work].contains(p) {
        data.habits[i].active = areas.contains(p)   // deactivates unselected pillars
    }
    ...
}
...
updateModules { m in
    m.health = areas.contains(.health)
    ...
    m.prayer = areas.contains(.spirituality) && faith == "islam"
    m.workStudy = areas.contains(.work)
}
```
With the default `areas` excluding `.work`, a Work/Study user's Work habits are set `active=false` and the `workStudy` module is turned off (hidden). `finish()` also runs `prayer.setEnabled(muslim)` / `fasting.enabled` (OnboardingView.swift:326-331).

**Correction to the original report:** with the hardcoded defaults (`faith="islam"`, spirituality selected) the prayer module is *enabled*, not hidden — so for a non-Muslim who deliberately disabled prayer, replay forces prayer back on and marks them Muslim. The unambiguous *deactivation* case is Work/Study. Either way it is an unwanted config mutation driven by defaults, not by the user's real state.

**Targets mutate live during navigation.** The stepper/field closures write straight to the store as the user pages through (`OnboardingView.swift:166-202`, e.g. `store.updateTargets { $0.calories += 50 }`, and prize fields bound to `store.targets.*`). These edits persist immediately, independent of whether the user "finishes."

**Severity correction (High → Medium):** habits are deactivated (`active=false`) not deleted, modules are re-toggleable, and targets are re-editable — the damage is reversible through Settings, and the areas step is visible so an attentive user can re-select Work. This is a genuine UX/config-integrity defect, not a security vulnerability or permanent data loss, so Medium fits the product-ux dimension under threat model (a).

## Failure / exploit scenario

Threat model (a), self-inflicted: A Work/Study user taps Settings → "Run setup again" out of curiosity, expecting a harmless walkthrough of "Replay the guided onboarding." The Areas step defaults to Health + Spirituality only (Work unselected). Not realizing the selection is the live source of truth, they tap Continue through the pages — steppers along the way silently rewrite `store.targets` — and press "Start winning days." On finish, `applyOnboarding` sets every Work-pillar habit `active=false` and turns off the `workStudy` module (it vanishes from the Today tab). There is no Cancel and force-quitting mid-flow doesn't help (the reset flag is already persisted), so the user cannot back out without completing and applying. They must then manually reactivate each habit and re-enable the module in Settings to recover.

## Impact

A Settings entry advertised as a harmless replay can deactivate habits and hide modules the user depends on, and immediately persists any target edits made while navigating. Compounded by a dead-end presentation with no Cancel and no escape via force-quit, the user is forced to complete the flow and apply the hardcoded defaults. The change is reversible through Settings (habits are deactivated, not deleted), so it is a config-integrity and UX-trap problem rather than permanent data loss.

## Recommendation

1. **Preload state on replay.** Initialize `OnboardingView`'s `@State` from the user's current config — `areas` from active pillars/enabled modules, `faith` from `prayer.enabled`/branch — so completing the flow re-affirms the existing setup instead of overwriting it with defaults.
2. **Provide an escape hatch.** Add a Cancel/Close control (or make the `fullScreenCover` dismissible) that sets `onboardingDone=true` without calling `applyOnboarding`, so the user can back out. Guard `finish()` so a replay is additive — do not deactivate habits/modules the user did not explicitly turn off.
3. **Don't persist target edits until confirmation on replay.** Buffer stepper/field changes in local `@State` during the flow and commit via `store.updateTargets` only in `finish()`, so navigating out (or cancelling) leaves existing targets untouched.
4. Optionally, distinguish a "first-run" onboarding from a "reconfigure" mode so the replay copy and defaults reflect editing an existing setup.


---

_Finding PROD-02. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._