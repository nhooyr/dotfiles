#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")/.."

  shellcheck --exclude=SC2046 $(git ls-files "*.sh")
}

main "$@"
