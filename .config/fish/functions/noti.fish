function noti
	set -l message
	set -l subtitle
	set -l title
	if test (count $argv) -ge 1
		set message $argv[1]
	end
	if test (count $argv) -ge 2
		set subtitle $argv[2]
	end
	if test (count $argv) -ge 3
		set title $argv[3]
	end
	# TODO use proper disown command when it comes out
	# TODO takes a lot of energy if I don't use timeout because it stays on in the background, wtf
	fish -c "terminal-notifier -sender com.apple.Terminal -activate com.apple.Terminal -timeout 8 -message '$message' -subtitle '$subtitle' -title '$title'  ^ /dev/null &"
end
