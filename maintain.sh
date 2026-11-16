#!/bin/bash
# maintain.sh - hourly launchd job installed by setup.sh. Groups by Kind every
# folder that is not grouped yet (new folders start ungrouped because Finder has
# no global grouping default), plus any folder whose saved view/sort drifted.
#   - does nothing unless you have been idle FV_IDLE_MIN minutes (default 15)
#     and Finder is not busy (e.g. copying), unless FV_FORCE=1
#   - does nothing if every folder already complies (--check)
#   - otherwise pauses Finder (SIGSTOP: it can neither read nor write back its
#     cached .DS_Store copies), writes the missing records, then SIGKILLs it so
#     the relaunched Finder reads the new files. No Apple events, no
#     Accessibility, no prompts.
# Log: ~/Library/Logs/finder-view-fix.log
set -u
cd "$(dirname "$0")"
LOG="$HOME/Library/Logs/finder-view-fix.log"
STATUS="$PWD/last-run.txt"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
# Without Full Disk Access a launchd job cannot list these folders (TCC);
# fail loudly instead of silently skipping them.
if ! ls "$HOME/Documents" >/dev/null 2>&1; then
  log "ERROR: no Full Disk Access for FinderViewFix.app (see README)"; echo "error: no Full Disk Access" > "$STATUS"; exit 1
fi
PY="$PWD/venv/bin/python"
if ! "$PY" -c 'import ds_store' 2>/dev/null; then   # self-heal the private env
  UV=$(command -v uv || ls /opt/homebrew/bin/uv "$HOME/.local/bin/uv" 2>/dev/null | head -1)
  "$UV" venv -q --python 3.12 venv && "$UV" pip install -q --python "$PY" ds-store || { log "ERROR no python env"; exit 1; }
fi

if [ "${FV_FORCE:-0}" != 1 ]; then
  IDLE=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  [ "${IDLE:-0}" -lt $(( ${FV_IDLE_MIN:-15} * 60 )) ] && exit 0
fi

T="$PWD/targets.txt"
FV_TARGETS="$T" bash make_targets.sh >/dev/null
if "$PY" bulk_group_stamp.py --check "$T" > "$PWD/check.txt" 2>&1; then   # all compliant
  echo "ok $(date '+%F %T') nothing to change" > "$STATUS"; exit 0
fi

FPID=$(pgrep -x Finder || true)
if [ -n "$FPID" ] && [ "${FV_FORCE:-0}" != 1 ]; then
  CPU=$(ps -o %cpu= -p "$FPID" | awk '{print int($1)}')
  [ "${CPU:-0}" -gt 5 ] && { log "skip: Finder busy (cpu $CPU%)"; exit 0; }
fi
[ -n "$FPID" ] && kill -STOP "$FPID"
OUT=$("$PY" bulk_group_stamp.py "$T" 2>&1); RC=$?
if [ -n "$FPID" ]; then
  kill -KILL "$FPID"
  for _ in $(seq 1 20); do sleep 0.5; pgrep -x Finder >/dev/null && break; done
  pgrep -x Finder >/dev/null || open -a Finder
fi
log "rc=$RC $(echo "$OUT" | head -1)"
[ $RC = 0 ] && echo "ok $(date '+%F %T') $(echo "$OUT" | head -1)" > "$STATUS" || echo "error rc=$RC $(echo "$OUT" | head -1)" > "$STATUS"
echo "$OUT" | grep 'FAIL:' | head -5 | while IFS= read -r l; do log "  $l"; done
exit $RC
