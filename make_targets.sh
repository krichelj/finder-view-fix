#!/bin/bash
# Builds the folder list (/tmp/fv_targets.txt) for bulk_group_stamp.py:
# home top level + Documents/Downloads/Desktop/Pictures/Movies/Music/Public
# + Google Drive, excluding hidden dirs, app bundles, node_modules.
MD="$HOME/My Drive"; [ -L "$MD" ] && MD="$(readlink "$MD")"
{ echo "$HOME"; find "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop" "$HOME/Pictures" "$HOME/Movies" "$HOME/Music" "$HOME/Public" "$MD" \( -name '.*' -o -name '*.app' -o -name '*.bundle' -o -name '*.framework' -o -name '*.photoslibrary' -o -name 'node_modules' \) -prune -o -type d -print 2>/dev/null; } | sort -u > /tmp/fv_targets.txt
echo "$(wc -l < /tmp/fv_targets.txt | tr -d ' ') folders -> /tmp/fv_targets.txt"
