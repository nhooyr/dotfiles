use std::env;
use std::fs;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(0);
const HARNESS: &str = r#"
set -p fish_function_path "$(path dirname -- "$WIDGET_SOURCE")"
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
    contains -- --read0 $argv; and cat >/dev/null
    printf '\0'
end
function fzf
    cat >/dev/null
    printf '%s\0' (string split \n -- "$TEST_SELECTION")
end
fzf_path_widget "$TEST_WIDGET"
printf '%s' "$inserted"
"#;

struct Fixture(PathBuf);

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn run(commandline: &str, selection: &str) -> (String, bool) {
    run_widget("fzf-path-widget", commandline, selection)
}

fn run_widget(widget_name: &str, commandline: &str, selection: &str) -> (String, bool) {
    let id = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
    let fixture = Fixture(env::temp_dir().join(format!("fzf-widget-{}-{id}", std::process::id())));
    fs::create_dir(&fixture.0).unwrap();
    fs::create_dir(fixture.0.join("bin")).unwrap();
    fs::create_dir(fixture.0.join("directory")).unwrap();
    let nvim = fixture.0.join("bin/nvim");
    fs::write(&nvim, "#!/bin/sh\nprintf '%s\\0' \"$PWD/README.md\"\n").unwrap();
    fs::set_permissions(nvim, fs::Permissions::from_mode(0o700)).unwrap();
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
        .env(
            "PATH",
            env::join_paths(
                std::iter::once(fixture.0.join("bin"))
                    .chain(env::split_paths(&env::var_os("PATH").unwrap())),
            )
            .unwrap(),
        )
        .env("WIDGET_SOURCE", widget)
        .env("TEST_WIDGET", widget_name)
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
fn recent_files_use_the_same_insertion_rules() {
    for (commandline, selection) in [
        ("", "./script"),
        ("", "script"),
        ("", "./binary"),
        ("", "./script\nREADME.md"),
        ("nvim ", "script"),
    ] {
        assert_eq!(
            run_widget("fzf-recent-widget", commandline, selection),
            run(commandline, selection)
        );
    }
}

#[test]
fn multiple_paths_choose_a_command_for_the_entire_selection() {
    for (selection, expected) in [
        ("./script\nREADME.md", "nvim -- ./script README.md "),
        ("README.md\n./script", "nvim -- README.md ./script "),
        ("./binary\nREADME.md", "file -- ./binary README.md "),
        ("README.md\n./binary", "file -- README.md ./binary "),
        ("directory\nREADME.md", "nvim -- directory README.md "),
        ("README.md\ndirectory", "nvim -- README.md directory "),
        ("directory\n./script", "nvim -- directory ./script "),
        ("./script\ndirectory", "nvim -- ./script directory "),
        ("directory\n./binary", "file -- directory ./binary "),
        ("./binary\ndirectory", "file -- ./binary directory "),
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
set -p fish_function_path "$(path dirname -- "$WIDGET_SOURCE")"
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
    if test "$inserted" != "-- ./$name/file "
        printf 'unexpected insertion: <%s>\n' "$inserted" >&2
        exit 1
    end
end
"#;
    assert!(path_case(script, "").is_empty());
}

#[test]
fn dot_paths_in_option_values_keep_searches_local() {
    let script = r#"
set -g HOME "$PWD"
set -g nhooyr /global
function fzfpaths
    printf '%s\0' $argv > scan
end
function fzf
    cat >/dev/null
    printf '%s' $argv > query
end
fzf_path_widget "$TEST_WIDGET"
set -l args $(string split0 < scan)
printf '%s\0' "$args[-3]" "$args[-2]" "$(cat query)"
"#;
    for widget in ["fzf-file-widget", "fzf-cd-widget", "fzf-path-widget"] {
        for token in ["./example", "--file=./example", "-I./example"] {
            let script = format!("set -g TEST_WIDGET {widget}\n{script}");
            let query = if widget == "fzf-path-widget" {
                "./example"
            } else {
                "example"
            };
            assert_eq!(
                path_case(&script, token),
                format!(".\0\0--query={query}\0").as_bytes(),
                "{widget}: {token}"
            );
        }
    }
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
fn recent_files_use_the_file_picker_query() {
    let script = r#"
mkdir bin
printf '#!/bin/sh\nexit 0\n' > bin/nvim
chmod +x bin/nvim
set -lx PATH "$PWD/bin" $PATH
function fzfpaths
    cat >/dev/null
end
function fzf
    cat >/dev/null
    printf '%s' $argv > query
end
fzf_path_widget fzf-recent-widget
cat query
"#;
    assert_eq!(path_case(script, "link/../tar"), b"--query=tar");
}

#[test]
fn recent_files_only_pass_absolute_filenames_to_the_scanner() {
    let script = r#"
set -lx TEST_NVIM "$(command -s nvim)"
set -lx TEST_OLDFILES '["man://ls(1)","/second file","relative","scp://host/file","/first file"]'
mkdir bin
printf '%s\n' '#!/bin/sh' 'exec "$TEST_NVIM" -i NONE --cmd "lua vim.v.oldfiles = vim.json.decode(vim.env.TEST_OLDFILES)" "$@"' > bin/nvim
chmod +x bin/nvim
set -lx PATH "$PWD/bin" $PATH
function fzfpaths
    cat > input
end
function fzf
    cat >/dev/null
end
fzf_path_widget fzf-recent-widget
cat input
"#;
    assert_eq!(path_case(script, ""), b"/second file\0/first file\0");
}

#[test]
fn absolute_command_search_runs_scripts_using_directory_aliases() {
    let script = r#"
set -g nhooyr "$PWD/global"
set -g secrets "$nhooyr/secrets"
set -g aqsnow_fzf_diralis secrets
set -g CDPATH "$PWD/cdroot"
mkdir -p "$secrets" "$CDPATH/only-cd"
git init --quiet "$secrets"
printf '#!/bin/sh\n' > "$secrets/init.sh"
chmod +x "$secrets/init.sh"
printf local > local-only
function commandline
    switch "$argv[1]"
        case --current-token
            printf '%s' "$TEST_TOKEN"
        case --cut-at-cursor
            test -n "$test_command"; and printf '%s\n' "$test_command"
        case -rt
            set -g inserted "$argv[3]"
    end
end
function fzfpaths
    set -l separator $(contains -i -- -- $argv)
    set -l directory "$argv[$(math "$separator + 1")]"
    if test "$TEST_TOKEN" = /
        test -z "$directory"; or begin
            printf 'slash search tried to scan %s\n' "$directory" >&2
            return 1
        end
        test "$argv[$(math "$separator + 2")]" = "$nhooyr"; or return 2
        if test "$current_widget" = fzf-file-widget
            not contains -- --cdpath $argv; or return 3
        else
            contains -- --cdpath $argv; or return 4
        end
    else
        test "$directory" -ef "$PWD/external"; or begin
            printf 'absolute path searched the wrong directory: %s\n' "$directory" >&2
            return 5
        end
    end
    command "$FZFPATHS" $argv
end
function fzf
    set -l paths
    while read --null --local path
        set path $(string replace --all --regex -- '\e\[[0-9;]*m' '' "$path")
        set path $(string replace --regex -- '.$' '' "$path")
        set -a paths "$path"
    end
    test "$TEST_TOKEN" = /; or return
    contains -- --query= $argv; or return 6
    for target in $requested
        test "$(count $(string match -- "$target" $paths))" -eq 1; or return 7
    end
    printf '%s\0' $requested
end
for widget in fzf-file-widget fzf-path-widget fzf-cd-widget
    set -g current_widget "$widget"
    set -g inserted ''
    set -g requested '$secrets/init.sh'
    test "$current_widget" = fzf-cd-widget; and set requested '$CDPATH/only-cd'
    fzf_path_widget "$current_widget"
    if test "$current_widget" = fzf-cd-widget
        test "$inserted" = 'cd -- only-cd '; or exit 1
    else
        test "$inserted" = '$secrets/init.sh '; or exit 2
    end
end
set -g current_widget fzf-path-widget
set -g requested '$secrets/init.sh'
set -g test_command nvim
fzf_path_widget "$current_widget"
test "$inserted" = '-- $secrets/init.sh '; or exit 5
set -e test_command
chmod -x "$secrets/init.sh"
fzf_path_widget "$current_widget"
test "$inserted" = 'nvim -- $secrets/init.sh '; or exit 6
chmod +x "$secrets/init.sh"
printf '#!/bin/sh\n' > "$secrets/second.sh"
chmod +x "$secrets/second.sh"
mkfifo "$secrets/pipe"
ln -s pipe "$secrets/pipe-link"
ln -s missing "$secrets/broken"
git -C "$secrets" add -- pipe-link broken
set -g current_widget fzf-path-widget
set -g requested '$secrets/init.sh' '$secrets/second.sh'
fzf_path_widget "$current_widget"
test "$inserted" = 'nvim -- $secrets/init.sh $secrets/second.sh '; or exit 3
printf text > "$secrets/README"
set -l directory "$(string escape -n -- "$PWD/cdroot/only-cd")"
for name in init.sh README
    set -g requested '$CDPATH/only-cd' '$secrets/'"$name"
    fzf_path_widget "$current_widget"
    test "$inserted" = "nvim -- $directory "'$secrets/'"$name "; or exit 7
end
for special in pipe-link broken
    set -g requested '$secrets/init.sh' '$secrets/'"$special"
    fzf_path_widget "$current_widget"
    test "$inserted" = 'file -- $secrets/init.sh $secrets/'"$special "; or exit 4
end
set -g TEST_TOKEN "$PWD/external/"
set -g current_widget fzf-file-widget
fzf_path_widget "$current_widget"
"#;
    assert!(path_case(script, "/").is_empty());
}

#[test]
fn recent_absolute_command_search_uses_one_aliased_script() {
    let script = r#"
set -g project "$PWD"
set -g aqsnow_fzf_diralis project
set -g expected_paths 1
set -g selected_path 1
printf '#!/bin/sh\n' > script.sh
chmod +x script.sh
ln -s script.sh link.sh
mkdir bin
printf '%s\n' '#!/bin/sh' 'printf "%s\\0" "$TEST_OLDFILE"' > bin/nvim
chmod +x bin/nvim
set -lx PATH "$PWD/bin" $PATH
function commandline
    switch "$argv[1]"
        case --current-token
            printf '%s' "$TEST_TOKEN"
        case --cut-at-cursor
            printf ''
        case -rt
            set -g inserted "$argv[3]"
    end
end
function fzfpaths
    command "$FZFPATHS" $argv
end
function fzf
    set -l paths
    while read --null --local path
        set -a paths "$path"
    end
    test "$(count $paths)" -eq "$expected_paths"; or return 1
    set -l path $(string replace --all --regex -- '\e\[[0-9;]*m' '' "$paths[$selected_path]")
    printf '%s\0' $(string replace --regex -- '.$' '' "$path")
end
for name in script.sh link.sh
    set -lx TEST_OLDFILE "$PWD/$name"
    fzf_path_widget fzf-recent-widget
    test "$inserted" = '$project/'"$name "; or exit 1
end
set -gx TEST_OLDFILE "$PWD/script.sh"
set -g aqsnow_fzf_diralis
fzf_path_widget fzf-recent-widget
test "$inserted" = "$PWD/script.sh "; or exit 2
set -g TEST_TOKEN ./
set -g expected_paths 2
fzf_path_widget fzf-recent-widget
test "$inserted" = 'nvim -- script.sh '; or exit 3
set -g selected_path 2
fzf_path_widget fzf-recent-widget
test "$inserted" = './script.sh '; or exit 4
set -g TEST_TOKEN /
set -g expected_paths 1
set -g selected_path 1
set -g aqsnow_fzf_diralis project
printf 'binary' > binary
chmod +x binary
set -gx TEST_OLDFILE "$PWD/binary"
fzf_path_widget fzf-recent-widget
test "$inserted" = '$project/binary '; or exit 5
"#;
    assert!(path_case(script, "/").is_empty());
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
fn completion_preserves_quoted_arguments_and_caller_variables() {
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
set -g list sentinel
fzf_complete
test "$list" = sentinel; or exit 1
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

#[test]
fn command_position_ignores_only_leading_decorators() {
    for commandline in ["command -- ", "exec -- ", "not command -- "] {
        assert_eq!(run(commandline, "./script"), ("./script ".into(), true));
    }
    for commandline in ["git ls -- ", "command -- git ls -- "] {
        assert_eq!(run(commandline, "./script"), ("./script ".into(), false));
    }
    assert_eq!(
        run("command -- nvim ", "README.md"),
        ("-- README.md ".into(), false)
    );
}

#[test]
fn option_values_skip_the_separator_only_for_nvim() {
    for commandline in ["nvim -u ", "/usr/local/bin/nvim -u ", "command -- nvim -u "] {
        assert_eq!(run(commandline, "README.md"), ("README.md ".into(), false));
    }
    for commandline in ["cd -u ", "/bin/cd -u ", "nvim ", "nvim -u config "] {
        assert_eq!(
            run(commandline, "README.md"),
            ("-- README.md ".into(), false)
        );
    }
}

#[test]
fn history_selection_preserves_other_lines() {
    let script = r#"
set -g fish_history __fzf_history_line_test
set -g fish_private_mode 1
function commandline
    switch "$argv[1]"
        case -L
            printf '%s\n' "$test_line"
        case -f
        case --
            set -g test_buffer "$(string join \n -- $argv[2..])"
        case -a
            set -g test_buffer "$test_buffer$(string join \n -- $argv[3..])"
        case '*'
            printf '%s\n' "$test_buffer"
    end
end
function fzf
    cat >/dev/null
    printf 'selected\0'
end
for line in 1 2 3
    set -g test_line "$line"
    set -g test_buffer 'before
middle
after'
    fzf-history-widget
    printf '%s\0' "$test_buffer"
end
"#;
    assert_eq!(
        path_case(script, ""),
        b"selected\nmiddle\nafter\0before\nselected\nafter\0before\nmiddle\nselected\0"
    );
}
