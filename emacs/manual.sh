#!/bin/sh
set -eu
cd -- "$(dirname "$0")"

case $1 in
  enc)
    gpg --yes --armor --symmetric --cipher-algo AES256 --pinentry-mode loopback --passphrase "$2" --output - .manual.txt | base64 > manual.txt
    ;;
  dec)
    base64 --decode -i manual.txt | gpg --quiet --yes --armor --decrypt --pinentry-mode loopback --passphrase "$2" --output .manual.txt -
    ;;
  *)
    echo "second argument must be enc or dec"
    exit 1
    ;;
esac
