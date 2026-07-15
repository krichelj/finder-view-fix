# finder-view-fix

Force every Finder folder on macOS to the same view: **list, grouped by Kind, sorted by Name**.

macOS has no global setting for grouping — it lives per-folder in the parent's `.DS_Store` (code `GRP0`). These scripts set the global list/sort defaults and bulk-write the grouping for every folder.

## Run

```sh
git clone https://github.com/krichelj/finder-view-fix.git
cd finder-view-fix
pip3 install --user --break-system-packages ds-store

bash fix_finder_views.sh      # 1. global defaults + wipe old per-folder overrides
bash make_targets.sh          # 2. build folder list
osascript -e 'tell app "Finder" to quit'; python3 bulk_group_stamp.py /tmp/fv_targets.txt; open -a Finder   # 3. stamp grouping (seconds)
bash finder_verify_quick.sh   # 4. verify (no windows)
```

Optional full E2E test (flashes Finder windows ~3 min): `bash finder_view_test_suite.sh`
