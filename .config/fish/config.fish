if status --is-interactive
	set -U fish_greeting
	set -U fish_color_user 66233c
	set -U fish_color_host 875f5f
	set -U fish_color_cwd af005f
	set -U fish_color_search_match --background=ffff87
	set -U fish_pager_color_description 581D5B
	set -U fish_pager_color_prefix --bold black
	set -U fish_pager_color_progress brwhite --background=af005f

	set -gx EDITOR 'subl -w'
	set -gx MANPAGER 'nvim -c "set ft=man" -'
	set -gx PATH ~/.local/bin $PATH
	if test (hostname) = aubble
		set -gx PATH /snap/bin $PATH
	end

	set -gx GOPATH ~/Programming/gopath
	set -gx PATH $GOPATH/bin $PATH

	set -g fish_prompt_pwd_dir_length 0

	# Occasionally things give me errors because the default limit is so low.
	ulimit -n 8192

	abbr --add --global b brew
	abbr --add --global bc brew cask
	abbr --add --global bin brew install
	abbr --add --global bcin brew cask install
	abbr --add --global bif brew info
	abbr --add --global bcif brew cask info
	abbr --add --global br brew remove
	abbr --add --global bcr brew cask remove
	abbr --add --global bu brew update\; and brew upgrade\; and brew cask upgrade
	abbr --add --global bs brew search

	abbr --add --global g git
	abbr --add --global gch git checkout
	abbr --add --global ga git add
	abbr --add --global gcm git commit
	abbr --add --global gb git branch
	abbr --add --global grt git reset
	abbr --add --global grb git rebase
	abbr --add --global gpl git pull
	abbr --add --global gps git push --set-upstream origin HEAD
	abbr --add --global gs git status
	abbr --add --global gst git stash
	abbr --add --global gsh git show
	abbr --add --global gd git diff
	abbr --add --global gdc git diff --cached
	abbr --add --global gl git log
	abbr --add --global gll git_log_line
	abbr --add --global gpr git pull-request
	abbr --add --global gm git merge
	abbr --add --global gcl git clone
	abbr --add --global grv git revert
	# Not grm to avoid confusion with git rm.
	abbr --add --global gro git remote
	abbr --add --global gcp git cherry-pick

	abbr --add --global r source ~/.config/fish/config.fish $argv

	abbr --add --global vim nvim

	abbr --add --global e eval '$EDITOR'
	abbr --add --global ec eval '$EDITOR' ~/.config/fish/config.fish

	abbr --add --global l ls -lh
	abbr --add --global ll ls -lhA

	abbr --add --global rgni rg --no-ignore

	# Set the default plain text editor to sublime text.
	defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add \
		'{LSHandlerContentType=public.plain-text;LSHandlerRoleAll=com.sublimetext.3;}'
end
