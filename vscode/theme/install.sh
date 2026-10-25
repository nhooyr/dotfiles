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
if [ "$force" != true ] && code --list-extensions --show-versions | grep -qF "$publisher.$name@$version"; then
	echo "vscode/theme: Already installed $publisher.$name@$version" >&2
	echo "vscode/theme: Run $0 with -f to force update." >&2
	exit 0
fi
rm ./*.vsix || true
vsce package
code --install-extension "./$name-$version.vsix"
