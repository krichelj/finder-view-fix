-- Enforcement logic, loaded by FinderViewEnforcer.app once per second.
-- Kept outside the signed applet so it can change without macOS asking for
-- the Accessibility/Automation grants again.
-- argv: {lastKey}. Returns the new key, plus "\n<log line>" when it changed
-- something; raises an error (and the applet retries next second) when a
-- step could not be confirmed. Acts only when Finder is frontmost and its
-- front window shows a folder not yet enforced (new window or navigation):
--   List view and sort by Name: Finder scripting
--   Group by Kind: View menu via Accessibility (no scripting API exists)

on run argv
	set lastKey to "-" -- never empty: the applet splits the result on linefeeds
	try
		set lastKey to item 1 of argv
	end try
	if lastKey is "" then set lastKey to "-"
	if application "Finder" is not running then return lastKey
	tell application "System Events"
		if name of (first application process whose frontmost is true) is not "Finder" then return lastKey
	end tell
	tell application "Finder"
		if (count of Finder windows) is 0 then return lastKey
		set w to front Finder window
		try
			set tgt to POSIX path of (target of w as alias)
		on error
			return lastKey -- Recents, search results, AirDrop... have no folder target
		end try
		set winKey to ((id of w) as text) & ":" & tgt
		if winKey is lastKey then return lastKey
		set wName to name of w
	end tell
	-- the menu bar reflects the key window: make sure it is this one
	tell application "System Events" to tell process "Finder"
		if (name of window 1) is not wName then return lastKey
	end tell
	set changed to ""
	tell application "Finder"
		if current view of w is not list view then
			set current view of w to list view
			set changed to changed & "view "
		end if
		if (name of sort column of list view options of w) is not name column then
			set sort column of list view options of w to name column
			set changed to changed & "sort "
		end if
	end tell
	if not my groupsOn() then
		tell application "System Events" to tell process "Finder" to click menu item "Use Groups" of menu 1 of menu bar item "View" of menu bar 1
		if not my waitFor("groupsOn") then error "Use Groups did not turn on for " & tgt
		set changed to changed & "groups "
	end if
	-- the Group By submenu is built lazily after grouping turns on
	if not my waitFor("groupByExists") then error "Group By menu missing for " & tgt
	if not my kindOn() then
		tell application "System Events" to tell process "Finder" to click menu item "Kind" of menu 1 of menu item "Group By" of menu 1 of menu bar item "View" of menu bar 1
		if not my waitFor("kindOn") then error "Group By Kind did not take for " & tgt
		set changed to changed & "kind "
	end if
	tell application "Finder"
		if current view of w is not list view then error "view not list for " & tgt
		if (name of sort column of list view options of w) is not name column then error "sort not Name for " & tgt
	end tell
	if changed is not "" then return winKey & linefeed & "fixed [" & changed & "] " & tgt
	return winKey
end run

on groupsOn()
	tell application "System Events" to tell process "Finder"
		return (value of attribute "AXMenuItemMarkChar" of menu item "Use Groups" of menu 1 of menu bar item "View" of menu bar 1) is not missing value
	end tell
end groupsOn

on kindOn()
	try
		tell application "System Events" to tell process "Finder"
			return (value of attribute "AXMenuItemMarkChar" of menu item "Kind" of menu 1 of menu item "Group By" of menu 1 of menu bar item "View" of menu bar 1) is not missing value
		end tell
	on error
		return false -- submenu not there yet
	end try
end kindOn

-- poll a check for up to 3 s: menus update asynchronously after a click, and
-- clicking again on a stale reading would toggle grouping back off
on groupByExists()
	tell application "System Events" to tell process "Finder"
		return exists menu item "Kind" of menu 1 of menu item "Group By" of menu 1 of menu bar item "View" of menu bar 1
	end tell
end groupByExists

on waitFor(check)
	repeat 15 times
		if check is "groupsOn" then
			if my groupsOn() then return true
		else if check is "groupByExists" then
			if my groupByExists() then return true
		else
			if my kindOn() then return true
		end if
		delay 0.2
	end repeat
	return false
end waitFor
