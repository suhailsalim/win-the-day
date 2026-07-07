# AI coach

The coach is a chat that can actually *see your data* — not a generic chatbot.

## Conversations

Multiple **threads**, like any modern chat app: create, rename, swipe to delete; titles are
auto-generated from the first message. History is stored on-device only.

## How it reads your data

With a capable provider, the coach uses **tools**: instead of receiving a stale summary, it fetches
exactly what your question needs, live —

- a specific day's log, meals, and prayers
- your recent days, week stats, and streak
- Sleep/Readiness/Active/Eating scores *and the factors behind them*
- your health profile (body composition, labs, notes) and configured targets

So "why was my readiness low on Tuesday?" pulls Tuesday's actual factors, and "am I eating enough
protein this week?" computes from your real log. The coach is instructed to never invent numbers —
scores come from the app's deterministic engines, and the AI only explains them.

## Providers & fallbacks

Tool-calling works on Anthropic, OpenAI, Gemini, OpenRouter, DeepSeek, and tool-trained Ollama
models. Providers that can't do tools (e.g. Apple Intelligence) still work — the coach falls back
to a compact context summary. You always get an answer; the app degrades, it doesn't fail.

## Privacy

Chat content and whatever data the coach reads are sent to **your chosen provider** — that's the
point, and the UI says so. Prefer maximum privacy? Use Ollama with a local model and nothing leaves
your machines, or Apple Intelligence for on-device processing. API keys stay in the Keychain.

## Beyond chat

The same AI layer powers meal estimates, the week outlook, occasion/trip planning, day tips, ring
explanations, and parsing lab/InBody reports — all through the provider you configured once.
