#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")"

  git submodule update --init

  # Install homebrew.
  PATH="$PATH:/opt/homebrew/bin"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

  # Enable touchid sudo.
  sudo sh -c "cat > /etc/pam.d/sudo" << EOF
auth sufficient pam_tid.so
$(cat /etc/pam.d/sudo)
EOF

  brew install neovim --HEAD
  brew install \
    gnupg \
    go \
    node \
    yarn \
    shellcheck \
    shfmt \
    duti \
    coreutils \
    google-cloud-sdk

  brew install \
    alfred \
    spotify \
    bettertouchtool \
    docker \
    parallels \
    google-chrome \
    firefox \
    slack
}

main "$@"
