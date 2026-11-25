#!/bin/sh
set -eu
cd -- "$(dirname "$0")"
PATH="$PWD/../bin:$PATH"

NO_OVERWRITE=1 dotln ./config.fish ~/.config/fish/config.fish
dotln ./functions ~/.config/fish/functions
dotln ./completions ~/.config/fish/completions
