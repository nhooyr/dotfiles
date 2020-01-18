all: ensure fmt

.SILENT:

.PHONY: *

.ONESHELL:
SHELL = bash
.SHELLFLAGS = -ceuo pipefail

HOSTNAME := $(shell hostname -s)
ifeq ($(HOSTNAME), ien)
ensure: ensure-ien
else ifeq ($(HOSTNAME), xayah)
ensure: ensure-xayah
endif
ensure: ensure-root
	$(MAKE) link SRC=git TO=~/.config/git
	$(MAKE) link SRC=nvim TO=~/.config/nvim
	$(MAKE) link SRC=fish TO=~/.config/fish
	$(MAKE) link SRC=mutagen/mutagen.yml TO=~/.mutagen.yml
	$(MAKE) link SRC=fd/fdignore TO=~/.fdignore

ensure-ien:
	$(MAKE) link SRC=ien/gpg-agent.conf TO=~/.gnupg/gpg-agent.conf

ensure-xayah:
	sudo cp xayah/green.timer /etc/systemd/system/green.timer
	sudo cp xayah/green.service /etc/systemd/system/green.service

ensure-root:
	sudo $(MAKE) link SRC=~/.config TO=~root/.config
	sudo $(MAKE) link SRC=~/.local TO=~root/.local
	sudo $(MAKE) link SRC=~/src TO=~root/src

link:
	if [[ -L $$TO ]]; then
	  echo "overwriting $$TO"
	  rm "$$TO"
	elif [[ -e $$TO ]]; then
	  echo "$$TO exists and is not a symlink"
	  exit 1
	else
		echo "linking $$TO"
	fi
	mkdir -p "$$(dirname "$$TO")"
	ln -s "$$(realpath "$$SRC")" "$$TO"

fmt: prettier fish_indent shfmt
ifdef CI
	if [[ $$(git ls-files --other --modified --exclude-standard) != "" ]]; then
	  echo "Files need generation or are formatted incorrectly:"
	  git -c color.ui=always status | grep --color=no '\[31m'
	  echo "Please run the following locally:"
	  echo "  make fmt"
	  exit 1
	fi
endif

prettier:
	prettier --write --print-width=120 --no-semi --trailing-comma=all --loglevel=warn $$(git ls-files "*.yml" "*.md" "*.js")

fish_indent:
	git ls-files "*.fish" | xargs -I{} fish_indent -w {}

shfmt:
	shfmt -i 2 -w -s -sr .

ci-image:
	docker build -f .github/workflows/Dockerfile -t nhooyr/dotfiles-ci .
	docker push nhooyr/dotfiles-ci
