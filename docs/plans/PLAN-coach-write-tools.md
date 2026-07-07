# PLAN: Coach write tools — staged, confirm-before-commit, journaled

## Goal
The tool-calling coach shipped with **8 read-only tools** ([CoachTools.swift:20–46](WinTheDay/AI/CoachTools.swift):
getDay, getRecentDays, getWeekStats, getReadiness, getFoodLog, getPrayers, getHealthIndex,
getTargets). The master plan's write half of M7 — `logFood`, `setMealText`, `setMealTime`,
`togglePrayer`, `removeFood` — is unimplemented, and the safety design is non-negotiable:
**every write is a staged proposal rendered as an inline confirm/cancel card in chat; nothing
mutates until the user taps Confirm; confirmed writes are journaled and one-tap undoable.**
(Owner decision 2026-07-02, docs/plans/2026-07-improvement-plan.md §5.)

## Files to touch
- `WinTheDay/AI/CoachTools.swift` — tool schemas + staged execution.
- `WinTheDay/Core/Models.swift` — `PendingCoachWrite` + `CoachWriteRecord` structs (tolerant Codable),
  `ChatMessage` gains an optional `pendingWrite` field.
- `WinTheDay/Core/AppStore.swift` — `commitCoachWrite`/`rejectCoachWrite`/`undoCoachWrite` + journal
  persistence (`coach_write_log_v1` UserDefaults key) + a read-only settings toggle.
- `WinTheDay/Coach/CoachChatView.swift` — render the confirm/cancel card; "Coach changes" undo sheet.
- `WinTheDay/Settings/SettingsView.swift` — "Coach can propose changes" toggle (default on).

## Steps, in order
1. **Read first:** all of `CoachTools.swift` (how tools declare schemas and how the runner executes
   them and returns results per provider), the chat send loop in `CoachChatView.swift`/`AppStore`,
   and `ChatMessage` in Models.swift. Match those exact patterns — do not invent a new runner.
2. **Models.** Add (with hand-written tolerant `init(from:)` per AGENTS.md convention 1, and keep
   `encode` symmetric):
   ```swift
   struct PendingCoachWrite: Codable, Equatable, Identifiable {
       var id: String            // UUID string
       var kind: String          // "logFood" | "setMealText" | "setMealTime" | "togglePrayer" | "removeFood"
       var date: String          // yyyy-MM-dd target day
       var summary: String       // human line shown on the card, e.g. "Log 2 idli + sambar to breakfast (~310 kcal)"
       var payloadJSON: String   // kind-specific args, re-parsed on commit
       var status: String = "pending"   // pending | confirmed | rejected
   }
   struct CoachWriteRecord: Codable, Identifiable { // journal entry
       var id: String; var epoch: Double; var summary: String
       var undoJSON: String      // snapshot needed to reverse (e.g. removed FoodEntry, prior meal text)
   }
   ```
   `ChatMessage` gains `var pendingWrite: PendingCoachWrite? = nil` (+ tolerant decode line!).
3. **Tool schemas.** Add the 5 write tools to the registry with tight JSON schemas (foods take
   name/qty/kcal/protein/mealKey; togglePrayer takes prayer name + on/off; setMealText takes
   mealKey + text). In each tool's description write: "Proposes the change; the user must confirm
   in-app before it is saved."
4. **Staged execution.** A write tool's execute path does NOT call any mutating AppStore method.
   It builds a `PendingCoachWrite`, attaches it to the assistant chat message being assembled
   (or appends a dedicated chat message carrying it — pick whichever the message-assembly code
   makes natural), and returns the tool result string
   `"Proposed. Awaiting user confirmation in the app — do not assume it was applied."`
   so the model's follow-up text is honest.
5. **Commit/reject.** `AppStore.commitCoachWrite(_ w: PendingCoachWrite)`:
   - re-parse `payloadJSON`, apply via the SAME existing methods the UI uses (find the existing
     food-log add / meal-text set / prayer-toggle methods and call those — never duplicate
     mutation logic);
   - capture the pre-state into `undoJSON`, append a `CoachWriteRecord` to the journal (cap the
     journal at last 20 records), persist under `coach_write_log_v1`;
   - flip `status = "confirmed"` on the message's pendingWrite and persist the thread.
   `rejectCoachWrite` just flips status to `"rejected"`.
6. **UI.** In `CoachChatView`'s message renderer: if `msg.pendingWrite != nil`, render a compact
   card (house style: GlassCard, Theme colors) with the `summary` and Confirm / Dismiss buttons
   when pending, or a small "✓ Applied" / "✕ Dismissed" caption once resolved. Add a toolbar/menu
   item "Coach changes" opening a sheet listing the journal with an Undo button per row →
   `undoCoachWrite(record)` (re-parse `undoJSON`, reverse via existing methods, remove the record).
7. **Settings toggle.** `AppSettings.coachWritesEnabled: Bool = true` (+ tolerant decode line).
   When false, write tools are omitted from the tool list sent to providers entirely (cleanest —
   the model can't call what it can't see). Add the toggle in SettingsView near the coach/AI rows.
8. **Build** with `SWIFT_STRICT_CONCURRENCY=complete` (AppStore is a manager). Install, then verify
   end-to-end with a real provider: ask the coach "log 2 boiled eggs for breakfast" → card appears,
   nothing in the food log yet → Confirm → food log shows it → Coach changes sheet → Undo → gone.
9. Commit: `feat: coach write tools — staged confirm-before-commit + journaled undo`.

## Edge cases a weaker model would miss
- **The tool result must say "awaiting confirmation"** — if it returns "done", the model tells the
  user it logged the food when it didn't. This exact string contract is in the master plan.
- **Cross-provider:** the runner already normalizes Anthropic/OpenAI-compat/Gemini tool wire
  formats. Add write tools ONLY through the existing registry so all three adapters inherit them;
  touch zero adapter code. Providers without tool support (Apple Intelligence, non-tool Ollama)
  already fall back to the text path — write tools simply never appear there; don't special-case.
- **Stale confirms:** the user can confirm a card hours later. `commitCoachWrite` must re-resolve
  the target day by the stored `date` string, not "today", and tolerate the entry having changed
  meanwhile (e.g. meal text edited manually) — apply anyway, journal captures the pre-state.
- **Thread persistence:** chat threads live in UserDefaults with a size ceiling; `payloadJSON` and
  `undoJSON` must stay compact (no base64, no photos). Cap journal at 20.
- **Double-tap Confirm:** guard `status == "pending"` inside `commitCoachWrite` or a fast double
  tap logs the food twice.
- **Tolerant decode on every new stored field** (`pendingWrite`, `coachWritesEnabled`, the two new
  structs) — one missing line wipes chat history or settings on next launch. Add round-trip tests
  in `EngineTests` if that package exists by now (see PLAN-test-target.md).
- **togglePrayer semantics:** prayer marking is timestamped/banded (PrayerClassifier). Marking via
  coach must route through the same method the UI uses so the band/timestamp is recorded — a naive
  bool flip would silently bypass on-time classification.

## Acceptance criteria
- [ ] Asking the coach to log a food produces a confirm card; the food log is unchanged until
      Confirm is tapped, and updated immediately after.
- [ ] The model's reply text after proposing does NOT claim the change was applied.
- [ ] Dismissing a card leaves data untouched and the card shows "Dismissed" after re-opening the
      thread (state persists).
- [ ] Coach-changes sheet lists confirmed writes; Undo restores the exact prior state (verify with
      setMealText: original text returns verbatim).
- [ ] Settings toggle off → the provider request contains no write-tool schemas (verify via debug
      print or the request-building code path), and the coach still answers read questions.
- [ ] Build green under `SWIFT_STRICT_CONCURRENCY=complete`; old chat threads still load.
