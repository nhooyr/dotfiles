#!/bin/sh
set -eu

main() {
  # Install homebrew.
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  
  # Enable passwordless sudo.
  sudo sh -c "cat > /etc/sudoers.d/passwordless" <<EOF
%admin    ALL = (ALL) NOPASSWD: ALL
EOF
}

main "$@"
