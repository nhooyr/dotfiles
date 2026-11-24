use std::env;
use std::fs;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(0);
const HARNESS: &str = r#"
source "$WIDGET_SOURCE"
set -g nhooyr ''
set -g aqsnow_fzf_diralis
set -g CDPATH .
function commandline
    switch "$argv[1]"
        case -Cp
            string length -- "$TEST_COMMANDLINE"
        case -p
            printf '%s' "$TEST_COMMANDLINE"
        case --current-token
            # These cases complete an empty token after the existing command.
            printf ''
        case --cut-at-cursor
            printf '%s\0' "$TEST_COMMANDLINE" | read --null --array --tokenize tokens
            set -q tokens[1]; and printf '%s\n' $tokens
        case -rt
            set -g inserted "$argv[3]"
    end
end
function fzfpaths
    contains -- --keep-dot $argv; and printf yes > "$TEST_FLAGS"
    printf '\0'
end
function fzf
    cat >/dev/null
    printf '%s\0' (string split \n -- "$TEST_SELECTION")
end
fzf_path_widget fzf-path-widget
printf '%s' "$inserted"
"#;

struct Fixture(PathBuf);

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn run(commandline: &str, selection: &str) -> (String, bool) {
    let id = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
    let fixture = Fixture(env::temp_dir().join(format!("fzf-widget-{}-{id}", std::process::id())));
    fs::create_dir(&fixture.0).unwrap();
    for (name, contents) in [
        ("script", b"#!/bin/sh\n".as_slice()),
        ("binary", b"\x7fELF\0".as_slice()),
        ("README.md", b"read me\n".as_slice()),
    ] {
        let path = fixture.0.join(name);
        fs::write(&path, contents).unwrap();
        if name != "README.md" {
            fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
        }
    }
    let widget = Path::new(env!("CARGO_MANIFEST_DIR")).join("../functions/fzf_accept_and_run.fish");
    let output = Command::new("fish")
        .args(["--no-config", "-c", HARNESS])
        .current_dir(&fixture.0)
        .env("XDG_CONFIG_HOME", &fixture.0)
        .env("WIDGET_SOURCE", widget)
        .env("TEST_COMMANDLINE", commandline)
        .env("TEST_SELECTION", selection)
        .env("TEST_FLAGS", fixture.0.join("flags"))
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    (
        String::from_utf8(output.stdout).unwrap(),
        fixture.0.join("flags").exists(),
    )
}

#[test]
fn multiple_paths_choose_a_command_for_the_entire_selection() {
    for (selection, expected) in [
        ("./script\nREADME.md", "nvim -- ./script README.md "),
        ("README.md\n./script", "nvim -- README.md ./script "),
        ("./binary\nREADME.md", "file -- ./binary README.md "),
        ("README.md\n./binary", "file -- README.md ./binary "),
        ("./script", "./script "),
    ] {
        assert_eq!(run("", selection), (expected.into(), true), "{selection}");
    }
}

#[test]
fn variable_assignments_preserve_command_position() {
    for commandline in ["VAR=1 ", "1foo=1 "] {
        assert_eq!(run(commandline, "./script"), ("./script ".into(), true));
    }
    assert_eq!(
        run("VAR=1 1foo=2 nvim ", "README.md"),
        ("-- README.md ".into(), false)
    );
}

fn path_case(script: &str, token: &str) -> Vec<u8> {
    let id = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
    let fixture =
        Fixture(env::temp_dir().join(format!("fzf-path-widget-{}-{id}", std::process::id())));
    fs::create_dir_all(fixture.0.join("external/child")).unwrap();
    fs::create_dir(fixture.0.join("external/target")).unwrap();
    symlink("external/child", fixture.0.join("link")).unwrap();
    let widget = Path::new(env!("CARGO_MANIFEST_DIR")).join("../functions/fzf_accept_and_run.fish");
    let setup = r#"
source "$WIDGET_SOURCE"
set -g nhooyr ''
set -g aqsnow_fzf_diralis
set -g CDPATH link/..
function commandline
    switch "$argv[1]"
        case -Cp
            printf 0
        case -p
            printf ''
        case --current-token
            printf '%s\n' "$TEST_TOKEN"
        case --cut-at-cursor
            printf nvim
        case -rt
            set -g inserted "$argv[3]"
    end
end
"#;
    let mut child = Command::new("fish")
        .args(["--no-config", "-c", &format!("{setup}\n{script}")])
        .current_dir(&fixture.0)
        .env("WIDGET_SOURCE", widget)
        .env("TEST_TOKEN", token)
        .env("FZFPATHS", env!("CARGO_BIN_EXE_fzfpaths"))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while child.try_wait().unwrap().is_none() {
        if Instant::now() >= deadline {
            child.kill().unwrap();
            child.wait().unwrap();
            panic!("path widget did not finish");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    output.stdout
}

#[test]
fn parser_stops_if_no_directory_is_accessible() {
    let script = r#"
function path
    test "$argv[1]" = is; and return 1
    builtin path $argv
end
__fzf_parse_commandline
"#;
    assert_eq!(path_case(script, "missing"), b".\0missing\0\0");
    assert_eq!(path_case(script, "/missing"), b"/\0missing\0\0");
}

#[test]
fn directory_names_are_not_parsed_as_scanner_options() {
    let script = r#"
mkdir -- --help --color
printf text > --help/file
printf text > --color/file
function fzfpaths
    command "$FZFPATHS" $argv
end
function fzf
    while read --null --local path
        set path "$(string replace -ra '\e\[[0-9;]*m' '' -- "$path")"
        set path "$(string replace -r '.$' '' -- "$path")"
        printf '%s\0' "$path"
    end
end
for name in --help --color
    set -g TEST_TOKEN "$name/fi"
    fzf_path_widget fzf-file-widget
    if test "$inserted" != "-- $name/file "
        printf 'unexpected insertion: <%s>\n' "$inserted" >&2
        exit 1
    end
end
"#;
    assert!(path_case(script, "").is_empty());
}

#[test]
fn parser_preserves_symlink_parents() {
    for (token, directory, query, prefix) in [
        ("link/../tar", "link/..", "tar", ""),
        ("./link/../tar", "./link/..", "tar", ""),
        ("link/../target/", "link/../target/", "", ""),
        ("link/../word space", "link/..", "word space", ""),
        ("--file=link/../tar", "link/..", "tar", "--file="),
    ] {
        let output = path_case("__fzf_parse_commandline", token);
        assert_eq!(
            output,
            format!("{directory}\0{query}\0{prefix}\0").as_bytes(),
            "{token:?}"
        );
    }
}

#[test]
fn cdpath_insertion_preserves_symlink_parents_and_aliases() {
    let script = r#"
function fzfpaths
    printf '\0'
end
function fzf
    cat >/dev/null
    printf '%s\0' '$CDPATH/target'
end
set -g TEST_TOKEN ''
fzf_path_widget fzf-path-widget
eval "set -l paths $inserted"
test -d "$paths[-1]"; or exit 1
string match -q -- '*/link/../target ' "$inserted"; or exit 1
set -g test_alias "$PWD/link/../"
set -g aqsnow_fzf_diralis test_alias
fzf_path_widget fzf-path-widget
test "$inserted" = '-- $test_alias/target '; or exit 1
eval "set -l paths $inserted"
test -d "$paths[-1]"; or exit 1
"#;
    assert!(path_case(script, "").is_empty());
}

#[test]
fn completion_preserves_quoted_arguments() {
    let script = r#"
function commandline
    switch "$argv[1]"
        case --paging-mode
            return 1
        case -t
            printf fe
        case -pc
            if contains -- --tokens-expanded $argv
                printf '%s\n' repro --dir "$TEST_TOKEN"
            else
                string join ' ' -- repro --dir "$(string escape -- "$TEST_TOKEN")"
            end
        case --tokens-expanded
            builtin commandline $argv
        case -rt
            set -g inserted "$argv[3]"
    end
end
function isatty
    return 0
end
function candidates
    set -l tokens $(builtin commandline -opc)
    test "$tokens[3]" = "$TEST_TOKEN"; and printf feature
end
complete -c repro -f -a '$(candidates)'
function fzf
    while read -l line
        printf '%s\n' "$line"
    end
end
set -g COLUMNS 80
set -g FZF_DEFAULT_OPTS
fzf_complete
printf '%s' "$inserted"
"#;
    for argument in [
        "repo space",
        "single'quote",
        "dollar$sign",
        "semi;colon",
        r"back\slash",
    ] {
        assert_eq!(path_case(script, argument), b"feature ", "{argument:?}");
    }
}

#[test]
fn history_widget_exports_its_session_only_within_the_widget() {
    let script = r#"
set -gx XDG_DATA_HOME "$PWD/data"
function commandline
    test "$argv[1]" = -L; and printf 1
end
function fzf
    cat >/dev/null
    command sh -c 'printf "%s" "${fish_history-unset}"' > history-session
    return 1
end
set -g --unexport fish_history "$TEST_TOKEN"
fzf-history-widget
cat history-session
set -q --export fish_history
printf ':%s' "$status"
"#;
    for session in ["custom_session", ""] {
        assert_eq!(
            path_case(script, session),
            format!("{session}:1").as_bytes()
        );
    }
}

#[test]
fn option_prefix_detection_checks_tokens_instead_of_quoted_text() {
    let script = r#"
set -g TEST_SEPARATOR --
function commandline
    switch "$argv[1]"
        case -xpc
            builtin commandline --tokens-expanded --input="$TEST_TOKEN"
        case --current-token
            printf '%s' '--file=missing'
    end
end
__fzf_parse_commandline
"#;
    for input in [
        "grep -e ' -- ' --file=missing",
        "grep -e 'x; -- y' --file=missing",
        "grep '' --file=missing",
    ] {
        assert_eq!(path_case(script, input), b".\0missing\0--file=\0");
    }
    assert_eq!(
        path_case(script, "grep -- --file=missing"),
        b".\0--file=missing\0\0"
    );
    assert_eq!(
        path_case(script, "grep $TEST_SEPARATOR --file=missing"),
        b".\0--file=missing\0\0"
    );
}
