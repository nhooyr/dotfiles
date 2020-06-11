DOTFILES="$HOME/src/nhooyr/dotfiles"

bookmarks=(
  "/usr/local/Cellar"
  "/usr/local/Homebrew"
  "~/.local/share/gopath"
  "~/src"
  "~src/nhooyr"
  "~src/cdr"

  "~nhooyr/dotfiles"
  "~dotfiles/nvim"
  "~dotfiles/zsh"
  "~dotfiles/secrets"
  "~dotfiles/ssh"

  "~nhooyr/websocket"
  "~nhooyr/blog"
  "~cdr/x11wasm"
  "~cdr/code-server"
)

setup_bookmarks() {
  for b in "${bookmarks[@]}"; do
    local name="$(basename "$b")"
    local full_path="$(eval "echo $b")"

    hash -d "$name=$full_path"
  done
}
setup_bookmarks

prepend_path CDPATH ~/src
prepend_path CDPATH ~/.config
prepend_path CDPATH ~/src/cdr
prepend_path CDPATH ~/src/nhooyr
prepend_path CDPATH ~/src/nhooyr/dotfiles
