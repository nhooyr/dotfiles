ObjC.import("CoreFoundation");
ObjC.import("CoreServices");
function run(argv) {
    if (argv[0] === "--verify") {
        argv.slice(1).forEach(function (type) {
            var identifier = type.charAt(0) === "." ? $.UTTypeCreatePreferredIdentifierForTag(
                $.kUTTagClassFilenameExtension, $(type.slice(1)), $.kUTTypeData) : $(type);
            var handler = $.LSCopyDefaultRoleHandlerForContentType(identifier, $.kLSRolesAll);
            if (ObjC.unwrap(ObjC.castRefToObject(handler)) !== "io.nhooyr.nvim-terminal") {
                throw new Error("Could not verify the default for " + type);
            }
        });
        return;
    }
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
