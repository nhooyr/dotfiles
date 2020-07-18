#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")/.."

  doctoc --notitle macos/INSTALL.md

  ignore_file="$(mktemp)"
  git config --file .gitmodules --get-regexp "path" | awk '{ print $2 }' > "$ignore_file"
  git ls-files -io --exclude-standard --directory >> "$ignore_file"
  prettier \
    --write \
    --print-width=120 \
    --no-semi \
    --trailing-comma=all \
    --no-bracket-spacing \
    --arrow-parens=avoid \
    "--ignore-path=$ignore_file" \
    . || true

  files="$(shfmt -f $(git ls-files))"
  if [ -s "$ignore_file" ]; then
    files="$(echo "$files" | grep -Fvf "$ignore_file" || true)"
  fi
  shfmt -i 2 -w -s -sr $files

  if [ "${CI-}" ]; then
    ensure_fmt
  fi
}

ensure_fmt() {
  changed_files="$(git ls-files --other --modified --exclude-standard)"
  if [ ! "$changed_files" ]; then
    return
  fi

  echo "$changed_files" | sed "s/^/~ /"
  echo

  git -c color.ui=always --no-pager diff
  echo

  echo "Please run:"
  echo "./ci/fmt.sh"
  exit 1
}

main "$@"
