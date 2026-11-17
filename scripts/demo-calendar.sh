#!/bin/sh
# Fills a "Demo" calendar with fake meetings timed around now, for screenshots.
# Then: open NextMeetingBar.app --args -onlyCalendar Demo
set -eu

osascript > /dev/null <<'APPLESCRIPT'
on mins(n)
	return (current date) + n * minutes
end mins

tell application "Calendar"
	if not (exists calendar "Demo") then make new calendar with properties {name:"Demo"}
	set cal to calendar "Demo"
	delete (every event of cal)

	-- {title, start offset (min), duration (min), location, notes}
	set specs to {¬
		{"Team standup", -300, 15, "", ""}, ¬
		{"Design review: onboarding flow", -180, 45, "", ""}, ¬
		{"1:1 with Sam", -60, 30, "", ""}, ¬
		{"Team sync", 10, 30, "https://meet.google.com/abc-defg-hij", "Agenda: https://docs.example.com/team-sync"}, ¬
		{"Lunch & learn: SwiftUI animations", 90, 60, "https://zoom.us/j/1234567890", ""}, ¬
		{"Sprint planning", 1440, 60, "https://meet.google.com/xyz-abcd-efg", ""}, ¬
		{"Coffee chat", 1500, 30, "Bean There Café", ""}, ¬
		{"Quarterly roadmap review", 2940, 90, "https://teams.microsoft.com/l/meetup-join/demo", ""}}

	repeat with s in specs
		set startAt to my mins(item 2 of s)
		make new event at end of events of cal with properties ¬
			{summary:item 1 of s, start date:startAt, end date:startAt + (item 3 of s) * minutes, ¬
				location:item 4 of s, description:item 5 of s}
	end repeat
end tell
APPLESCRIPT

echo "Demo calendar ready: next meeting \"Team sync\" starts in 10 minutes."
