if [ -f ~/src/emscripten-core/emsdk/emsdk_env.fish ]
    source ~/src/emscripten-core/emsdk/emsdk_env.fish >/dev/null
end

alias b="apt"
alias ls="ls --indicator-style=classify --color=auto"
alias i="sudo apt install"
alias bu="sudo apt update; and sudo apt full-upgrade; and sudo snap refresh"
alias ports="ss -ltpn"

addToPath ~/src/nhooyr/dotfiles/remote/bin
addToPath /snap/bin
addToPath /sbin
addToPath /home/nhooyr/.yarn/bin

fzf_key_bindings
