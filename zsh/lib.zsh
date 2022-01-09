source_if_exists() {
  if [[ -f "$1" ]]; then
    source "$@"
    return 0
  fi
  return 1
}

append_PATH() {
  if [[ "$PATH" != *$1* ]]; then
    PATH="$PATH:$1"
  fi
}

# - 2021-01-09,07:26:24am: edit: so much over engineering dude jesus christ what was I thinking
# Look at how much simpler it is to specialize instead of deduplicate in append_PATH.
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


  if [[ "$p" == /usr/local/* ]]; then
    # For ARM macOS
    prepend_path "$var" "${p/#\/usr\/local//opt/homebrew}"
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

# TODO REMOVE THIS, idt a good idea
quote_args() {
  local args=""
  for a in "$@"; do
    if [ ! "${ESCAPE_ALL_ARGS-}" ]; then
      case "$a" in
        "&&"|"||"|")"|"("|";"|"|"|"!")
          args+=" $a"
          continue
          ;;
        "$"*)
          args+=" $a"
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
