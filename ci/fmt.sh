#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

npx doctoc --notitle macos/install.md

git submodule update --init
./ci/ci/fmt.sh
