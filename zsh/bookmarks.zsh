DOTFILES="$HOME/src/nhooyr/dotfiles"

bookmarks=(
  "/usr/local/Cellar"
  "/usr/local/Homebrew"
  "$HOME/.local/share/gopath"
  "$HOME/src/nhooyr"
  "$HOME/src/cdr"

  "$HOME/src/nhooyr/dotfiles"
  "$HOME/src/nhooyr/dotfiles/nvim"
  "$HOME/src/nhooyr/dotfiles/zsh"
  "$HOME/src/nhooyr/dotfiles/secrets"
  "$HOME/src/nhooyr/dotfiles/ssh"
  "$HOME/src/nhooyr/notes"

  "$HOME/src/nhooyr/websocket"
  "$HOME/src/nhooyr/blog"
  "$HOME/src/nhooyr/lip"
  "$HOME/src/cdr/x11wasm"
  "$HOME/src/cdr/bark"
  "$HOME/src/cdr/enterprise"
  "$HOME/src/cdr/c"
  "$HOME/src/cdr/code-server"

  "$HOME/src/neovim/neovim"

  "$HOME/Pictures"
)

setup_bookmarks() {
  for b in "${bookmarks[@]}"; do
    local full_path="$b"
    local name="${b##*/}"

    hash -d "$name=$full_path"
  done
}
setup_bookmarks
