#!/bin/sh
set -eu

case "$*" in
'') ;;
-h | --help)
	printf 'Usage: %s\nInstall Fish 4.9.3 and fish_indent for Linux x86_64 CI.\n' "${0##*/}"
	exit 0
	;;
*)
	printf 'Usage: %s\n' "${0##*/}" >&2
	exit 2
	;;
esac

directory=$(mktemp -d)
trap 'rm -rf "$directory"' 0
curl --fail --location --silent --show-error --output "$directory/fish.tar.xz" \
	https://github.com/fish-shell/fish-shell/releases/download/4.9.3/fish-4.9.3-linux-x86_64.tar.xz
tar -xf "$directory/fish.tar.xz" -C "$directory"
# The standalone binary also runs as fish_indent when invoked with that name.
for name in fish fish_indent; do
	sudo install "$directory/fish" "/usr/local/bin/$name"
done
