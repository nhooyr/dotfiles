#!/bin/sh
set -eu

cd -- "$(dirname "$0")"
bat cache --build >/dev/null
printf 'dotfiles: bat: %s: Built theme cache.\n' "${0##*/}"
