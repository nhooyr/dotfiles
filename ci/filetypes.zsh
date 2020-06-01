#!/bin/zsh
set -euo pipefail

# It'd be nice to have proper icons at some point.
# Maybe I should write a proper macOS app instead of using
# Automator.
main() {
  local utis=(
    "public.plain-text"
    "public.shell-script"
    "public.zsh-script"
    "net.daringfireball.markdown"
    "public.json"
    "public.mpeg-2-transport-stream"
    "com.netscape.javascript-source"
  )
  local uti
  for uti in "${utis[@]}"; do
    duti -s com.apple.automator.Editor "$uti" all
  done
}

main "$@"
