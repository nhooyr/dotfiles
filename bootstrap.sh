#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")"

  if [ ! -d ../secrets ]; then
     git clone https://github.com/nhooyr/secrets ../secrets
  fi

  # Install homebrew.
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

  # Enable touchid sudo.
  sudo sh -c "cat > /etc/pam.d/sudo" << EOF
auth sufficient pam_tid.so
$(cat /etc/pam.d/sudo)
EOF

  brew install emacs gnupg

  brew cask install \
    alfred \
    spotify \
    bettertouchtool \
    docker \
    parallels
}

main "$@"
