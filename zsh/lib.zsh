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
