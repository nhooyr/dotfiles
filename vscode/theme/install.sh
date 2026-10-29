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

cd "$(dirname "$0")"
publisher=$(jq -r .publisher ./package.json)
name=$(jq -r .name ./package.json)
version=$(jq -r .version ./package.json)
if [ "$force" != true ] && code --list-extensions --show-versions | grep -qFx "$publisher.$name@$version"; then
	printf '%s: Already installed %s.%s@%s: Run with -f to force update.\n' "${0##*/}" "$publisher" "$name" "$version" >&2
	exit 0
fi
rm -f -- ./*.vsix
NO_COLOR=1 vsce package
code ${force:+--force} --install-extension "./$name-$version.vsix"
