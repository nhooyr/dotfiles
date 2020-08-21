source_if_exists() {
  if [[ -f "$1" ]]; then
    source "$@"  
    return 0
  fi
  return 1
}

prepend_path() {
  local var="$1"
  local p="$2"

  if [[ ! "${(P)var}" ]]; then
    eval "$var=$p"
    return
  fi

  if [[ "${(P)var}" != *$p* ]]; then
    eval "$var=$p:${(P)var}"
  fi
}

prepend_PATH() {
  prepend_path PATH "$@"
}

command_exists() {
  command -v "$@" > /dev/null
}

echo_on_failure() {
  if ! out=$("$@" 2>&1); then
    echo "$out" >&2
    return 1
  fi
}

filter_duplicates() {
  awk '!seen[$0]++'
}

echoerr() {
  echo "$@" >&2
}

if [[ -f /etc/os-release ]]; then
  DISTRO="$(. /etc/os-release && echo "$ID")"
fi

quote_args() {
  local args=""
  for a in "$@"; do
    if [ ! "${ESCAPE_ALL_ARGS-}" ]; then
      case "$a" in
        "&&")
          args+=" &&"
          continue
          ;;
        "||")
          args+=" ||"
          continue
          ;;
        ")")
          args+=" )"
          continue
          ;;
        "(")
          args+=" ("
          continue
          ;;
      esac
    fi

    args+=" ${(q)a}"
  done

  echo "$args"
}

run_quoted() {
  args="$(quote_args "$@")"
  # ESCAPE_ALL_ARGS is used when there are two nested shells.
  # e.g. noti and t in aliases.zsh.
  #
  # The first shell must escape everything and the second must not
  # escape certain symbols whitelisted above.
  unset ESCAPE_ALL_ARGS
  eval "$args"
}
