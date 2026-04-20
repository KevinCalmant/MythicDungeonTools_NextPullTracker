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

## 1.1.0

- Adaptive mini-map zoom: each pull is now framed to its own bounding box, so dungeons with wide pulls (e.g. Magisters' Terrace) no longer render off-screen or feel zoomed-out.
- Non-tank opt-in prompt: on Mythic+ start, non-tank players are asked whether to display the Beacon. Includes a "Never ask" option that persists.
- Beacon position now saves on drag-end, so a disconnect or crash mid-session no longer loses the position you just moved it to.
