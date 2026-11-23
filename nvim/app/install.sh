#!/bin/sh
set -eu

report() { printf 'dotfiles: nvim/app: %s: %s\n' "${0##*/}" "$*"; }

usage() {
	printf 'Usage: %s [--set-defaults]\n' "${0##*/}"
	printf 'Install the nvim app; optionally make it the default for text and source files.\n'
}

set_defaults=false
case "$*" in
'') ;;
-h | --help)
	usage
	exit 0
	;;
--set-defaults)
	set_defaults=true
	;;
*)
	usage >&2
	exit 2
	;;
esac

if [ "$(uname -s)" != Darwin ]; then
	report 'macOS is required' >&2
	exit 1
fi
: "${HOME:?HOME must be set}"
if ! command -v timeout >/dev/null 2>&1; then
	report 'GNU timeout is required (brew install coreutils)' >&2
	exit 1
fi
if [ "$set_defaults" = true ] && ! command -v duti >/dev/null 2>&1; then
	report 'duti is required (brew install duti)' >&2
	exit 1
fi
cd -- "$(dirname "$0")"
PATH="$PWD/../../bin:$PATH"
if grep -qFx 'version https://git-lfs.github.com/spec/v1' ./icon.png; then
	report 'Run git lfs pull to download icon.png' >&2
	exit 1
fi

applications_dir=$HOME/Applications
destination=$applications_dir/nvim.app
cache_dir=$HOME/Library/Caches/dotfiles
lock_dir=$cache_dir/nvim-app-install.lock
staging_dir=
backup=
installed=false
bundle_id=ca.aqsnow.nvim

exists() { [ -e "$1" ] || [ -L "$1" ]; }

timeout --kill-after=2 30 mkdir -p "$cache_dir"
if ! mkdir -m 700 "$lock_dir" 2>/dev/null; then
	report "another installation is running, or a previous run left this lock: $lock_dir" | hpath >&2
	report 'If no installer is running, remove that lock directory before retrying' >&2
	exit 1
fi

cleanup() {
	cleanup_status=$?
	trap - 0
	trap '' HUP INT TERM
	if [ "$installed" != true ] && exists "$backup"; then
		if exists "$destination" || ! timeout --kill-after=2 30 mv "$backup" "$destination"; then
			report "previous app preserved at $backup; restore it manually" | hpath >&2
			staging_dir=
			cleanup_status=1
		fi
	fi
	if [ -n "$staging_dir" ]; then
		timeout --kill-after=2 30 rm -rf "$staging_dir" || cleanup_status=1
	fi
	timeout --kill-after=2 30 rmdir "$lock_dir" || cleanup_status=1
	exit "$cleanup_status"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
staging_dir=$(timeout --kill-after=2 30 mktemp -d "$cache_dir/nvim-build.XXXXXX")
backup=$staging_dir/previous.app

run() { timeout --kill-after=2 30 "$@"; }

quiet() {
	if run "$@" >"$staging_dir/command.log" 2>&1; then
		return 0
	else
		command_status=$?
		cat "$staging_dir/command.log" >&2
		return "$command_status"
	fi
}

current_handler() {
	run duti -d "$1" 2>/dev/null || {
		query_status=$?
		# A type without a default handler still needs to be set.
		case "$query_status" in
		124 | 137)
			report "duti lookup timed out for $1" >&2
			return "$query_status"
			;;
		esac
	}
}

apply_defaults() {
	[ "$set_defaults" = true ] || return 0
	set -- public.text public.plain-text public.source-code \
		.txt .text .md .markdown .rst .log .csv .tsv \
		.go .py .pyi .rs .c .h .cc .cpp .cxx .hpp .m .mm .swift \
		.java .kt .kts .scala .cs .rb .php .pl .r \
		.js .mjs .cjs .jsx .ts .tsx .vue .svelte \
		.json .jsonc .jsonl .yaml .yml .toml \
		.html .svg .htm .css .scss .sass .less .xml .sql \
		.sh .bash .zsh .fish .lua .vim .conf .cfg .ini
	# Match macOS's preferred types; duti's extension lookup uses a different base type.
	types=$(run osascript -l JavaScript -e '
ObjC.import("CoreServices");
function run(args) {
    var types = args.map(function (type) {
        return type.charAt(0) === "." ? ObjC.unwrap(ObjC.castRefToObject(
            $.UTTypeCreatePreferredIdentifierForTag($.kUTTagClassFilenameExtension,
                $(type.slice(1)), $.kUTTypeData))) : type;
    });
    return types.filter(function (type, i) { return types.indexOf(type) === i; }).join("\n");
}' "$@")
	printf '%s\n' "$types" | while IFS= read -r type; do
		handler=$(current_handler "$type")
		[ "$handler" != "$bundle_id" ] || continue
		report "Setting $type default to nvim"
		deadline=$(($(date +%s) + 120))
		timeout --kill-after=2 120 duti -s "$bundle_id" "$type" all
		while :; do
			handler=$(current_handler "$type")
			[ "$handler" != "$bundle_id" ] || break
			if [ "$(date +%s)" -ge "$deadline" ]; then
				report "could not verify nvim as the default for $type" >&2
				return 1
			fi
			sleep 1
		done
	done
	report 'Verified text and code defaults'
}

source_hash=$(run shasum -a 256 ./install.sh ./nvim.applescript ./icon.png)
if exists "$destination"; then
	installed_id=$(run plutil -extract CFBundleIdentifier raw -o - "$destination/Contents/Info.plist")
	if [ "$installed_id" != "$bundle_id" ]; then
		report "refusing to replace an unrelated app at $destination" | hpath >&2
		exit 1
	fi
fi
if [ "$source_hash" = "$(cat "$destination/Contents/Resources/dotfiles.sha256" 2>/dev/null)" ]; then
	if run codesign --verify --strict "$destination"; then
		report "Already installed $destination" | hpath
		apply_defaults
		exit 0
	else
		command_status=$?
		case "$command_status" in 124 | 137) exit "$command_status" ;; esac
	fi
fi

app=$staging_dir/nvim.app
quiet osacompile -o "$app" ./nvim.applescript
iconset=$staging_dir/nvim.iconset
run mkdir "$iconset"
for size in 16 32 128 256 512; do
	run sips -z "$size" "$size" ./icon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
	double_size=$((size * 2))
	run sips -z "$double_size" "$double_size" ./icon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
run iconutil -c icns "$iconset" -o "$app/Contents/Resources/nvim.icns"

plist=$app/Contents/Info.plist
run plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
run plutil -replace CFBundleShortVersionString -string 1.0 "$plist"
run plutil -replace CFBundleVersion -string 1 "$plist"
run plutil -replace CFBundleIconFile -string nvim.icns "$plist"
run plutil -remove CFBundleIconName "$plist" 2>/dev/null || {
	command_status=$?
	[ "$command_status" -eq 1 ] || exit "$command_status"
}
run plutil -replace NSAppleEventsUsageDescription -string 'Open files in nvim using Terminal.' "$plist"
run plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"Text and source files","CFBundleTypeRole":"Editor","LSItemContentTypes":["public.plain-text","public.source-code"],"LSHandlerRank":"Alternate"}]' "$plist"
quiet plutil -lint "$plist"
printf '%s\n' "$source_hash" >"$app/Contents/Resources/dotfiles.sha256"
quiet codesign --force --sign - "$app"
run codesign --verify --strict "$app"

run mkdir -p "$applications_dir"
if exists "$destination"; then
	run mv "$destination" "$backup"
fi
run mv "$app" "$destination"
installed=true
report "Installed $destination" | hpath
apply_defaults
