function noti
	# Activate does not actually work at the moment but whatever.
	terminal-notifier -message "You wanted a notification" -title Terminal -ignoreDnD -sender com.apple.faketerminal -activate com.apple.Terminal -sound glass
end