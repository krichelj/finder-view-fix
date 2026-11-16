#!/bin/bash
# T5 visual E2E for Group-by-Kind (Finder exposes grouping to no API, so look
# at the pixels): two fresh fixture folders with identical contents, one
# stamped GRP0=Kind by bulk_group_stamp.py, one control stamped GRP0=None.
# Finder renders both; Apple Vision OCR reads the window. PASS iff the
# stamped one shows Kind group headers and the control shows none.
# Needs Screen Recording for the calling app.
set -u -o pipefail; cd "$(dirname "$0")/.."
FX=$(mktemp -d "$HOME/.fv_e2e.XXXX"); trap 'rm -rf "$FX"' EXIT
for d in grouped control; do
  mkdir -p "$FX/$d/zsub"; echo x > "$FX/$d/notes.txt"; echo 'print(1)' > "$FX/$d/tool.py"; echo '#!/bin/sh' > "$FX/$d/run.sh"
done
osascript -e 'tell application "Finder" to quit'; sleep 2; mkdir -p tests/shots
printf '%s\n' "$FX/grouped" "$FX/control" > "$FX/list"
uv run --quiet bulk_group_stamp.py "$FX/list" >/dev/null
uv run --quiet --with ds-store python - "$FX" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("b", "bulk_group_stamp.py"); b = importlib.util.module_from_spec(s); s.loader.exec_module(b)
ds = sys.argv[1] + "/.DS_Store"; r = b.read_records(ds)
r[("control", "GRP0")] = ("ustr", "None"); b.write_records(ds, r)
PY
open -a Finder; sleep 2
# Finder renders each fixture; visual_sample.sh captures the window by ID
# and OCRs it (grouped = list header shows a Kind label, not "Name").
G=$(bash tests/visual_sample.sh 0 "$FX/grouped"); C=$(bash tests/visual_sample.sh 0 "$FX/control")
echo "grouped: $G"; echo "control: $C"
cp tests/shots/visual/1.png tests/shots/t5_control.png 2>/dev/null
NG=$(echo "$G" | grep -c '^OK'); NC=$(echo "$C" | grep -c '^OK')
if [ "$NG" -eq 1 ] && [ "$NC" -eq 0 ]; then echo "T5 PASS"; else echo "T5 FAIL"; exit 1; fi
