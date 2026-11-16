-- FinderViewEnforcer: stay-open background applet run by launchd
-- (com.krichelj.finderviewenforcer). Once per second it runs tick.scpt, which
-- puts the front Finder window's folder in List view, sorted by Name, grouped
-- by Kind whenever a new folder is shown. For writable folders Finder then
-- persists GRP0=Kind itself, so .DS_Store files heal as you browse; where
-- Finder never persists grouping (cloud-drive roots) it is re-applied on
-- every visit. The applet holds the Accessibility/Automation grants; the
-- logic lives in tick.scpt so it can change without re-granting.

property lastKey : ""
property lastErr : ""

on supportDir()
	return (POSIX path of (path to home folder)) & "Library/Application Support/FinderViewEnforcer/"
end supportDir

on run
	my logLine("started")
end run

on idle
	try
		set res to run script (POSIX file (my supportDir() & "tick.scpt")) with parameters {lastKey}
		set AppleScript's text item delimiters to linefeed
		set parts to text items of res
		set AppleScript's text item delimiters to ""
		set lastKey to item 1 of parts
		if (count of parts) > 1 then my logLine(item 2 of parts)
		set lastErr to ""
	on error errMsg number errNum
		set e to "error " & errNum & ": " & errMsg
		if e is not lastErr then my logLine(e)
		set lastErr to e
		set lastKey to ""
	end try
	return 1
end idle

on logLine(s)
	try
		set lp to (POSIX path of (path to home folder)) & "Library/Logs/FinderViewEnforcer.log"
		set ts to do shell script "date '+%Y-%m-%d %H:%M:%S'"
		do shell script "printf '%s %s\\n' " & quoted form of ts & " " & quoted form of s & " >> " & quoted form of lp
	end try
end logLine
