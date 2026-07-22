# PROD-05 — Secondary ink colors (tertiaryInk/quaternaryInk) fall below WCAG AA contrast for the 10–13px state-bearing text they render, worsened by the transparent "liquid glass" surfaces

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Product & UX |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Location(s)** | `WinTheDay/UI/Theme.swift`, `WinTheDay/Settings/SettingsView.swift`, `WinTheDay/Settings/SettingsPages.swift`, `WinTheDay/Trends/TrendsView.swift`, `WinTheDay/Today/TodayView.swift` |

## Summary

The two faint text tokens used pervasively for subtitles, hints, counts and metadata resolve to roughly 3:1 and 2:1 contrast on a white card — below WCAG AA's 4.5:1 for normal text — and the app's default near-transparent material surfaces lower the effective contrast against whatever shows through the glass still further.

## Details

Verified directly in `WinTheDay/UI/Theme.swift`:

```swift
static var tertiaryInk: Color  { adaptive(light: 0x9096A6, darkGrey: 0x7E8698) }   // line 113
/// The faintest readable text …
static var quaternaryInk: Color { adaptive(light: 0xB3B8C4, darkGrey: 0x646C7E) }  // line 115
```

Independent sRGB relative-luminance math on the light values:
- `tertiaryInk` `0x9096A6` = RGB(144,150,166) → L≈0.305 → contrast on white ≈ **2.96:1**. This fails AA normal-text (4.5:1) and even marginally fails the 3:1 large-text bar.
- `quaternaryInk` `0xB3B8C4` = RGB(179,184,196) → L≈0.479 → contrast on white ≈ **1.98:1**. Fails every WCAG threshold, including the 3:1 non-text/large-text floor.

These are not confined to decorative glyphs. `rg` across `WinTheDay/` shows both tokens applied to real, state-bearing text at 10–13px (all well below the AA large-text threshold of 18pt regular / 14pt bold):
- `WinTheDay/Settings/SettingsView.swift:130` — row subtitle `Text(sub) … size:12 … tertiaryInk`.
- `WinTheDay/Settings/SettingsPages.swift:89` — `Text(sub) … size:12 … tertiaryInk`; also `:218` "Stored in your device Keychain", `:333` "Your machine's address on this network", `:157/:171/:182/:388/:434` all size-12 tertiaryInk metadata.
- `WinTheDay/Trends/TrendsView.swift` — `:309` "avg score N", `:347` "N sessions", `:371` "vs daily value", `:417` "doses marked", `:427` "taken/scheduled · pct%" — all size 12, tertiaryInk (some size 10, `:76/:381`).
- `WinTheDay/Food/FoodLogView.swift:403` "kcal" size 11 tertiaryInk; `CatalogView.swift:84` macro line.
- `quaternaryInk` also carries meaningful text, not just chevrons: `WinTheDay/Today/TodayView.swift:1782` hint (size 12), `:1529` target (size 12); `WinTheDay/Health/HealthView.swift:387` and `BiologyView.swift:170/197` (size 12); `SettingsPages.swift:143` a bold size-12 tag/badge.

The translucency claim is also accurate. `Theme.swift:145-148`:
```swift
static var surfaceOverlay: Color {
    adaptive(light: 0xFFFFFF, darkGrey: 0x2A2E38, darkBlack: 0x101116)
        .opacity(glassOff ? 1 : 0.42)
}
```
By default (Reduce Transparency off) the solid white tint under the material is only 42% opaque over `WarmBackground`'s coloured gradient + refraction blobs (`Theme.swift:190+`), so the composited background behind this text is not pure white — the 2.96:1 / 1.98:1 figures are an upper bound; real on-glass contrast is lower. Only when the user enables iOS Reduce Transparency (`glassOff`) does the surface become opaque white and the pure-white numbers apply.

Corrections to the original report: the reported ratios (3.1:1 / 2.1:1) are essentially right but slightly optimistic — the true figures are ~2.96:1 and ~1.98:1, meaning tertiaryInk also just misses the 3:1 large-text floor. And quaternaryInk is not purely decorative: several call sites use it for hints/targets/tags that convey information.

## Failure / exploit scenario

Threat model (e), accessibility/usability: a low-vision user, or any user in bright/outdoor lighting, opens Settings or Trends. Row subtitles that convey real state — an auto-backup date, "Stored in your device Keychain", "avg score", "taken/scheduled · pct%", a plan hint — are drawn in `tertiaryInk`/`quaternaryInk` at 11–13px over 42%-opaque glass sitting on a tinted gradient. At ~3:1 (and ~2:1 for quaternaryInk) these are below the WCAG AA 4.5:1 normal-text minimum, and the translucent composite pushes effective contrast lower, so the text is difficult or impossible to read. This is not a security exposure; it is a readability/accessibility defect affecting a broad swath of secondary UI. No malicious actor is required — the default configuration triggers it.

## Impact

A large amount of secondary but meaningful UI text across Settings, Trends, Food, Today and Health tabs is hard to read for low-vision users and in bright conditions. Because these strings carry actual state (backup dates, keychain notices, LAN address help, dose/adherence counts, scores), the failure degrades comprehension, not just polish. It is also an App Store accessibility-guideline / WCAG-AA gap that could surface in review or accessibility complaints. No data-integrity or security consequence.

## Recommendation

Raise the luminance of the light-scheme faint inks so state-bearing text clears 4.5:1 against the *composited* glass surface, not pure white:
- Darken `tertiaryInk` from `0x9096A6` toward roughly `0x6C7182`–`0x676C7C` (≈4.5:1 on white, with headroom for the 42% overlay) — verify against `surfaceOverlay` over `WarmBackground`, not against white.
- Reserve `quaternaryInk` (`0xB3B8C4`) strictly for genuinely decorative marks — chevrons, dividers (`Components.swift:95`), progress dots, the `/total` denominators — and switch its text call sites (`TodayView.swift:1782/1529`, `HealthView.swift:387`, `BiologyView.swift:170/197`, `SettingsPages.swift:143`) to `secondaryInk`/`tertiaryInk`.
- Alternatively/additionally, raise the under-text solid tint (increase `surfaceOverlay` opacity above 0.42, or layer an opaque tint specifically behind text-bearing cards) so the effective background is closer to opaque where small text lives.
- Only keep 3:1 where the text is truly large (≥18pt regular / ≥14pt bold) — none of the confirmed call sites qualify, they are 10–13px.
Validate the fix by sampling the rendered composite (glass over gradient/blobs), since the pure-white math understates the real deficit.

## References

- WCAG 2.1 SC 1.4.3 Contrast (Minimum) — 4.5:1 normal text, 3:1 large text (≥18pt / ≥14pt bold)
- Apple Human Interface Guidelines — Accessibility → Color and contrast


---

_Finding PROD-05. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._