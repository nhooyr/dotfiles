#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")/.."

  ./ci/fmt.sh
  ./ci/lint.sh
}

main "$@"
