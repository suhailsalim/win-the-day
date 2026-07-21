# website/assets

Static images for the public site. Nothing here is generated — drop files in and they ship.

## icon.png

The app icon, downscaled from `WinTheDay/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
to 512×512. Regenerate after an icon change with:

```bash
sips -Z 512 --out website/assets/icon.png \
  WinTheDay/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

## screenshot-1..4.png — **to be captured**

The landing page's screenshot strip paints these as CSS backgrounds over a grey placeholder
(`.shot-frame` in `website/style.css`). While a file is missing you see the grey box and its
caption; the moment you drop the PNG in with the right filename it appears. **No HTML edit is
needed** — but if you change what a screenshot shows, update the matching `aria-label` and
`<figcaption>` in `website/index.html`.

Capture these four, in this order, on a portrait iPhone with a realistic day of data
(Simulator: ⌘S; device: side + volume up):

| File | Screen | What must be visible |
|---|---|---|
| `screenshot-1.png` | Today tab, scrolled to top | The ring row and the habit checklist below it |
| `screenshot-2.png` | Today tab, prayer module | Today's prayer times with on-time bands marked |
| `screenshot-3.png` | Coach tab, an open thread | A question and an answer that clearly uses the day's data |
| `screenshot-4.png` | Sleep card / Health tab | Sleep stages plus the Sleep and Readiness scores |

Guidelines:

- **Portrait only.** The frames are `9 / 19.5` and use `background-size: cover`, so a landscape
  or square image will be cropped hard.
- **Scrub personal data** before committing — real weights, labs, health notes and locations
  should be replaced with plausible demo values. These files are public.
- Keep each file well under 1 MB (`sips -Z 1200 --out screenshot-1.png <source>.png` is usually
  enough; the frames render at roughly 260 pt wide).
- Light mode matches the site's design; the app's white glass reads better than dark here.
