function set_reminder
	if not test (count $argv) -eq 1
		return
	end
  osascript -e "
		tell application \"Reminders\"
			make new reminder with properties {name:\""$argv" Minute Reminder\", remind me date:(current date) + ("$argv" * 60)}
		end tell" > /dev/null
end