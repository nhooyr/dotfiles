prompt() {
  echo -n "%(0?..⭕
)"

  echo -n "%B"

  if [[ "$USER" != "nhooyr" ]]; then
    local user=1
    if [[ $USER == "root" ]]; then
      echo -n "%F{red}"
    else
      echo -n "%F{yellow}"
    fi
    echo -n "%n%f"
  fi

  if [[ $HOST != ien* ]]; then
    local host=1
    if [[ $user ]]; then
      echo -n "@"
    fi
    echo -n "%F{green}%m%f"
  fi

  if [[ $user || $host ]]; then
    echo -n ":"
  fi

  echo -n "%~"

  local branch_name="$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"
  if [[ "$branch_name" ]]; then
    echo -n "%F{blue}:$branch_name%f"
  fi
  if [[ "$(git status --short 2> /dev/null)" ]]; then
    echo -n "*"
  fi

  echo
  if [[ $USER == root ]]; then
    echo -n "%F{red}"
  fi
  echo -n "%(!.#.$)%f%b "
}

branch_name() {
  local branch_name
  branch_name="$(git rev-parse --abbrev-ref HEAD)" || return 1
  echo ":$branch_name"
}

setopt PROMPT_SUBST
PROMPT='$(prompt)'
