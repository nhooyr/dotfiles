#!/usr/bin/env bash

set -euo pipefail

ensure_fmt() {
  local files
  mapfile -t files < <(git ls-files --other --modified --exclude-standard)
  if [[ ${files[*]} == "" ]]; then
    return
  fi

  echo "Files need generation or are formatted incorrectly:"
  for f in "${files[@]}"; do
    echo "  $f"
  done

  echo
  echo "Please run the following locally:"
  echo "  make fmt"
  exit 1
}

main() {
  local fishFiles
  mapfile -t fishFiles < <(git ls-files "*.fish")
  fish_indent -w "${fishFiles[@]}"

  local shellFiles
  mapfile -t shellFiles < <(git ls-files "*.sh")
  shfmt -i 2 -w -s -sr "${shellFiles[@]}"
  shellcheck $"${shellFiles[@]}"

  if [[ ${CI-} ]]; then
    ensure_fmt
  fi
}

main "$@"
