#!/bin/bash
# Builds the folder list (/tmp/fv_targets.txt) for bulk_group_stamp.py:
# every visible folder under $HOME (plus Google Drive), excluding ~/Library,
# hidden dirs, bundles, node_modules and symlinks.
MD="$HOME/My Drive"; [ -L "$MD" ] && MD="$(readlink "$MD")"
PRUNE=( \( -path "$HOME/Library" -o -name '.*' -o -name '*.app' -o -name '*.bundle' -o -name '*.framework' -o -name '*.photoslibrary' -o -name '*.pkg' -o -name '*.xcodeproj' -o -name '*.lproj' -o -name '*.xcassets' -o -name '*.plugin' -o -name '*.kext' -o -name node_modules \) -prune )
{ echo "$HOME"; find "$HOME" "${PRUNE[@]}" -o -type d -print 2>/dev/null
  [ -d "$MD" ] && find "$MD" "${PRUNE[@]}" -o -type d -print 2>/dev/null; } | sort -u > /tmp/fv_targets.txt
echo "$(wc -l < /tmp/fv_targets.txt | tr -d ' ') folders -> /tmp/fv_targets.txt"
