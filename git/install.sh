#!/bin/sh
set -eu
cd -- "$(dirname "$0")"
PATH="$PWD/../bin:$PATH"

dotln ./gitconfig ~/.gitconfig
dotln ./gitignore ~/.config/git/ignore
