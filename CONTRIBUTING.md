# Contributing

Thanks for taking the time to contribute! This is a small, solo-maintained addon, so the process is light. These notes should cover the common cases.

## Reporting bugs & requesting features

Open a [GitHub issue](https://github.com/Kanegasi/MythicDungeonTools_NextPullHelper/issues). For bugs, please include:

- WoW version (Retail / Midnight) and addon version.
- The name of the dungeon and whether you were in a Mythic+ key.
- A short description of what you expected vs. what happened.
- Output of `/npt info` if tracking was active.
- Any Lua errors (screenshot or copy-paste from BugSack / default error UI).

## Translating the addon

All user-facing strings live in [`Locales/`](Locales/). Each language is a single Lua file that sets keys on `MDT_NPT.L`. Adding a translation takes three steps:

1. Copy [`Locales/enUS.lua`](Locales/enUS.lua) to `Locales/<locale>.lua` (e.g. `deDE.lua`, `frFR.lua`, `zhCN.lua`). The locale code must match WoW's client locale codes.
2. Translate the right-hand string of each line. Keep the left-hand key in English — it's the lookup ID, never shown to users.
3. Register the new file in [`locales.xml`](locales.xml) by adding a `<Script file="Locales/<locale>.lua"/>` entry.

You don't need to translate every string. Missing keys fall back to English automatically.

If you're adding an entirely new string to the code, add it to `enUS.lua` first — that's the source of truth — then translate it in any other locale files you can.

## Code contributions

### Development setup

1. Fork and clone the repo.
2. Symlink (or copy) the folder into your WoW `Interface/AddOns/` directory as `MythicDungeonTools_NextPullTracker` so the game loads it.
3. `/reload` in-game to pick up changes.

### Tests

Unit tests run outside WoW via [busted](https://lunarmodules.github.io/busted/). Tests live in [`spec/`](spec/):

```bash
busted
```

WoW API calls are mocked in [`spec/helpers/wow_mocks.lua`](spec/helpers/wow_mocks.lua). If your change touches a WoW API we don't mock yet, add it there.

An in-game integration test lives in [`Developer/Tests/`](Developer/Tests/) — the `Developer/` folder is excluded from releases (see [`.pkgmeta`](.pkgmeta)).

### Commit messages

The project uses [Conventional Commits](https://www.conventionalcommits.org/). Use one of:

- `feat:` — new user-visible functionality.
- `fix:` — bug fix.
- `chore:` / `docs:` / `test:` / `refactor:` — everything else.

Examples:

```
feat: add sound cue on pull advance
fix: beacon position lost after disconnect
docs: clarify /npt skip behavior in README
```

### Pull requests

- Keep PRs focused. One change per PR is easier to review.
- For non-trivial changes, open an issue first so we can agree on the approach before you spend time.
- Update [`CHANGELOG.md`](CHANGELOG.md) under the appropriate version (Added / Changed / Fixed). The format follows [Keep a Changelog](https://keepachangelog.com/).
- Make sure `busted` passes.

### Versioning

We follow [SemVer](https://semver.org/):

- Bug fixes, translations, docs → patch (`1.1.x`).
- New user-visible features → minor (`1.x.0`).
- Breaking changes (e.g. saved-variable layout overhaul) → major (`x.0.0`).

## Licensing

This project is licensed under the terms of [`LICENSE`](LICENSE). By submitting a contribution you agree to license it under the same terms.
