all: ensure fmt lint

.SILENT:

ensure: ensure-root
ifeq ($(shell uname), Darwin)
ensure: ensure-macos
endif
ifdef REMOTE
ensure: ensure-remote
endif
	./link.sh git ~/.config/git
	./link.sh nvim ~/.config/nvim
	./link.sh fish ~/.config/fish
	./link.sh mutagen/mutagen.yml ~/.mutagen.yml
	./link.sh fd/fdignore ~/.fdignore
	./link.sh gnupg ~/.gnupg

ensure-macos:
	./link.sh macos/gpg-agent.conf ~/.gnupg/gpg-agent.conf

ensure-remote:
	sudo cp remote/green.sh /usr/local/bin/green.sh
	sudo cp remote/green.timer /etc/systemd/system/green.timer
	sudo cp remote/green.service /etc/systemd/system/green.service

ensure-root:
	sudo ./link.sh ~/.config ~root/.config
	sudo ./link.sh ~/.local ~root/.local
	sudo ./link.sh ~/src ~root/src

fmt: fish_indent shfmt
ifdef CI
	./ci/ensure_fmt.sh
endif

lint: shellcheck

fish_indent:
	fish_indent -w $$(git ls-files "*.sh")

shfmt:
	shfmt -i 2 -w -s -sr $$(git ls-files "*.sh")

shellcheck:
	shellcheck $$(git ls-files "*.sh")
