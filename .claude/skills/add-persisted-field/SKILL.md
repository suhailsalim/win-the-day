---
name: add-persisted-field
description: Add a stored property to any persisted struct (Entry, AppData, AppSettings, ModulePrefs, Occasion, …) without wiping user data. Use BEFORE adding/renaming any field that gets saved.
---

# Add a persisted field (the data-loss-proof way)

**The iron rule:** every persisted struct has a hand-written tolerant `init(from:)`. A field
without its decode line = user data wiped on next launch. Never rely on synthesized Codable.

## Procedure
1. Add the `var` with a **default value**:
   `var newThing: Int = 0` (or `Int?` with `nil` = "never computed" when a real `0` must be
   distinguishable from "absent" — never use `0` as a sentinel).
2. In the struct's `init(from:)`, add the matching tolerant line **in the same order**:
   ```swift
   newThing = (try? c.decode(Int.self, forKey: .newThing)) ?? 0
   ```
3. Check whether the struct has an **explicit `CodingKeys` enum**. If yes, add `case newThing` —
   otherwise the field decodes but is silently dropped on every save (the inverse data-loss bug).
   If keys are synthesized, nothing to do.
4. Nested new types: the new struct itself needs the same treatment (tolerant init, defaults).
5. Enums stored in persisted structs need an unknown-value fallback
   (`?? .unknown` / `?? .custom`), never a throwing decode.

## Verify (all three, every time)
- Build green.
- **Old data loads:** run the app over an existing install; past entries must render.
- **Round-trip:** encode → decode preserves the new field with a non-default value. If
  `EngineTests/` exists, extend `CodableToleranceTests` with the field.

## Don'ts
- Don't rename persisted keys — decode old key as fallback if a rename is unavoidable.
- Don't add non-defaulted `let`s to persisted structs.
- Don't grow `SharedSnapshot` carelessly — it shares the ~1MB UserDefaults ceiling
  (see add-snapshot-field skill).
