#!/bin/sh
set -eu

cd "$(dirname "$0")"
publisher=$(jq -r .publisher ./package.json)
name=$(jq -r .name ./package.json)
version=$(jq -r .version ./package.json)
if test "$*" != '-f' && code --list-extensions --show-versions | grep -qF "$publisher.$name@$version"; then
	echo "vscode/theme: Already installed $publisher.$name@$version" >&2
	echo "vscode/theme: Run install.sh with -f to force update." >&2
	exit 0
fi
rm ./*.vsix || true
vsce package
code --install-extension "./$name-$version.vsix"
