#!/usr/bin/env bash

set -euo pipefail

main() {
  declare -A ports
  for listenPort in $(x ss -ltn --no-header | awk '{split($4, a, ":"); print a[length(a)]}' | sort -u); do
    ports[$listenPort]="$listenPort"
  done

  unset ports["22"]
  unset ports["2424"]

  declare -A activeForwarders
  mapfile -t lines < <(pgrep -l -f 'ssh -NT -L .* xayah-unshared' | awk '{split($5, a, ":"); printf("%s %s\n", a[1], $1)}')
  for line in "${lines[@]}"; do
    read -r -a fields <<< "$line"
    activeForwarders[${fields[0]}]="${fields[1]}"
  done

  for port in "${ports[@]}"; do
    if [[ ${activeForwarders[$port]:-} ]]; then
      unset activeForwarders["$port"]
      continue
    fi

    echo "spawning forwarding for $port"

    local localPortUser
    localPortUser=$(netstat -vanp tcp | grep LISTEN | grep "$port") || true
    if [[ $localPortUser ]]; then
      echo "conflict: $port in use locally as well by $$localPortUser"
      continue
    fi

    ssh -NT -L "$port:localhost:$port" xayah-unshared &
    disown
  done

  for port in "${!activeForwarders[@]}"; do
    echo "terminating forwarding for $port"
    kill "${activeForwarders[$port]}"
  done
}

main "$@"
