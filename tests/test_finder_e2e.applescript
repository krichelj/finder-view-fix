-- Live E2E: asks Finder itself (not the .DS_Store files) what it renders.
-- Opens each folder given as an argument, reads current view + sort column.
on run argv
	set fails to 0
	set out to ""
	repeat with p in argv
		tell application "Finder"
			set w to make new Finder window to (POSIX file (p as text) as alias)
			delay 1
			set v to current view of w
			set sc to name of sort column of list view options of w
			close w
			set ok to (v is list view) and (sc is name column)
		end tell
		if not ok then set fails to fails + 1
		set out to out & (ok as text) & " | " & (v as text) & " | " & (sc as text) & " | " & p & linefeed
	end repeat
	return out & "FAILS: " & fails
end run
