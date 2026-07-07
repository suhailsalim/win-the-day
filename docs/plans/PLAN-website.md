# PLAN: Public website — landing page + hosted docs

## Goal
One public web presence serving three jobs: (1) a marketing **landing page** that sells the app's
story (local-first, deterministic scores, faith-aware, bring-your-own-AI), (2) the **hosted user
docs** (the MkDocs site already in this repo), (3) the App Store compliance pages every submission
needs (**privacy policy** and **support**). Zero backend, zero cost: everything static on GitHub
Pages.

## Architecture decision
- **Docs:** the existing MkDocs Material site (`mkdocs.yml` + `docs/`) — already builds `--strict`.
- **Landing + legal pages:** hand-written static HTML/CSS in a new `website/` folder at the repo
  root. NOT a JS framework — one page, no build step, trivially maintainable. Design language
  should echo the app: white "liquid glass" cards, sage/amber/coral accents, generous serif
  headings.
- **Deploy:** one GitHub Actions workflow builds MkDocs into `site/`, copies `website/` over the
  root, and publishes to GitHub Pages. Result:
  - `/` → landing page
  - `/privacy/`, `/support/` → legal/support
  - `/docs/` → MkDocs user guide + developer docs
- **Domain:** start at `https://<user>.github.io/win-the-day/`; a custom domain (see the app-rename
  discussion) is a CNAME file + DNS later, no rework.

## Files to create
- `website/index.html` — landing page
- `website/style.css` — shared styles
- `website/privacy/index.html` — privacy policy
- `website/support/index.html` — support page
- `website/press/index.html` — press kit (screenshots, icon, one-paragraph description) [optional v2]
- `.github/workflows/site.yml` — build & deploy
- Edit `mkdocs.yml`: set `site_url` to the final URL + `/docs/`, and set `use_directory_urls: true`
  (default).

## Steps, in order
1. **Landing page content** (write it from `docs/index.md` — do not invent new claims):
   - Hero: app icon, name, one-liner ("Run your whole day — scored honestly, coached by AI,
     stored only on your phone"), App Store badge placeholder (link `#` until published).
   - Three pillars section: Private by design / Deterministic scores / Faith as a first-class
     pillar — each ~40 words, lifted from docs/index.md.
   - Feature grid: 8 cards mirroring the docs feature map (rings, food, faith, sleep, coach,
     planning, trends, widgets), each linking into the corresponding `/docs/guide/...` page.
   - Screenshot strip: reference `assets/screenshot-{1..4}.png` — add a `website/assets/README.md`
     saying which screens to capture (Today ring row, prayer module, coach thread, sleep card);
     use grey placeholder boxes until real screenshots are dropped in.
   - Footer: links to Docs, Privacy, Support, GitHub.
2. **Privacy policy** (`website/privacy/index.html`) — must be truthful to the code, and this app's
   story is unusually good; say it plainly:
   - No accounts, no analytics, no tracking, no app-operated servers.
   - Data stored on-device (UserDefaults/Documents/Keychain); HealthKit governed by iOS permissions
     and never transmitted by the app.
   - AI features transmit user-entered text (meals, chat, health notes the user submits) to the
     **user-selected** provider under that provider's terms; list the possible providers.
   - Location used on-device for prayer times/Qibla; coordinates sent only to Open-Meteo for
     weather; barcode/search queries go to Open Food Facts.
   - Contact email; effective date. Keep it in plain English, ~1 page.
3. **Support page**: FAQ link (into `/docs/guide/faq/`), contact email, and a bug-report link to
   GitHub issues.
4. **Workflow** `.github/workflows/site.yml`:
   ```yaml
   name: site
   on: { push: { branches: [main], paths: [docs/**, website/**, mkdocs.yml] }, workflow_dispatch: {} }
   permissions: { contents: read, pages: write, id-token: write }
   jobs:
     build:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: actions/setup-python@v5
           with: { python-version: '3.12' }
         - run: pip install mkdocs-material
         - run: mkdocs build --strict --site-dir _site/docs
         - run: cp -r website/* _site/
         - uses: actions/upload-pages-artifact@v3
         - deploy: (use actions/deploy-pages@v4 in a dependent deploy job with environment github-pages)
   ```
   (Write the real two-job build/deploy pattern from the actions/deploy-pages README — the sketch
   above compresses it.)
5. Repo settings: enable Pages with "GitHub Actions" as the source (manual step — note it in the
   commit message and README).
6. Update `README.md` with the site URL; update `mkdocs.yml` `site_url`.
7. Verify locally: open `website/index.html` in a browser (it must work as a plain file — no
   absolute `/` asset paths, use relative `style.css`), and `mkdocs build --strict`.
8. Commit: `feat: public website — landing, privacy, support + Pages deploy for docs`.

## Edge cases a weaker model would miss
- **Path prefix:** on `github.io/<repo>/` the site is NOT at the domain root. All landing-page
  links must be **relative** (`docs/`, `privacy/`), never `/docs/` — absolute paths break on
  project pages and survive a later custom-domain move only by luck.
- `mkdocs build --strict` fails on broken nav links — if you add cross-links from docs to the
  landing page, use full URLs, not relative paths escaping `docs_dir`.
- The MkDocs 2.x warning seen locally: **pin `mkdocs-material`** (1.x-compatible latest) in the
  workflow to avoid the announced MkDocs 2.0 breakage; add `mkdocs<2` to the pip install line.
- Don't commit `site/` (already git-ignored); the workflow builds it fresh.
- Privacy policy must not overpromise: the app DOES send user content to third-party AI providers
  when AI features are used. Apple reviews privacy policies against App Store privacy labels —
  keep the two consistent when the App Store listing is written.
- No cookies/analytics on the site itself keeps the privacy story clean — do not add a tracking
  snippet "for later".

## Acceptance criteria
- [ ] `mkdocs build --strict` green; workflow runs green on push to main.
- [ ] Landing page renders correctly opened as a local file AND at the Pages URL (all links
      relative).
- [ ] `/docs/` serves the full user guide with working nav and search.
- [ ] `/privacy/` and `/support/` load, are accurate to the current code's behavior, and carry a
      contact address.
- [ ] Lighthouse (or by-hand check): landing page has no external JS, loads a single CSS file,
      images have alt text.
