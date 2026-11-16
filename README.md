# finder-view-fix

![macOS](https://img.shields.io/badge/platform-macOS-black) ![License: MIT](https://img.shields.io/badge/license-MIT-green) ![uv](https://img.shields.io/badge/deps-uv-purple)

Every Finder folder on your Mac in **List view, grouped by Kind, sorted by Name**, set up once and kept that way with no further action.

## Install (once)

```sh
git clone https://github.com/krichelj/finder-view-fix.git
cd finder-view-fix
bash setup.sh
```

macOS asks once to give **FinderViewFix** Full Disk Access (System Settings > Privacy & Security > Full Disk Access > + > `~/Library/Application Support/finder-view-fix/FinderViewFix.app`). Without it a background job cannot list Documents, Desktop, Downloads or iCloud Drive. After that nothing needs attention. The repo can be deleted or moved; the job runs from its own copy.

Uninstall: `bash setup.sh --uninstall`.

Requirements: macOS 26 or 27, [uv](https://docs.astral.sh/uv/), Xcode Command Line Tools (`swiftc`).

## How it works

Measured on macOS 27.2.1:

- **List view and sort by Name are global defaults.** Finder applies them to every folder that has no saved view of its own. `setup.sh` sets them once: `FXPreferredViewStyle = Nlsv` and `StandardViewSettings` list `sortColumn = name`.
- **Grouping has no global default.** None of `FXPreferredGroupBy`, `FXArrangeGroupViewBy`, `FK_ArrangeBy`, `StandardViewSettings.GroupBy`, `FK_StandardViewSettings.GroupBy`, `FXGroupViewBy`, or View Options > "Use as Defaults" groups a new folder. Finder saves grouping per folder only, as record `GRP0` in the **parent** folder's `.DS_Store`, or in the folder's own `.` record when the parent is read-only (e.g. `/Applications`).
- **Finder caches `.DS_Store` files** and writes its cached copy back when windows close. Records written while Finder holds the parent in memory are lost.

So the only per-folder work is writing `GRP0 = Kind` for folders that do not have it yet (new folders), plus correcting a saved view or sort that is not list / Name. That is the job:

- `maintain.sh` runs hourly via launchd (`com.krichelj.finder-view-fix`). It does nothing unless you have been idle 15 minutes and every folder is not already compliant.
- When there is work, it pauses Finder (`SIGSTOP`, so Finder can neither read nor write its cache), writes the missing records, then `SIGKILL`s Finder. launchd relaunches Finder, which reads the new files and restores its windows.
- It uses no Apple events and no Accessibility, so it shows no prompts. A run that finds nothing to change never touches Finder.
- Log: `~/Library/Logs/finder-view-fix.log`.

| File | Role |
|---|---|
| `setup.sh` | One-time install: global defaults, job, Full Disk Access check, first run |
| `maintain.sh` | The hourly job (idle gate, `--check`, pause, stamp, restart Finder) |
| `make_targets.sh` | Folder list: everything visible under `$HOME` except `~/Library`, plus `~/Library/CloudStorage/*`, iCloud Drive, `/Applications` (`FV_EXTRA_ROOTS` / `FV_TARGETS` to override) |
| `bulk_group_stamp.py` | Writes `GRP0 = Kind` (and fixes a saved non-list view / non-Name sort); stores that already comply are not rewritten; `--check` only counts |
| `launcher.swift` | The job's executable (`FinderViewFix.app`), the thing Full Disk Access is granted to |

**Why not a global default plus deleting `.DS_Store` files:** grouping has no global default, so deleting records only ungroups folders. The old wipe step (`find ~ -name .DS_Store -delete`) was removed: it also destroyed icon layouts and your own per-folder choices, and reached into synced cloud folders.

**Why not a UI enforcer:** an earlier version clicked View > Group By > Kind through Accessibility whenever a folder was shown. It only worked while Finder was frontmost, polled every second, overrode manual choices, lost its permission on every rebuild, and ran a script from a user-writable folder with that permission. It was removed.

**The `.DS_Store` writer:** `ds-store` 1.3.x corrupts files when a B-tree node splits, so the stamper reads all records and rebuilds each file bottom-up. It uses the library only for its allocator and record encoding, sorts with an explicit case-insensitive total order, and writes through a unique temp file plus `os.replace`.

## Limits

macOS gives Finder nowhere to save a view for these folders, so no tool can make it permanent:

- `/` (Macintosh HD): sealed, read-only system volume, even for root.
- `/Volumes`: protected.
- `/Users`: Finder ignores its own `.` record there.
- The top folders (`My Drive`, `Other computers`) of a cloud drive whose account folder in `~/Library/CloudStorage` is read-only: Finder ignores their own `.` record. Everything inside them is fixed.

Other limits:

- A folder created now is grouped at the next idle hour, not instantly.
- Folders you cannot write to, and whose parent you cannot write to, are skipped.
- `.DS_Store` internals are undocumented by Apple. The tests below check what Finder actually renders.

## Tests

```sh
bash tests/run_tests.sh              # N=40 bash tests/run_tests.sh for a bigger live sample
bash tests/independent/run.sh        # edge-case suite, parallel
```

| Test | What it proves |
|---|---|
| T1 `test_dsstore_btree.py` | Writer property test: 40 random trees (up to ~12k records, sorted/reversed/shuffled), written twice, read back by the stock library in a separate process and compared to an oracle, including B-tree key lookups |
| T2 `audit_views.py` | Walks every folder the job covers, independently of its target list: `GRP0 = Kind`, no saved non-list view, no saved non-Name sort |
| T3 `test_finder_e2e.applescript` | Finder itself reports list view + Name sort for N random folders |
| T4 re-audit | After Finder opened/closed those windows and rewrote their `.DS_Store`, the settings survived |
| T5 `test_grouping_visual.sh` | Visual: a stamped fixture renders Kind groups, an identical control (`GRP0 = None`) does not (window captured by ID, Apple Vision OCR) |
| T6 `test_maintain_e2e.sh` | The job: loaded hourly, global defaults set; idle gate leaves everything alone while you are active; a new folder in a parent Finder has cached renders ungrouped (control), one job run groups it, the record and the rendering survive window close and Finder restart, and a second run is a no-op that does not touch Finder |
| T7 `visual_sample.sh` | What Finder renders for every sidebar location it can save a view for, and N random folders |

T3/T5/T6/T7 drive Finder and need Screen Recording for the calling app. A visual check that catches another app in front is re-checked once before it counts.

### Independent edge-case suite

```sh
bash tests/independent/run.sh                 # pytest -n auto (one process per core)
uv run python tests/independent/scan_real.py  # validate every real .DS_Store under $HOME
```

Validates output with its own `.DS_Store` parser (`dsparse.py`, no shared code with `ds-store` or the tool) that checks B-tree structure: page bounds, uniform leaf depth, record/node counts, Finder key order. Covers 0 to 6000 records, sorted/reversed/shuffled inserts, exact node-capacity boundaries, 255-char Unicode/emoji names, case-only collisions, `.` home record, foreign record preservation, malformed plists, byte-identical idempotence, compliant stores never rewritten, `--check` mode, missing/file/read-only/corrupt targets, backups of unreadable stores, `make_targets.sh` extra roots, exclusions and odd names (quotes, leading dashes, newlines, symlinks), audit defect detection, and parallel runs in threads and processes, including 8 processes writing one `.DS_Store` while a thread parses it. `BGS_PATH=<file>` runs the suite against another version of the stamper.

## License

[MIT](LICENSE)
