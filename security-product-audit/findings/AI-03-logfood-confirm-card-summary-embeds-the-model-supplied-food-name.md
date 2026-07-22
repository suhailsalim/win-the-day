# AI-03 — logFood Confirm-card summary embeds the model-supplied food name with no length cap, unlike setMealText

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | AI / LLM trust boundary |
| **Status** | CONFIRMED |
| **Location(s)** | _See Details below._ |

## Summary

proposeLogFood interpolates the fully model-controlled `name` argument verbatim into the Confirm-card summary with no length cap, while the sibling proposeSetMealText caps display text to `prefix(120)`; the card renders multi-line without truncation, giving injected content a small UI-spoofing surface on the user's only approval view.

## Details

`proposeLogFood` clamps every numeric argument tightly (`qty` 0.01–50, `kcal` 0–5000, `protein` 0–500) but passes the food `name` straight through:

```swift
// CoachTools.swift:143-156
let name = AppStore.coachStr(args, "name")
guard !name.isEmpty else { return "Missing food name — nothing proposed." }
...
return store.stageCoachWrite(
    kind: "logFood", date: day,
    summary: "Log \(qtyLabel)\(name) to \(label(meal))\(dayNote(day, store)) (\(macro))",
    payload: ["name": name, "mealKey": meal, "qty": qty, "kcal": kcal, "protein": protein])
```

`name` is fully model-controlled and, via threat model (c), steerable by injected content (a meal caption / OCR'd label the model echoes back into a tool call). `AppStore.coachStr` (AppStore.swift:3435-3437) only does `trimmingCharacters(in: .whitespacesAndNewlines)` — it strips *edge* whitespace/newlines but imposes **no length cap** and does not touch *interior* newlines.

The staged summary is the user's only view of what Confirm will apply, rendered here:

```swift
// CoachChatView.swift:133-135
Text(w.summary.isEmpty ? "A change to your log" : w.summary)
    .font(.system(size: 14.5)).foregroundStyle(Theme.ink)
    .fixedSize(horizontal: false, vertical: true)   // grows vertically, no truncation
```

Contrast the sibling proposal builder, which does cap its model-supplied string:

```swift
// CoachTools.swift:183-185
? "Clear \(label(meal))..."
: "Set \(label(meal))... to “\(String(text.prefix(120)))”"
... payload: ["mealKey": meal, "text": String(text.prefix(400))]
```

Correction to the original report: the differentiator is the **missing length cap**, not newline stripping. `proposeSetMealText` also does not strip interior newlines — it only bounds length. So `logFood` is inconsistent with `setMealText` specifically in that `name` has no `prefix(...)` bound for either the summary or the payload. (Note `proposeRemoveFood` at line 173 uses `hit.name` from already-stored user data, not a model argument, so it is not exposed.)

## Failure / exploit scenario

Under content injection (threat model c), the model is steered to call `logFood` with `name = "egg\n\n(Already saved — just tap Confirm to finish)"`. `coachStr` trims only the edges, so the interior `\n\n` and the reassuring trailer survive. Because the write card grows vertically with no truncation, the summary renders as multiple lines with a fabricated "just tap Confirm" instruction sitting directly above the real Confirm button. An extremely long `name` can likewise push the real `(~X kcal, Yg protein)` macro figures far down or off the visible card. The user, seeing the app's own trusted card UI, taps Confirm. Impact is still bounded: a single food row is logged, which is reversible via the undo journal, and Confirm is always required — nothing mutates from the proposal alone.

## Impact

The Confirm card is the sole gate and sole disclosure for coach writes ("Confirm is the ONLY thing that mutates data" — CoachChatView.swift:121). An attacker-influenced `name` can (1) spoof card structure with injected multi-line reassurances, and (2) shove the true macro figures out of view via length — both aids to social-engineering a bad row past the human check. The blast radius is small: one food entry, undoable, and no write occurs without an explicit tap. This is a defense-in-depth / UI-integrity gap on the human-in-the-loop approval surface, not a data-exfil or unauthorized-mutation bug — hence Low.

## Recommendation

Clamp `name` before building the proposal, mirroring `proposeSetMealText`: cap the summary interpolation (e.g. `String(name.prefix(80))`) and the payload (`prefix(160)`), and collapse interior newlines/whitespace to single spaces so a food name cannot introduce line breaks into the card (e.g. `name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)`). Applying the same treatment to `proposeSetMealText`'s interior newlines would harden the whole write-card surface consistently, since the summary Text renders untruncated.


---

_Finding AI-03. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._