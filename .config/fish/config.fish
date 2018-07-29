if status --is-interactive
	# TODO https://github.com/fish-shell/fish-shell/issues/583 for prevd and nextd and then ignore cd in here.
	function __fasd_run -e fish_preexec
		fasd --proc (fasd --sanitize "$argv" | string split ' ') &
	end

	function preexec --on-event fish_preexec
		set -g preexec_time (date +%s)
	end

	function postexec --on-event fish_postexec
		if test (uname) != Darwin
			return
		end
		set -l message "finished"
		if test $status -ne 0
			set message "errored"
		end
		return
		set -l tty (osascript -e 'tell application "Terminal"
		if frontmost of window 1 then
		  return tty of selected tab of window 1
		end if
	  end tell')
		if test "$tty" != (tty)
			if test -f "/tmp/e-$TERM_SESSION_ID"
				rm "/tmp/e-$TERM_SESSION_ID"
			else
				if test $message = "errored"
					echo -en '\a'
				end
				set -l cmd (string split ' ' $argv)[1]
				set -l duration (math (date +%s) - $preexec_time)
				# TODO clicking on this should switch to the tab and window of completed command
				noti "$argv" "$duration"s "$cmd $message"
			end
		end
	end

	# TODO I don't like the way this stuff works.
	# it's a bad idea to store it in a universal variable
	# that is not globally shared across multiple computers
	set -U fish_greeting
	set -U fish_color_user 66233c
	set -U fish_color_host 875f5f
	set -U fish_color_cwd af005f
	set -U fish_color_search_match --background=ffff87
	set -U fish_pager_color_description 581D5B
	set -U fish_pager_color_prefix --bold black
	set -U fish_pager_color_progress brwhite --background=af005f

	set -gx EDITOR 'e'
	set -gx MANPAGER 'nvim -c "set ft=man" -'
	set -gx PATH ~/.local/bin $PATH
	if test (hostname) = aubble
		set -gx PATH /snap/bin $PATH
	end

	if test -d ~/Programming/coder/bash
		set -gx PATH ~/Programming/coder/bash $PATH
	end

	set -gx GOPATH ~/Programming/gopath
	set -gx PATH $GOPATH/bin $PATH

	ulimit -n 8192

	# TODO set LS COLORS

	abbr --add --global b brew

	abbr --add --global g git
	abbr --add --global gch git checkout
	abbr --add --global ga git add
	abbr --add --global gcm git commit
	abbr --add --global gb git branch
	abbr --add --global grt git reset
	abbr --add --global grb git rebase
	abbr --add --global gpl git pull
	abbr --add --global gpsh git push --set-upstream origin HEAD
	abbr --add --global gst git status
	abbr --add --global gd git diff
	abbr --add --global gl git log
	abbr --add --global gpr git pull-request
	abbr --add --global gm git merge
	abbr --add --global gcl git clone

	abbr --add --global r reload

	abbr --add --global vim nvim

	defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add \
		'{LSHandlerContentType=public.plain-text;LSHandlerRoleAll=com.sublimetext.3;}'
end
