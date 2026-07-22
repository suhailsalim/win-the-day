# FAQ

**Do I need an Apple Watch?**
No. Sleep, Readiness (phone-tracked sleep), Active (from iPhone motion/active calories), and
everything else work phone-only. A Watch adds sleep stages, overnight HRV, and per-minute heart
rate, which sharpen the scores.

**Do I need an AI subscription?**
No. All scoring, logging, prayer times, and planning structure are deterministic and local. AI
features need a provider — Apple Intelligence (free, on-device) and local Ollama are no-cost
options.

**Why does a ring say "calibrating"?**
Readiness and Sleep compare you to *your own* baseline, which needs about a week of data. With
existing Apple Health history, the app imports your last 30 days on first launch and calibrates
immediately.

**Why is a ring grey with "—"?**
The data for it genuinely doesn't exist for that day (e.g. no sleep recorded). The app shows
"unavailable" rather than a misleading zero.

**My prayer times look off.**
Check the calculation method, branch, and madhab in Settings → Prayer times — Asr in particular
differs by madhab. Also confirm the app has location access; times are location-dependent.

**Is my data uploaded anywhere?**
No backend, no account. The only data that leaves the device is what you send to your chosen AI
provider when using an AI feature, plus coordinates to the free weather service. See
[Settings & privacy](settings.md).

**Can I export my data?**
Yes. Settings → Backup & data exports a full backup (and auto-backs up to the Files app whenever
you leave the app); the same page restores one. A doctor-ready PDF report is also built-in, under
Settings → Apple Health.

**Where does the Health tab's profile come from?**
It's composed automatically on your device — from your targets, the latest body-comp import, meds
and notes. Nothing is typed twice: it updates itself on import, and it's what gives the AI coach
its context.

**Why did a "finding" note appear that I didn't write?**
After a lab or body-comp import, out-of-range results become an automatic finding note on the
Health tab, marked with an AUTO badge. It's computed on-device from general reference ranges — no
extra AI call. Turn it off in Settings → Apple Health → Auto notes from imports.

**What happens to my streak if I'm sick or traveling?**
Set the day's status (sick / rest / travel) — a legitimate off-day won't break your streak.

**The widget isn't updating.**
Widgets refresh from a snapshot the app writes — open the app once and give iOS a moment. iOS also
throttles widget refreshes system-wide.

**Does marking a prayer late judge me?**
No. Timing bands are recorded neutrally ("made up" rather than anything judgmental), and you can
turn timing penalties off entirely so any marked prayer counts fully.

**Which AI provider is best?**
Anthropic, OpenAI, and Gemini give the full coach experience (tool-calling). OpenRouter/DeepSeek
work well too. Ollama depends on the model (tool-trained models get tools; others get the standard
context mode). Apple Intelligence is the most private zero-setup option.
