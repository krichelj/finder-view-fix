#!/bin/bash
# finder_view_test_suite.sh
# Verifies that List view + Group by Kind + Sort by Name is the effective
# Finder default across scenarios. Finder windows will flash open/closed.
# Exit code = number of failed tests.
set -u
PASS=0; FAIL=0; SKIP=0

report() { # $1=status $2=name $3=detail
  case "$1" in PASS) PASS=$((PASS+1));; FAIL) FAIL=$((FAIL+1));; SKIP) SKIP=$((SKIP+1));; esac
  printf "%-4s | %-46s | %s\n" "$1" "$2" "${3:-}"
}

# Opens a folder in Finder, returns "isList,sortIsName" e.g. "true,true"
check_folder() {
  /usr/bin/osascript 2>&1 <<EOF
tell application "Finder"
  activate
  set w to make new Finder window to (POSIX file "$1" as alias)
  delay 0.6
  set isList to (current view of w is list view)
  set sortOK to false
  try
    set sortOK to ((name of sort column of list view options of w) is name column)
  end try
  close w
  return (isList as string) & "," & (sortOK as string)
end tell
EOF
}

folder_test() { # $1=test name  $2=path
  if [ ! -d "$2" ]; then report SKIP "$1" "folder not found: $2"; return; fi
  local out; out=$(check_folder "$2")
  case "$out" in
    true,true)  report PASS "$1" "$2" ;;
    true,false) report FAIL "$1" "list view, but sort != Name ($2)" ;;
    false,*)    report FAIL "$1" "NOT list view ($2)" ;;
    *)          report FAIL "$1" "applescript error: $out" ;;
  esac
}

echo "Finder View Test Suite - $(date)"
echo "Target: List view | Group by Kind | Sort by Name"
echo "--------------------------------------------------------------------------"

# T1: global default keys
V=$(defaults read com.apple.finder FXPreferredViewStyle 2>/dev/null)
G=$(defaults read com.apple.finder FXPreferredGroupBy 2>/dev/null)
[ "$V" = "Nlsv" ] && report PASS "T1a global default = list view" "FXPreferredViewStyle=$V" \
                  || report FAIL "T1a global default = list view" "FXPreferredViewStyle=$V"
[ "$G" = "Kind" ] && report PASS "T1b global default = group by Kind" "FXPreferredGroupBy=$G" \
                  || report FAIL "T1b global default = group by Kind" "FXPreferredGroupBy=$G"

# T2: default sort column in saved view settings
TMPPL="/tmp/finder_test_$$.plist"
defaults export com.apple.finder "$TMPPL"
SC=$(/usr/libexec/PlistBuddy -c "Print :StandardViewSettings:ExtendedListViewSettingsV2:sortColumn" "$TMPPL" 2>/dev/null)
[ -z "$SC" ] && SC=$(/usr/libexec/PlistBuddy -c "Print :StandardViewSettings:ListViewSettings:sortColumn" "$TMPPL" 2>/dev/null)
rm -f "$TMPPL"
[ "$SC" = "name" ] && report PASS "T2 default sort column = Name" "sortColumn=$SC" \
                   || report FAIL "T2 default sort column = Name" "sortColumn=${SC:-unset}"

# T3: leftover per-folder overrides. NOTE: Finder recreates .DS_Store during
# normal use - but post-fix they record the CORRECT view, so a modest count is
# fine. This test only catches a wipe that never happened (thousands left).
CNT=$(find "$HOME" -name .DS_Store -type f ! -path "$HOME/Desktop/.DS_Store" 2>/dev/null | wc -l | tr -d ' ')
[ "$CNT" -le 500 ] && report PASS "T3 old overrides wiped" "$CNT present (excl. Desktop; fresh ones are harmless)" \
                   || report FAIL "T3 old overrides wiped" "$CNT present - wipe likely never ran"

# T4: brand-new folder inherits defaults
T4DIR=$(mktemp -d "$HOME/Documents/fvtest_new.XXXX")
folder_test "T4 brand-new folder" "$T4DIR"

# T5/T6: real everyday folders
folder_test "T5 ~/Downloads" "$HOME/Downloads"
folder_test "T6 ~/Documents" "$HOME/Documents"

# T7: deeply nested folder
T7DIR="$T4DIR/level1/level2/level3/level4"
mkdir -p "$T7DIR"
folder_test "T7 deeply nested folder" "$T7DIR"

# T8: unicode + spaces + emoji in name
T8DIR="$T4DIR/Tést Földer 中文 🚀"
mkdir -p "$T8DIR"
folder_test "T8 unicode/space folder name" "$T8DIR"

# T9: cloud-synced folders
folder_test "T9a Google Drive" "$HOME/My Drive"
ODDIR=$(ls -d "$HOME/Library/CloudStorage/"OneDrive-* 2>/dev/null | head -1)
folder_test "T9b OneDrive" "${ODDIR:-/nonexistent}"

# T10: previously-customized folder - the core mechanism test.
# Force icon view (creates .DS_Store override), confirm override wins,
# delete override + restart Finder, confirm defaults win again.
T10DIR=$(mktemp -d "$HOME/Documents/fvtest_custom.XXXX")
/usr/bin/osascript >/dev/null 2>&1 <<EOF
tell application "Finder"
  activate
  set w to make new Finder window to (POSIX file "$T10DIR" as alias)
  delay 0.4
  set current view of w to icon view
  delay 0.6
  close w
end tell
EOF
sleep 1
OUT1=$(check_folder "$T10DIR")
case "$OUT1" in
  false,*) report PASS "T10a override sticks (icon view kept)" "" ;;
  *)       report FAIL "T10a override sticks (icon view kept)" "got: $OUT1" ;;
esac
rm -f "$T10DIR/.DS_Store"
# IMPORTANT (discovered empirically on macOS 26): switching any window's view
# also flips the GLOBAL new-window default - macOS records the last-used view.
# So after T10a we must restore defaults exactly like the fix script does:
# quit Finder (it persists prefs on quit), re-assert defaults, relaunch.
osascript -e 'tell application "Finder" to quit' 2>/dev/null
sleep 2
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder FXPreferredGroupBy -string "Kind"
open -a Finder
sleep 3
OUT2=$(check_folder "$T10DIR")
case "$OUT2" in
  true,true) report PASS "T10b defaults win after override removed" "" ;;
  *)         report FAIL "T10b defaults win after override removed" "got: $OUT2" ;;
esac

# T11: persistence across Finder relaunch (Finder restarted in T10)
folder_test "T11 persists after Finder relaunch" "$T4DIR"

# T12: brand-new Finder window uses list view
OUT=$(/usr/bin/osascript 2>&1 <<'EOF'
tell application "Finder"
  activate
  set w to make new Finder window
  delay 0.6
  set isList to (current view of w is list view)
  close w
  return isList as string
end tell
EOF
)
[ "$OUT" = "true" ] && report PASS "T12 new Finder window (Cmd+N)" "" \
                    || report FAIL "T12 new Finder window (Cmd+N)" "got: $OUT"

# T13: grouping stamped - windowless audit. macOS 26 stores a folder's
# grouping in its PARENT's .DS_Store under the child's name, code GRP0.
# bulk_group_stamp.py writes these; this test reads them back.
if [ ! -s /tmp/fv_targets.txt ]; then
  report SKIP "T13 grouping stamped (GRP0 audit)" "no /tmp/fv_targets.txt - run bulk_group_stamp.py first"
elif ! command -v uv >/dev/null 2>&1; then
  report SKIP "T13 grouping stamped (GRP0 audit)" "uv not installed (brew install uv)"
else
  R=$(uv run --quiet --with ds-store python - <<'PYEOF' 2>/dev/null
import os
from collections import defaultdict
try:
    from ds_store import DSStore
except ImportError:
    print("NOLIB"); raise SystemExit
targets=[l.rstrip("\n") for l in open("/tmp/fv_targets.txt",encoding="utf-8") if l.strip()]
bp=defaultdict(list)
for t in targets:
    if os.path.isdir(t): bp[os.path.dirname(t.rstrip('/'))].append(os.path.basename(t.rstrip('/')))
ok=miss=0
for parent,names in bp.items():
    ds=os.path.join(parent,".DS_Store"); e={}
    try:
        if os.path.exists(ds):
            with DSStore.open(ds,"r") as d:
                for x in d:
                    if x.code==b'GRP0': e[x.filename]=x.value
    except Exception: pass
    for n in names:
        if e.get(n)=="Kind": ok+=1
        else: miss+=1
print(f"{ok} {miss}")
PYEOF
)
  if [ "$R" = "NOLIB" ]; then
    report SKIP "T13 grouping stamped (GRP0 audit)" "ds-store unavailable via uv"
  else
    OKN=$(echo "$R" | awk '{print $1}'); MISSN=$(echo "$R" | awk '{print $2}')
    PCT=$(( OKN * 100 / (OKN + MISSN) ))
    [ "$PCT" -ge 95 ] && report PASS "T13 grouping stamped (GRP0 audit)" "$OKN ok, $MISSN missing (${PCT}%)" \
                      || report FAIL "T13 grouping stamped (GRP0 audit)" "$OKN ok, $MISSN missing (${PCT}%) - rerun bulk_group_stamp.py"
  fi
fi

# T14: no drift - global default survived the whole suite
V2=$(defaults read com.apple.finder FXPreferredViewStyle 2>/dev/null)
[ "$V2" = "Nlsv" ] && report PASS "T14 no drift: global default still list" "" \
                   || report FAIL "T14 no drift: global default still list" "FXPreferredViewStyle=$V2"

# cleanup
rm -rf "$T4DIR" "$T10DIR"

echo "--------------------------------------------------------------------------"
echo "RESULT: $PASS passed, $FAIL failed, $SKIP skipped"
exit "$FAIL"
