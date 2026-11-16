# finder-view-fix

![macOS](https://img.shields.io/badge/platform-macOS-black) ![License: MIT](https://img.shields.io/badge/license-MIT-green) ![uv](https://img.shields.io/badge/deps-uv-purple)

Force **every** Finder folder on your Mac to the same view - **list, grouped by Kind, sorted by Name** - in seconds.

"Use as Defaults" in Finder has never actually done this: per-folder overrides beat it, and grouping has **no global setting at all**. Grouping lives per-folder inside the *parent* folder's `.DS_Store` under entry code `GRP0`. This tool sets the real global defaults, wipes stale per-folder overrides, and bulk-writes `GRP0 = Kind` for thousands of folders at once - no window automation, no clicking.

## Requirements

- macOS (developed on macOS 26, verified on macOS 27)
- [uv](https://docs.astral.sh/uv/) - `brew install uv` (Python deps resolve automatically)

## Run

```sh
git clone https://github.com/krichelj/finder-view-fix.git
cd finder-view-fix
bash run.sh
```

Rerun anytime - it's idempotent (do so after creating many new folders, since macOS offers no grouping default for them).

## Keep it enforced: FinderViewEnforcer

A one-off stamp drifts. Finder caches every `.DS_Store` it has read and writes its cached copy back when windows close, so changes made while it runs are overwritten; new folders start with no settings; and some locations (Google Drive / cloud-drive roots) never persist grouping at all. The enforcer fixes what you see, when you see it:

```sh
bash enforcer/install.sh     # build, sign (ad hoc) and load the launchd agent
bash enforcer/uninstall.sh   # remove it
```

- `FinderViewEnforcer.app` (`~/Applications`, no Dock icon) runs as launchd agent `com.krichelj.finderviewenforcer`: started at login, restarted if it exits.
- Once a second, while Finder is frontmost, it checks the front window. On every new window or navigation it sets list view and sort by Name (Finder scripting) and Use Groups + Group By Kind (View menu via Accessibility, because grouping has no scripting API). Every step is verified and retried until it holds.
- For writable folders Finder then saves the grouping itself, so the `.DS_Store` files heal as you browse. Locations Finder never saves (cloud-drive roots) get it applied again on every visit.
- The logic is `enforcer/tick.applescript`, compiled to `~/Library/Application Support/FinderViewEnforcer/tick.scpt` and loaded by the app. `bash enforcer/install.sh --logic-only` updates it without touching the signed app, so macOS keeps its grants.
- One-time grants (macOS will not let a script grant these): System Settings > Privacy & Security > Accessibility > FinderViewEnforcer ON, and Allow when asked to control Finder / System Events. A full reinstall changes the ad-hoc signature, so remove the old Accessibility entry and add the app again.
- Log: `~/Library/Logs/FinderViewEnforcer.log` (one line per folder it changed, plus errors).

## What it runs

| Script | Role |
|---|---|
| `run.sh` | One-shot entry point (all of the below, in order) |
| `fix_finder_views.sh` | Global defaults: list view, sort by Name; wipes old per-folder overrides |
| `make_targets.sh` | Builds the folder list (`/tmp/fv_targets.txt`): every visible folder under `$HOME` except `~/Library`, plus `~/Library/CloudStorage/*`, iCloud Drive and `/Applications` (override with `FV_EXTRA_ROOTS`) |
| `bulk_group_stamp.py` | Writes `GRP0 = Kind`, `vstl = Nlsv` and list-view `sortColumn = name` into each folder's parent `.DS_Store`, or into the folder's own `.` record when the parent is not writable (as Finder does for `/Applications`) |
| `finder_verify_quick.sh` | Windowless verification |
| `enforcer/` | FinderViewEnforcer launchd agent (see above) |
| `tests/run_tests.sh` | Formal tests T1-T7 (see Tests) |
| `finder_view_test_suite.sh` | Optional full E2E suite (flashes Finder windows ~3 min) |

## How it works

- **View style & sort order** are global: `com.apple.finder` → `FXPreferredViewStyle = Nlsv`, `StandardViewSettings…sortColumn = name`. They only apply once per-folder overrides are gone, so stale `.DS_Store` files under `$HOME` are deleted first.
- **Grouping** has no global key (`FXPreferredGroupBy` is written by Finder but never read for folder windows). Finder stores it per-folder in the **parent** directory's `.DS_Store` as an entry keyed by the child folder's name, code `GRP0`. `bulk_group_stamp.py` writes those entries directly with the `ds-store` library - ~5,600 folders in ~2 seconds.

- **Per-folder sort overrides.** Finder saves a sort column per folder in `lsvp`/`lsvC` (e.g. Downloads defaults to Date Added), which beats the global sort. The stamper rewrites existing ones to `name` and pre-seeds `lsvC` where none exists.
- **Own B-tree writer.** `ds-store` 1.3.x corrupts files as soon as a B-tree node splits (incremental inserts raise `IndexError`/`BuddyError`, and its `initial_entries` bulk builder fails on multi-level trees). The stamper reads all records and rebuilds each `.DS_Store` bottom-up, using the library only for its allocator and record encoding.

## Tests

```sh
bash tests/run_tests.sh        # N=40 bash tests/run_tests.sh for a bigger live sample
```

| Test | What it proves |
|---|---|
| T1 `test_dsstore_btree.py` | Writer property test: 40 random trees (up to ~12k records, sorted/reversed/shuffled), written twice, read back by the stock library in a separate process and compared to an oracle, including B-tree key lookups |
| T2 `audit_views.py` | Walks every folder under `$HOME`, the cloud drives, iCloud Drive and `/Applications` independently of the target list: `GRP0 = Kind`, list view, sort = name |
| T3 `test_finder_e2e.applescript` | Finder itself reports list view + Name sort for N random folders |
| T4 re-audit | After Finder opened/closed those windows and rewrote their `.DS_Store`, the settings survived (Finder parsed the files) |
| T5 `test_grouping_visual.sh` | Visual: a stamped fixture folder renders Kind group headers and an identical control (`GRP0 = None`) renders none, read via Apple Vision OCR (`ocr.swift`) |
| T6 `test_enforcer_e2e.sh` | Enforcer agent: running, restarted after SIGKILL; control fixtures (icon view, no grouping, date sort) render wrong with the agent stopped; with it running they render list + grouped + Name on open and on navigation; Finder then saves GRP0=Kind and list view itself; a cloud-drive root renders grouped |
| T7 `visual_sample.sh` | What Finder actually renders (window captured by ID, OCR) for every sidebar location (home, Desktop, Documents, Downloads, Applications, /Users, /Volumes, iCloud Drive, each cloud drive) and N random folders |

T3/T5/T6/T7 drive Finder and need Screen Recording for the calling app. The agent acts only while Finder is frontmost, so a visual check that catches another app in front is re-checked once before it counts. T5 pauses the agent (it would group the control folder too).

### Independent edge-case suite

```sh
bash tests/independent/run.sh                 # pytest -n auto (one process per core)
uv run python tests/independent/scan_real.py  # validate every real .DS_Store under $HOME
```

Validates output with its own `.DS_Store` parser (`dsparse.py`, no shared code with `ds-store` or the tool) that checks B-tree structure: page bounds, uniform leaf depth, record/node counts, Finder key order. Covers 0 to 6000 records, sorted/reversed/shuffled inserts, exact node-capacity boundaries, 255-char Unicode/emoji names, case-only collisions, `.` home record, foreign record preservation, malformed plists, byte-identical idempotence, missing/file/read-only/corrupt targets, backups, `make_targets.sh` exclusions and odd names (quotes, leading dashes, newlines, symlinks), audit defect detection, and parallel runs in threads and processes, including 8 processes writing one `.DS_Store` while a thread parses it. `BGS_PATH=<file>` runs the suite against another version of the stamper.

## Caveats

- Wiping `.DS_Store` resets saved window sizes/positions and custom icon layouts (Desktop's own layout is preserved). Folder *contents* are untouched.
- Modified `.DS_Store` files are backed up to `/tmp/dsstore_backups/` per run.
- `.DS_Store` internals are undocumented by Apple; verified on macOS 26. Older versions may store grouping differently.
- Finder must restart briefly (twice) during a run; open windows close and restore. Stamping while Finder runs does not work: Finder overwrites the files from its cache.
- Grouping changes made by the enforcer use the real View menu; if you turn grouping off by hand it stays off until you leave that folder and come back.

## License

[MIT](LICENSE)
