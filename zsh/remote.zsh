GCP_ZONE="--zone=northamerica-northeast1-a"

xgcloud() {
  gcloud --configuration=nhooyr-coder "$@"
}

remote_instance() {
  echo "${REMOTE_HOST#*@}"
}

xssh() {
  ssh "$REMOTE_HOST" "$@"
}

xsshq() {
  sshq "$REMOTE_HOST" "$@"
}

xcreate() {(
  set -euo pipefail

  if [[ "$(remote_instance)" == "xayah" ]]; then
    set -- \
      --address=xayah \
      --private-network-ip=xayah-internal \
      "$@"
  fi
  xgcloud compute instances create "$(remote_instance)" \
    "$GCP_ZONE" \
    --machine-type=e2-custom-8-16384 \
    --subnet=main \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --image=debian-sid-v20190812 \
    --image-project=debian-cloud-testing \
    --boot-disk-size=128GB \
    --boot-disk-type=pd-ssd \
    "$@"
)}

xinit() {(
  set -euo pipefail

  sed -i.bak "/^$(remote_instance)[, ]/d" ~/.ssh/known_hosts

  local i
  for i in {1..10}; do
    if ! xssh true; then
      sleep 1
      continue
    fi
    xssh sh < ~dotfiles/debian/init.sh
    xsshq
    return
  done

  false
)}

xdelete() {
  xgcloud compute instances delete "$GCP_ZONE" "$(remote_instance)"
}

xstart() {
  echo_on_failure xgcloud compute instances start "$GCP_ZONE" "$(remote_instance)"
}

xstop() {
  xssh sudo poweroff
}

x() {(
  set -euo pipefail
  setopt +o NOMATCH
  if ! ls ~/.ssh/sockets/*@$(remote_instance) &> /dev/null; then
    local vm_status="$(xgcloud compute instances describe "$GCP_ZONE" "$(remote_instance)" --format=json | jq -r .status)"
    if [[ "$vm_status" != "RUNNING" ]]; then
      echo "$(remote_instance): $vm_status"
      xstart
    fi
  fi

  if [[ $# -gt 0 ]]; then
    local args="-c '$*'"
  fi
  xssh -t "cd ./${PWD#$HOME} 2> /dev/null; \$SHELL -li ${args-}"
)}

xp() {(
  set -euo pipefail

  if [[ "$#" -ne 1 ]]; then
    echo "bad arguments"
    return 1
  fi

  local fields=("${(@s/:/)1}")
  local local_port="${fields[1]}"
  if [[ "${#fields[@]}" -eq 1 ]]; then
    local local_host="localhost"
    local remote_port="$local_port"
  elif [[ "${#fields[@]}" -eq 2 ]]; then
    local local_host="localhost"
    local remote_port="${fields[2]}"
  else
    local local_host="${fields[2]}"
    local remote_port="${fields[3]}"
  fi

  x true
  local success_msg="$(print -P "%B%F{green}=%f%b")"
  xssh \
    -oControlPath=none \
    -L "$local_port:$local_host:$remote_port" \
    "echo '$success_msg' && cat > /dev/null"
)}

xs() {(
  set -euo pipefail

  if [[ "$#" -eq 0 ]]; then
    set -- "$PWD"
  fi

  for local_path in "$@"; do
    local local_path="$(realpath "$local_path")"
    _xs "$local_path"
  done
)}

_xs() {
  local local_path="$1"
  local remote_path="${local_path#$HOME/}"

  if [[ ! -e "$local_path" ]]; then
    echo "${(q)local_path} does not exist" >&2
    return 1
  fi
  if [[ -f "$local_path" ]]; then
    rs "$local_path" "$REMOTE_HOST:$remote_path"
    return
  fi
  if [[ ! -d "$local_path" ]]; then
    echo "can only sync a file or directory" >&2
    return 1
  fi
  xssh mkdir -p "$remote_path"

  local rsync_args=()
  local git_dir="$(git -C "$local_path" rev-parse --show-toplevel 2> /dev/null)"
  if [[ "$git_dir" ]]; then
    local exclude_from="$(mktemp)"
    git_exclude_paths "$git_dir" | sed "s#^$local_path##" > "$exclude_from"
    rsync_args+=(
      "--exclude-from=$exclude_from"
    )
  fi

  rs --delete "${rsync_args[@]}" "$local_path/" "$REMOTE_HOST:$remote_path/"
}

git_exclude_paths() {
  local git_dir="$1"
  git -C "$git_dir" ls-files --exclude-standard -io --directory | sed "s#^#$git_dir/#"

  if [[ ! -f "$git_dir/.gitmodules" ]]; then
    return
  fi

  local submodules=(
    "${(@f)$(git config --file "$git_dir/.gitmodules" --get-regexp "path" | awk '{ print $2 }' | sed "s#^#$git_dir/#" )}"
  )
  for sub in "${submodules[@]}"; do
    if [[ "$sub" == "$local_path"* ]]; then
      git_exclude_paths "$sub"
    fi
  done
}

xi() {(
  set -euo pipefail

  if [[ "$#" -eq 0 ]]; then
    set -- "$PWD"
  fi

  for local_path in "$@"; do
    local local_path="$(realpath "$local_path")"
    _xi "$local_path"
  done
)}

_xi() {
  local local_path="$1"
  local remote_path="${local_path#$HOME/}"

  if xssh [ ! -e "$remote_path" ]; then
    echo "${(q)remote_path} does not exist" >&2
    return 1
  fi
  if xssh [ -f "$remote_path" ]; then
    rs "$REMOTE_HOST:$remote_path" "$local_path"
    return
  fi
  if xssh [ ! -d "$remote_path" ]; then
    echo "can only sync a file or directory" >&2
    return 1
  fi
  mkdir -p "$local_path"

  local rsync_args=()
  local git_dir="$(xssh git -C "$remote_path" rev-parse --show-toplevel 2> /dev/null)"
  if [[ "$git_dir" ]]; then
    local exclude_from="$(mktemp)"
    git_exclude_paths "$git_dir" | sed "s#^$remote_path##" > "$exclude_from"
    rsync_args+=(
      "--exclude-from=$exclude_from"
    )
  fi

  rs --update --delete "${rsync_args[@]}" "$REMOTE_HOST:$remote_path/" "$local_path/"
}
