---
name: add-coach-tool
description: Add a tool to the AI coach's tool registry (CoachTools.swift) so it can read (or propose writing) app data. Use when the coach needs access to a new data surface.
---

# Add a coach tool

All coach tools live in `WinTheDay/AI/CoachTools.swift` — one registry consumed by every provider
adapter (Anthropic / OpenAI-compat / Gemini). **Never touch adapter/wire code** to add a tool;
the registry is the only extension point.

## Procedure
1. Open `CoachTools.swift`, read one existing tool end-to-end (schema declaration → execution →
   JSON result) — currently 8 read tools (`getDay`, `getRecentDays`, `getWeekStats`,
   `getReadiness`, `getFoodLog`, `getPrayers`, `getHealthIndex`, `getTargets`).
2. Declare the tool: name (camelCase verb), 1-sentence description written FOR THE MODEL
   (when to call it, what it returns), and a tight JSON-schema for parameters (dates are
   `yyyy-MM-dd` strings).
3. Execute against existing `AppStore` methods — tools are thin JSON views over the store, never
   new business logic. Return **compact JSON** (short keys, no nulls, no prose): every byte goes
   into the context window each turn.
4. Errors → an instructive string the model can recover from ("no entry for that date; the user
   started logging 2026-05-01"), flagged as an error result — never throw, never empty.

## Rules
- Tool execution is **serial on @MainActor** by design — no TaskGroup parallelism, no off-actor
  AppStore access. Cheap in-memory reads only; anything slow needs a Sendable snapshot pattern.
- **Write tools must never mutate directly.** They return staged proposals the user confirms in
  the chat UI (see docs/plans/PLAN-coach-write-tools.md). The tool result must say "awaiting user
  confirmation", or the model will claim the change happened.
- Tool output stays confined to tool-result blocks — never splice it into system/user text
  (prompt-injection surface).
- Date-less variants default to today; always accept an optional `date` param for history
  questions.

## Verify
- Ask the coach a question only the new tool can answer, on one Anthropic-style AND one
  OpenAI-compat provider. Confirm Apple Intelligence / non-tool Ollama still answer via the
  fallback context path (they just won't have the new data).
