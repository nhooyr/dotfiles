#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")/.."

  npx prettier \
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
  if [ "$(git ls-files --other --modified --exclude-standard)" ]; then
    git -c color.ui=always --no-pager diff
    echo
    echo "Please run the following locally:"
    echo "  ./ci/fmt.sh"
    exit 1
  fi
}

main "$@"
