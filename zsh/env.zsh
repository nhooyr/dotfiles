export GOPATH=~gopath
prepend_PATH ~gopath/bin

if command_exists nvim; then
  export EDITOR=nvim
  export MANPAGER="nvim +Man!"
elif command_exists vim; then
  export EDITOR=vim
elif command_exists vi; then
  export EDITOR=vi
elif command_exists nano; then
  export EDITOR=nano
fi
export MANWIDTH=80

prepend_PATH /usr/local/bin
prepend_PATH ~/.local/bin
