#!/bin/bash
# fix_finder_views.sh
# Enforces a uniform Finder view everywhere under $HOME:
#   List view | Group by: Kind | Sort by: Name
#
# Why this works when "Use as Defaults" doesn't:
# Finder stores per-folder view overrides in hidden .DS_Store files.
# Any folder with an override ignores the global default. This script
# sets the global defaults AND deletes the overrides.
#
# Usage:  bash fix_finder_views.sh
#         SKIP_DESKTOP=0 bash fix_finder_views.sh   # also reset Desktop icon layout
set -u
SKIP_DESKTOP="${SKIP_DESKTOP:-1}"

echo "[1/5] Quitting Finder (so it can't rewrite settings mid-fix)..."
osascript -e 'tell application "Finder" to quit' 2>/dev/null || killall Finder 2>/dev/null
sleep 2

echo "[2/5] Setting global view defaults..."
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"        # List view
defaults write com.apple.finder FXPreferredGroupBy -string "Kind"          # Group by Kind
defaults write com.apple.finder FXArrangeGroupViewBy -string "Kind"        # (legacy key)
defaults write com.apple.finder FXPreferredSearchViewStyle -string "Nlsv"  # search results too

echo "[3/5] Setting default list-view sort column to Name..."
PLIST="/tmp/finder_prefs_$$.plist"
defaults export com.apple.finder "$PLIST"
for ROOT in StandardViewSettings FK_StandardViewSettings; do
  for KEY in ExtendedListViewSettingsV2 ListViewSettings; do
    /usr/libexec/PlistBuddy -c "Set :$ROOT:$KEY:sortColumn name" "$PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :$ROOT:$KEY:sortColumn string name" "$PLIST" 2>/dev/null
  done
done
defaults import com.apple.finder "$PLIST"
rm -f "$PLIST"

echo "[4/5] Deleting per-folder overrides (.DS_Store) under $HOME ..."
if [ "$SKIP_DESKTOP" = "1" ]; then
  echo "      (keeping ~/Desktop/.DS_Store to preserve Desktop icon positions)"
  DELETED=$(find "$HOME" -name .DS_Store -type f ! -path "$HOME/Desktop/.DS_Store" -delete -print 2>/dev/null | wc -l | tr -d ' ')
else
  DELETED=$(find "$HOME" -name .DS_Store -type f -delete -print 2>/dev/null | wc -l | tr -d ' ')
fi
echo "      deleted: $DELETED override files"

echo "[5/5] Relaunching Finder..."
open -a Finder
sleep 2

echo ""
echo "Verification of global defaults:"
echo "  view style : $(defaults read com.apple.finder FXPreferredViewStyle)  (Nlsv = list)"
echo "  group by   : $(defaults read com.apple.finder FXPreferredGroupBy)"
echo "DONE"
