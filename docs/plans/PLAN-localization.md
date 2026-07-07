# PLAN: Localization — String Catalog + Malayalam & Arabic (RTL)

## Goal
Every user-facing string is hardcoded English. Given the app's audience (faith features, Kerala
food coverage), Malayalam (`ml`) and Arabic (`ar`) are the natural first locales — and Arabic
forces the RTL audit that pays quality dividends everywhere. Foundation first: adopt a **String
Catalog** so all strings are extractable, then ship the two locales.

## Files to touch
- `WinTheDay/Localizable.xcstrings` — NEW String Catalog (auto-joins target).
- Widget/watch targets each need the catalog file added (or a shared one wired in pbxproj — prefer
  per-target catalogs to avoid pbxproj surgery on `Shared/`).
- Every view file — mechanical `Text("…")` audit (SwiftUI auto-localizes `Text` string literals
  once a catalog exists; `String` variables need `String(localized:)`).
- `WinTheDay/Core/Models.swift` — static content (habit starters, tips, module labels) via
  `String(localized:)`.

## Steps, in order
1. Create the String Catalog; build once — Xcode's build extracts `Text`/`Label` literals
   automatically. From CLI: `xcodebuild` with `SWIFT_EMIT_LOC_STRINGS=YES` populates the catalog.
2. Sweep non-literal strings: grep for `"` in ViewBuilders where strings pass through variables,
   `label(_:)` functions, notification bodies, App Intents phrases, and widget text — convert to
   `String(localized: "…", comment: "…")` with meaningful comments (translators see them).
3. **Do NOT localize**: UserDefaults keys, module/habit/metric identifier strings (`"rings"`,
   `"prayer"`, meal keys), AI prompt text (English prompts perform best; the AI answers in the
   user's language when asked), or log messages. Mark this list in a code comment atop the
   catalog adoption commit — it is the classic localization data-corruption trap: `label("rings")`
   the KEY must stay `"rings"` forever even when its LABEL translates.
4. Translate: machine-translate `ml` and `ar` as a first pass (state that in the PR), with the
   faith vocabulary hand-checked (prayer names stay Arabic transliterations in `ml`; in `ar` use
   the proper names الفجر، الظهر، العصر، المغرب، العشاء).
5. RTL audit with Arabic set: chevrons/arrows should flip automatically (SF Symbols do); check
   custom drawing — ring gauges and charts stay LTR (numbers/charts conventionally LTR even in
   RTL locales — wrap charts in `.environment(\.layoutDirection, .leftToRight)`), the Qibla
   compass must NOT flip (it's geographic), and `HStack`s using manual `.leading` paddings need
   review.
6. Numbers/dates: replace any hand-rolled formatting with `formatted()` styles so Arabic gets
   proper digit/locale handling; the app's internal `yyyy-MM-dd` keys must keep
   `Locale(identifier: "en_US_POSIX")` on their DateFormatters — audit every `DateFormatter` in
   the codebase for this (grep `DateFormatter`).
7. Build + run in each locale (scheme argument `-AppleLanguages (ar)`), screenshot key screens,
   fix truncations (Malayalam runs long — buttons need `minimumScaleFactor` or wrapping).
8. Commit in two commits: (a) catalog adoption + key/label separation, (b) translations + RTL
   fixes.

## Edge cases a weaker model would miss
- The **identifier-vs-label trap** in step 3 — localizing a switch key silently breaks decoding
  and module rendering for non-English users. This is the one change that can corrupt data.
- `yyyy-MM-dd` DateFormatters without POSIX locale produce Arabic-Indic digits under `ar`,
  generating unreadable entry keys → every existing entry "disappears". Audit is mandatory.
- Widget/watch targets have separate bundles — strings used there need catalogs in those targets
  or they silently stay English.
- Prayer time strings from `PrayerTimes` and AI-generated content (tips, coach) will arrive in
  whatever language the AI writes — set expectations: system UI localized, AI output follows the
  user's chat language.
- Pluralization: use catalog plural variants for "N glasses", "N days" — Arabic has six plural
  categories; hardcoded `"s"` suffixes read as broken.

## Acceptance criteria
- [ ] App fully navigable in `ml` and `ar`; no raw key strings visible anywhere in UI.
- [ ] Under `ar`: layout mirrors, Qibla compass geographically correct, charts LTR, entry keys
      still `yyyy-MM-dd` ASCII (verify a new entry's key in the blob).
- [ ] Switching back to English shows zero regressions; old data loads in all locales.
- [ ] Widgets and watch render localized strings.
