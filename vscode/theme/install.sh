#!/bin/sh
set -eu

help() {
	echo "Usage: $0 [-f]"
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
	echo "$(basename "$0"): Already installed $publisher.$name@$version" >&2
	echo "$(basename "$0"): Run with -f to force update." >&2
	exit 0
fi
rm -f ./*.vsix
vsce package
code ${force:+--force} --install-extension "./$name-$version.vsix"
