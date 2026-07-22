# PROD-03 — App-wide fixed font sizes — Dynamic Type / "Larger Text" accessibility setting has no effect anywhere

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Product & UX |
| **Status** | CONFIRMED |
| **Location(s)** | _See Details below._ |

## Summary

Every text label in the iOS app is styled with a hardcoded point size via `.font(.system(size:))`. There are zero uses of semantic text styles, `ScaledMetric`, or `relativeTo:`, so the user's iOS Text Size / Accessibility → Larger Text setting has no effect on any screen.

## Details

Independently re-read and grepped the repo; the report's core claims hold exactly.

- **784 hardcoded sizes, 0 Dynamic Type.** `rg -o '\.system\(size:' WinTheDay/ | wc -l` → **784**, spread across **41 files**. A grep for every scalable path — semantic styles `.font(.body|.headline|.title|.caption|.subheadline|.footnote|.callout|.largeTitle)`, `relativeTo:`, `ScaledMetric`, `@Environment(\.sizeCategory)`, `dynamicTypeSize`, and `Font.TextStyle` — returns **zero matches** anywhere in `WinTheDay/`.
- **The shared type helper itself is non-scaling.** `Theme.swift:153-157`:
  ```swift
  static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
      .system(size: size, weight: weight, design: .rounded)
  }
  static func serif(_ size: CGFloat) -> Font { display(size) }
  ```
  Both take a raw `CGFloat` and return a fixed-point `.system(...)` font, so even the app's own type abstraction cannot scale.
- **Cited call sites verified.** `OnboardingView.swift:254-255` — title `.font(.system(size: 27, weight: .bold))`, subtitle `.font(.system(size: 15))`. `SettingsView.swift:129-130` — row title `.font(.system(size: 16))`, subtitle `.font(.system(size: 12))` with `.lineLimit(1)`.
- **Sizes skew small.** Size histogram: the most common sizes are **12pt (138 occurrences)**, **13pt (120)**, **16pt (117)**, **11pt (71)**, and the smallest are **5pt, 8.5pt, 9pt, 10pt** used for ring/metric micro-labels. None of these respond to the OS setting.

The report's numbers, line citations, and the `Theme.serif(_:CGFloat)` evidence are all accurate. This is a real, reachable, genuinely app-wide condition — not theoretical.

I downgraded severity from High to Medium: this is an accessibility/usability gap under threat model (e), not a data-loss, security, or App Store hard-rejection issue (Apple does not typically reject solely for missing Dynamic Type). It is nonetheless a complete, app-wide removal of a first-class iOS accessibility affordance, which keeps it above Low.

## Failure / exploit scenario

**Threat model (e) — accessibility / HIG compliance.** A presbyopic or low-vision user who has set iOS **Settings → Display & Brightness → Text Size** (or **Accessibility → Larger Text**) to a large value opens Win the Day. Every screen renders at its designer-fixed size regardless: Settings-row subtitles stay at 12pt (`SettingsView.swift:130`), body/hint text at 15-16pt, and ring/metric micro-labels at 8.5-10pt. Because there is not a single `ScaledMetric`, `relativeTo:`, or semantic style anywhere, the OS text-size slider is completely inert inside the app — the user has no in-app way to enlarge anything either. For a daily health/discipline tracker whose audience skews toward users who need to read small numeric labels (scores, macros, timers), this is a persistent daily barrier, not an edge case.

## Impact

Low-vision and presbyopic users cannot enlarge any text in the app through the standard iOS mechanism; the entire UI is locked to designer point sizes as small as 5-8.5pt for ring labels and 11-12pt for the most common body/hint text. This is one of the most common iOS accessibility failures and here it is total (0 of 784 text sites scale). It affects usability for a meaningful share of a health-app audience and is a HIG/accessibility-compliance gap, though not a security or data-integrity defect and not typically an App Store hard-rejection trigger.

## Recommendation

Adopt Dynamic Type incrementally, starting with the highest-traffic reading surfaces (Settings rows, onboarding copy, coach chat bubbles, Today body text):

- Prefer semantic styles (`.font(.body)`, `.headline`, `.subheadline`, `.caption`) where the existing size roughly maps to one.
- Where a specific size must be preserved, make it scale: `.font(.system(size: 15, relativeTo: .body))` or drive it with `@ScaledMetric var size: CGFloat = 15`.
- Extend the shared helper so scaling is the default path — e.g. add a `relativeTo: Font.TextStyle` parameter to `Theme.display(_:)`/`serif(_:)` in `Theme.swift:153-157` so every call site scales without a rewrite.
- For dense layouts (rings, timers, complications) that genuinely cannot flex, cap growth with `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` rather than leaving them fixed — this still gives partial relief.
- Audit the sub-11pt labels (5pt, 8.5pt, 9pt, 10pt) separately; those are below comfortable legibility even at default text size.

## References

- Apple HIG — Typography / Dynamic Type
- WCAG 2.1 SC 1.4.4 Resize Text


---

_Finding PROD-03. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._