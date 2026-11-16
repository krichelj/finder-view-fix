#!/bin/bash
# T6 live E2E for the FinderViewEnforcer launchd agent. Exit 1 on any failure.
#  a) agent loaded and running; SIGKILL -> launchd restarts it (KeepAlive)
#  b) control: with the agent stopped, two fixture folders stored as
#     icon view / no grouping, with sort by date set, render NOT list+grouped
#  c) agent started: opening fixture A renders list + grouped + sort by name
#  d) navigation in the same window to fixture B is enforced too
#  e) self-heal: after the windows close, Finder itself has persisted
#     GRP0=Kind and list view for both fixtures in their parent .DS_Store
#  f) a location where Finder never persists grouping (cloud-drive root,
#     if present) renders grouped on every visit
# Needs the agent installed (enforcer/install.sh) with its grants, and
# Screen Recording for the calling app.
set -u -o pipefail; cd "$(dirname "$0")/.."
LABEL="com.krichelj.finderviewenforcer"; DOM="gui/$(id -u)"; PL="$HOME/Library/LaunchAgents/$LABEL.plist"
F=0; pass() { echo "PASS | $*"; }; fail() { echo "FAIL | $*"; F=1; }
pid() { launchctl print "$DOM/$LABEL" 2>/dev/null | awk '/^\tpid =/{print $3}'; }

# a) running + KeepAlive
P1=$(pid); [ -n "$P1" ] && pass "a1 agent running (pid $P1)" || fail "a1 agent not running"
kill -9 "$P1" 2>/dev/null; P2=""
for _ in $(seq 1 20); do sleep 1; P2=$(pid); [ -n "$P2" ] && [ "$P2" != "$P1" ] && break; done
[ -n "$P2" ] && [ "$P2" != "$P1" ] && pass "a2 restarted after SIGKILL (pid $P2)" || fail "a2 not restarted after SIGKILL"

# fixtures with a deliberately wrong stored view, written while Finder is down
X=$(mktemp -d "$HOME/.fv_enf.XXXX"); trap 'rm -rf "$X"' EXIT
for s in A B; do mkdir -p "$X/$s/zsub"; echo n > "$X/$s/n.txt"; echo 'print()' > "$X/$s/t.py"; done
launchctl bootout "$DOM/$LABEL" 2>/dev/null
osascript -e 'tell application "Finder" to quit'; sleep 3
uv run --quiet --with ds-store python - "$X" <<'PY'
# Wrong stored view for A and B: icon view, grouping None.
import sys, importlib.util
s = importlib.util.spec_from_file_location("b", "bulk_group_stamp.py"); b = importlib.util.module_from_spec(s); s.loader.exec_module(b)
r = {}
for n in ("A", "B"):
    r[(n, "GRP0")] = ("ustr", "None"); r[(n, "vstl")] = ("type", b"icnv"); r[(n, "vSrn")] = ("long", 1)
b.write_records(sys.argv[1] + "/.DS_Store", r)
PY
open -a Finder; sleep 3

# b) control, agent stopped. Wrong sort too: Finder keeps a sort set by
# script for the session, so set Date Modified on both and confirm it sticks.
for s in A B; do osascript -e "tell application \"Finder\"
  set w to make new Finder window to (POSIX file \"$X/$s\" as alias)
  set current view of w to list view
  set sort column of list view options of w to modification date column
  set current view of w to icon view
  close w
end tell" >/dev/null; done
SO=$(osascript -e "tell application \"Finder\"
  set w to make new Finder window to (POSIX file \"$X/A\" as alias)
  set s to name of sort column of list view options of w
  close w
  return s as text
end tell")
echo "$SO" | grep -q 'modification date' && pass "b0 control: Finder sorts fixture by date ($SO)" || fail "b0 control: fixture sort not wrong ($SO)"
OUT=$(bash tests/visual_sample.sh 0 "$X/A" "$X/B"); echo "$OUT" | sed 's/^/      /'
[ "$(echo "$OUT" | grep -c '^FAIL')" = 2 ] && pass "b control: fixtures render wrong without the agent" || fail "b control fixtures already uniform (test is vacuous)"

launchctl bootstrap "$DOM" "$PL"; sleep 2
[ -n "$(pid)" ] && pass "c0 agent started" || fail "c0 agent did not start"

# c) open A with the agent running
OUT=$(bash tests/visual_sample.sh 0 "$X/A"); echo "$OUT" | sed 's/^/      /'
echo "$OUT" | grep -q '^OK' && pass "c fixture A enforced on open" || fail "c fixture A not enforced"

# d) navigate the same window to B (up to 2 attempts: the agent only acts
# while Finder is frontmost, so a click into another app can delay it)
for attempt in 1 2; do
  osascript -e "tell application \"Finder\"
    activate
    set w to make new Finder window to (POSIX file \"$X/A\" as alias)
    delay 2
    set target of w to (POSIX file \"$X/B\" as alias)
    activate
  end tell" >/dev/null
  sleep 3
  R=$(osascript -e 'tell application "Finder" to get {current view of front Finder window, name of sort column of list view options of front Finder window, name of front Finder window}')
  WID=$(swift tests/winid.swift B); screencapture -x -o -l "$WID" "tests/shots/visual/nav.png"
  osascript -e 'tell application "Finder" to close every window' >/dev/null
  T=$(swift tests/ocr.swift tests/shots/visual/nav.png)
  if echo "$R" | grep -q 'list view' && echo "$R" | grep -q 'name column' && echo "$T" | grep -q 'Date Modified' && ! echo "$T" | grep -qE '^[^[:alnum:]]*Name[^[:alnum:]]*$'; then
    pass "d navigation to B enforced ($R, attempt $attempt)"; break
  elif [ $attempt = 2 ]; then fail "d navigation not enforced ($R)"; fi
done

# e) Finder persisted grouping + list view itself (it flushes 10-30 s after
# a window closes; poll up to 60 s). Sort set by script is session-only in
# Finder, which is why the agent re-checks it on every visit.
for _ in 1 2 3 4 5 6; do sleep 10; FV_QUIET=1 uv run --quiet --with ds-store python - "$X" <<'PY' && break
import sys
from ds_store import DSStore
d = {}
with DSStore.open(sys.argv[1] + "/.DS_Store") as s:
    for e in s: d[(e.filename, e.code.decode())] = e.value
sys.exit(0 if all(d.get((n, "GRP0")) == "Kind" for n in ("A", "B")) else 1)
PY
done
uv run --quiet --with ds-store python - "$X" <<'PY' && pass "e Finder persisted GRP0=Kind and list view for A and B" || fail "e grouping/view not persisted"
import sys
from ds_store import DSStore
d = {}
with DSStore.open(sys.argv[1] + "/.DS_Store") as s:
    for e in s: d[(e.filename, e.code.decode())] = e.value
bad = [n for n in ("A", "B") if d.get((n, "GRP0")) != "Kind" or bytes(d.get((n, "vstl"), b"Nlsv")) != b"Nlsv"]
print("   records:", {k: v for k, v in d.items() if k[1] in ("GRP0", "vstl")})
sys.exit(1 if bad else 0)
PY

# f) never-persisting cloud root
CR=$(ls -d "$HOME"/Library/CloudStorage/GoogleDrive-*/"My Drive" 2>/dev/null | head -1)
if [ -n "$CR" ]; then
  OUT=$(bash tests/visual_sample.sh 0 "$CR"); echo "$OUT" | sed 's/^/      /'
  echo "$OUT" | grep -q '^OK' && pass "f cloud root grouped" || fail "f cloud root not grouped"
else echo "SKIP | f no Google Drive root"; fi
echo "T6: $([ $F = 0 ] && echo PASS || echo FAIL)"; exit $F
