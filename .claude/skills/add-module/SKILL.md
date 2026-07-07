---
name: add-module
description: Add a new Today-tab module (card/section) to Win the Day — the full 6-touchpoint checklist. Use when adding any new section, card, or feature surface to the Today screen.
---

# Add a Today module

A module = one key wired through 6 touchpoints. Missing any one → invisible module or a crash in
the modules editor.

## Checklist (all in order)
1. **`Models.swift` → `ModulePrefs`**: add the `var myKey: Bool = true`, its tolerant decode line,
   AND the key string in `defaultOrder` (position = default placement). The tolerant order
   migration appends missing keys to existing users' orders automatically.
2. **Same file**: add the key to the `label(_:)`, `enabled(_:)`, and `setEnabled(_:)` switches.
3. **`TodayView.moduleView(_:)`**: add `case "myKey": myModule` and build the view as a computed
   property using house components (GlassCard / `glassList()`, `Theme.*`, `SectionHeader`,
   `Hairline`).
4. **`AppStore.moduleColor(_:)`**: give it a color case.
5. **`SettingsView.colorableModules`**: append the key so users can recolor it.
6. **Core module?** Only if it must be un-disableable, add to `coreKeys`.

## Conventions
- The key string is an **identifier, never localized, never renamed** once shipped.
- Modules that are situational (e.g. only during Ramadan, only when data exists) hide themselves
  inside their own view (`if` around content), staying toggleable in the editor.
- Module state lives in `Entry`/`AppData`/a manager — the module view is dumb rendering + calls
  into `AppStore` methods (`mutate {}` for entry edits).

## Verify
- Module appears on Today at the default position for an EXISTING install (order migration).
- Shows in ModulesEditorView, reorders by drag, toggles off/on.
- Color picker in Settings affects it.
