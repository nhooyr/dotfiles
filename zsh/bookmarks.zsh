DOTFILES="$HOME/src/nhooyr/dotfiles"

bookmarks=(
  "/usr/local/Cellar"
  "/usr/local/Homebrew"
  "$HOME/.local/share/gopath"
  # This one is a little weird I agree but really helps when writing something with ~ and
  # then realizing its not bookmarked, way more "consistent" to just replace with src and
  # keep going.
  "$HOME/src"
  "$HOME/src/nhooyr"
  "$HOME/src/nhooyr-ts"
  "$HOME/src/cdr"

  "$HOME/src/nhooyr/dotfiles"
  "$HOME/src/nhooyr/dotfiles/nvim"
  "$HOME/src/nhooyr/dotfiles/zsh"
  "$HOME/src/nhooyr/dotfiles/secrets"
  "$HOME/src/nhooyr/dotfiles/ssh"
  "$HOME/src/nhooyr/notes"
  "$HOME/src/nhooyr/notes/thoughts"
  "$HOME/src/nhooyr/notes/decisions"
  "$HOME/src/nhooyr/notes/friends"
  "$HOME/src/nhooyr/notes/coder"
  "$HOME/src/nhooyr/scratch"

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

  "$HOME/src/terrastruct"
  "$HOME/src/terrastruct/terrastruct-backend"
  "$HOME/src/terrastruct/terrastruct-frontend"
  "$HOME/src/terrastruct/wiki"
  "$HOME/src/terrastruct/ansible"
  "$HOME/src/terrastruct/envs"
)

setup_bookmarks() {
  for b in "${bookmarks[@]}"; do
    local full_path="$b"
    local name="${b##*/}"

    hash -d "$name=$full_path"
  done
}
setup_bookmarks
