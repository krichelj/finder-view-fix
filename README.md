# finder-view-fix

![macOS](https://img.shields.io/badge/platform-macOS-black) ![License: MIT](https://img.shields.io/badge/license-MIT-green) ![uv](https://img.shields.io/badge/deps-uv-purple)

Force **every** Finder folder on your Mac to the same view — **list, grouped by Kind, sorted by Name** — in seconds.

"Use as Defaults" in Finder has never actually done this: per-folder overrides beat it, and grouping has **no global setting at all**. Grouping lives per-folder inside the *parent* folder's `.DS_Store` under entry code `GRP0`. This tool sets the real global defaults, wipes stale per-folder overrides, and bulk-writes `GRP0 = Kind` for thousands of folders at once — no window automation, no clicking.

## Requirements

- macOS (developed and tested on macOS 26)
- [uv](https://docs.astral.sh/uv/) — `brew install uv` (Python deps resolve automatically)

## Run

```sh
git clone https://github.com/krichelj/finder-view-fix.git
cd finder-view-fix
bash run.sh
```

Rerun anytime — it's idempotent (do so after creating many new folders, since macOS offers no grouping default for them).

## What it runs

| Script | Role |
|---|---|
| `run.sh` | One-shot entry point (all of the below, in order) |
| `fix_finder_views.sh` | Global defaults: list view, sort by Name; wipes old per-folder overrides |
| `make_targets.sh` | Builds the folder list (`/tmp/fv_targets.txt`) |
| `bulk_group_stamp.py` | Writes `GRP0 = Kind` into each folder's parent `.DS_Store` |
| `finder_verify_quick.sh` | Windowless verification |
| `finder_view_test_suite.sh` | Optional full E2E suite (flashes Finder windows ~3 min) |

## How it works

- **View style & sort order** are global: `com.apple.finder` → `FXPreferredViewStyle = Nlsv`, `StandardViewSettings…sortColumn = name`. They only apply once per-folder overrides are gone, so stale `.DS_Store` files under `$HOME` are deleted first.
- **Grouping** has no global key (`FXPreferredGroupBy` is written by Finder but never read for folder windows). Finder stores it per-folder in the **parent** directory's `.DS_Store` as an entry keyed by the child folder's name, code `GRP0`. `bulk_group_stamp.py` writes those entries directly with the `ds-store` library — ~5,600 folders in ~2 seconds.

## Caveats

- Wiping `.DS_Store` resets saved window sizes/positions and custom icon layouts (Desktop's own layout is preserved). Folder *contents* are untouched.
- Modified `.DS_Store` files are backed up to `/tmp/dsstore_backups/` per run.
- `.DS_Store` internals are undocumented by Apple; verified on macOS 26. Older versions may store grouping differently.
- Finder must restart briefly (twice) during a run; open windows close and restore.

## License

[MIT](LICENSE)
