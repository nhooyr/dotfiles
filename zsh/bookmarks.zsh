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
  "$HOME/src/nhooyr/archive"
  "$HOME/src/nhooyr/dotfiles/nvim"
  "$HOME/src/nhooyr/dotfiles/zsh"
  "$HOME/src/nhooyr/dotfiles/secrets"
  "$HOME/src/nhooyr/dotfiles/ssh"
  "$HOME/src/nhooyr/notes"
  "$HOME/src/nhooyr/notes/thoughts"
  "$HOME/src/nhooyr/notes/decisions"
  "$HOME/src/nhooyr/notes/friends"
  "$HOME/src/nhooyr/notes/coder"
  "$HOME/src/nhooyr/notes/2021"
  "$HOME/src/nhooyr/notes/2022"
  "$HOME/src/nhooyr/notes/2023"
  "$HOME/src/nhooyr/scratch"

  "$HOME/src/nhooyr/websocket"
  "$HOME/src/nhooyr/blog"
  "$HOME/src/nhooyr/lip"
  "$HOME/src/nhooyr/flappybird"
  "$HOME/src/cdr/x11wasm"
  "$HOME/src/cdr/bark"
  "$HOME/src/cdr/enterprise"
  "$HOME/src/cdr/c"
  "$HOME/src/cdr/code-server"

  "$HOME/src/neovim/neovim"

  "$HOME/Pictures"

  "$HOME/src/terrastruct"
  "$HOME/src/terrastruct/d2"
  "$HOME/src/terrastruct/d2-2"
  "$HOME/src/terrastruct/xos"
  "$HOME/src/terrastruct/xdefer"
  "$HOME/src/terrastruct/src/backend/tala"
  "$HOME/src/terrastruct/d2-docs"
  "$HOME/src/terrastruct/util-go"
)

setup_bookmarks() {
  for b in "${bookmarks[@]}"; do
    local full_path="$b"
    local name="${b##*/}"

    hash -d "$name=$full_path"
  done
}
setup_bookmarks
hash -d "tsrc=$HOME/src/terrastruct/src"
hash -d "tsrc-2=$HOME/src/terrastruct/src-2"
hash -d "tbackend=$HOME/src/terrastruct/src/backend"
hash -d "tfrontend=$HOME/src/terrastruct/src/frontend"
hash -d "tci=$HOME/src/terrastruct/ci"
hash -d "twiki=$HOME/src/terrastruct/src/wiki"
hash -d "tstruct=$HOME/src/terrastruct"
