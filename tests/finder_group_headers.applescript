-- Prints the group-header labels Finder renders in the list for folder argv[1]
-- (read via Accessibility: grouped list views draw each Kind group as an
-- AXButton inside the file outline). Empty output = not grouped.
on run argv
	tell application "Finder"
		activate
		set w to make new Finder window to (POSIX file (item 1 of argv) as alias)
		delay 1.5
	end tell
	set out to {}
	tell application "System Events" to tell process "Finder"
		repeat with e in (entire contents of window 1)
			try
				if role of e is "AXButton" then
					set p to value of attribute "AXParent" of e
					set inList to false
					repeat 6 times
						if role of p is in {"AXOutline", "AXTable"} then
							set inList to true
							exit repeat
						end if
						set p to value of attribute "AXParent" of p
					end repeat
					if inList then set end of out to (description of e)
				end if
			end try
		end repeat
	end tell
	tell application "Finder" to close w
	set AppleScript's text item delimiters to ","
	return out as text
end run
