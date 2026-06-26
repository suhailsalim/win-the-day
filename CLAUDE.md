# CLAUDE.md

**Read [AGENTS.md](AGENTS.md) first — it is the single source of truth** for building, conventions,
and gotchas. This file only adds Claude-Code-specific notes; everything else lives in AGENTS.md and
[`docs/`](docs/).

## Token discipline (important)

- Don't re-explore the repo each session. Start from [AGENTS.md](AGENTS.md) and the relevant
  [`docs/`](docs/) page; only open source files you're actually changing.
- This project uses **OpenWolf** for project intelligence + repeated-read prevention. `.wolf/anatomy.md`
  has a per-file index with token estimates — consult it before reading whole files. Refresh with
  `openwolf scan` after large changes. (`.wolf/` is git-ignored and per-developer.)

## Quick reference

- Build/install commands, strict-concurrency rules, signing limits: see **AGENTS.md → Build / run / install**.
- Adding fields/modules/managers/widgets: see **AGENTS.md → Conventions**. The non-negotiable one is
  **tolerant `init(from:)`** on every persisted struct — a missing decode line wipes user data.
- Verify with a device build (`SWIFT_STRICT_CONCURRENCY=complete` when touching managers), install, and
  confirm old data still loads.

## House style

- Match the surrounding SwiftUI idiom (GlassCard, Theme.*, SectionHeader, FlowLayout).
- Keep changes minimal and self-contained; one feature → its models + AppStore methods + a view.
