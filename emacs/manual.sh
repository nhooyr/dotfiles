#!/bin/sh
set -eu

case $1 in
  enc)
    gpg --yes --armor --symmetric --cipher-algo AES256 --pinentry-mode loopback --passphrase "$2" --output manual.txt .manual.txt
    ;;
  dec)
    gpg --quiet --yes --armor --decrypt --pinentry-mode loopback --passphrase "$2" --output .manual.txt manual.txt
    ;;
  *)
    echo "second argument must be enc or dec"
    exit 1
    ;;
esac
