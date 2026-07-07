# PLAN: iPad & landscape adaptive layout

## Goal
The app is a single-column iPhone layout. On iPad (and iPhone landscape) that means a stretched
ribbon of cards. Ship an adaptive layout: two-column module flow on wide screens, side-by-side
Plan/Trends detail, and a proper coach split view (threads | conversation) — without forking any
view logic.

## Files to touch
- `WinTheDay/App/RootView.swift` — size-class detection, wide-layout container.
- `WinTheDay/Today/TodayView.swift` — module stack → adaptive columns.
- `WinTheDay/Coach/CoachChatListView.swift` / `CoachChatView.swift` — `NavigationSplitView` on regular
  width.
- `WinTheDay/Info.plist` / project settings — verify iPad device family + orientations (check
  `TARGETED_DEVICE_FAMILY` in project.pbxproj; if `1` only, add `2`).

## Steps, in order
1. Check current state: does the target include iPad at all? If `TARGETED_DEVICE_FAMILY = 1`,
   set `1,2` (pbxproj edit, both Debug/Release). Run on an iPad simulator to see the baseline.
2. Read `@Environment(\.horizontalSizeClass)` in `RootView`; pass a `isWide` flag down (or read
   the environment locally per view — prefer local reads, fewer plumbing changes).
3. TodayView: the module list currently renders in a `VStack`/`LazyVStack` order from
   `ModulePrefs`. On `.regular` width, lay modules into two columns while PRESERVING user order
   (fill columns like a newspaper: odd indices left, even right is wrong — use a masonry-ish
   two-bucket split by index parity is acceptable v1; note it). Rings row + tip strip stay
   full-width above.
4. Coach: `NavigationSplitView { CoachChatListView() } detail: { CoachChatView(thread:) }` on
   regular width; existing push navigation on compact. Keep one source of truth for the selected
   thread in AppStore.
5. Sheets (editors, food log): on regular width present as `.sheet` with
   `.presentationSizing(.form)`-style constrained sizes so they don't stretch edge-to-edge.
6. Landscape iPhone: verify the two-column Today doesn't trigger on compact-height landscape
   (size class is `.compact` width on most iPhones in landscape — it naturally won't; just verify).
7. Keyboard: iPad hardware-keyboard users get focus traversal for free; verify no
   `.scrollDismissesKeyboard` fights.
8. Build for iPad destination, screenshot every tab in both orientations, fix truncations, commit.

## Edge cases a weaker model would miss
- The custom `TabBar` is hand-built (not `TabView`) — verify it centers with sane max width on
  iPad rather than stretching icons across 12 inches; cap its width (~500pt) and center it.
- `RootView`'s `.id(store.tab)` scroll-reset trick (added in the WIP commit) also resets scroll on
  size-class changes if the id compounds — leave the id keyed on tab only.
- Widgets/watch are untouched; don't add iPad widget sizes in this pass.
- `GeometryReader`-based components (water bottle, HR zone bar, charts) assume phone widths —
  spot-check each at iPad card widths; cap card content width (~560pt) rather than redesigning.
- Live Activities don't exist on iPad lock screen the same way — the study/focus flows must not
  assume a Live Activity started successfully (they already fail soft; verify).
- Stage-manager resizing changes size class at runtime — state must survive a compact↔regular
  flip mid-session (the split-view selected thread is the risky bit; keep selection in AppStore).

## Acceptance criteria
- [ ] iPad portrait + landscape: Today shows two ordered columns, no stretched cards; all tabs
      usable and visually reasonable.
- [ ] Coach on iPad shows threads and conversation side by side; selection survives rotation.
- [ ] iPhone (all sizes) pixel-identical to before this change.
- [ ] Editors/sheets present at sane sizes on iPad.
- [ ] Device-family change builds and installs on both device types.
