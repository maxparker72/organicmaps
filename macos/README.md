# mapo

A native macOS map planner (SwiftUI) built on the [Organic Maps](https://organicmaps.app) engine. It is a fork
kept in sync with upstream; everything Mac-specific lives in `macos/`.

## Use it

- Build and install: run the `macos-release` skill in Claude Code, or see `.claude/skills/macos-release/SKILL.md`.
  The app is installed to `/Applications/mapo.app`, ad-hoc signed for this Mac.
- Your data (bookmarks, downloaded maps, settings): `~/Library/Application Support/com.maxparker72.mapo/`.
  Move it with **Settings → Storage → Change Location…**.
- Report a problem: run the `macos-triage` skill. It reads crash reports and the app log and files the
  issue in the project tracker.

## What it does

Offline map browsing, search, map downloads, bookmarks and tracks (import/export KML, KMZ, GPX), tags,
projects and filters, and route planning (no turn-by-turn navigation). The full list with status is
[docs/SPEC.md](docs/SPEC.md).

## Develop it

Start with [CLAUDE.md](CLAUDE.md), then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/DECISIONS.md](docs/DECISIONS.md). Merge upstream with the `macos-sync` skill.

## Credits

Built by Maxwell Parker. Based on Organic Maps, licensed under Apache 2.0.
Map data © OpenStreetMap contributors (ODbL).
