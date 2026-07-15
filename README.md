# finder-view-fix

Force every Finder folder on macOS to the same view: **list, grouped by Kind, sorted by Name**.

macOS has no global setting for grouping — it lives per-folder in the parent's `.DS_Store` (code `GRP0`). This sets the global list/sort defaults and bulk-writes the grouping for every folder in seconds.

Requires [uv](https://docs.astral.sh/uv/) (`brew install uv`).

## Run

```sh
git clone https://github.com/krichelj/finder-view-fix.git
cd finder-view-fix
bash run.sh
```

Rerun anytime (e.g. after creating new folders). Optional full E2E test (flashes Finder windows ~3 min): `bash finder_view_test_suite.sh`
