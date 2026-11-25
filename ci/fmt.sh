#!/bin/sh
set -eu
cd -- "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish shfmt cargo rustfmt cpanminus
	perl_lib="$PWD/.build/perltidy-20260826-$(perl -e 'print $^V')"
	export PERL_CPANM_HOME="$PWD/.build/cpanm"
	export PERL5LIB="$perl_lib/lib/perl5"
	export PATH="$perl_lib/bin:$PATH"
	perl "$(command -v cpanm)" --notest --local-lib-contained "$perl_lib" 'Perl::Tidy@20260826'
fi

git ls-files --cached --others --exclude-standard -z -- '*.fish' |
	perl -0ne 'chomp; print "./$_\0" if -f && !-l' | xargs -0 fish_indent -w
git ls-files --cached --others --exclude-standard -z -- '*.pl' '*.pm' '*.t' |
	xargs -0 -n1 sh -c 'test ! -f "$1" || test -L "$1" || perltidy -npro -l=110 -conv -b -bext=/ "./$1"' sh
cargo fmt --quiet --manifest-path fzfp/Cargo.toml
git ls-files --cached --others --exclude-standard -z |
	perl -0ne 'chomp; print "./$_\0" if -f && !-l' |
	xargs -0 shfmt -f=0 | xargs -0 shfmt -s -w

if [ "${CI-}" ]; then
	git add --intent-to-add --ignore-removal .

	tput() { command tput -Txterm-256color "$@"; }

	if ! git --no-pager diff --color=always --stat --patch --exit-code; then
		tput bold
		printf '%s %s: unexpected diff\n' "$(printf '%40s' | tr ' ' '^')" "${0##*/}"
		tput sgr0
		exit 1
	fi
fi
