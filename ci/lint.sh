#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")/.."

  shellcheck -e SC2046,SC1091,SC2086 $(git ls-files "*.sh")
}

main "$@"
