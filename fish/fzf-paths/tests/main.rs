use std::collections::HashSet;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io;
use std::os::unix::{ffi::OsStringExt, fs::symlink, fs::PermissionsExt, process::CommandExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(0);

struct Fixture {
    root: PathBuf,
    owner: PathBuf,
    repo: PathBuf,
    local: PathBuf,
}

fn checked(command: &mut Command) -> Output {
    let output = command.output().expect("run command");
    assert!(output.status.success(), "{command:?}: {output:?}");
    output
}

fn write(root: &Path, name: &str) {
    let path = root.join(name);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, "fixture").unwrap();
}

impl Fixture {
    fn new() -> Self {
        let root = loop {
            let id = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
            let path = env::temp_dir().join(format!("fzf-paths-{}-{id}", std::process::id()));
            match fs::create_dir(&path) {
                Ok(()) => break path,
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("create fixture: {error}"),
            }
        };
        let fixture = Self {
            owner: root.join("owner"),
            repo: root.join("owner/project"),
            local: root.join("local"),
            root,
        };
        fs::create_dir_all(&fixture.repo).unwrap();
        fs::create_dir(&fixture.local).unwrap();
        fixture.git(&["init", "-q"]);
        for name in [
            "tracked",
            "nested/child",
            ".hidden",
            "line\nbreak/end",
            "removed",
            "node_modules/tracked",
        ] {
            write(&fixture.repo, name);
        }
        fixture.git(&["add", "--", "."]);
        fs::remove_file(fixture.repo.join("removed")).unwrap();
        write(&fixture.repo, "untracked");
        for name in [
            "file",
            "executable",
            "$literal",
            "~literal",
            "dir/child",
            "node_modules/excluded",
            ".git/excluded",
        ] {
            write(&fixture.local, name);
        }
        fs::set_permissions(
            fixture.local.join("executable"),
            fs::Permissions::from_mode(0o700),
        )
        .unwrap();
        symlink(fixture.local.join("dir"), fixture.local.join("linked")).unwrap();
        symlink(&fixture.local, fixture.local.join("loop")).unwrap();
        symlink(fixture.local.join("missing"), fixture.local.join("broken")).unwrap();
        fixture
    }

    fn git(&self, args: &[&str]) {
        checked(
            Command::new("git")
                .current_dir(&self.repo)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", "/dev/null")
                .args(args),
        );
    }

    fn command(
        &self,
        cwd: &Path,
        owner: &Path,
        kind: &str,
        keep_dot: bool,
        aliases: &[(&str, &Path)],
    ) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_fzf-paths"));
        command
            .current_dir(cwd)
            .env("PWD", cwd)
            .arg(".")
            .arg(owner)
            .arg(kind)
            .arg(if keep_dot { "true" } else { "false" });
        for (label, path) in aliases {
            command.arg(label).arg(path);
        }
        command
    }

    fn run(&self, command: &mut Command) -> Vec<OsString> {
        let output = checked(command);
        assert!(output.stderr.is_empty(), "{output:?}");
        assert!(output.stdout.ends_with(b"\0"));
        output
            .stdout
            .split(|&byte| byte == 0)
            .filter(|path| !path.is_empty())
            .map(|path| OsString::from_vec(path.to_vec()))
            .collect()
    }

    fn pick(&self) -> Vec<OsString> {
        self.run(&mut self.command(&self.local, &self.owner, "-fd", false, &[]))
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

#[test]
fn local_paths_are_first_and_unique() {
    let fixture = Fixture::new();
    let paths = fixture.pick();
    let first_global = paths.iter().position(|path| path == &fixture.repo).unwrap();
    assert!(first_global > 0);
    assert!(paths[..first_global]
        .iter()
        .all(|path| !Path::new(path).is_absolute()));
    assert_eq!(paths.len(), paths.iter().collect::<HashSet<_>>().len());
}

#[test]
fn tracked_files_and_parents() {
    let fixture = Fixture::new();
    let paths = fixture.pick();
    for name in [
        "tracked",
        "nested",
        "nested/child",
        ".hidden",
        "line\nbreak/end",
        "node_modules/tracked",
    ] {
        assert!(paths.contains(&fixture.repo.join(name).into_os_string()));
    }
    for name in ["untracked", "removed"] {
        assert!(!paths.contains(&fixture.repo.join(name).into_os_string()));
    }
}

#[test]
fn longest_alias_and_raw_local_copy() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(
        &fixture.repo,
        &fixture.owner,
        "-fd",
        false,
        &[("$owner", &fixture.owner), ("$project", &fixture.repo)],
    ));
    let raw = paths.iter().position(|p| p == "nested/child").unwrap();
    let alias = paths
        .iter()
        .position(|p| p == "$project/nested/child")
        .unwrap();
    assert!(raw < alias);
    assert!(!paths
        .iter()
        .any(|path| Path::new(path).starts_with("$owner/project")));
}

#[test]
fn directories_only() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(&fixture.local, &fixture.owner, "-d", false, &[]));
    assert!(paths.contains(&"dir".into()));
    assert!(paths.contains(&fixture.repo.join("nested").into_os_string()));
    assert!(paths.iter().all(|path| fixture.local.join(path).is_dir()));
}

#[test]
fn executables_keep_dot_prefix() {
    let fixture = Fixture::new();
    let paths =
        fixture.run(&mut fixture.command(&fixture.local, &fixture.owner, "-fdx", true, &[]));
    assert!(paths.contains(&"./executable".into()));
    assert!(!paths.contains(&"./file".into()));
    assert!(paths.iter().all(|path| {
        fixture
            .local
            .join(path)
            .metadata()
            .unwrap()
            .permissions()
            .mode()
            & 0o111
            != 0
    }));
}

#[test]
fn literal_prefixes_are_escaped() {
    let paths = Fixture::new().pick();
    assert!(paths.contains(&"./$literal".into()));
    assert!(paths.contains(&"./~literal".into()));
}

#[test]
fn ignored_directories_broken_links_and_cycles() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", false, &[]));
    for absent in ["node_modules", ".git", "broken"] {
        assert!(!paths.contains(&absent.into()));
    }
    assert!(paths.contains(&"linked/child".into()));
    assert!(paths.contains(&"loop".into()));
    assert!(!paths
        .iter()
        .any(|path| Path::new(path).starts_with("loop") && path != "loop"));
}

#[test]
fn empty_or_missing_owner() {
    let fixture = Fixture::new();
    let empty = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", false, &[]));
    let missing = fixture.run(&mut fixture.command(
        &fixture.local,
        &fixture.root.join("absent"),
        "-fd",
        false,
        &[],
    ));
    assert_eq!(empty, missing);
}

#[test]
fn logical_working_directory() {
    let fixture = Fixture::new();
    let link = fixture.root.join("logical");
    symlink(&fixture.local, &link).unwrap();
    let mut command = fixture.command(&fixture.local, &fixture.owner, "-fd", false, &[]);
    command.env("PWD", link);
    assert_eq!(fixture.pick(), fixture.run(&mut command));
}

#[test]
fn invalid_arguments() {
    let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
        .arg0("/some/path/renamed-picker")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert_eq!(
        output.stderr,
        b"usage: renamed-picker DIR OWNER TYPE KEEP_DOT [LABEL DIRECTORY]...\n"
    );
}

#[test]
fn help_uses_invoked_basename() {
    for flag in ["--help", "-h"] {
        let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
            .arg0("/some/path/renamed-picker")
            .arg(flag)
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(output.stderr.is_empty());
        assert_eq!(
            output.stdout,
            b"usage: renamed-picker DIR OWNER TYPE KEEP_DOT [LABEL DIRECTORY]...\n"
        );
    }
}

#[test]
fn unpaired_alias_is_a_usage_error() {
    let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
        .arg0("/some/path/renamed-picker")
        .args([".", "", "-fd", "false", "unpaired"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert_eq!(
        output.stderr,
        b"usage: renamed-picker DIR OWNER TYPE KEEP_DOT [LABEL DIRECTORY]...\n"
    );
}

#[test]
fn runtime_errors_use_invoked_basename() {
    let fixture = Fixture::new();
    let output = fixture
        .command(&fixture.local, &fixture.owner, "-fd", false, &[])
        .arg0("/some/path/renamed-picker")
        .env("PATH", fixture.root.join("no-commands"))
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stderr.starts_with(b"renamed-picker: "));
}
