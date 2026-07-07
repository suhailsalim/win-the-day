# PLAN: App lock (Face ID / passcode) + privacy redaction

## Goal
The app holds health notes, labs, prayer records, and photos — sensitive by any definition — yet
opens unprotected. Add an optional **Face ID/Touch ID app lock** (device passcode fallback), a
**redaction cover** in the app switcher, and a per-launch grace period. Local-only, ~a day of work,
large trust payoff.

## Files to touch
- `WinTheDay/Managers/AppLock.swift` — NEW: small `@MainActor` ObservableObject wrapping
  `LAContext` (`LocalAuthentication`).
- `WinTheDay/App/WinTheDayApp.swift` — scene-phase hooks + lock overlay above `RootView`.
- `WinTheDay/Settings/SettingsView.swift` + `Models.swift` — `AppSettings.appLockEnabled`,
  `appLockGraceMinutes` (0/1/5/15) with tolerant decode lines.
- `Info.plist` — `NSFaceIDUsageDescription`.

## Steps, in order
1. `AppLock`: `@Published var locked`, `unlock()` calling
   `LAContext().evaluatePolicy(.deviceOwnerAuthentication, ...)` (this policy includes passcode
   fallback automatically — do NOT use `.deviceOwnerAuthenticationWithBiometrics` alone).
   Snapshot main-actor state before the evaluate closure (strict concurrency).
2. Lifecycle: on `scenePhase` → `.background`, record the timestamp and show the redaction cover;
   on `.active`, if lock enabled and `now - backgroundedAt > grace`, set `locked = true` and
   trigger `unlock()`.
3. Overlay: a full-screen blur + app icon + "Unlock" button rendered ABOVE RootView in a ZStack
   whenever `locked || inSwitcher`. The switcher redaction must appear on `.inactive` (not just
   `.background`) — that's what the app-switcher screenshot captures.
4. Settings: toggle + grace picker. Enabling runs one authentication immediately (prove it works
   before locking the user out). If `LAContext.canEvaluatePolicy` fails (no passcode set), show
   why and refuse to enable.
5. Build strict, verify on device: lock, background, reopen → Face ID prompt; app switcher shows
   the cover, not your data.

## Edge cases a weaker model would miss
- Widgets, watch, and Live Activities still show data when the phone is unlocked — the lock is
  app-level. Note it under the toggle ("widgets are governed by iOS") rather than pretending.
- Notifications/App Intents keep working while locked (they don't run the UI) — correct and fine.
- Failed/cancelled auth must remain on the cover with a retry button — never fall through to
  content, and never infinite-loop the Face ID sheet (only auto-prompt once per foreground).
- `.inactive` also fires for Control Center pulls and permission dialogs — the cover will blink;
  that's standard behavior (every banking app does it), don't "fix" it with delays.
- If the user disables the device passcode later, `evaluatePolicy` fails: detect on foreground
  and degrade to unlocked-with-banner rather than a permanent lockout.
- Grace period uses a monotonic-enough clock: wall-clock changes (timezone travel) shouldn't lock
  or unlock surprisingly — clamp negative deltas to "expired".

## Acceptance criteria
- [ ] Toggle on → backgrounding past grace → reopening demands Face ID; cancel keeps data hidden.
- [ ] App switcher thumbnail shows the cover in all states when enabled.
- [ ] No-passcode device: toggle refuses with explanation.
- [ ] Grace 5 min: quick app switches don't re-prompt; 6-minute absence does.
- [ ] Build green under `SWIFT_STRICT_CONCURRENCY=complete`; settings survive relaunch.
