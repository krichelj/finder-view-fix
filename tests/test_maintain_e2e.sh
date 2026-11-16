#!/bin/bash
# T6 live E2E for the maintenance job (setup.sh must have been run).
#  a) job installed in launchd with an hourly interval; global defaults set
#  b) idle gate: with FV_IDLE_MIN huge and no FV_FORCE, a pending new folder
#     is left alone and Finder is not touched
#  c) a new folder created while Finder shows (and caches) its parent renders
#     UNgrouped (control)
#  d) one forced job run (through launchd, as the hourly run would) groups it:
#     record written, Finder renders it list + grouped + Name
#  e) the record survives Finder closing windows and a Finder restart
#     (Finder did not write its stale cached copy back)
#  f) a second run finds nothing to change and does not restart Finder
set -u -o pipefail; cd "$(dirname "$0")/.."
LABEL="com.krichelj.finder-view-fix"; DOM="gui/$(id -u)"
SUP="$HOME/Library/Application Support/finder-view-fix"; STATUS="$SUP/last-run.txt"
F=0; pass() { echo "PASS | $*"; }; fail() { echo "FAIL | $*"; F=1; }
run_job() {  # $@: env assignments for this run
  rm -f "$STATUS"; for kv in "$@"; do launchctl setenv "${kv%%=*}" "${kv#*=}"; done
  launchctl kickstart -k "$DOM/$LABEL"
  sleep 2
  for _ in $(seq 1 150); do launchctl print "$DOM/$LABEL" | grep -q 'state = running' || break; sleep 1; done
  for kv in "$@"; do launchctl unsetenv "${kv%%=*}"; done
}
grp0() {  # $1 folder -> its GRP0 value in the parent store
  "$SUP/venv/bin/python" - "$1" <<'PY'
import sys, os
from ds_store import DSStore
p = sys.argv[1].rstrip("/"); ds = os.path.join(os.path.dirname(p), ".DS_Store")
v = None
if os.path.exists(ds):
    with DSStore.open(ds) as d:
        for e in d:
            if e.filename == os.path.basename(p) and e.code == b"GRP0": v = e.value
print(v)
PY
}

# a)
launchctl print "$DOM/$LABEL" 2>/dev/null | grep -q 'run interval = 3600' && pass "a1 job loaded, hourly" || fail "a1 job not loaded hourly"
[ "$(defaults read com.apple.finder FXPreferredViewStyle)" = Nlsv ] && pass "a2 global list view" || fail "a2 global view not list"
SC=$(defaults export com.apple.finder - | plutil -extract StandardViewSettings.ExtendedListViewSettingsV2.sortColumn raw -o - - 2>/dev/null)
[ "$SC" = name ] && pass "a3 global sort = name" || fail "a3 global sort = $SC"

# fixture: visible folder under $HOME so make_targets finds it
X=$(mktemp -d "$HOME/fvjob-test.XXXX"); trap 'rm -rf "$X"' EXIT
osascript -e "tell application \"Finder\" to open (POSIX file \"$X\" as alias)" >/dev/null; sleep 2   # Finder caches $X
mkdir -p "$X/new/zsub"; echo n > "$X/new/n.txt"; echo 'print()' > "$X/new/t.py"

# b) idle gate
P0=$(pgrep -x Finder); run_job FV_IDLE_MIN=100000
[ ! -s "$STATUS" ] && [ "$(grp0 "$X/new")" = None ] && [ "$(pgrep -x Finder)" = "$P0" ] \
  && pass "b idle gate: job did nothing while you are active" || fail "b idle gate did not hold"

# c) control
OUT=$(bash tests/visual_sample.sh 0 "$X/new"); echo "$OUT" | sed 's/^/      /'
echo "$OUT" | grep -q '^FAIL' && pass "c control: new folder renders ungrouped" || fail "c control: new folder already grouped (vacuous)"

# d) forced run
P1=$(pgrep -x Finder); run_job FV_FORCE=1; cat "$STATUS" | sed 's/^/      /'
[ "$(grp0 "$X/new")" = Kind ] && pass "d1 record GRP0=Kind written" || fail "d1 record not written"
[ "$(pgrep -x Finder)" != "$P1" ] && pass "d2 Finder was restarted (stale cache dropped)" || fail "d2 Finder not restarted"
sleep 3
OUT=$(bash tests/visual_sample.sh 0 "$X/new"); echo "$OUT" | sed 's/^/      /'
echo "$OUT" | grep -q '^OK' && pass "d3 Finder renders it list + grouped" || fail "d3 not rendered grouped"
SO=$(osascript -e "tell application \"Finder\"
  set w to make new Finder window to (POSIX file \"$X/new\" as alias)
  set s to name of sort column of list view options of w
  close w
  return s as text
end tell")
[ "$SO" = "name column" ] && pass "d4 sorted by Name" || fail "d4 sort = $SO"

# e) survives window close + Finder restart
osascript -e 'tell application "Finder" to close every window' >/dev/null; sleep 20
osascript -e 'tell application "Finder" to quit' >/dev/null; sleep 3; open -a Finder; sleep 3
[ "$(grp0 "$X/new")" = Kind ] && pass "e1 record kept after close + restart" || fail "e1 record lost"
OUT=$(bash tests/visual_sample.sh 0 "$X/new"); echo "$OUT" | sed 's/^/      /'
echo "$OUT" | grep -q '^OK' && pass "e2 still rendered grouped after restart" || fail "e2 not grouped after restart"

# f) idempotent
P2=$(pgrep -x Finder); run_job FV_FORCE=1
grep -q 'nothing to change' "$STATUS" && [ "$(pgrep -x Finder)" = "$P2" ] && pass "f second run: nothing to change, Finder untouched" || fail "f second run changed something: $(cat "$STATUS")"
echo "T6: $([ $F = 0 ] && echo PASS || echo FAIL)"; exit $F
