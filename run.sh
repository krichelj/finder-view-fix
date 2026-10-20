#!/bin/bash
# run.sh - one shot: every Finder folder becomes list view, grouped by Kind,
# sorted by Name. Idempotent; rerun anytime (e.g. after creating new folders).
set -e
cd "$(dirname "$0")"

echo "==[1/4] Global defaults (list view, sort by Name) + wipe old overrides"
bash fix_finder_views.sh

echo "==[2/4] Building folder list"
bash make_targets.sh

echo "==[3/4] Stamping Group-by-Kind (windowless, seconds)"
osascript -e 'tell application "Finder" to quit' 2>/dev/null || true
sleep 2
uv run bulk_group_stamp.py /tmp/fv_targets.txt
open -a Finder

echo "==[4/4] Verifying"
bash finder_verify_quick.sh
