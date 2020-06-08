GCP_ZONE="--zone=northamerica-northeast1-a"

xgcloud() {
  gcloud --configuration=nhooyr-coder "$@"
}

xcreate() {(
  set -euo pipefail

  if [[ "$REMOTE_HOST" == "xayah" ]]; then
    set -- \
      --address=xayah \
      --private-network-ip=xayah-internal \
      "$@"
  fi
  xgcloud compute instances create "$REMOTE_HOST" \
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

  sed -i.bak "/^${REMOTE_HOST}[, ]/d" ~/.ssh/known_hosts

  local i
  for i in {1..10}; do
    if ! ssh "$REMOTE_HOST" true; then
      sleep 1
      continue
    fi
    ssh "$REMOTE_HOST" sh < ~dotfiles/debian/init.sh
    sshq "$REMOTE_HOST"
    return
  done

  false
)}

xdelete() {
  xgcloud compute instances delete "$GCP_ZONE" "$REMOTE_HOST"
}

xstart() {
  if [[ "$REMOTE_HOST" == "xayah" ]]; then
    echo_on_failure xgcloud compute instances start "$GCP_ZONE" "$REMOTE_HOST"
  fi
}

xstop() {
  ssh "$REMOTE_HOST" sudo poweroff
}

x() {(
  set -euo pipefail
  setopt +o NOMATCH
  if ! ls ~/.ssh/sockets/*@$REMOTE_HOST &> /dev/null; then
    local vm_status="$(xgcloud compute instances describe "$GCP_ZONE" "$REMOTE_HOST" --format=json | jq -r .status)"
    if [[ "$vm_status" != "RUNNING" ]]; then
      echo "$REMOTE_HOST: $vm_status"
      xstart
    fi
  fi

  if [[ $# -gt 0 ]]; then
    local argv="-c '$*'"
  fi
  ssh -t "$REMOTE_HOST" "cd ./${PWD#$HOME} 2> /dev/null; \$SHELL -li $argv"
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

  local success_msg="$(print -P "%B%F{green}=%f%b")"
  ssh \
    -oControlPath=none \
    -L "$local_port:$local_host:$remote_port" \
    "$REMOTE_HOST" \
    "echo '$success_msg' && cat > /dev/null"
)}

xrs() {(
  set -euo pipefail

  local sync_path="${1-$PWD}"

  if [[ ! -e "$sync_path" ]]; then
    echo "cannot sync nonexistent path" >&2
    return 1
  fi

  if [[ "$sync_path" != /* ]]; then
    local abs_path="$PWD/$sync_path"
  else
    local abs_path="$sync_path"
  fi
  if [[ "$abs_path" != $HOME/* ]]; then
    echo "cannot sync path not in ~" >&2
    return 1
  fi
  local rel_path="${abs_path#$HOME/}"

  local remote_sha="$(ssh "$REMOTE_HOST" sh -s -- <<EOF
  set -eu
  mkdir -p "$rel_path"
  git -C "$rel_path" rev-parse HEAD 2> /dev/null
EOF
)"

  if [[ -f "$sync_path" ]]; then
    rs "$sync_path" "$REMOTE_HOST:$rel_path"
    return
  fi
  if [[ ! -d "$sync_path" ]]; then
    echo "can only sync a file or directory" >&2
    return 1
  fi

  # We're syncing a directory.
  local local_sha="$(git -C "$sync_path" rev-parse HEAD 2> /dev/null)"

  # No git, we have to sync everything.
  if [[ ! "$local_sha" ]]; then
    rs --delete "$sync_path/" "$REMOTE_HOST:$rel_path/"
    return
  fi
  
  set -x

  # We have git available, we sync only what's changed.
  # If the commits are different we push and check it out remotely.
  if [[ "$remote_sha" != "$local_sha" ]]; then
    # Make sure repo exists remotely.
    ssh "$REMOTE_HOST" "mkdir -p \"$rel_path\" && cd \"$rel_path\" && git init -q"
    git push "ssh://$REMOTE_HOST/~/$rel_path" "${local_sha}:refs/heads/xrs"
    ssh "$REMOTE_HOST" "cd \"$rel_path\" && git checkout -f $local_sha"
    ssh "$REMOTE_HOST" "cd \"$rel_path\" && git submodule update -f --init"
  fi

  local untracked_files="$(mktemp)"
  local modified_files="$(mktemp)"
  local modified_staged_files="$(mktemp)"
  git -C "$sync_path" ls-files --exclude-standard -o > "$files_from"
  git -C "$sync_path" diff --name-only >> "$files_from"
  #git -C "$sync_path" diff --name-only --cached >> "$files_from"
  if [[ ! -s "$files_from" ]]; then
    # Nothing to sync.
    return
  fi
  cat "$files_from"
  rs --delete \
    "--files-from=$files_from" \
    "--files-from=$files_from" \
    "$sync_path/" "$REMOTE_HOST:$rel_path/"
)}

xor_files() {
  local first="$1"
  local second="$2"
  local dst="$3"

  cat "$first" "$second" | sort | uniq -u > "$dst.incomplete"
  mv "$dst.incomplete" "$dst"
}

xsr() {
}
