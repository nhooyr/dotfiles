#!/bin/sh
set -eu

main() {
  src="$1"
  to="$2"

  if [ -f "$to" ]; then
    echo "overwriting $to"
  elif [ -e "$to" ]; then
    echo "$to exists and is not a file"
    exit 1
  else
    echo "copying to $to"
  fi

  tmp="$(mktemp)"
  cp "$src" "$tmp"

  mkdir -p "$(dirname "$to")"
  mv "$tmp" "$to"
}

main "$@"
