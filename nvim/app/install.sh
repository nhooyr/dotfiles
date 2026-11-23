#!/bin/sh
set -eu

usage() {
	printf 'Usage: %s [--set-defaults]\n' "${0##*/}"
}

set_defaults=false
case "$*" in
'') ;;
--set-defaults) set_defaults=true ;;
-h | --help)
	usage
	exit 0
	;;
*)
	usage >&2
	exit 1
	;;
esac

if [ "$(uname -s)" != Darwin ]; then
	printf '%s: macOS is required.\n' "${0##*/}" >&2
	exit 1
fi
: "${HOME:?HOME must be set}"
cd -- "$(dirname "$0")"
PATH="$PWD/../../bin:$PATH"
if grep -qFx 'version https://git-lfs.github.com/spec/v1' ./icon.png; then
	printf '%s: Run git lfs pull to download icon.png.\n' "${0##*/}" >&2
	exit 1
fi

applications_dir=$HOME/Applications
destination=$applications_dir/nvim.app
source_hash=$(shasum -a 256 ./install.sh ./nvim.applescript ./icon.png)
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ "$source_hash" = "$(cat "$destination/Contents/Resources/dotfiles.sha256" 2>/dev/null)" ] &&
	codesign --verify --strict "$destination" >/dev/null 2>&1; then
	printf 'dotfiles: nvim/app: %s: Already installed %s\n' "${0##*/}" "$destination" | hpath
else
	mkdir -p "$applications_dir"
	staging_dir=$(mktemp -d "$applications_dir/.nvim.XXXXXX")
	cleanup() {
		if [ -e "$staging_dir/previous.app" ] || [ -L "$staging_dir/previous.app" ]; then
			if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
				if ! mv "$staging_dir/previous.app" "$destination"; then
					printf '%s: Could not restore the previous app; it remains at %s/previous.app.\n' "${0##*/}" "$staging_dir" | hpath >&2
					return
				fi
			fi
		fi
		rm -rf "$staging_dir"
	}
	trap cleanup 0
	trap 'exit 1' HUP INT TERM

	quiet() {
		"$@" >"$staging_dir/command.log" 2>&1 || {
			command_status=$?
			hpath <"$staging_dir/command.log" >&2
			return "$command_status"
		}
	}

	app=$staging_dir/nvim.app
	quiet osacompile -o "$app" ./nvim.applescript

	iconset=$staging_dir/nvim.iconset
	mkdir "$iconset"
	for size in 16 32 128 256 512; do
		quiet sips -z "$size" "$size" ./icon.png --out "$iconset/icon_${size}x${size}.png"
		double_size=$((size * 2))
		quiet sips -z "$double_size" "$double_size" ./icon.png --out "$iconset/icon_${size}x${size}@2x.png"
	done
	quiet iconutil -c icns "$iconset" -o "$app/Contents/Resources/nvim.icns"

	plist=$app/Contents/Info.plist
	plutil -replace CFBundleIdentifier -string io.nhooyr.nvim-terminal "$plist"
	plutil -replace CFBundleShortVersionString -string 1.0 "$plist"
	plutil -replace CFBundleVersion -string 1 "$plist"
	plutil -replace CFBundleIconFile -string nvim.icns "$plist"
	plutil -remove CFBundleIconName "$plist" 2>/dev/null || :
	plutil -replace NSAppleEventsUsageDescription -string 'Open files in nvim using Terminal.' "$plist"
	plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"Files","CFBundleTypeRole":"Editor","LSItemContentTypes":["public.data"],"LSHandlerRank":"Alternate"}]' "$plist"
	printf '%s\n' "$source_hash" >"$app/Contents/Resources/dotfiles.sha256"
	quiet codesign --force --sign - "$app"
	quiet codesign --verify --strict "$app"

	if [ -e "$destination" ] || [ -L "$destination" ]; then
		mv "$destination" "$staging_dir/previous.app"
	fi
	mv "$app" "$destination"
	printf 'dotfiles: nvim/app: %s: Installed %s\n' "${0##*/}" "$destination" | hpath
fi
"$lsregister" -f "$destination"

if [ "$set_defaults" = true ]; then
	set -- public.text public.plain-text public.source-code \
		.txt .text .md .markdown .rst .log .csv .tsv \
		.go .py .pyi .rs .c .h .cc .cpp .cxx .hpp .m .mm .swift \
		.java .kt .kts .scala .cs .rb .php .pl .r \
		.js .mjs .cjs .jsx .ts .tsx .vue .svelte \
		.json .jsonc .jsonl .yaml .yml .toml \
		.html .svg .htm .css .scss .sass .less .xml .sql \
		.sh .bash .zsh .fish .lua .vim .conf .cfg .ini
	# System setters trigger a macOS dialog for each type. Update the user's
	# handler preferences in one batch, preserving unrelated types and URLs.
	osascript -l JavaScript ./set-defaults.js "$@"
	# Launch Services reads these preferences at startup. Register the app again
	# afterward, since restarting can discard a recent unsaved registration.
	/usr/bin/killall -u "$(id -un)" lsd 2>/dev/null || :
	"$lsregister" -f "$destination"
	osascript -l JavaScript ./set-defaults.js --verify "$@"
	printf 'dotfiles: nvim/app: %s: Registered nvim.app as the default for text and code types.\n' "${0##*/}"
fi
