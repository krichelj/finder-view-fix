#!/bin/bash
# Builds the folder list (/tmp/fv_targets.txt, or $FV_TARGETS) for
# bulk_group_stamp.py: every visible folder under $HOME (excluding ~/Library)
# plus the extra roots Finder shows in its sidebar: cloud drives under
# ~/Library/CloudStorage, iCloud Drive and /Applications. Override the extra
# roots with FV_EXTRA_ROOTS (newline-separated). Hidden dirs, bundles,
# node_modules and symlinks are skipped.
OUT="${FV_TARGETS:-/tmp/fv_targets.txt}"
if [ -z "${FV_EXTRA_ROOTS+x}" ]; then
  FV_EXTRA_ROOTS="$(ls -d "$HOME"/Library/CloudStorage/*/ 2>/dev/null | sed 's:/$::')
$HOME/Library/Mobile Documents/com~apple~CloudDocs
/Applications"
fi
MD="$HOME/My Drive"; [ -L "$MD" ] && MD="$(readlink "$MD")"
PRUNE=( \( -path "$HOME/Library" -o -name '.*' -o -name '*.app' -o -name '*.bundle' -o -name '*.framework' -o -name '*.photoslibrary' -o -name '*.pkg' -o -name '*.xcodeproj' -o -name '*.lproj' -o -name '*.xcassets' -o -name '*.plugin' -o -name '*.kext' -o -name node_modules \) -prune )
{ echo "$HOME"; find "$HOME" "${PRUNE[@]}" -o -type d -print 2>/dev/null
  [ -d "$MD" ] && find "$MD" "${PRUNE[@]}" -o -type d -print 2>/dev/null
  while IFS= read -r R; do
    [ -n "$R" ] && [ -d "$R" ] && find "$R" "${PRUNE[@]}" -o -type d -print 2>/dev/null
  done <<< "$FV_EXTRA_ROOTS"
} | sort -u > "$OUT"
echo "$(wc -l < "$OUT" | tr -d ' ') folders -> $OUT"
