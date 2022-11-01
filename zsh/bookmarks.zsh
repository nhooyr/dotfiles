DOTFILES="$HOME/sync/src/nhooyr/dotfiles"

bookmarks=(
  "/usr/local/Cellar"
  "/usr/local/Homebrew"
  "$HOME/.local/share/gopath"
  # This one is a little weird I agree but really helps when writing something with ~ and
  # then realizing its not bookmarked, way more "consistent" to just replace with src and
  # keep going.
  "$HOME/sync/src"
  "$HOME/sync/src/nhooyr"
  "$HOME/sync/src/nhooyr-ts"
  "$HOME/sync/src/cdr"

  "$HOME/sync/src/nhooyr/dotfiles"
  "$HOME/sync/src/nhooyr/archive"
  "$HOME/sync/src/nhooyr/dotfiles/nvim"
  "$HOME/sync/src/nhooyr/dotfiles/zsh"
  "$HOME/sync/src/nhooyr/dotfiles/secrets"
  "$HOME/sync/src/nhooyr/dotfiles/ssh"
  "$HOME/sync/src/nhooyr/notes"
  "$HOME/sync/src/nhooyr/notes/thoughts"
  "$HOME/sync/src/nhooyr/notes/decisions"
  "$HOME/sync/src/nhooyr/notes/friends"
  "$HOME/sync/src/nhooyr/notes/coder"
  "$HOME/sync/src/nhooyr/scratch"

  "$HOME/sync/src/nhooyr/websocket"
  "$HOME/sync/src/nhooyr/blog"
  "$HOME/sync/src/nhooyr/lip"
  "$HOME/sync/src/cdr/x11wasm"
  "$HOME/sync/src/cdr/bark"
  "$HOME/sync/src/cdr/enterprise"
  "$HOME/sync/src/cdr/c"
  "$HOME/sync/src/cdr/code-server"

  "$HOME/sync/src/neovim/neovim"

  "$HOME/Pictures"

  "$HOME/sync/src/terrastruct"
  "$HOME/sync/src/terrastruct/d2"
  "$HOME/sync/src/terrastruct/xos"
  "$HOME/sync/src/terrastruct/xdefer"
  "$HOME/sync/src/terrastruct/sync/src/backend/tala"
)

setup_bookmarks() {
  for b in "${bookmarks[@]}"; do
    local full_path="$b"
    local name="${b##*/}"

    hash -d "$name=$full_path"
  done
}
setup_bookmarks
hash -d "tsrc=$HOME/sync/src/terrastruct/sync/src"
hash -d "tbackend=$HOME/sync/src/terrastruct/sync/src/backend"
hash -d "tfrontend=$HOME/sync/src/terrastruct/sync/src/frontend"
