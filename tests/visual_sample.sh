#!/bin/bash
# Visual check of what Finder actually renders for real folders (no fixtures).
# Usage: visual_sample.sh [N] [folder...]   (default: N random non-empty folders)
# Per folder: open in Finder, capture that window by CGWindowID (works even if
# another app covers it), OCR it (Apple Vision).
#   list view  <=> Finder reports current view = list view
#   grouped    <=> the first column header is NOT "Name" (grouped list views
#                  show the current group's Kind label there instead)
# Prints one line per folder and exits 1 if any folder is not list+grouped.
# Needs Screen Recording permission for the calling app.
set -u -o pipefail; cd "$(dirname "$0")/.."; N="${1:-15}"; shift || true
mkdir -p tests/shots/visual
if [ $# -gt 0 ]; then SAMPLE=$(printf '%s\n' "$@"); else
  SAMPLE=$(find "$HOME" \( -path "$HOME/Library" -o -name '.*' -o -name '*.app' -o -name '*.bundle' -o -name '*.framework' -o -name '*.photoslibrary' -o -name node_modules \) -prune -o -type d -print 2>/dev/null \
    | sort -R | while IFS= read -r d; do [ -n "$(ls -A "$d" 2>/dev/null | grep -v '^\.')" ] && echo "$d"; done | head -"$N")
fi
F=0; i=0
check() {  # $1 folder, $2 image -> prints "L G" (1 = ok)
  local d="$1" img="$2"
  osascript -e "tell application \"Finder\"
    activate
    set w to make new Finder window to (POSIX file \"$d\" as alias)
    set bounds of w to {80, 80, 1100, 700}
  end tell" >/dev/null 2>&1 || return 1
  sleep "${SHOT_DELAY:-3}"
  WID=$(swift tests/winid.swift "$(basename "$d")") || WID=$(swift tests/winid.swift)
  screencapture -x -o -l "$WID" "$img"
  V=$(osascript -e 'tell application "Finder" to get current view of front Finder window')
  osascript -e 'tell application "Finder" to close front window' >/dev/null
  T=$(swift tests/ocr.swift "$img"); echo "$T" > "$img.txt"
  L=$([ "$V" = "list view" ] && echo 1 || echo 0)
  # grouped needs the header row captured (Date Modified) and no "Name" header
  # (OCR may glue the sort caret onto a header, e.g. "^ Date Modified")
  G=$(echo "$T" | grep -q 'Date Modified' && ! echo "$T" | grep -qE '^[^[:alnum:]]*Name[^[:alnum:]]*$' && echo 1 || echo 0)
  echo "$L $G"
}
# The agent only acts while Finder is frontmost; if you are using another app
# at that moment a check can catch the window unenforced, so a failure is
# re-checked once (with Finder activated again) before it counts.
while IFS= read -r d <&3; do
  i=$((i+1)); img="tests/shots/visual/$i.png"
  R=$(check "$d" "$img" </dev/null) || { echo "ERR  | cannot open | $d"; F=1; continue; }
  if [ "$R" != "1 1" ]; then
    FRONT=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true')
    R=$(check "$d" "$img" </dev/null) || R="0 0"
    [ "$R" = "1 1" ] && { echo "OK   | list grouped (on retry; front app was $FRONT) | $d"; continue; }
  fi
  if [ "$R" = "1 1" ]; then echo "OK   | list grouped | $d"; else echo "FAIL | list/grouped=$R | $(head -1 "$img.txt") | $d"; F=1; fi
done 3<<< "$SAMPLE"
exit $F
