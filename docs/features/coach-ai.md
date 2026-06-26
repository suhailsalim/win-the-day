# Coach & AI

## Providers (`AIEstimator` + `Providers`)
One client, many providers: **Anthropic, OpenAI, Google Gemini, OpenRouter, DeepSeek, Ollama
(local), Ollama Cloud, Apple Intelligence**. OpenAI/OpenRouter/DeepSeek/Ollama/Ollama-Cloud all go
through one OpenAI-compatible `/chat/completions` client; Anthropic and Gemini have their own.
- `AIProvider` flags: `needsKey`, `isLocal`, `allowsCustomModel`. `apiModelID` maps internal model
  ids → real API ids. Custom model id + Ollama host live in `AppSettings`.
- Keys are stored per-provider in the **Keychain** (`Keychain.swift`). **Test connection** in Settings
  runs `estimator.testConnection`.
- JSON helpers `parseObject`/`parseResult`/`sliceJSON` tolerate markdown fences and extra prose.

## Coach surfaces (all in `AppStore`)
- **Daily suggestion** (`refreshSuggestion`/`suggestionPrompt`) — one time-aware nudge on Today,
  weather- and day-status-aware.
- **Coach chat** (`CoachChatView`, `sendChat`, `coachContext`) — a data-aware conversation. The
  system preamble (`coachContext`) includes config, today, the week, recent days, and the
  **health index**. Transcript persisted (`coach_chat_v1`).
- **Weekly review** (`refreshWeeklyReview`) — Trends card; **week outlook** + **week plan** — see
  [planning](planning.md). All reuse `estimator.suggest`/`generateWeekPlan`.

## Health index (context for the coach)
`AppStore.healthIndex()` consolidates the latest body comp, recent labs, and user **health notes**
(conditions/meds/injuries/goals, edited in `HealthView` → `HealthNoteEditor`). Injected into the
coach context, weekly review and planner so advice respects the user's real health.

> Privacy: the health index (notes + lab values) is sent to the selected AI provider, same as meal
> data. The UI says so. Apple Intelligence is on-device (no vision); other providers are cloud.

## Key files
`AIEstimator.swift`, `Models.swift` (`Providers`, `AIProvider`, `ChatMessage`, `HealthNote`),
`AppStore.swift` (`coachContext`/`sendChat`/`refreshSuggestion`/`refreshWeeklyReview`/`healthIndex`),
`CoachChatView.swift`, `Keychain.swift`, `AppleIntelligence.swift`.
