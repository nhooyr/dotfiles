#!/bin/sh
set -eu

main() {
  export DEBIAN_FRONTEND=noninteractive

  sudo -E apt update
  sudo -E apt full-upgrade -y --purge
  sudo -E apt autoremove -y --purge
  sudo -E apt install -y \
    rsync \
    jq \
    build-essential \
    cmake \
    git \
    curl
  sudo git config --system credential.helper store

  install_dotfiles

  install_go
  install_node
  install_neovim
  install_docker
  install_locale
  install_gcloud
  install_misc

  # Allows searching through the package database.
  sudo -E apt-file update
}

install_node() {
  sudo apt-get install -y npm

  sudo npm install -g yarn
  yarn config set prefix ~/.local
  yarn global add \
    vim-language-server \
    typescript \
    typescript-language-server \
    prettier \
    doctoc
}

install_go() {
  sudo -E apt install -y golang

  export GOPATH="$HOME/.local/share/gopath"
  export GO111MODULE=on
  go get golang.org/x/tools/gopls@latest
  go get mvdan.cc/sh/v3/cmd/shfmt@latest
  go get golang.org/x/tools/cmd/goimports@latest
  go get golang.org/x/tools/cmd/stringer@latest
  go get golang.org/x/lint/golint@latest
  go get github.com/agnivade/wasmbrowsertest@latest
  go get github.com/mikefarah/yq/v3
}

install_docker() {
  sudo -E apt install -y docker.io
  sudo groupadd -f docker
  sudo usermod -aG docker "$USER"
  newgrp docker
}

install_dotfiles() {
  sudo -E apt install -y \
    zsh \
    fzf \
    fd-find
  if [ ! -d ~/src/nhooyr/dotfiles ]; then
    mkdir -p ~/src/nhooyr
    git clone --recurse-submodules https://github.com/nhooyr/dotfiles ~/src/nhooyr/dotfiles
  fi
  ~/src/nhooyr/dotfiles/ensure.sh
  sudo chsh -s "$(command -v zsh)" "$USER"
}

install_neovim() {
  sudo -E apt install -y python3-neovim
  # https://github.com/neovim/neovim/wiki/Building-Neovim
  sudo -E apt install -y ninja-build \
    gettext \
    libtool \
    libtool-bin \
    autoconf \
    automake \
    cmake \
    g++ \
    pkg-config \
    unzip
  if [ ! -d ~/src/neovim/neovim ]; then
    mkdir -p ~/src/neovim
    git clone -b nhooyr https://github.com/nhooyr/neovim ~/src/neovim/neovim
  fi
  cd ~/src/neovim/neovim
  make CMAKE_BUILD_TYPE=RelWithDebInfo
  sudo make install
  cd -
}

install_misc() {
  sudo -E apt install -y \
    shellcheck \
    ripgrep \
    htop \
    tmux \
    apt-file \
    apparmor-utils \
    kubectl
  # Exits with non-zero if already disabled.
  sudo -E aa-disable /etc/apparmor.d/usr.bin.man || true
}

install_locale() {
  sudo -E apt install -y locales
  sudo -E sed -i "s/# en_CA.UTF-8/en_CA.UTF-8/" /etc/locale.gen
  sudo -E locale-gen
  sudo -E update-locale LANG=en_CA.UTF-8
}

install_gcloud() {
  if [ ! -f /etc/apt/sources.list.d/google-cloud-sdk.list ]; then
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg]" \
      " https://packages.cloud.google.com/apt cloud-sdk main" \
      | sudo -E tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  fi
  sudo -E apt install -y apt-transport-https
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo -E apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
  sudo -E apt update
  sudo -E apt install -y google-cloud-sdk

  # Install helm.
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3)"
}

main "$@"
