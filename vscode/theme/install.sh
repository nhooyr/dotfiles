#!/bin/sh
set -eu

cd "$(dirname "$0")"
publisher=$(jq -r .publisher ./package.json)
name=$(jq -r .name ./package.json)
version=$(jq -r .version ./package.json)
if code --list-extensions --show-versions | grep -qF "$publisher.$name@$version"; then
	exit 0
fi
rm ./*.vsix
vsce package
code --install-extension "./$name-$version.vsix"
