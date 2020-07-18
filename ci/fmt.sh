#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")/.."

  doctoc --title '# INSTALL' macos/INSTALL.md
  prettier \
    --write \
    --print-width=120 \
    --no-semi \
    --trailing-comma=all \
    --loglevel=warn \
    --arrow-parens=avoid \
    $(git ls-files "*.yml" "*.md" "*.js" "*.css" "*.html")
  shfmt -i 2 -w -s -sr $(git ls-files "*.sh")

  if [ "${CI-}" ]; then
    ensure_fmt
  fi
}

ensure_fmt() {
  # In case there's an untracked file.
  git add -A

  diff="$(git -c color.ui=always --no-pager diff)"
  if [ ! "$diff" ]; then
    return
  fi

  echo "$diff"
  echo
  echo "Please run:"
  echo "./ci/fmt.sh"
  exit 1
}

main "$@"
