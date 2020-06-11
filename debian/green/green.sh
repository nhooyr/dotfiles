#!/usr/bin/env bash

set -euo pipefail

main() {
  local activeUsers
  activeUsers="$(who | grep -E '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})')" || true
  if [[ ${activeUsers-} ]]; then
    echo "remote users logged in:"
    echo "$activeUsers"
    exit 0
  fi

  local now
  local lastLogin
  local oneHour
  now="$(date +%s)"
  lastLogin="$(stat -c %Y /var/log/wtmp)"
  oneHour=$((60 * 60))
  echo "now       = $(date -d "@$now")"
  echo "lastLogin = $(date -d "@$lastLogin")"
  if [[ $((now - lastLogin)) -lt $oneHour ]]; then
    echo "keeping system up"
    exit 0
  fi

  echo "powering off"
  poweroff
}

main "$@"
