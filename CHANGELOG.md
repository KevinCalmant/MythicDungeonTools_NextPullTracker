# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.5] - 2026-04-21

### Added

- Manual mini-map zoom on the Next Pull beacon: scroll the mouse wheel over the mini-map, or click the on-screen `+` / `-` buttons, to zoom in past the adaptive default or zoom out for more context.
- Outline drawn around the current pull on the mini-map, wrapping the enemy cluster's actual shape (convex hull). The outline color tracks the pull state (green = next, orange = in combat).

### Changed

- Mini-map enemy dots now render at a consistent size across pulls; the current pull is distinguished by the new outline rather than by dot size.
- Beacon pull badge now shows progress as `Pull X / Total` (e.g. `Pull 3 / 10`) instead of just the current pull number.

## [1.1.4] - 2026-04-20

### Fixed

- Scenario rounding tolerance now matches Blizzard's up-to-1% floor-rounding error (was 0.5%), so the "next pull" indicator no longer stalls at the tick boundary on pulls that end at a high-fraction percentage.

## [1.1.3] - 2026-04-20

### Fixed

- Fallback to english when language is not covered by locales file

## [1.1.2] - 2026-04-20

### Added

- French (`frFR`) translation.

## [1.1.1] - 2026-04-20

### Added

- Russian (`ruRU`) translation.

## [1.1.0] - 2026-04-20

### Added

- Non-tank opt-in prompt on Mythic+ start, with a "Never ask" option that persists.

### Changed

- Adaptive mini-map zoom: each pull is framed to its own bounding box, so dungeons with wide pulls (e.g. Magisters' Terrace) no longer render off-screen or feel zoomed out.

### Fixed

- Beacon position now saves on drag-end, so a disconnect or crash mid-session no longer loses a position you just moved it to.

## [1.0.0] - 2026-04-20

Initial release.

### Added

- Scenario-based next-pull tracking (no combat-log dependency).
- Heads-up Beacon with mini-map preview, enemy portraits, and a live forces bar.
- Upcoming-pull preview.
- Per-character or account-wide Beacon position.
- Manual controls: mark complete, skip to pull, revert.
- Auto-start on Mythic+ key start, auto-stop on key end.
- Auto-sync MDT's selected dungeon to the player's zone on start, so auto-start and `/npt start` pick up the right route without switching dungeon manually in MDT. Falls back to the MDT-selected preset when the zone isn't a known dungeon.
- One-shot migration of Next Pull settings from the parent MDT addon.
- Slash commands: `/npt start|stop|skip|complete|status|info`.
- Retail (Midnight / 12.0) support.
