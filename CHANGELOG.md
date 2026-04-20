# Changelog

## 1.0.0

Initial release.

- Scenario-based next-pull tracking (no combat log dependency)
- Heads-up Beacon with mini-map preview, enemy portraits, and live forces bar
- Upcoming-pull preview
- Per-character or account-wide Beacon position
- Manual controls: mark complete, skip to pull, revert
- Auto-start on Mythic+ key start, auto-stop on key end
- One-shot migration of Next Pull settings from the parent MDT addon
- Slash commands: `/npt start|stop|skip|complete|status|info`
- Retail (Midnight / 12.0) support
- Auto-sync MDT's selected dungeon to the player's current zone on `Start`, so auto-start (and manual `/npt start`) picks up the right route without manually switching dungeon in MDT. Falls back to the MDT-selected preset when the zone isn't a known dungeon.
