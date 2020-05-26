alias e="nvim"
alias r="source ~/.zshrc"
alias l="ls -lh"
alias ll="ls -lha"
alias up="cd .."

ls() {
	if command -v gls > /dev/null; then
		gls --indicator-style=classify --color=auto --group-directories-first "$@"
	else
		command ls -GF "$@"
	fi
}
