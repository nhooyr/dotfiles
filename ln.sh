#!/bin/sh
set -eu

main() {
  src="$1"
  to="$2"

  if [ -L "$to" ]; then
    echo "overwriting symlink $to"
    rm "$to"
  elif [ -e "$to" ]; then
    echo "$to exists and is not a symlink"
    exit 1
  else
    echo "linking $to"
  fi

  mkdir -p "$(dirname "$to")"
  case "$src" in
  /*) ;;
  *) src="$PWD/$src" ;;
  esac
  ln -s "$src" "$to"
}

main "$@"
