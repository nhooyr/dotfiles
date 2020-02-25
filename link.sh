#!/usr/bin/env bash

set -euo pipefail

main() {
  local to
  local src
  src="$1"
  to="$2"

  if [[ -L $to ]]; then
    echo "overwriting $to"
    rm "$to"
  elif [[ -e $to ]]; then
    echo "$to exists and is not a symlink"
    exit 1
  else
    echo "linking $to"
  fi

  mkdir -p "$(dirname "$to")"
  ln -s "$(realpath "$src")" "$to"
}

main "$@"
