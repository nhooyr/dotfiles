#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

git submodule update --init
./ci/ci/lint.sh
