#!/bin/bash
# Builds FinderViewEnforcer.app (stay-open applet, no Dock icon, ad-hoc signed)
# into ~/Applications and loads it as a launchd agent that starts at login and
# is restarted if it ever exits. macOS then asks once for Accessibility and
# Automation (Finder, System Events) for "FinderViewEnforcer": allow both.
# install.sh --logic-only updates just tick.scpt (no re-grant needed).
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/FinderViewEnforcer.app"
LABEL="com.krichelj.finderviewenforcer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
SUP="$HOME/Library/Application Support/FinderViewEnforcer"
mkdir -p "$SUP"
osacompile -o "$SUP/tick.scpt" tick.applescript
if [ "${1:-}" = "--logic-only" ]; then echo "updated $SUP/tick.scpt"; exit 0; fi
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -rf "$APP"
osacompile -s -o "$APP" FinderViewEnforcer.applescript
pset() {  # pset KEY TYPE VALUE: set or add an Info.plist key
  /usr/libexec/PlistBuddy -c "Set :$1 $3" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$APP/Contents/Info.plist"
}
pset LSUIElement bool true
pset CFBundleIdentifier string "$LABEL"
pset CFBundleName string FinderViewEnforcer
pset NSAppleEventsUsageDescription string "Keeps every Finder folder in List view, grouped by Kind, sorted by Name."
codesign --force --deep -s - "$APP"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/applet</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/FinderViewEnforcer.err</string>
</dict></plist>
PL
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed: $APP (launchd label $LABEL); log: ~/Library/Logs/FinderViewEnforcer.log"
