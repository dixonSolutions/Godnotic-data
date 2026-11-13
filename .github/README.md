# Godnotic-data

**The game code and data packs of [Godnotic](https://github.com/dixonSolutions/Godnotic)**, a custom fork of [Xonotic](https://xonotic.org) for Android, Linux, Ubuntu Touch and the browser.

This is a fork of Xonotic's [`xonotic-data.pk3dir`](https://gitlab.com/xonotic/xonotic-data.pk3dir): the QuakeC source of the game, the menu and the HUD (`qcsrc/`), and the configs. On top of upstream it adds Godnotic's touch controls and layouts, the screens its native interfaces draw, and the hooks its Lua mods use. Godnotic's own files are named `touch_*`; everything else is upstream's, changed as little as possible.

Its **releases are the data packs** every Godnotic client downloads on first launch (maps, textures, models, sounds, music):

| Release | What it is |
|---|---|
| `data-<date>` | The full set, as stock Xonotic ships it (about 1 GB) |
| `data-slim` | The phone-sized set: ASTC textures, zstd packs, Opus music (about 390 MB) |

**This repository does not build a game by itself.** To play, to build, or to report a problem, go to [dixonSolutions/Godnotic](https://github.com/dixonSolutions/Godnotic).

## The Godnotic repositories

| Repository | What it is |
|---|---|
| [Godnotic](https://github.com/dixonSolutions/Godnotic) | The game as it ships: packaging, native interfaces, releases, docs, issues. Carries a copy of this repository in `engine/data/xonotic-data.pk3dir` |
| [Godnotic-darkplaces](https://github.com/dixonSolutions/Godnotic-darkplaces) | The engine |
| **Godnotic-data** (this one) | The game code and the data packs |
| [dixonSolutions.github.io](https://github.com/dixonSolutions/dixonSolutions.github.io) | Keeps the update addresses of installs made before the rename working |

Play in the browser: <https://godnotic.vercel.app>

## Changing the game code

Most work is done in the main repository, where the engine, the game code and the packages build together, and is published here from there (`scripts/component-push.sh`). A commit or pull request made here directly is built and tested inside the main repository by this repository's workflow; once on `main` it is imported there, merged and released.

`.github/` belongs to this repository alone and is never copied to or from the main one. The slim packs are built here by `.github/workflows/slim-data.yml`.

## Licence

GPL-3.0-or-later, as Xonotic's game code and data; some files under `qcsrc/` may also be used under the licences named in the COPYING files there.
