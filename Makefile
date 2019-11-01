all: ensure fmt

.SILENT:

.PHONY: *

.ONESHELL:
SHELL = bash
.SHELLFLAGS = -ceuo pipefail

fmt: prettier fish_indent shfmt
ifdef CI
	if [[ $$(git ls-files --other --modified --exclude-standard) != "" ]]; then
	  echo "Files need generation or are formatted incorrectly:"
	  git -c color.ui=always status | grep --color=no '\e\[31m'
	  echo "Please run the following locally:"
	  echo "  make fmt"
	  exit 1
	fi
endif

prettier:
	prettier --write --print-width=120 --no-semi --trailing-comma=all --loglevel=warn $$(git ls-files "*.yml" "*.md")

fish_indent:
	git ls-files "*.fish" | xargs -I{} fish_indent -w {}

shfmt:
	shfmt -i 2 -w -s -sr .

ifeq ($(shell hostname), ien)
ensure: ien
else ifeq ($(shell hostname), xayah)
ensure: xayah
endif
ensure:
	$(MAKE) link SRC=git TO=~/.config/git
	$(MAKE) link SRC=nvim TO=~/.config/nvim
	$(MAKE) link SRC=fish TO=~/.config/fish
	$(MAKE) link SRC=mutagen/mutagen.yml TO=~/.mutagen.yml
	$(MAKE) link SRC=fd/fdignore TO=~/.fdignore

ien:
	$(MAKE) link SRC=ien/gpg-agent.conf TO=~/.gnupg/gpg-agent.conf

xayah:
	sudo cp xayah/green.timer /etc/systemd/system/green.timer
	sudo cp xayah/green.service /etc/systemd/system/green.service

link:
	if [[ -L $$TO ]]; then
	  echo "overwriting $$TO"
	elif [[ -e $$TO ]]; then
	  echo "$$TO exists and is not a symlink"
	  exit 1
	fi
	rm "$$TO"
	ln -s "$$PWD/$$SRC" "$$TO"

