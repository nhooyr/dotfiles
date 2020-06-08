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

  rsx "$PWD"
  if [[ "$#" -gt 0 ]]; then
    x "$@"
  fi
)}

rsx() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --no-ignore)
        local NO_IGNORE=1
        ;;
      -*)
        echoerr "Unknown flag $1"
        return 1
        ;;
    esac

    shift
  done

  local local_path="$(realpath "${1-$PWD}")"
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

  local local_sha="$(git -C "$local_path" rev-parse HEAD 2> /dev/null)"
  if [[ ! "$local_sha" || "${NO_IGNORE-}" ]]; then
    rs --delete "$local_path/" "$REMOTE_HOST:$remote_path/"
    return
  fi

  local remote_sha="$(xssh git -C "$remote_path" rev-parse HEAD 2> /dev/null)"

  if [[ "$remote_sha" != "$local_sha" ]]; then
    xssh git init -q "$remote_path"
    git push -q "ssh://$REMOTE_HOST/~/$remote_path" "${local_sha}:refs/heads/xrs"
    xssh git -C "$remote_path" checkout -qf "$local_sha"
  fi

  # Sync all untracked and modified files.
  local local_files="$(mktemp)"
  # Both -m and -c are required here as when a modified file is staged, it only shows up with -c.
  # This does mean we get all the files in the index but that's no big deal.
  git -C "$local_path" ls-files --exclude-standard -mco | filter_duplicates > "$local_files"
  rs "--files-from=$local_files" "$local_path/" "$REMOTE_HOST:$remote_path/"

  # Sync deletions.
  local remote_files="$(mktemp)"
  xssh git -C "$remote_path" ls-files --exclude-standard -mco | filter_duplicates > "$remote_files"

  # These files exist on only the remote end as we just synced local.
  # Therefore they must be deleted.
  local unique_files=("${(@f)$(cat "$local_files" "$remote_files" | sort | uniq -u)}")
  if [[ "${#unique_files[@]}" -gt 0 ]]; then
    xssh "git -C $remote_path rm -qf ${unique_files[*]} 2>/dev/null || true"
    xssh "cd $remote_path && rm -f ${unique_files[*]} || true"
  fi
}

rsi() {(
  set -euo pipefail

  local local_path="$(realpath "$1")"
  local remote_path="${local_path#$HOME/}"
  if xssh [ -f "$remote_path" ]; then
    rs "$local_path" "$REMOTE_HOST:$remote_path"
  else
    rs --delete "$local_path/" "$REMOTE_HOST:$remote_path/"
  fi
)}
