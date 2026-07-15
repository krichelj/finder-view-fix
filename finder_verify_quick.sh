#!/bin/bash
# finder_verify_quick.sh — WINDOWLESS verification of the uniform Finder view.
# Safe to run anytime; opens no windows, touches nothing.
# Checks: global list view, global sort-by-Name, per-folder Group-by-Kind stamps.
set -u
PASS=0; FAIL=0

chk() { # $1 name, $2 ok(0/1), $3 detail
  if [ "$2" = "1" ]; then PASS=$((PASS+1)); printf "PASS | %-38s | %s\n" "$1" "$3"
  else FAIL=$((FAIL+1)); printf "FAIL | %-38s | %s\n" "$1" "$3"; fi
}

V=$(defaults read com.apple.finder FXPreferredViewStyle 2>/dev/null)
chk "global view = list" "$([ "$V" = "Nlsv" ] && echo 1 || echo 0)" "FXPreferredViewStyle=$V"

TMPPL="/tmp/fvq_$$.plist"; defaults export com.apple.finder "$TMPPL"
SC=$(/usr/libexec/PlistBuddy -c "Print :StandardViewSettings:ExtendedListViewSettingsV2:sortColumn" "$TMPPL" 2>/dev/null)
rm -f "$TMPPL"
chk "global sort = Name" "$([ "$SC" = "name" ] && echo 1 || echo 0)" "sortColumn=${SC:-unset}"

if [ -s /tmp/fv_targets.txt ]; then
  R=$(python3 - <<'PYEOF' 2>/dev/null
import os
from collections import defaultdict
from ds_store import DSStore
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
  OKN=$(echo "$R" | awk '{print $1}'); MISSN=$(echo "$R" | awk '{print $2}')
  PCT=$(( OKN * 100 / (OKN + MISSN) ))
  chk "group-by-Kind stamps (GRP0)" "$([ "$PCT" -ge 95 ] && echo 1 || echo 0)" "$OKN stamped, $MISSN missing (${PCT}%)"
else
  echo "SKIP | group-by-Kind stamps | no /tmp/fv_targets.txt"
fi

echo "RESULT: $PASS passed, $FAIL failed"
exit "$FAIL"
