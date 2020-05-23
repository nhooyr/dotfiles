#!/bin/sh
set -eu

main() {
  # Install homebrew.
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

  # Enable touchid sudo.
  sudo sh -c "cat > /etc/pam.d/sudo" <<EOF
auth sufficient pam_tid.so
$(cat /etc/pam.d/sudo)
EOF

  brew cask install \
    alfred \
    spotify \
    bettertouchtool \
    docker \
    parallels
}

main "$@"
