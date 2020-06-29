#!/bin/sh
set -eu

main() {
  tmux_sessions="$(tmux ls 2> /dev/null || true)"
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
  one_hour=$((60 * 60))
  echo "now       = $(date -d "@$now")"
  echo "last_login = $(date -d "@$last_login")"
  if [ $((now - last_login)) -lt $one_hour ]; then
    echo "keeping system up"
    exit 0
  fi

  echo "powering off"
  poweroff
}

main "$@"
