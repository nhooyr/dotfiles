#!/bin/sh
set -eu
cd -- "$(dirname "$0")"
PATH="$PWD/../bin:$PATH"

dotln ./settings.json ~/Library/Application\ Support/Code/User/settings.json
./theme/install.sh
