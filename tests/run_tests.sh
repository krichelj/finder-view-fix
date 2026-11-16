#!/bin/bash
# Independent test battery. Exit != 0 on any failure.
#  T1 property test of the .DS_Store writer (40 random trees, oracle compare)
#  T2 full-$HOME audit with the stock reader (does not use fv_targets.txt)
#  T3 live Finder E2E on N random folders (view + sort as Finder reports them)
#  T4 re-audit after Finder opened/closed those windows and rewrote their
#     .DS_Store: proves Finder parsed our files and kept GRP0=Kind
#  T5 visual: Finder renders Kind group headers (OCR), control folder does not
#  T6 maintenance job: installed, idle gate, new folder ungrouped -> grouped
#     by one run, survives Finder restart, second run is a no-op
#  T7 visual: what Finder renders for every sidebar location Finder can save a
#     view for, and N random folders
set -u -o pipefail; cd "$(dirname "$0")/.."; N="${N:-25}"; F=0
# (outputs captured first: piping into head under pipefail can SIGPIPE the producer)
echo "== T1 writer property test"; O=$(uv run --quiet tests/test_dsstore_btree.py) || F=1; echo "$O" | tail -1
echo "== T2 full audit";           O=$(uv run --quiet tests/audit_views.py) || F=1; echo "$O" | head -5
SAMPLE=$(find "$HOME" \( -path "$HOME/Library" -o -name '.*' -o -name '*.app' -o -name '*.bundle' -o -name '*.framework' -o -name '*.photoslibrary' -o -name '*.pkg' -o -name '*.xcodeproj' -o -name '*.lproj' -o -name '*.xcassets' -o -name '*.plugin' -o -name '*.kext' -o -name node_modules \) -prune -o -type d -print 2>/dev/null | sort -R | head -"$N")
echo "== T3 live Finder ($N random folders)"
IFS=$'\n'; R=$(osascript tests/test_finder_e2e.applescript $SAMPLE); unset IFS
echo "$R" | tail -4; echo "$R" | grep -q 'FAILS: 0' || F=1
echo "== T4 post-Finder re-audit of the sampled folders"
sleep 2; O=$(echo "$SAMPLE" | tr '\n' '\0' | xargs -0 uv run --quiet tests/audit_views.py --only) || F=1; echo "$O" | head -5
echo "== T5 visual grouping (OCR)"; bash tests/test_grouping_visual.sh || F=1
echo "== T6 maintenance job E2E"; bash tests/test_maintain_e2e.sh || F=1
echo "== T7 visual: random folders + every sidebar location"
# Not included, because macOS gives Finder nowhere to save their view: / (sealed
# system volume), /Volumes, /Users, and the top folders of a cloud drive whose
# account folder is read-only (see README, Limits).
SIDEBAR=("$HOME" "$HOME/Desktop" "$HOME/Documents" "$HOME/Downloads" /Applications "$HOME/Library/Mobile Documents/com~apple~CloudDocs")
for r in "$HOME"/Library/CloudStorage/*/; do
  SIDEBAR+=("${r%/}")
  [ -w "$r" ] && for c in "$r"*/; do SIDEBAR+=("${c%/}"); done
done
bash tests/visual_sample.sh 0 "${SIDEBAR[@]}" || F=1
bash tests/visual_sample.sh "${N}" || F=1
echo "OVERALL: $([ $F = 0 ] && echo PASS || echo FAIL)"; exit $F
