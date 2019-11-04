	source /usr/local/opt/fzf/shell/key-bindings.fish

	alias ls="gls --indicator-style=classify --color=auto"
	alias icloud="cd ~/Library/Mobile\ Documents/com~apple~CloudDocs"
	alias bu="brew update && brew upgrade && brew cask upgrade"
	alias b="brew"
	alias i="brew install"
	alias fp="fp.js"
	alias ports="netstat -vanp tcp"

	function tra
			for file in $argv
					set -l file (realpath "$file")
					osascript -e "tell application \"Finder\" to delete POSIX file \"$file\"" >/dev/null
			end
	end

	function ms
			set -l localPath (realpath "$argv")
			set remotePath (string replace ~ /home/nhooyr "$localPath")
			mutagen sync create -n=(basename "$localPath") "$localPath" xayah-unshared:"$remotePath"
	end

	# https://stackoverflow.com/a/58445755/4283659
	# x2go's CLI needs this.
	set -gx DYLD_LIBRARY_PATH /usr/local/opt/openssl/lib

	addToPath ~/.cargo/bin
	addToPath /usr/local/opt/make/libexec/gnubin
	addToPath /usr/local/opt/gnu-sed/libexec/gnubin
	addToPath ~/src/nhooyr/dotfiles/ien/bin
