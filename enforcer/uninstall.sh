#!/bin/bash
LABEL="com.krichelj.finderviewenforcer"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/FinderViewEnforcer.app" "$HOME/Library/Application Support/FinderViewEnforcer"
echo "uninstalled"
