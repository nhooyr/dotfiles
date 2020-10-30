#!/bin/sh
set -eu

main() {
  tmux_sessions="$(tmux -S /tmp/tmux ls 2> /dev/null || true)"
  if [ "$tmux_sessions" ]; then
    echo "tmux sessions active:"
    echo "$tmux_sessions"
    exit 0
  fi

  active_users="$(who | grep -E '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})' || true)"
  if [ "$active_users" ]; then
    echo "remote users logged in:"
    echo "$active_users"
    exit 0
  fi

  now="$(date +%s)"
  last_login="$(stat -c %Y /var/log/wtmp)"
  timeout=$((60 * 60 * 2)) # 2 hours
  echo "now       = $(date -d "@$now")"
  echo "last_login = $(date -d "@$last_login")"
  if [ $((now - last_login)) -lt $timeout ]; then
    echo "keeping system up"
    exit 0
  fi

  echo "powering off"
  poweroff
}

main "$@"
