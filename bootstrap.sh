#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")"

  git submodule update --init

  # Install homebrew.
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

  # Enable touchid sudo.
  sudo sh -c "cat > /etc/pam.d/sudo" << EOF
auth sufficient pam_tid.so
$(cat /etc/pam.d/sudo)
EOF

  brew install \
    emacs \
    gnupg \
    go \
    node \
    yarn \
    shellcheck \
    shfmt

  brew cask install \
    alfred \
    spotify \
    bettertouchtool \
    docker \
    parallels \
    google-chrome \
    firefox
}

main "$@"
