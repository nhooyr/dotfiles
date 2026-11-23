use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

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
