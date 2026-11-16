#!/bin/bash
# setup.sh - run once. Makes every Finder folder List view, grouped by Kind,
# sorted by Name, and keeps it that way with no further action:
#   1. global defaults: list view + sort by Name (Finder honours these for
#      every folder without its own saved view; grouping has no global default)
#   2. installs the maintenance job (launchd, hourly, acts only when you have
#      been idle) that groups any folder not grouped yet: see maintain.sh
#   3. asks once for Full Disk Access for the job (macOS requires it to list
#      Documents/Desktop/Downloads/iCloud), then runs the job once
# Re-running is safe. Remove with: bash setup.sh --uninstall
set -euo pipefail
cd "$(dirname "$0")"
LABEL="com.krichelj.finder-view-fix"
SUP="$HOME/Library/Application Support/finder-view-fix"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"; rm -rf "$SUP"
  echo "uninstalled (global Finder defaults left as they are)"; exit 0
fi

# 1. global defaults, written while Finder is paused so it cannot overwrite them
FPID=$(pgrep -x Finder || true)
[ -n "$FPID" ] && kill -STOP "$FPID"
trap '[ -n "$FPID" ] && kill -CONT "$FPID" 2>/dev/null || true' EXIT
defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
P="$(mktemp -d)/finder.plist"
defaults export com.apple.finder "$P"
for ROOT in StandardViewSettings FK_StandardViewSettings; do
  for KEY in ExtendedListViewSettingsV2 ListViewSettings; do
    /usr/libexec/PlistBuddy -c "Set :$ROOT:$KEY:sortColumn name" "$P" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :$ROOT:$KEY:sortColumn string name" "$P" 2>/dev/null || true
  done
done
defaults import com.apple.finder "$P"
[ -n "$FPID" ] && kill -CONT "$FPID"; FPID=""

# 2. install the job: copy the scripts and a private Python env out of the repo,
# so the job keeps working if the repo moves or uv's cache is cleaned
mkdir -p "$SUP" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp maintain.sh make_targets.sh bulk_group_stamp.py launcher.swift "$SUP/"
[ -x "$SUP/venv/bin/python" ] || uv venv -q --python 3.12 "$SUP/venv"
uv pip install -q --python "$SUP/venv/bin/python" ds-store
# The job's executable is a tiny signed app (launcher.swift), because macOS
# lets a launchd job list Documents/Desktop/Downloads/iCloud only with Full
# Disk Access, granted per executable. Built once and kept, so the grant holds.
APP="$SUP/FinderViewFix.app"
if [ ! -x "$APP/Contents/MacOS/FinderViewFix" ]; then
  mkdir -p "$APP/Contents/MacOS"
  swiftc -O -o "$APP/Contents/MacOS/FinderViewFix" launcher.swift
  cat > "$APP/Contents/Info.plist" <<IP
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>FinderViewFix</string>
  <key>CFBundleExecutable</key><string>FinderViewFix</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
IP
  codesign --force -s - --identifier "$LABEL" "$APP"
fi
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/FinderViewFix</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# 3. one-time grant, then the first run through launchd itself
STATUS="$SUP/last-run.txt"
until { rm -f "$STATUS"; launchctl setenv FV_FORCE 1; launchctl kickstart -k "gui/$(id -u)/$LABEL"
        for _ in $(seq 1 120); do [ -s "$STATUS" ] && break; sleep 1; done
        launchctl unsetenv FV_FORCE; grep -q '^ok' "$STATUS" 2>/dev/null; }; do
  echo "Grant Full Disk Access to FinderViewFix (opening System Settings; use + and add:"
  echo "  $APP ) then press Enter."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
  read -r _ || { echo "Not interactive: grant it, then run setup.sh again."; exit 1; }
done
cat "$STATUS"
