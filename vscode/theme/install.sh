#!/bin/sh
set -eu

help() {
	printf 'Usage: %s [-f]\n' "${0##*/}"
}

force=
case "$*" in
'') ;;
-f | --force) force=true ;;
-h | --help)
	help
	exit 0
	;;
*)
	help >&2
	exit 1
	;;
esac

cd -- "$(dirname "$0")"
publisher=$(jq -r .publisher ./package.json)
name=$(jq -r .name ./package.json)
version=$(jq -r .version ./package.json)
if [ "$force" != true ] && code --list-extensions --show-versions | grep -qFx "$publisher.$name@$version"; then
	printf 'dotfiles: vscode/theme: %s: Already installed %s.%s@%s: Run with -f to force update.\n' "${0##*/}" "$publisher" "$name" "$version" >&2
	exit 0
fi
if grep -qFx 'version https://git-lfs.github.com/spec/v1' ./icon.jpg; then
	printf 'dotfiles: vscode/theme: %s: Run git lfs pull to download icon.jpg.\n' "${0##*/}" >&2
	exit 1
fi
if output=$(
	NO_COLOR=1 vsce package 2>&1 &&
		NODE_NO_WARNINGS=1 code ${force:+--force} --install-extension "./$name-$version.vsix" 2>&1
); then
	printf 'dotfiles: vscode/theme: %s: Installed %s.%s@%s\n' "${0##*/}" "$publisher" "$name" "$version"
else
	result=$?
	printf '%s\n' "$output" >&2
	exit "$result"
fi
