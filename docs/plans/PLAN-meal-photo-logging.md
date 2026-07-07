# PLAN: Meal photo logging — snap a plate, get editable food rows

## Goal
The AI layer already parses *images* for InBody/lab reports (`ImportReportView` → vision-capable
providers), and the food log already accepts AI-parsed editable rows. Connect the two: photograph a
meal → vision model identifies items + portions → the SAME editable approve-before-save rows the
text parser produces. This is the single biggest logging-friction reducer for home-cooked
(especially Kerala/South-Indian) meals that barcode/search can't cover.

## Files to touch
- `WinTheDay/AI/AIEstimator.swift` — `estimateMealPhoto(image:knownFoods:settings:)` reusing the
  existing image-payload plumbing from `parseBodyComp` (find how it base64s/attaches images per
  provider and copy that exactly).
- `WinTheDay/Food/FoodLogView.swift` — camera button on each meal section → ImagePicker (exists) →
  parse → the existing editable-rows approval UI.
- `WinTheDay/Core/Models.swift` — nothing new persisted (photos of meals are NOT stored in v1; only the
  resulting rows). If a meal-photo thumbnail is wanted, that's v2.

## Steps, in order
1. Read `ImportReportView.swift` + the vision path in `AIEstimator` to learn the exact
   per-provider image format handling (Anthropic/OpenAI/Gemini differ; some providers have no
   vision — find the existing capability gate).
2. Prompt design: system text instructs — identify distinct foods, estimate portion in household
   measures, return the same JSON schema `parseEntries` uses, reuse `knownFoods` (user library)
   values verbatim when an item matches, mark low-confidence items `"confidence": "low"`. Feed
   the image + optional user caption ("my lunch, the curry is fish").
3. Apply the app's established JSON → lenient → deterministic-fallback contract: on total parse
   failure, fall back to one editable freeform row "Photo meal — describe it" rather than an error
   dead-end.
4. UI: camera/photo-library button beside the meal's add-food row → progress state → present the
   parsed rows in the existing approval editor (qty steppers, per-row delete) → save through the
   existing food-log add path (rows tagged `source: .llm`).
5. Provider gating: show the camera button only when the selected provider supports vision
   (extend/reuse the existing capability check; Ollama vision models exist — gate the same way
   tool support is gated, allowlist + graceful failure).
6. Build, verify on device with a real plate photo on two providers (one Anthropic-style, one
   OpenAI-style), commit.

## Edge cases a weaker model would miss
- **Image size:** a 12MP photo blows token/byte budgets. Downscale to ≤1024px longest side and
  JPEG ~0.6 before sending (check whether the InBody path already does this — reuse its resize).
- The photo itself must NOT be persisted into UserDefaults or chat threads (1MB ceiling) and NOT
  auto-saved to the day's progress photos — they're different features.
- Portion estimates from photos are systematically overconfident: the approval step is mandatory,
  never auto-commit; keep every row editable and default qty to 1 serving.
- A meal photo can match multiple library items with the same name — prefer the library value but
  keep the model's portion, and say so in the row subtitle ("your library values").
- Offline/failed upload: time out cleanly (~30s) back to the meal sheet with the fallback row.

## Acceptance criteria
- [ ] Photographing a multi-item plate yields ≥2 editable rows with plausible kcal/protein; Save
      adds them to the correct meal with `llm` source badges.
- [ ] An item matching the user's library arrives with the library's macro values.
- [ ] Non-vision provider selected → camera button hidden; no crash path.
- [ ] Airplane mode → graceful failure with the freeform fallback row.
- [ ] No image bytes appear in UserDefaults after use (inspect the blob size before/after).
