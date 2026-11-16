#!/bin/sh
set -eu

usage() {
	printf 'Usage: %s [--set-defaults]\n' "${0##*/}"
}

if [ "$#" -gt 1 ]; then
	usage >&2
	exit 1
fi
set_defaults=false
case "${1-}" in
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
if [ "$set_defaults" = true ] && ! command -v duti >/dev/null 2>&1; then
	printf '%s: Install duti first: brew install duti\n' "${0##*/}" >&2
	exit 1
fi
: "${HOME:?HOME must be set}"
script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
if grep -qFx 'version https://git-lfs.github.com/spec/v1' "$script_dir/icon.png"; then
	printf '%s: Run git lfs pull to download icon.png.\n' "${0##*/}" >&2
	exit 1
fi

applications_dir=$HOME/Applications
destination=$applications_dir/Neovim.app
mkdir -p "$applications_dir"
staging_dir=$(mktemp -d "$applications_dir/.Neovim.XXXXXX")
cleanup() {
	if [ -e "$staging_dir/previous.app" ] || [ -L "$staging_dir/previous.app" ]; then
		if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
			if ! mv "$staging_dir/previous.app" "$destination"; then
				printf '%s: Could not restore the previous app; it remains at %s/previous.app.\n' "${0##*/}" "$staging_dir" >&2
				return
			fi
		fi
	fi
	rm -rf "$staging_dir"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

app=$staging_dir/Neovim.app
osacompile -o "$app" "$script_dir/Neovim.applescript"

iconset=$staging_dir/Neovim.iconset
mkdir "$iconset"
for size in 16 32 128 256 512; do
	sips -z "$size" "$size" "$script_dir/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
	double_size=$((size * 2))
	sips -z "$double_size" "$double_size" "$script_dir/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Neovim.icns"

plist=$app/Contents/Info.plist
plutil -replace CFBundleIdentifier -string io.nhooyr.nvim-terminal "$plist"
plutil -replace CFBundleShortVersionString -string 1.0 "$plist"
plutil -replace CFBundleVersion -string 1 "$plist"
plutil -replace CFBundleIconFile -string Neovim.icns "$plist"
plutil -remove CFBundleIconName "$plist" 2>/dev/null || :
plutil -replace NSAppleEventsUsageDescription -string 'Open files in Neovim using Terminal.' "$plist"
plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"Files","CFBundleTypeRole":"Editor","LSItemContentTypes":["public.data"],"LSHandlerRank":"Alternate"}]' "$plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

if [ -e "$destination" ] || [ -L "$destination" ]; then
	mv "$destination" "$staging_dir/previous.app"
fi
mv "$app" "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
printf 'Installed %s\n' "$destination"

if [ "$set_defaults" = true ]; then
	set -- public.text public.plain-text public.source-code \
		.txt .text .md .markdown .rst .log .csv .tsv \
		.go .py .pyi .rs .c .h .cc .cpp .cxx .hpp .m .mm .swift \
		.java .kt .kts .scala .cs .rb .php .pl .r \
		.js .mjs .cjs .jsx .tsx .vue .svelte \
		.json .jsonc .jsonl .yaml .yml .toml \
		.html .htm .css .scss .sass .less .xml .sql \
		.sh .bash .zsh .fish .lua .vim .conf .cfg .ini
	# duti's setters trigger a macOS dialog for each type. Update the user's
	# handler preferences in one batch, preserving unrelated types and URLs.
	osascript -l JavaScript - "$@" <<'JXA'
ObjC.import("CoreFoundation");
ObjC.import("CoreServices");
function run(argv) {
    var domain = $("com.apple.LaunchServices/com.apple.launchservices.secure");
    var raw = $.CFPreferencesCopyAppValue($("LSHandlers"), domain);
    var handlers = ObjC.deepUnwrap(ObjC.castRefToObject(raw)) || [];
    if (!Array.isArray(handlers)) throw new Error("Invalid LSHandlers preferences");
    // Named text types can take precedence over extension preferences.
    var types = argv.slice();
    argv.filter(function (type) { return type.charAt(0) === "."; }).forEach(function (type) {
        var identifiers = $.UTTypeCreateAllIdentifiersForTag(
            $.kUTTagClassFilenameExtension, $(type.slice(1)), $.kUTTypeData);
        (ObjC.deepUnwrap(ObjC.castRefToObject(identifiers)) || []).forEach(function (identifier) {
            if ($.UTTypeConformsTo($(identifier), $.kUTTypeText) && types.indexOf(identifier) === -1) {
                types.push(identifier);
            }
        });
    });
    handlers = handlers.filter(function (entry) {
        if (types.indexOf(entry.LSHandlerContentType) !== -1) return false;
        return entry.LSHandlerContentTagClass !== "public.filename-extension" ||
            argv.indexOf("." + String(entry.LSHandlerContentTag).toLowerCase()) === -1;
    });
    var overrides = types.map(function (type) {
        var entry = {
            LSHandlerRoleAll: "io.nhooyr.nvim-terminal",
            LSHandlerPreferredVersions: {LSHandlerRoleAll: "-"},
            LSHandlerModificationDate: Math.floor($.CFAbsoluteTimeGetCurrent())
        };
        if (type.charAt(0) === ".") {
            entry.LSHandlerContentTag = type.slice(1);
            entry.LSHandlerContentTagClass = "public.filename-extension";
        } else {
            entry.LSHandlerContentType = type;
        }
        return entry;
    });
    $.CFPreferencesSetAppValue($("LSHandlers"), ObjC.castObjectToRef($(overrides.concat(handlers))), domain);
    if (!$.CFPreferencesAppSynchronize(domain)) throw new Error("Could not save file defaults");
}
JXA
	# Launch Services reads these preferences at startup. Register the app again
	# afterward, since restarting can discard a recent unsaved registration.
	/usr/bin/killall -u "$(id -un)" lsd 2>/dev/null || :
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
	failed=false
	for type; do
		case "$type" in
		.*) actual=$(duti -x "${type#.}" 2>/dev/null | tail -n 1) ;;
		*) actual=$(duti -d "$type" 2>/dev/null || :) ;;
		esac
		if [ "$actual" != io.nhooyr.nvim-terminal ]; then
			printf '%s: Could not verify the default for %s.\n' "${0##*/}" "$type" >&2
			failed=true
		fi
	done
	if [ "$failed" = true ]; then
		exit 1
	fi
	printf 'Set Neovim as the default for text and code types.\n'
fi
