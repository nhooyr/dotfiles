#!/usr/bin/env bash


set -o pipefail

#if type brew &>/dev/null; then
#    for COMPLETION in "$(brew --prefix)/etc/bash_completion.d/"*; do
#        # shellcheck disable=SC1090
#        [[ -f $COMPLETION ]] && source "$COMPLETION"
#    done
#    if [[ -f "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]]; then
#        # shellcheck disable=SC1090
#        source "$(brew --prefix)/etc/profile.d/bash_completion.sh"
#    fi
#fi

add_path() {
    if [[ $PATH != *${1}:* ]]; then
        PATH="$1:${PATH}"
    fi
}

export EDITOR=editor
export MANWIDTH=80
export MANPAGER="ansifilter | pager"
export GOPATH=~/Programming/gopath
add_path "${GOPATH}/bin"
add_path /usr/local/opt/ruby/
add_path /usr/local/lib/ruby/gems/2.6.0/bin
add_path ~/.local/bin

# Occasionally things give me errors because the default limit is so low.
ulimit -n 8192

alias l="ls -lh"
alias ll="ls -lhA"

source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.bash.inc
source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.bash.inc

# Avoid duplicates
HISTCONTROL=ignoredups:erasedups  
# When the shell exits, append to the history file instead of overwriting it
shopt -s histappend
export MANPAGER='nvim +Man!'

bind '"\ee"':shell-expand-line
