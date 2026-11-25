use std::collections::HashSet;
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::net::UnixListener;
use std::os::unix::{ffi::OsStringExt, fs::PermissionsExt, fs::symlink, process::CommandExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc;
use std::time::{Duration, Instant};

static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(0);
const LS_COLORS: &str =
    "di=34:ln=36:so=32:pi=32:ex=35:bd=37;42:cd=37;42:su=37;45:sg=37;45:tw=37;44:ow=37;44:st=34";

struct Fixture {
    root: PathBuf,
    global_dir: PathBuf,
    repo: PathBuf,
    repo_alias: PathBuf,
    local: PathBuf,
}

fn checked(command: &mut Command) -> Output {
    let output = command.output().expect("run command");
    assert!(output.status.success(), "{command:?}: {output:?}");
    output
}

fn from_input(command: &mut Command, paths: &[&Path]) -> Vec<OsString> {
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    for path in paths {
        input
            .write_all(path.as_os_str().as_encoded_bytes())
            .unwrap();
        input.write_all(&[0]).unwrap();
    }
    drop(input);
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    output
        .stdout
        .split(|byte| *byte == 0)
        .filter(|path| !path.is_empty())
        .map(|path| OsString::from_vec(path.to_vec()))
        .collect()
}

fn mock_ls_files(path: &Path, script: &str) -> io::Result<()> {
    // These fixtures mock slow repository scans, not configuration reads.
    fs::write(
        path,
        script.replacen(
            "#!/bin/sh\n",
            "#!/bin/sh\nif [ \"$3\" = config ]; then printf '\\0'; exit 0; fi\n",
            1,
        ),
    )
}

fn write(root: &Path, name: &str) {
    let path = root.join(name);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, "fixture").unwrap();
}

fn make_executable(path: impl AsRef<Path>) {
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
}

fn write_script(root: &Path, name: &str) {
    let path = root.join(name);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(&path, "#!/bin/sh\n").unwrap();
    make_executable(path);
}

fn assert_error_cancels_stalled_git(command: &mut Command, release: &Path, message: &str) {
    let mut child = command
        .env("FZF_TEST_RELEASE", release)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    let exited = loop {
        if child.try_wait().unwrap().is_some() {
            break true;
        }
        if Instant::now() >= deadline {
            break false;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    // Release the sibling on failure so the regression test leaves no processes.
    fs::write(release, "continue").unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(
        exited,
        "the scan failure waited for stalled Git: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains(message));
}

impl Fixture {
    fn new() -> Self {
        let root = loop {
            let id = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
            let path = env::temp_dir().join(format!("fzfpaths-{}-{id}", std::process::id()));
            match fs::create_dir(&path) {
                Ok(()) => break path,
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("create fixture: {error}"),
            }
        };
        let fixture = Self {
            global_dir: root.join("global_dir"),
            repo: root.join("global_dir/project"),
            repo_alias: PathBuf::from("$global/project"),
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
            "line break/end",
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
            "$literal",
            "~literal",
            "dir/child",
            "node_modules/excluded",
            ".git/excluded",
        ] {
            write(&fixture.local, name);
        }
        write_script(&fixture.local, "executable");
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
        global_dir: &Path,
        kind: &str,
        env_dirs: &[(&str, &Path)],
    ) -> Command {
        self.command_with_flags(&[], cwd, global_dir, kind, env_dirs)
    }

    fn command_with_flags(
        &self,
        flags: &[&str],
        cwd: &Path,
        global_dir: &Path,
        kind: &str,
        env_dirs: &[(&str, &Path)],
    ) -> Command {
        self.command_with_cdpath(flags, cwd, global_dir, None, kind, env_dirs)
    }

    fn command_with_cdpath(
        &self,
        flags: &[&str],
        cwd: &Path,
        global_dir: &Path,
        cdpath: Option<&OsStr>,
        kind: &str,
        env_dirs: &[(&str, &Path)],
    ) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_fzfpaths"));
        command
            .current_dir(cwd)
            .env("PWD", cwd)
            .env("LS_COLORS", LS_COLORS)
            .args(flags);
        if let Some(cdpath) = cdpath {
            command.arg("--cdpath").arg(cdpath);
        }
        if global_dir.as_os_str().is_empty() {
            command.args([".", "", kind]);
        } else {
            let directory = cwd.join(global_dir);
            let alias = env_dirs
                .iter()
                .find(|(_, path)| *path == directory)
                .map(|(name, _)| *name);
            command.args([".", alias.unwrap_or("$global"), kind]);
            if alias.is_none() {
                command.args(["--dirali", "$global"]).arg(directory);
            }
        }
        for (env, path) in env_dirs {
            command.arg("--dirali").arg(env).arg(path);
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
        self.run(&mut self.command(&self.local, &self.global_dir, "-fd", &[]))
    }

    fn filesystem_path(&self, candidate: impl AsRef<Path>) -> PathBuf {
        let candidate = candidate.as_ref();
        match candidate.strip_prefix("$global") {
            Ok(relative) => self.global_dir.join(relative),
            Err(_) => self.local.join(candidate),
        }
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

#[test]
fn local_and_global_paths_are_unique() {
    let fixture = Fixture::new();
    let paths = fixture.pick();
    assert!(paths.contains(&"file".into()));
    assert!(paths.contains(&OsString::from("$global/project")));
    assert_eq!(paths.len(), paths.iter().collect::<HashSet<_>>().len());
}

#[test]
fn local_paths_replace_global_aliases_in_every_mode() {
    let fixture = Fixture::new();
    write_script(&fixture.repo, "script");
    for kind in ["-f", "-d", "-fd"] {
        let local = fixture.run(&mut fixture.command_with_flags(
            &["--keep-dot"],
            &fixture.repo,
            Path::new(""),
            kind,
            &[],
        ));
        let paths = fixture.run(&mut fixture.command_with_flags(
            &["--keep-dot"],
            &fixture.repo,
            &fixture.global_dir,
            kind,
            &[("$project", &fixture.repo)],
        ));
        for path in local {
            assert!(paths.contains(&path), "missing local {path:?}");
            let path = Path::new(&path)
                .strip_prefix(".")
                .unwrap_or(Path::new(&path));
            assert!(!paths.contains(&Path::new("$project").join(path).into_os_string()));
            assert!(!paths.contains(&fixture.repo_alias.join(path).into_os_string()));
        }
    }
}

#[test]
fn local_exclusions_also_hide_overlapping_global_paths() {
    let fixture = Fixture::new();
    write(&fixture.repo, "ignored");
    fs::write(fixture.repo.join(".gitignore"), "ignored\n").unwrap();
    fixture.git(&["add", "-f", "ignored"]);
    let paths = fixture.run(&mut fixture.command(
        &fixture.repo,
        &fixture.global_dir,
        "-fd",
        &[("$project", &fixture.repo)],
    ));
    for path in ["ignored", "node_modules/tracked"] {
        assert!(!paths.contains(&OsString::from(path)));
        assert!(!paths.contains(&Path::new("$project").join(path).into_os_string()));
    }
    assert!(!paths.contains(&"$project".into()));
}

#[test]
fn local_and_global_overlap_uses_physical_directory_roots() {
    let fixture = Fixture::new();
    let local = fixture.root.join("local-link");
    let global = fixture.root.join("global-link");
    symlink(&fixture.repo, &local).unwrap();
    symlink(&fixture.global_dir, &global).unwrap();
    let paths = fixture.run(&mut fixture.command(
        &local,
        &global,
        "-f",
        &[("$project", &global.join("project"))],
    ));
    assert!(paths.contains(&"tracked".into()));
    assert!(!paths.contains(&"$project/tracked".into()));
    assert!(!paths.contains(&global.join("project/tracked").into_os_string()));
}

#[test]
fn absolute_local_paths_do_not_add_an_alias_copy() {
    let fixture = Fixture::new();
    let paths = fixture.run(
        Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .current_dir(&fixture.local)
            .arg(&fixture.repo)
            .arg("$global")
            .args(["--dirali", "$global"])
            .arg(&fixture.global_dir)
            .args(["-f", "--dirali", "$project"])
            .arg(&fixture.repo),
    );
    assert!(paths.contains(&fixture.repo.join("tracked").into_os_string()));
    assert!(!paths.contains(&"$project/tracked".into()));
}

#[test]
fn unrelated_globals_stream_while_the_local_scan_is_blocked() {
    let fixture = Fixture::new();
    write(&fixture.repo, "nested/ignored");
    fs::write(fixture.repo.join("nested/.gitignore"), "ignored\n").unwrap();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    fs::write(&git, "#!/bin/sh\nif [ \"$3\" = config ]; then\n  while [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done\n  printf '\\0'\nelse\n  printf 'nested/child\\0nested/ignored\\0tracked\\0'\nfi\n").unwrap();
    make_executable(&git);
    let release = fixture.root.join("release");
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let mut child = fixture
        .command(&fixture.repo.join("nested"), &fixture.global_dir, "-f", &[])
        .env("PATH", path)
        .env("FZF_TEST_RELEASE", &release)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (sender, receiver) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        let mut stdout = BufReader::new(stdout);
        let mut output = Vec::new();
        stdout.read_until(0, &mut output).unwrap();
        sender.send(output.clone()).unwrap();
        io::copy(&mut stdout, &mut output).unwrap();
        output
    });
    let first = receiver.recv_timeout(Duration::from_secs(5));
    fs::write(release, "continue").unwrap();
    assert!(child.wait().unwrap().success());
    let output = reader.join().unwrap();
    let mut expected = b"$global/project/tracked".to_vec();
    expected.push(0);
    assert_eq!(first.unwrap(), expected);
    let paths: Vec<_> = output.split(|byte| *byte == 0).collect();
    assert!(paths.contains(&b"child".as_slice()));
    for name in ["nested/child", "nested/ignored"] {
        assert!(!paths.contains(&fixture.repo_alias.join(name).as_os_str().as_encoded_bytes()));
    }
}

#[test]
fn local_subdirectory_searches_keep_nested_paths() {
    let fixture = Fixture::new();
    write(&fixture.local, "first/deep/leaf");
    write(&fixture.local, "second/deep/leaf");
    let paths = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", &[]));
    for name in [
        "first/deep",
        "first/deep/leaf",
        "second/deep",
        "second/deep/leaf",
    ] {
        assert!(paths.contains(&name.into()));
    }
}

#[test]
fn global_files_follow_git_order() {
    let fixture = Fixture::new();
    let paths = fixture.pick();
    let files: Vec<_> = paths
        .iter()
        .map(Path::new)
        .filter(|path| {
            path.strip_prefix("$global")
                .is_ok_and(|relative| fixture.global_dir.join(relative).is_file())
        })
        .collect();
    let expected: Vec<_> = [
        fixture.repo_alias.join(".hidden"),
        fixture.repo_alias.join("line break/end"),
        fixture.repo_alias.join("nested/child"),
        fixture.repo_alias.join("node_modules/tracked"),
        fixture.repo_alias.join("tracked"),
        fixture.repo_alias.join("untracked"),
    ]
    .into();
    assert_eq!(files, expected);
}

#[test]
fn global_scan_keeps_sparse_indexes_sparse() {
    let fixture = Fixture::new();
    write(&fixture.repo, "removed");
    fixture.git(&[
        "-c",
        "user.name=Fixture",
        "-c",
        "user.email=fixture@example.invalid",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-qm",
        "fixture",
    ]);
    fixture.git(&[
        "sparse-checkout",
        "set",
        "--cone",
        "--sparse-index",
        "nested",
    ]);
    let indexed = checked(
        Command::new("git")
            .current_dir(&fixture.repo)
            .args(["ls-files", "--sparse", "-z"]),
    );
    assert!(
        indexed
            .stdout
            .split(|&byte| byte == 0)
            .any(|path| path == b"line break/")
    );
    let paths = fixture.run(&mut fixture.command(&fixture.local, &fixture.global_dir, "-f", &[]));
    assert!(paths.contains(&fixture.repo_alias.join("nested/child").into_os_string()));
    assert!(!paths.contains(&fixture.repo_alias.join("line break/end").into_os_string()));
}

#[test]
fn first_local_result_arrives_before_global_scan_finishes() {
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\nwhile [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done\nprintf 'tracked\\0'\n",
    )
    .unwrap();
    make_executable(&git);
    let release = fixture.root.join("release");
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let mut child = fixture
        .command(&fixture.local, &fixture.global_dir, "-f", &[])
        .env("PATH", path)
        .env("FZF_TEST_RELEASE", &release)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (sender, receiver) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        let mut stdout = BufReader::new(stdout);
        let mut first = Vec::new();
        stdout.read_until(0, &mut first).unwrap();
        sender.send(first).unwrap();
        io::copy(&mut stdout, &mut io::sink()).unwrap();
    });
    let first = receiver.recv_timeout(Duration::from_secs(5));
    fs::write(release, "continue").unwrap();
    assert!(child.wait().unwrap().success());
    reader.join().unwrap();
    let mut first = first.expect("first local result was buffered while Git waited");
    assert_eq!(first.pop(), Some(0));
    let first = OsString::from_vec(first);
    assert!(!Path::new(&first).is_absolute());
    let first = fixture.local.join(first);
    assert!(first.symlink_metadata().is_ok() && !first.is_dir());
}

#[test]
fn global_scan_starts_while_local_output_is_blocked() {
    let fixture = Fixture::new();
    // Long paths fill the stdout pipe well before the former 1,000-result gate.
    let directory = vec!["long".repeat(40); 4].join("/");
    for index in 0..1005 {
        write(&fixture.local, &format!("{directory}/file-{index}"));
    }
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\n: > \"$FZF_TEST_STARTED\"\nprintf 'tracked\\0'\n",
    )
    .unwrap();
    make_executable(&git);
    let started = fixture.root.join("started");
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let child = fixture
        .command(&fixture.local, &fixture.global_dir, "-f", &[])
        .env("PATH", path)
        .env("FZF_TEST_STARTED", &started)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while !started.exists() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    let concurrent = started.exists();
    // Always drain stdout so even a regression can finish before we assert.
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    assert!(concurrent, "Git waited for the blocked local scan");
}

#[test]
fn cdpath_results_arrive_while_git_is_waiting() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath");
    fs::create_dir_all(directory.join("junegunn/fzf")).unwrap();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\nwhile [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done\nprintf 'nested/child\\0'\n",
    )
    .unwrap();
    make_executable(&git);
    let release = fixture.root.join("release");
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let mut child = fixture
        .command_with_cdpath(
            &[],
            &fixture.local,
            &fixture.global_dir,
            Some(directory.as_os_str()),
            "-fd",
            &[],
        )
        .env("PATH", path)
        .env("FZF_TEST_RELEASE", &release)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (sender, receiver) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        for path in BufReader::new(stdout).split(0) {
            sender.send(path.unwrap()).unwrap();
        }
    });
    let mut local = false;
    let mut cdpath = false;
    while !local || !cdpath {
        match receiver.recv_timeout(Duration::from_secs(5)) {
            Ok(path) => {
                local |= path == b"file";
                cdpath |= path == b"$CDPATH/junegunn/fzf";
            }
            Err(_) => break,
        }
    }
    fs::write(release, "continue").unwrap();
    assert!(child.wait().unwrap().success());
    reader.join().unwrap();
    assert!(local, "local results waited for Git");
    assert!(cdpath, "CDPATH results waited for Git");
}

#[test]
fn global_results_arrive_before_git_finishes() {
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\nprintf 'nested/child\\0'\nwhile [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done\nprintf 'tracked\\0'\n",
    )
    .unwrap();
    make_executable(&git);
    let release = fixture.root.join("release");
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let mut child = fixture
        .command(&fixture.local, &fixture.global_dir, "-fd", &[])
        .env("PATH", path)
        .env("FZF_TEST_RELEASE", &release)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (sender, receiver) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        for path in BufReader::new(stdout).split(0) {
            sender.send(path.unwrap()).unwrap();
        }
    });
    let wanted = b"$global/project/nested/child".to_vec();
    let streamed = loop {
        match receiver.recv_timeout(Duration::from_secs(5)) {
            Ok(path) if path == wanted => break true,
            Ok(_) => continue,
            Err(_) => break false,
        }
    };
    fs::write(release, "continue").unwrap();
    assert!(child.wait().unwrap().success());
    reader.join().unwrap();
    assert!(streamed, "global paths were buffered until Git exited");
}

#[test]
fn a_slow_repository_does_not_hold_back_other_repositories() {
    let fixture = Fixture::new();
    let second = fixture.global_dir.join("second");
    fs::create_dir_all(second.join(".git")).unwrap();
    write(&second, "tracked");
    let blocked = fs::read_dir(&fixture.global_dir)
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let other = if blocked == second {
        &fixture.repo
    } else {
        &second
    };
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\nif [ \"$2\" = \"$FZF_TEST_BLOCKED_REPO\" ]; then\n  while [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done\nfi\nprintf 'tracked\\0'\n",
    )
    .unwrap();
    make_executable(&git);
    let release = fixture.root.join("release");
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let mut child = fixture
        .command(&fixture.local, &fixture.global_dir, "-f", &[])
        .env("PATH", path)
        .env("FZF_TEST_BLOCKED_REPO", blocked)
        .env("FZF_TEST_RELEASE", &release)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (sender, receiver) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        for path in BufReader::new(stdout).split(0) {
            sender.send(path.unwrap()).unwrap();
        }
    });
    let wanted = Path::new("$global")
        .join(other.strip_prefix(&fixture.global_dir).unwrap())
        .join("tracked")
        .into_os_string()
        .into_vec();
    let streamed = loop {
        match receiver.recv_timeout(Duration::from_secs(5)) {
            Ok(path) if path == wanted => break true,
            Ok(_) => continue,
            Err(_) => break false,
        }
    };
    fs::write(release, "continue").unwrap();
    assert!(child.wait().unwrap().success());
    reader.join().unwrap();
    assert!(streamed, "a slow repository held back another repository");
}

#[test]
fn parallel_searches_keep_all_local_paths() {
    let fixture = Fixture::new();
    let local = fixture.root.join("large");
    for i in 0..1005 {
        let name = format!("items/file-{i:04}");
        write_script(&local, &name);
    }
    for flags in [&[][..], &["--keep-dot"][..]] {
        let paths = fixture.run(&mut fixture.command_with_flags(
            flags,
            &local,
            &fixture.global_dir,
            "-fd",
            &[],
        ));
        assert!(paths.contains(&OsString::from("$global/project")));
        let local_paths: HashSet<_> = paths
            .iter()
            .filter(|path| !Path::new(path).starts_with("$global"))
            .collect();
        let forms = if flags.is_empty() { 1 } else { 2 };
        assert_eq!(local_paths.len(), 1 + 1005 * forms);
        assert!(local_paths.contains(&OsString::from("items")));
        for i in 0..1005 {
            assert!(local_paths.contains(&OsString::from(format!("items/file-{i:04}"))));
            if !flags.is_empty() {
                assert!(local_paths.contains(&OsString::from(format!("./items/file-{i:04}"))));
            }
        }
    }
    let paths = fixture.run(&mut fixture.command(&local, Path::new(""), "-fd", &[]));
    assert_eq!(paths.len(), 1006);
}

#[test]
fn closing_the_picker_does_not_leave_workers_blocked() {
    let fixture = Fixture::new();
    for index in 0..1005 {
        write(&fixture.local, &format!("many/file-{index}"));
    }
    let mut child = fixture
        .command(&fixture.local, &fixture.global_dir, "-fd", &[])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut first = Vec::new();
    stdout.read_until(0, &mut first).unwrap();
    drop(stdout);
    let deadline = Instant::now() + Duration::from_secs(5);
    let exited = loop {
        if child.try_wait().unwrap().is_some() {
            break true;
        }
        if Instant::now() >= deadline {
            child.kill().unwrap();
            break false;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    let output = child.wait_with_output().unwrap();
    assert!(exited, "workers stayed blocked after stdout closed");
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn closing_the_picker_cancels_stalled_git_and_its_subprocesses() {
    for pending_output in [false, true] {
        assert_stalled_git_stops(pending_output, None, false);
    }
    assert_stalled_git_stops(false, None, true);
}

#[test]
fn terminating_signals_stop_a_full_output_pipe_and_restore_its_flags() {
    for signal in [libc::SIGHUP, libc::SIGINT, libc::SIGTERM] {
        let fixture = Fixture::new();
        let mut fds = [0; 2];
        assert_eq!(unsafe { libc::pipe(fds.as_mut_ptr()) }, 0);
        for fd in fds {
            assert_eq!(
                unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) },
                0
            );
        }
        let reader = unsafe { fs::File::from_raw_fd(fds[0]) };
        let mut writer = unsafe { fs::File::from_raw_fd(fds[1]) };
        let fd = writer.as_raw_fd();
        let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
        assert_eq!(
            unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) },
            0
        );
        while writer.write(&[0; 4096]).is_ok() {}
        assert_eq!(unsafe { libc::fcntl(fd, libc::F_SETFL, flags) }, 0);
        let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
        let observer = writer.try_clone().unwrap();
        let mut child = fixture
            .command(&fixture.local, Path::new(""), "-f", &[])
            .stdout(Stdio::from(writer))
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(2);
        while unsafe { libc::fcntl(observer.as_raw_fd(), libc::F_GETFL) } & libc::O_NONBLOCK == 0
            && Instant::now() < deadline
        {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(child.try_wait().unwrap().is_none());
        assert_eq!(unsafe { libc::kill(child.id() as i32, signal) }, 0);
        let deadline = Instant::now() + Duration::from_secs(2);
        let stopped = loop {
            if child.try_wait().unwrap().is_some() {
                break true;
            }
            if Instant::now() >= deadline {
                break false;
            }
            std::thread::sleep(Duration::from_millis(10));
        };
        drop(reader); // Unblock the original implementation on failure.
        let output = child.wait_with_output().unwrap();
        assert!(stopped, "signal could not interrupt the full output pipe");
        assert_eq!(output.status.code(), Some(128 + signal), "{output:?}");
        assert_eq!(
            unsafe { libc::fcntl(observer.as_raw_fd(), libc::F_GETFL) },
            flags
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    }
}

#[test]
fn terminating_signals_cancel_stalled_git_and_its_subprocesses() {
    for signal in [1, 2, 15] {
        for pending_output in [false, true] {
            assert_stalled_git_stops(pending_output, Some(signal), false);
        }
    }
}

#[test]
fn terminating_signals_cancel_git_after_stdout_closes() {
    for signal in [1, 2, 15] {
        assert_stalled_git_stops(false, Some(signal), true);
    }
}

fn assert_stalled_git_stops(pending_output: bool, signal: Option<i32>, close_stdout: bool) {
    unsafe extern "C" {
        fn kill(pid: i32, signal: i32) -> i32;
    }
    let fixture = Fixture::new();
    fs::remove_dir_all(&fixture.local).unwrap();
    fs::create_dir(&fixture.local).unwrap();
    if pending_output {
        for index in 0..1005 {
            write(&fixture.local, &format!("many/file-{index}"));
        }
    }
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\n\
         if [ \"$FZF_TEST_CLOSE_STDOUT\" = 1 ]; then exec 1>&-; else printf 'tracked\\0'; fi\n\
         while [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done &\n\
         printf '%s\\n' \"$$\" > \"$FZF_TEST_PID\"\n\
         : > \"$FZF_TEST_STARTED\"\n\
         wait\n",
    )
    .unwrap();
    make_executable(&git);
    let started = fixture.root.join("started");
    let release = fixture.root.join("release");
    let pid_file = fixture.root.join("git.pid");
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let mut child = fixture
        .command(&fixture.local, &fixture.global_dir, "-f", &[])
        .env("PATH", path)
        .env("FZF_TEST_STARTED", &started)
        .env("FZF_TEST_RELEASE", &release)
        .env("FZF_TEST_PID", &pid_file)
        .env(
            "FZF_TEST_CLOSE_STDOUT",
            if close_stdout { "1" } else { "0" },
        )
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut first = Vec::new();
    if !close_stdout {
        stdout.read_until(0, &mut first).unwrap();
    }
    let deadline = Instant::now() + Duration::from_secs(5);
    while !started.exists() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    let git_started = started.exists();
    if close_stdout {
        // Let the reader reach the wait after Git's output has reached EOF.
        std::thread::sleep(Duration::from_millis(50));
    }
    if let Some(signal) = signal {
        assert_eq!(unsafe { kill(child.id() as i32, signal) }, 0);
    } else {
        drop(stdout);
    }
    let deadline = Instant::now() + Duration::from_secs(2);
    let exited = loop {
        if child.try_wait().unwrap().is_some() {
            break true;
        }
        if Instant::now() >= deadline {
            break false;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    let git_running = fs::read_to_string(pid_file)
        .ok()
        .and_then(|pid| pid.trim().parse().ok())
        .is_some_and(|pid| unsafe { kill(pid, 0) } == 0);
    // Unblock the fake Git on failure so the regression cannot leave it running.
    fs::write(release, "continue").unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(git_started, "Git did not start");
    assert!(!git_running, "Git survived cancellation");
    assert!(
        exited,
        "cancellation waited for stalled Git (pending_output={pending_output}, signal={signal:?})"
    );
    assert_eq!(
        output.status.code(),
        Some(signal.map_or(0, |signal| 128 + signal)),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn failed_git_scan_reports_failure() {
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\nprintf 'simulated Git failure\\n' >&2\nexit 7\n",
    )
    .unwrap();
    make_executable(&git);
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
        .current_dir(&fixture.local)
        .env("PATH", path)
        .arg("")
        .arg("$global")
        .args(["--dirali", "$global"])
        .arg(&fixture.global_dir)
        .arg("-f")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    let error = String::from_utf8(output.stderr).unwrap();
    assert!(error.contains("simulated Git failure"), "{error}");
    assert!(error.contains("git failed: exit status: 7"), "{error}");
}

#[test]
fn failed_git_scan_cancels_other_repositories() {
    for hold_output in [false, true] {
        let fixture = Fixture::new();
        fs::create_dir_all(fixture.global_dir.join("stalled/.git")).unwrap();
        let bin = fixture.root.join("bin");
        fs::create_dir(&bin).unwrap();
        let git = bin.join("git");
        mock_ls_files(
        &git,
        "#!/bin/sh\ncase \"$2\" in */project)\n  while [ ! -e \"$FZF_TEST_STARTED\" ]; do sleep 0.01; done\n  if [ \"$FZF_TEST_HOLD_OUTPUT\" = 1 ]; then\n    while [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done &\n  fi\n  exit 7;;\nesac\n: > \"$FZF_TEST_STARTED\"\nwhile [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done\n",
    )
    .unwrap();
        make_executable(&git);
        let path = env::join_paths(
            std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
        )
        .unwrap();
        let started = fixture.root.join("started");
        assert_error_cancels_stalled_git(
            fixture
                .command(&fixture.local, &fixture.global_dir, "-f", &[])
                .env("PATH", path)
                .env("FZF_TEST_STARTED", &started)
                .env("FZF_TEST_HOLD_OUTPUT", if hold_output { "1" } else { "0" }),
            &fixture.root.join("release"),
            "git failed: exit status: 7",
        );
        assert!(started.exists(), "the sibling repository never started");
    }
}

#[test]
fn global_files_and_parents() {
    let fixture = Fixture::new();
    let paths = fixture.pick();
    for name in [
        "tracked",
        "nested",
        "nested/child",
        ".hidden",
        "line break/end",
        "node_modules/tracked",
        "untracked",
    ] {
        assert!(paths.contains(&fixture.repo_alias.join(name).into_os_string()));
    }
    assert!(!paths.contains(&fixture.repo_alias.join("removed").into_os_string()));
}

#[test]
fn global_untracked_paths_respect_git_ignores_and_file_types() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/ignored/\n*.tmp\n").unwrap();
    fs::write(fixture.repo.join("nested/.gitignore"), "!keep.tmp\n").unwrap();
    fs::write(fixture.repo.join(".git/info/exclude"), "info-secret\n").unwrap();
    for name in [
        "new dir/deep/new file",
        ".hidden-new",
        "ignored/skip",
        "nested/keep.tmp",
        "nested/skip.tmp",
        "info-secret",
    ] {
        write(&fixture.repo, name);
    }
    symlink("new dir", fixture.repo.join("new-link")).unwrap();
    symlink("absent", fixture.repo.join("new-broken")).unwrap();

    for kind in ["-f", "-d", "-fd"] {
        let paths =
            fixture.run(&mut fixture.command(&fixture.local, &fixture.global_dir, kind, &[]));
        for name in [
            "new dir/deep/new file",
            ".hidden-new",
            "nested/keep.tmp",
            "new-broken",
        ] {
            assert_eq!(
                paths.contains(&fixture.repo_alias.join(name).into_os_string()),
                kind != "-d",
                "{kind}: {name:?}"
            );
        }
        for name in ["new dir", "new dir/deep", "new-link"] {
            assert_eq!(
                paths.contains(&fixture.repo_alias.join(name).into_os_string()),
                kind != "-f",
                "{kind}: {name:?}"
            );
        }
        for name in ["ignored", "ignored/skip", "nested/skip.tmp", "info-secret"] {
            assert!(
                !paths.contains(&fixture.repo_alias.join(name).into_os_string()),
                "{kind}: {name}"
            );
        }
    }
}

#[test]
fn global_ignore_hides_subtrees_without_filtering_local_paths() {
    let fixture = Fixture::new();
    let config = fixture.root.join("config");
    fs::create_dir_all(config.join("fzfpaths")).unwrap();
    fs::write(
        config.join("fzfpaths/ignore"),
        "/project/src/\n/project/android/\n/project/ios/\n",
    )
    .unwrap();
    for directory in ["src", "android", "ios"] {
        write(&fixture.repo, &format!("{directory}/tracked/child"));
    }
    fixture.git(&["add", "--", "src", "android", "ios"]);
    for directory in ["src", "android", "ios"] {
        write(&fixture.repo, &format!("{directory}/untracked/child"));
    }

    let other = fixture.global_dir.join("other");
    checked(Command::new("git").args(["init", "-q"]).arg(&other));
    write(&other, "src/visible");

    for kind in ["-f", "-d", "-fd"] {
        for aliases in [vec![], vec![("$project", fixture.repo.as_path())]] {
            let prefix = if aliases.is_empty() {
                PathBuf::from("$global/project")
            } else {
                PathBuf::from("$project")
            };
            let paths = fixture.run(
                fixture
                    .command(&fixture.repo, &fixture.global_dir, kind, &aliases)
                    .env("XDG_CONFIG_HOME", &config),
            );
            for directory in ["src", "android", "ios"] {
                assert!(
                    !paths
                        .iter()
                        .any(|path| Path::new(path).starts_with(prefix.join(directory))),
                    "{kind}: global {directory} was shown"
                );
                assert_eq!(
                    paths.contains(&directory.into()),
                    kind != "-f",
                    "{kind}: local {directory}"
                );
                for name in ["tracked", "untracked"] {
                    let file = format!("{directory}/{name}/child");
                    assert_eq!(
                        paths.contains(&file.into()),
                        kind != "-d",
                        "{kind}: local {directory}/{name}/child"
                    );
                }
            }
            assert_eq!(paths.contains(&"tracked".into()), kind != "-d");
            assert_eq!(paths.contains(&"nested".into()), kind != "-f");
            assert!(!paths.contains(&prefix.join("tracked").into_os_string()));
            assert!(!paths.contains(&prefix.join("nested").into_os_string()));
            let other_path = if kind == "-d" { "src" } else { "src/visible" };
            assert!(paths.contains(&Path::new("$global/other").join(other_path).into_os_string()));
        }
    }
}

#[test]
fn global_ignore_supports_file_globs_and_negations() {
    let fixture = Fixture::new();
    let config = fixture.root.join("config");
    fs::create_dir_all(config.join("fzfpaths")).unwrap();
    fs::write(
        config.join("fzfpaths/ignore"),
        "# Keep one matching file.\n/project/*.tmp\n!/project/keep.tmp\n/project/nested/*\n!/project/nested/child\n/project/literal\\[\n/project/class[ab]\n",
    )
    .unwrap();
    for name in ["tracked.tmp", "keep.tmp", "literal[", "classa"] {
        write(&fixture.repo, name);
    }
    fixture.git(&["add", "--", "tracked.tmp", "keep.tmp", "literal[", "classa"]);
    for name in ["untracked.tmp", "nested/hidden"] {
        write(&fixture.repo, name);
    }
    let paths = fixture.run(
        fixture
            .command(&fixture.local, &fixture.global_dir, "-f", &[])
            .env("XDG_CONFIG_HOME", &config),
    );
    for name in [
        "tracked.tmp",
        "untracked.tmp",
        "nested/hidden",
        "literal[",
        "classa",
    ] {
        assert!(!paths.contains(&fixture.repo_alias.join(name).into_os_string()));
    }
    for name in ["keep.tmp", "nested/child"] {
        assert!(paths.contains(&fixture.repo_alias.join(name).into_os_string()));
    }
}

#[test]
fn configured_ignore_rules_keep_local_and_global_scopes_separate() {
    let fixture = Fixture::new();
    let config = fixture.root.join("config");
    fs::create_dir_all(config.join("fzfpaths")).unwrap();
    fs::write(
        config.join("fzfpaths/ignore"),
        "*.tmp\n!nested/keep.tmp\nlocal-only\n/project/global-only\n/project/*.bin\n!/project/keep.bin\n",
    )
    .unwrap();
    for root in [&fixture.local, &fixture.repo] {
        for name in [
            "local-only",
            "global-only",
            "drop.tmp",
            "nested/drop.tmp",
            "nested/keep.tmp",
            "drop.bin",
            "keep.bin",
        ] {
            write(root, name);
        }
    }
    let paths = fixture.run(
        fixture
            .command(&fixture.local, &fixture.global_dir, "-f", &[])
            .env("XDG_CONFIG_HOME", &config),
    );
    for name in ["local-only", "drop.tmp", "nested/drop.tmp"] {
        assert!(!paths.contains(&name.into()), "local {name}");
        assert!(
            paths.contains(&fixture.repo_alias.join(name).into_os_string()),
            "global {name}"
        );
    }
    for name in ["global-only", "drop.bin"] {
        assert!(paths.contains(&name.into()), "local {name}");
        assert!(
            !paths.contains(&fixture.repo_alias.join(name).into_os_string()),
            "global {name}"
        );
    }
    for name in ["nested/keep.tmp", "keep.bin"] {
        assert!(paths.contains(&name.into()), "local {name}");
        assert!(
            paths.contains(&fixture.repo_alias.join(name).into_os_string()),
            "global {name}"
        );
    }
}

#[test]
fn configured_ignore_skips_only_the_initial_utf8_bom() {
    for pattern in ["*.tmp", "/project/*.tmp"] {
        let fixture = Fixture::new();
        for root in [&fixture.local, &fixture.repo] {
            write(root, "drop.tmp");
            write(root, "literal");
        }
        let config = fixture.root.join("config");
        fs::create_dir_all(config.join("fzfpaths")).unwrap();
        fs::write(
            config.join("fzfpaths/ignore"),
            format!("\u{feff}{pattern}\n\u{feff}literal\n\u{feff}/project/literal\n"),
        )
        .unwrap();
        let paths = fixture.run(
            fixture
                .command(&fixture.local, &fixture.global_dir, "-f", &[])
                .env("XDG_CONFIG_HOME", config),
        );
        assert_eq!(paths.contains(&"drop.tmp".into()), pattern.starts_with('/'));
        assert_eq!(
            paths.contains(&fixture.repo_alias.join("drop.tmp").into_os_string()),
            !pattern.starts_with('/')
        );
        assert!(paths.contains(&"literal".into()));
        assert!(paths.contains(&fixture.repo_alias.join("literal").into_os_string()));
    }
}

#[test]
fn local_ignore_negation_does_not_override_gitignore() {
    let fixture = Fixture::new();
    checked(Command::new("git").args(["init", "-q"]).arg(&fixture.local));
    write(&fixture.local, "native.tmp");
    write(&fixture.local, "drop.tmp");
    write(&fixture.local, "keep.tmp");
    fs::write(fixture.local.join(".gitignore"), "native.tmp\n").unwrap();
    let config = fixture.root.join("config");
    fs::create_dir_all(config.join("fzfpaths")).unwrap();
    fs::write(
        config.join("fzfpaths/ignore"),
        "*.tmp\n!native.tmp\n!keep.tmp\n",
    )
    .unwrap();
    let paths = fixture.run(
        fixture
            .command(&fixture.local, Path::new(""), "-f", &[])
            .env("XDG_CONFIG_HOME", &config),
    );
    assert!(!paths.contains(&"native.tmp".into()));
    assert!(!paths.contains(&"drop.tmp".into()));
    assert!(paths.contains(&"keep.tmp".into()));
}

#[test]
fn global_ignore_reports_unclosed_character_classes() {
    let fixture = Fixture::new();
    let config = fixture.root.join("config");
    fs::create_dir_all(config.join("fzfpaths")).unwrap();
    fs::write(config.join("fzfpaths/ignore"), "/[\n").unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
        .arg("")
        .arg("$global")
        .args(["--dirali", "$global"])
        .arg(&fixture.global_dir)
        .arg("-f")
        .env("XDG_CONFIG_HOME", config)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).contains("unclosed character class"));
}

#[test]
fn failed_scan_cancels_other_sources() {
    let fixture = Fixture::new();
    let config = fixture.root.join("config");
    fs::create_dir_all(config.join("fzfpaths")).unwrap();
    fs::write(config.join("fzfpaths/ignore"), "[\n").unwrap();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\nwhile [ ! -e \"$FZF_TEST_RELEASE\" ]; do sleep 0.01; done\n",
    )
    .unwrap();
    make_executable(&git);
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    assert_error_cancels_stalled_git(
        fixture
            .command(&fixture.local, &fixture.global_dir, "-f", &[])
            .env("PATH", path)
            .env("XDG_CONFIG_HOME", config),
        &fixture.root.join("release"),
        "unclosed character class",
    );
}

#[test]
fn global_ignore_uses_home_default_and_xdg_override() {
    let fixture = Fixture::new();
    let home = fixture.root.join("home");
    let config = fixture.root.join("config");
    for (directory, pattern) in [
        (home.join(".config/fzfpaths"), "/project/tracked\n"),
        (config.join("fzfpaths"), "/project/untracked\n"),
    ] {
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join("ignore"), pattern).unwrap();
    }
    for xdg in [None, Some(OsStr::new("")), Some(config.as_os_str())] {
        let mut command = fixture.command(&fixture.local, &fixture.global_dir, "-f", &[]);
        command.env("HOME", &home).env_remove("XDG_CONFIG_HOME");
        if let Some(xdg) = xdg {
            command.env("XDG_CONFIG_HOME", xdg);
        }
        let paths = fixture.run(&mut command);
        let overridden = xdg.is_some_and(|value| !value.is_empty());
        assert_eq!(
            paths.contains(&fixture.repo_alias.join("tracked").into_os_string()),
            overridden
        );
        assert_eq!(
            paths.contains(&fixture.repo_alias.join("untracked").into_os_string()),
            !overridden
        );
    }
}

#[test]
fn ignored_global_repository_is_not_scanned_or_filtered_from_cdpath() {
    let fixture = Fixture::new();
    let config = fixture.root.join("config");
    fs::create_dir_all(config.join("fzfpaths")).unwrap();
    fs::write(config.join("fzfpaths/ignore"), "/project/\n").unwrap();
    let output = checked(
        Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .arg("")
            .arg("$global")
            .args(["--dirali", "$global"])
            .arg(&fixture.global_dir)
            .arg("-fd")
            .env("XDG_CONFIG_HOME", &config)
            .env("PATH", fixture.root.join("no-commands")),
    );
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());

    let paths = fixture.run(
        fixture
            .command_with_cdpath(
                &[],
                &fixture.local,
                &fixture.global_dir,
                Some(fixture.global_dir.as_os_str()),
                "-d",
                &[],
            )
            .env("XDG_CONFIG_HOME", &config),
    );
    assert!(paths.contains(&"$CDPATH/project".into()));
    assert!(!paths.contains(&OsString::from("$global/project")));
}

#[test]
fn global_untracked_paths_use_directory_aliases() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(
        &fixture.local,
        &fixture.global_dir,
        "-f",
        &[("$project", &fixture.repo)],
    ));
    assert!(paths.contains(&OsString::from("$project/untracked")));
    assert!(!paths.contains(&fixture.repo_alias.join("untracked").into_os_string()));
}

#[test]
fn longest_env_keeps_local_paths_and_abbreviates_uncovered_globals() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(
        &fixture.repo.join("nested"),
        &fixture.global_dir,
        "-fd",
        &[
            ("$global_dir", &fixture.global_dir),
            ("$project", &fixture.repo),
        ],
    ));
    assert!(paths.contains(&"child".into()));
    assert!(paths.contains(&"$project".into()));
    assert!(paths.contains(&"$project/tracked".into()));
    assert!(!paths.contains(&"$project/nested".into()));
    assert!(!paths.contains(&"$project/nested/child".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("$global_dir/project"))
    );
}

#[test]
fn repeated_envs_are_rejected_before_emitting_paths() {
    let fixture = Fixture::new();
    for second_dir in [&fixture.repo, &fixture.local] {
        let output = fixture
            .command(
                &fixture.local,
                &fixture.global_dir,
                "-fd",
                &[("$project", &fixture.repo), ("$project", second_dir)],
            )
            .arg0("/test/renamed-picker")
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stdout.is_empty());
        assert_eq!(output.stderr, b"renamed-picker: duplicate env: $project\n");
    }
}

#[test]
fn different_envs_may_reference_the_same_directory() {
    let fixture = Fixture::new();
    fixture.run(&mut fixture.command(
        &fixture.local,
        &fixture.global_dir,
        "-fd",
        &[("$project", &fixture.repo), ("$code", &fixture.repo)],
    ));
}

#[test]
fn color_wraps_only_the_alias_and_preserves_candidates() {
    let fixture = Fixture::new();
    for alias in ["$project", "~"] {
        let env_dirs = [(alias, fixture.repo.as_path())];
        let raw = fixture.run(&mut fixture.command(
            &fixture.local,
            &fixture.global_dir,
            "-fd",
            &env_dirs,
        ));
        let colored = fixture.run(&mut fixture.command_with_flags(
            &["--color"],
            &fixture.local,
            &fixture.global_dir,
            "-fd",
            &env_dirs,
        ));
        let prefix = format!("\x1b[36m{alias}\x1b[0m");
        assert!(colored.contains(&OsString::from(&prefix)));
        assert!(colored.contains(&OsString::from(format!("{prefix}/nested/child"))));
        assert!(colored.contains(&OsString::from(format!("{prefix}/line break/end"))));
        assert!(colored.contains(&"file".into()));
        assert!(colored.contains(&"./$literal".into()));
        assert!(colored.contains(&"./~literal".into()));
        let plain: HashSet<_> = colored
            .iter()
            .map(|path| {
                let path = path.to_str().unwrap();
                if path.contains('\x1b') {
                    assert!(path.starts_with(&prefix), "unexpected coloring: {path:?}");
                }
                OsString::from(path.replace("\x1b[36m", "").replace("\x1b[0m", ""))
            })
            .collect();
        assert_eq!(plain, raw.into_iter().collect());
    }
}

#[test]
fn color_leaves_unaliased_paths_plain() {
    let fixture = Fixture::new();
    let raw = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", &[]));
    let colored = fixture.run(&mut fixture.command_with_flags(
        &["--color"],
        &fixture.local,
        Path::new(""),
        "-fd",
        &[],
    ));
    assert_eq!(
        colored.into_iter().collect::<HashSet<_>>(),
        raw.into_iter().collect()
    );
}

#[test]
fn color_wraps_only_the_cdpath_prefix() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath");
    fs::create_dir_all(directory.join("folder space/child 'with spaces")).unwrap();
    let colored = fixture.run(&mut fixture.command_with_cdpath(
        &["--color"],
        &fixture.local,
        Path::new(""),
        Some(directory.as_os_str()),
        "-d",
        &[],
    ));
    assert!(colored.contains(&"\x1b[36m$CDPATH\x1b[0m/folder space".into()));
    assert!(colored.contains(&"\x1b[36m$CDPATH\x1b[0m/folder space/child 'with spaces".into()));
    assert!(colored.contains(&"dir".into()));
    assert!(colored.iter().all(|path| {
        let path = path.to_str().unwrap();
        !path.contains('\x1b') || path.starts_with("\x1b[36m$CDPATH\x1b[0m/")
    }));
}

#[test]
fn classify_preserves_names_and_marks_file_types() {
    let fixture = Fixture::new();
    for name in [
        "ordinary*",
        "space at end ",
        "unit separator\x1f",
        "two separators\x1f\x1f",
        "line break*",
        "quote's",
    ] {
        write(&fixture.local, name);
    }
    write_script(&fixture.local, "run*");
    write_script(&fixture.repo, "tracked");
    fs::create_dir(fixture.local.join("directory*")).unwrap();
    symlink("executable", fixture.local.join("executable-link")).unwrap();
    symlink("tracked", fixture.repo.join("tracked-link")).unwrap();
    fixture.git(&["add", "--", "tracked-link"]);

    for keep_dot in [false, true] {
        let flags = if keep_dot { vec!["--keep-dot"] } else { vec![] };
        let raw = fixture.run(&mut fixture.command_with_flags(
            &flags,
            &fixture.local,
            &fixture.global_dir,
            "-fd",
            &[],
        ));
        let mut flags = flags;
        flags.push("--classify");
        let classified = fixture.run(&mut fixture.command_with_flags(
            &flags,
            &fixture.local,
            &fixture.global_dir,
            "-fd",
            &[],
        ));
        for name in ["unit separator\x1f", "two separators\x1f\x1f"] {
            assert!(raw.contains(&OsString::from(name)));
            assert!(classified.contains(&OsString::from(format!("{name}\x1f"))));
        }
        let mut restored = HashSet::new();
        for path in classified {
            let mut name = path.into_vec();
            let marker = name.pop().unwrap();
            let name = OsString::from_vec(name);
            let metadata = fixture.filesystem_path(&name).symlink_metadata().unwrap();
            let expected = if metadata.is_symlink() {
                b'@'
            } else if metadata.is_dir() {
                b'/'
            } else if metadata.permissions().mode() & 0o111 != 0 {
                b'*'
            } else {
                b'\x1f'
            };
            assert_eq!(marker, expected, "{name:?}");
            restored.insert(name);
        }
        assert_eq!(restored, raw.into_iter().collect());
    }
}

#[test]
fn classify_colors_basenames_and_suffixes() {
    let fixture = Fixture::new();
    write_script(&fixture.repo, "tracked");
    for name in ["run*", "$run", "dir/run*", "dir/exec name"] {
        write_script(&fixture.local, name);
    }
    write(&fixture.local, "ordinary*");
    fs::create_dir(fixture.local.join("directory*")).unwrap();
    symlink("executable", fixture.local.join("exec-link")).unwrap();
    symlink("tracked", fixture.repo.join("tracked-link")).unwrap();
    write_script(&fixture.repo, "nested/run*");
    fixture.git(&["add", "--", "nested/run*", "tracked-link"]);
    for alias in ["$project", "~"] {
        let paths = fixture.run(&mut fixture.command_with_flags(
            &["--classify", "--color", "--keep-dot"],
            &fixture.local,
            &fixture.global_dir,
            "-fd",
            &[(alias, fixture.repo.as_path())],
        ));
        for path in [
            "file\x1f",
            "ordinary*\x1f",
            "./$literal\x1f",
            "./~literal\x1f",
            "\x1b[34mdir/\x1b[0m",
            "\x1b[36mlinked@\x1b[0m",
            "\x1b[36mbroken@\x1b[0m",
            "\x1b[34mdirectory*/\x1b[0m",
            "\x1b[35mexecutable*\x1b[0m",
            "./\x1b[35mexecutable*\x1b[0m",
            "\x1b[36mexec-link@\x1b[0m",
            "./\x1b[36mexec-link@\x1b[0m",
            "\x1b[35mrun**\x1b[0m",
            "dir/\x1b[35mrun**\x1b[0m",
            "dir/\x1b[35mexec name*\x1b[0m",
            "./\x1b[35m$run*\x1b[0m",
        ] {
            assert!(paths.contains(&OsString::from(path)), "missing {path:?}");
        }
        let prefix = format!("\x1b[36m{alias}\x1b[0m");
        assert!(paths.contains(&OsString::from(format!("{prefix}\x1b[34m/\x1b[0m"))));
        assert!(paths.contains(&OsString::from(format!("{prefix}/\x1b[35mtracked*\x1b[0m"))));
        assert!(paths.contains(&OsString::from(format!(
            "{prefix}/\x1b[36mtracked-link@\x1b[0m"
        ))));
        assert!(paths.contains(&OsString::from(format!("{prefix}/\x1b[34mnested/\x1b[0m"))));
        assert!(paths.contains(&OsString::from(format!(
            "{prefix}/nested/\x1b[35mrun**\x1b[0m"
        ))));
        assert!(paths.contains(&OsString::from(format!("{prefix}/nested/child\x1f"))));
    }
}

#[test]
fn classify_keeps_invisible_separator_inside_background_color() {
    let fixture = Fixture::new();
    write(&fixture.local, "trailing ");
    write(&fixture.local, "separator\x1f");
    let paths = fixture.run(
        fixture
            .command_with_flags(
                &["--classify", "--color"],
                &fixture.local,
                Path::new(""),
                "-f",
                &[],
            )
            .env("LS_COLORS", "fi=37;44"),
    );
    for name in ["file", "trailing ", "separator\x1f"] {
        assert!(paths.iter().any(|path| {
            path.as_encoded_bytes()
                .ends_with(format!("{name}\x1f\x1b[0m").as_bytes())
        }));
    }
}

#[test]
fn classify_marks_cdpath_directory_links() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath");
    fs::create_dir_all(directory.join("folder*/child ")).unwrap();
    symlink("folder*", directory.join("linked")).unwrap();
    symlink("missing", directory.join("broken")).unwrap();
    write_script(&directory, "executable");
    let paths = fixture.run(&mut fixture.command_with_cdpath(
        &["--classify", "--color"],
        &fixture.local,
        Path::new(""),
        Some(directory.as_os_str()),
        "-d",
        &[],
    ));
    for (parent, name, color, marker) in [
        ("", "folder*", "34", "/"),
        ("folder*/", "child ", "34", "/"),
        ("", "linked", "36", "@"),
        ("linked/", "child ", "34", "/"),
    ] {
        assert!(paths.contains(&OsString::from(format!(
            "\x1b[36m$CDPATH\x1b[0m/{parent}\x1b[{color}m{name}{marker}\x1b[0m"
        ))));
    }
    assert!(
        paths
            .iter()
            .all(|path| path.as_encoded_bytes().ends_with(b"/\x1b[0m")
                || path.as_encoded_bytes().ends_with(b"@\x1b[0m"))
    );
    assert!(!paths.iter().any(|path| {
        let path = path.to_string_lossy();
        path.contains("broken") || path.contains("executable")
    }));
}

#[test]
fn special_files_and_broken_links_are_offered_for_inspection() {
    let fixture = Fixture::new();
    checked(Command::new("mkfifo").arg(fixture.local.join("pipe")));
    let _socket = UnixListener::bind(fixture.local.join("socket")).unwrap();
    symlink("file", fixture.local.join("file-link")).unwrap();
    symlink("pipe", fixture.local.join("pipe-link")).unwrap();
    symlink("socket", fixture.local.join("socket-link")).unwrap();
    symlink("/dev/null", fixture.local.join("device-link")).unwrap();
    let special = [
        "pipe",
        "socket",
        "broken",
        "pipe-link",
        "socket-link",
        "device-link",
    ];

    for kind in ["-f", "-fd"] {
        let raw = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), kind, &[]));
        for name in special {
            assert!(
                raw.contains(&OsString::from(name)),
                "missing {name} in {kind}"
            );
        }
        let colored = fixture.run(
            fixture
                .command_with_flags(
                    &["--classify", "--color"],
                    &fixture.local,
                    Path::new(""),
                    kind,
                    &[],
                )
                .env("LS_COLORS", "di=31:ln=32:pi=33:so=34:ex=36"),
        );
        for path in [
            "\x1b[32mfile-link@\x1b[0m",
            "\x1b[32mbroken@\x1b[0m",
            "\x1b[32mpipe-link@\x1b[0m",
            "\x1b[32msocket-link@\x1b[0m",
            "\x1b[32mdevice-link@\x1b[0m",
            "\x1b[33mpipe|\x1b[0m",
            "\x1b[34msocket=\x1b[0m",
            "\x1b[36mexecutable*\x1b[0m",
        ] {
            assert!(
                colored.contains(&OsString::from(path)),
                "missing {path:?} in {kind}"
            );
        }
    }

    let directories = fixture.run(&mut fixture.command_with_flags(
        &["--classify"],
        &fixture.local,
        Path::new(""),
        "-d",
        &[],
    ));
    assert!(directories.contains(&OsString::from("linked@")));
    for name in [
        "pipe|",
        "socket=",
        "broken@",
        "pipe-link@",
        "socket-link@",
        "device-link@",
        "file-link@",
    ] {
        assert!(!directories.contains(&OsString::from(name)));
    }
}

#[test]
fn global_special_and_broken_symlinks_are_offered_for_inspection() {
    let fixture = Fixture::new();
    symlink("absent", fixture.repo.join("broken-link")).unwrap();
    symlink("/dev/null", fixture.repo.join("device-link")).unwrap();
    fixture.git(&["add", "--", "broken-link", "device-link"]);
    for kind in ["-f", "-fd"] {
        for flags in [&[][..], &["--classify"][..]] {
            let paths = fixture.run(&mut fixture.command_with_flags(
                flags,
                &fixture.local,
                &fixture.global_dir,
                kind,
                &[("$project", &fixture.repo)],
            ));
            let suffix = if flags.is_empty() { "" } else { "@" };
            for name in ["broken-link", "device-link"] {
                assert!(paths.contains(&OsString::from(format!("$project/{name}{suffix}"))));
            }
            assert!(!paths.contains(&OsString::from(format!("$project/removed{suffix}"))));
        }
    }
}

#[test]
fn classify_uses_permission_specific_ls_colors() {
    let fixture = Fixture::new();
    for (name, mode) in [
        ("writable", 0o777),
        ("sticky-writable", 0o1777),
        ("sticky", 0o1700),
    ] {
        fs::create_dir(fixture.local.join(name)).unwrap();
        fs::set_permissions(fixture.local.join(name), fs::Permissions::from_mode(mode)).unwrap();
    }
    let paths = fixture.run(
        fixture
            .command_with_flags(
                &["--classify", "--color"],
                &fixture.local,
                Path::new(""),
                "-d",
                &[],
            )
            .env("LS_COLORS", "di=31:ow=32:tw=33:st=34"),
    );
    for path in [
        "\x1b[31mdir/\x1b[0m",
        "\x1b[32mwritable/\x1b[0m",
        "\x1b[33msticky-writable/\x1b[0m",
        "\x1b[34msticky/\x1b[0m",
    ] {
        assert!(paths.contains(&OsString::from(path)), "missing {path:?}");
    }
}

#[cfg(target_os = "linux")]
#[test]
fn color_preserves_non_utf8_filename_bytes() {
    let fixture = Fixture::new();
    let filename = OsString::from_vec(b"name-\xff".to_vec());
    fs::write(fixture.repo.join(&filename), "fixture").unwrap();
    checked(
        Command::new("git")
            .arg("-C")
            .arg(&fixture.repo)
            .args(["add", "--"])
            .arg(&filename),
    );
    for classify in [false, true] {
        let mut command = fixture.command_with_flags(
            &["--color"],
            &fixture.local,
            &fixture.global_dir,
            "-f",
            &[("$project", fixture.repo.as_path())],
        );
        let mut expected = b"\x1b[36m$project\x1b[0m/name-\xff".to_vec();
        if classify {
            command.arg("--classify");
            expected.push(b'\x1f');
        }
        let colored = fixture.run(&mut command);
        assert!(colored.contains(&OsString::from_vec(expected)));
    }
}

#[test]
fn files_only_excludes_directories_and_keeps_symlink_files() {
    let fixture = Fixture::new();
    symlink("file", fixture.local.join("file-link")).unwrap();
    symlink("tracked", fixture.repo.join("file-link")).unwrap();
    symlink("nested", fixture.repo.join("directory-link")).unwrap();
    fixture.git(&["add", "--", "file-link", "directory-link"]);
    fs::create_dir(fixture.repo.join("module")).unwrap();
    fixture.git(&[
        "update-index",
        "--add",
        "--cacheinfo",
        "160000,1111111111111111111111111111111111111111,module",
    ]);

    for flags in [&[][..], &["--keep-dot"][..]] {
        let paths = fixture.run(&mut fixture.command_with_flags(
            flags,
            &fixture.local,
            &fixture.global_dir,
            "-f",
            &[],
        ));
        for name in ["file", "file-link", "dir/child", "executable"] {
            assert!(paths.contains(&name.into()), "missing local file {name}");
        }
        for name in [
            "tracked",
            "file-link",
            "nested/child",
            "node_modules/tracked",
        ] {
            assert!(paths.contains(&fixture.repo_alias.join(name).into_os_string()));
        }
        assert!(paths.iter().all(|path| {
            let path = fixture.filesystem_path(path);
            path.symlink_metadata().is_ok() && !path.is_dir()
        }));
        assert_eq!(paths.contains(&"./executable".into()), !flags.is_empty());
    }
}

#[test]
fn cdpath_adds_two_directory_levels_from_all_roots() {
    let fixture = Fixture::new();
    let first = fixture.root.join("cdpath");
    let second = fixture.root.join("cdpath2");
    for directory in [
        "one/inside/deeper",
        "one/.git/excluded",
        "one/node_modules/excluded",
        "two",
        ".hidden",
        ".git/excluded",
        "node_modules/excluded",
    ] {
        fs::create_dir_all(first.join(directory)).unwrap();
    }
    fs::create_dir_all(second.join("three")).unwrap();
    write(&first, "not-a-directory");
    symlink("one", first.join("linked")).unwrap();
    symlink("missing", first.join("broken")).unwrap();
    let cdpath = env::join_paths([
        first.clone(),
        PathBuf::from("../cdpath2"),
        first.clone(),
        fixture.root.join("missing"),
        PathBuf::new(),
    ])
    .unwrap();

    for kind in ["-d", "-fd"] {
        let paths = fixture.run(&mut fixture.command_with_cdpath(
            &[],
            &fixture.local,
            &fixture.global_dir,
            Some(&cdpath),
            kind,
            &[],
        ));
        for directory in [
            "one",
            "one/inside",
            "two",
            ".hidden",
            "linked",
            "linked/inside",
        ] {
            assert!(paths.contains(&format!("$CDPATH/{directory}").into()));
        }
        assert!(paths.contains(&"$CDPATH/three".into()));
        assert!(paths.contains(&"$CDPATH/dir".into()));
        for omitted in [
            "one/inside/deeper",
            "linked/inside/deeper",
            "one/.git",
            "one/node_modules",
            "linked/.git",
            "linked/node_modules",
            "not-a-directory",
            "broken",
            ".git",
            "node_modules",
        ] {
            assert!(!paths.contains(&format!("$CDPATH/{omitted}").into()));
        }
        assert_eq!(HashSet::<_>::from_iter(&paths).len(), paths.len());
    }
}

#[test]
fn current_directory_cdpath_entries_use_only_the_local_scan() {
    let fixture = Fixture::new();
    let other = fixture.root.join("other");
    fs::create_dir_all(other.join("outside")).unwrap();
    for current in [".", "./", "./.", "././."] {
        let cdpath = env::join_paths([Path::new(current), &other]).unwrap();
        for kind in ["-d", "-fd"] {
            let paths = fixture.run(&mut fixture.command_with_cdpath(
                &[],
                &fixture.local,
                Path::new(""),
                Some(&cdpath),
                kind,
                &[],
            ));
            assert!(paths.contains(&"dir".into()));
            assert!(!paths.contains(&"$CDPATH/dir".into()), "{current:?}");
            assert!(paths.contains(&"$CDPATH/outside".into()));
        }
    }
}

#[test]
fn cdpath_labels_are_independent_of_aliases_and_global_repositories() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath with spaces");
    fs::create_dir_all(directory.join("child with spaces")).unwrap();
    fs::create_dir_all(directory.join("project")).unwrap();
    let cdpath = env::join_paths([&directory, &fixture.global_dir]).unwrap();
    for global_dir in [
        Path::new(""),
        &fixture.root.join("missing"),
        &fixture.global_dir,
    ] {
        let paths = fixture.run(&mut fixture.command_with_cdpath(
            &[],
            &fixture.local,
            global_dir,
            Some(&cdpath),
            "-d",
            &[("$places", &directory)],
        ));
        assert!(paths.contains(&"$CDPATH/child with spaces".into()));
        assert_eq!(
            paths
                .iter()
                .filter(|path| path.as_os_str() == "$CDPATH/project")
                .count(),
            1
        );
    }
}

#[test]
fn files_only_ignores_cdpath() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath");
    fs::create_dir_all(directory.join("child")).unwrap();
    write(&directory, "file");
    let paths = fixture.run(&mut fixture.command_with_cdpath(
        &[],
        &fixture.local,
        &fixture.global_dir,
        Some(directory.as_os_str()),
        "-f",
        &[],
    ));
    assert!(paths.contains(&"file".into()));
    assert!(paths.contains(&fixture.repo_alias.join("tracked").into_os_string()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with(&directory))
    );
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("$CDPATH"))
    );
    assert!(paths.iter().all(|path| {
        let path = fixture.filesystem_path(path);
        path.symlink_metadata().is_ok() && !path.is_dir()
    }));
}

#[test]
fn many_cdpath_directories_are_unique() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath");
    for index in 0..1005 {
        fs::create_dir_all(directory.join(format!("dir-{index}"))).unwrap();
    }
    let paths = fixture.run(&mut fixture.command_with_cdpath(
        &[],
        &fixture.local,
        &fixture.global_dir,
        Some(directory.as_os_str()),
        "-d",
        &[],
    ));
    assert_eq!(
        paths
            .iter()
            .filter(|path| Path::new(path).starts_with("$CDPATH"))
            .count(),
        1005
    );
    assert!(paths.contains(&OsString::from("$global/project")));
}

#[test]
fn cdpath_environment_is_ignored_without_option() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath");
    fs::create_dir_all(directory.join("child")).unwrap();
    let paths = fixture.run(
        fixture
            .command(&fixture.local, &fixture.global_dir, "-d", &[])
            .env("CDPATH", &directory),
    );
    assert!(paths.contains(&"dir".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("$CDPATH"))
    );
}

#[test]
fn cdpath_and_keep_dot_flags_work_in_both_orders() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath");
    fs::create_dir_all(directory.join("child")).unwrap();
    for keep_dot_first in [false, true] {
        let mut command = Command::new(env!("CARGO_BIN_EXE_fzfpaths"));
        command
            .current_dir(&fixture.local)
            .env("PWD", &fixture.local);
        if keep_dot_first {
            command.arg("--keep-dot");
        }
        command.arg("--cdpath").arg(&directory);
        if !keep_dot_first {
            command.arg("--keep-dot");
        }
        command
            .args([".", "$global", "-fd", "--dirali", "$global"])
            .arg(&fixture.global_dir);
        let paths = fixture.run(&mut command);
        assert!(paths.contains(&"$CDPATH/child".into()));
        assert!(paths.contains(&"./executable".into()));
    }
}

#[test]
fn empty_cdpath_disables_cdpath_choices() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command_with_cdpath(
        &[],
        &fixture.local,
        &fixture.global_dir,
        Some(OsStr::new("")),
        "-d",
        &[],
    ));
    assert!(paths.contains(&"dir".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("$CDPATH"))
    );
}

#[test]
fn directories_only() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(&fixture.local, &fixture.global_dir, "-d", &[]));
    assert!(paths.contains(&"dir".into()));
    assert!(paths.contains(&"linked".into()));
    assert!(paths.contains(&fixture.repo_alias.join("nested").into_os_string()));
    assert!(
        paths
            .iter()
            .all(|path| fixture.filesystem_path(path).is_dir())
    );
}

#[test]
fn global_directories_include_symlinks_and_submodules() {
    let fixture = Fixture::new();
    for (name, target) in [
        ("directory link\tname", "nested"),
        ("file-link", "tracked"),
        ("broken-link", "absent"),
    ] {
        symlink(target, fixture.repo.join(name)).unwrap();
    }
    fixture.git(&[
        "add",
        "--",
        "directory link\tname",
        "file-link",
        "broken-link",
    ]);
    fs::create_dir(fixture.repo.join("module")).unwrap();
    fixture.git(&[
        "update-index",
        "--add",
        "--cacheinfo",
        "160000,1111111111111111111111111111111111111111,module",
    ]);

    let paths = fixture.run(&mut fixture.command(&fixture.local, &fixture.global_dir, "-d", &[]));
    let global: HashSet<_> = paths
        .into_iter()
        .map(PathBuf::from)
        .filter(|path| Path::new(path).starts_with("$global/project"))
        .collect();
    let expected = [
        "",
        "nested",
        "line break",
        "node_modules",
        "directory link\tname",
        "module",
    ]
    .map(|path| fixture.repo_alias.join(path));
    assert_eq!(global, HashSet::from(expected));
}

#[test]
fn keep_dot_is_opt_in() {
    let fixture = Fixture::new();
    let paths = fixture.pick();
    assert!(paths.contains(&"executable".into()));
    assert!(!paths.contains(&"./executable".into()));
    let paths = fixture.run(&mut fixture.command_with_flags(
        &["--keep-dot"],
        &fixture.local,
        &fixture.global_dir,
        "-fd",
        &[],
    ));
    assert!(paths.contains(&"executable".into()));
    assert!(paths.contains(&"./executable".into()));
    assert!(!paths.contains(&"./file".into()));
    assert!(!paths.contains(&"./dir".into()));
}

#[test]
fn executable_paths_work_with_dot_roots_and_symlinks() {
    let fixture = Fixture::new();
    let name = "run with spaces";
    write_script(&fixture.local, name);
    symlink(
        fixture.local.join(name),
        fixture.local.join("linked-executable"),
    )
    .unwrap();
    for directory in [".", "./"] {
        let paths = fixture.run(
            Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
                .current_dir(&fixture.local)
                .env("PWD", &fixture.local)
                .args(["--keep-dot", directory, "", "-fd"]),
        );
        for executable in ["executable", name, "linked-executable"] {
            assert!(paths.contains(&OsString::from(executable)));
            assert!(paths.contains(&OsString::from(format!("./{executable}"))));
        }
        assert!(paths.contains(&"file".into()));
        assert!(!paths.contains(&"./file".into()));
        assert!(!paths.contains(&"./dir".into()));
    }
}

#[test]
fn executable_subdirectory_paths_get_both_forms() {
    let fixture = Fixture::new();
    write_script(&fixture.local, "fzfpaths/install.sh");
    for directory in [".", "fzfpaths"] {
        let paths = fixture.run(
            Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
                .current_dir(&fixture.local)
                .env("PWD", &fixture.local)
                .args(["--keep-dot", directory, "", "-fd"]),
        );
        assert!(paths.contains(&"fzfpaths/install.sh".into()));
        assert!(paths.contains(&"./fzfpaths/install.sh".into()));
    }
}

#[test]
fn executable_choices_preserve_plain_paths_and_env_dirs() {
    let fixture = Fixture::new();
    write_script(&fixture.repo, "tracked");
    let paths = fixture.run(&mut fixture.command_with_flags(
        &["--keep-dot"],
        &fixture.repo,
        &fixture.global_dir,
        "-fd",
        &[("$project", fixture.repo.as_path())],
    ));
    assert!(paths.contains(&"tracked".into()));
    assert!(paths.contains(&"./tracked".into()));
    assert!(!paths.contains(&"$project/tracked".into()));
    assert!(!paths.contains(&"./$project/tracked".into()));
    assert!(paths.contains(&"untracked".into()));
    assert!(!paths.contains(&"./untracked".into()));
    assert!(!paths.contains(&"./nested".into()));
}

#[test]
fn global_executables_do_not_add_relative_variants() {
    let fixture = Fixture::new();
    let executable = fixture.repo.join("tracked");
    make_executable(&executable);
    for env_dirs in [vec![], vec![("$project", fixture.repo.as_path())]] {
        let paths = fixture.run(&mut fixture.command_with_flags(
            &["--keep-dot"],
            &fixture.local,
            &fixture.global_dir,
            "-fd",
            &env_dirs,
        ));
        let edit = if env_dirs.is_empty() {
            "$global/project/tracked".into()
        } else {
            "$project/tracked".into()
        };
        assert!(paths.contains(&edit));
        assert!(!paths.iter().any(|path| {
            path.as_encoded_bytes().starts_with(b"./")
                && Path::new(path)
                    .file_name()
                    .is_some_and(|name| name == "tracked")
        }));
        assert!(!paths.contains(&"./$project/tracked".into()));
    }
}

#[test]
fn repositories_within_the_local_root_are_not_scanned_globally() {
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    mock_ls_files(
        &git,
        "#!/bin/sh\nprintf 'unexpected global scan' >&2\nexit 1\n",
    )
    .unwrap();
    make_executable(&git);
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let paths = fixture.run(
        fixture
            .command(&fixture.repo, &fixture.global_dir, "-fd", &[])
            .env("PATH", path),
    );
    assert!(paths.contains(&"tracked".into()));
    assert!(!paths.contains(&fixture.repo_alias.join("tracked").into_os_string()));
}

#[test]
fn literal_prefixes_are_escaped() {
    let fixture = Fixture::new();
    write(&fixture.local, "-literal");
    let paths = fixture.pick();
    assert!(paths.contains(&"./$literal".into()));
    assert!(paths.contains(&"./~literal".into()));
    assert!(paths.contains(&"./-literal".into()));
}

#[test]
fn executable_literal_prefixes_are_not_duplicated_or_expanded() {
    let fixture = Fixture::new();
    for name in ["$literal", "~literal", "-literal"] {
        write_script(&fixture.local, name);
    }
    let paths = fixture.pick();
    for name in ["$literal", "~literal", "-literal"] {
        let escaped = OsString::from(format!("./{name}"));
        assert_eq!(paths.iter().filter(|path| *path == &escaped).count(), 1);
        assert!(!paths.contains(&OsString::from(name)));
        assert!(!paths.contains(&OsString::from(format!("././{name}"))));
    }
}

#[test]
fn ignored_directories_and_cycles_preserve_broken_links() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", &[]));
    for absent in ["node_modules", ".git"] {
        assert!(!paths.contains(&absent.into()));
    }
    assert!(paths.contains(&"broken".into()));
    assert!(paths.contains(&"linked/child".into()));
    assert!(paths.contains(&"loop".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("loop") && path != "loop")
    );
}

#[test]
fn empty_or_missing_global_alias() {
    let fixture = Fixture::new();
    let empty = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", &[]));
    let missing =
        fixture.run(&mut fixture.command(&fixture.local, &fixture.root.join("absent"), "-fd", &[]));
    assert_eq!(
        HashSet::<_>::from_iter(empty),
        HashSet::<_>::from_iter(missing)
    );
}

#[test]
fn global_scan_requires_a_registered_alias_name() {
    let fixture = Fixture::new();
    for global in [OsStr::new("$missing"), fixture.global_dir.as_os_str()] {
        let output = Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .current_dir(&fixture.local)
            .arg(".")
            .arg(global)
            .args(["-fd", "--dirali", "$global"])
            .arg(&fixture.global_dir)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stdout.is_empty());
        assert_eq!(
            String::from_utf8(output.stderr).unwrap(),
            format!(
                "fzfpaths: unknown global directory alias: {}\n",
                global.to_string_lossy()
            )
        );
    }
}

#[test]
fn global_alias_uses_its_registered_directory() {
    let fixture = Fixture::new();
    let paths = fixture.run(
        fixture
            .command(&fixture.local, &fixture.global_dir, "-f", &[])
            .env("global", fixture.root.join("absent")),
    );
    assert!(paths.contains(&"$global/project/tracked".into()));
    assert!(!paths.iter().any(|path| Path::new(path).is_absolute()));
}

#[test]
fn logical_working_directory() {
    let fixture = Fixture::new();
    let link = fixture.root.join("logical");
    symlink(&fixture.local, &link).unwrap();
    let mut command = fixture.command(&fixture.local, &fixture.global_dir, "-fd", &[]);
    command.env("PWD", link);
    assert_eq!(
        HashSet::<_>::from_iter(fixture.pick()),
        HashSet::<_>::from_iter(fixture.run(&mut command))
    );
}

#[test]
fn relative_directory_aliases_are_rejected() {
    let fixture = Fixture::new();
    let logical = fixture.root.join("cwd-link");
    symlink(&fixture.local, &logical).unwrap();
    for cwd in [&fixture.local, &logical] {
        for directory in ["", ".", "relative", "../global_dir", "repo-link/.."] {
            let output = fixture
                .command(
                    cwd,
                    &fixture.global_dir,
                    "-f",
                    &[("$project", Path::new(directory))],
                )
                .output()
                .unwrap();
            assert_eq!(output.status.code(), Some(1));
            assert!(output.stdout.is_empty());
            assert_eq!(
                String::from_utf8(output.stderr).unwrap(),
                format!(
                    "fzfpaths: directory alias $project requires an absolute path: {directory}\n"
                )
            );
        }
    }
}

#[test]
fn global_symlink_parent_roots_use_the_target_and_preserve_aliases() {
    let fixture = Fixture::new();
    let child = fixture.global_dir.join("child");
    fs::create_dir(&child).unwrap();
    let link = fixture.local.join("global-link");
    symlink("../global_dir/child", fixture.local.join("middle-link")).unwrap();
    let root = link.join("..");
    let wrong = fixture.local.join("wrong-project");
    checked(Command::new("git").args(["init", "-q"]).arg(&wrong));
    write(&wrong, "wrong-file");

    for target in [
        child.as_path(),
        Path::new("../global_dir/child"),
        Path::new("middle-link"),
    ] {
        symlink(target, &link).unwrap();
        for aliases in [vec![], vec![("$project", fixture.repo.as_path())]] {
            let paths = fixture.run(&mut fixture.command(&fixture.local, &root, "-f", &aliases));
            let expected = if aliases.is_empty() {
                OsString::from("$global/project/tracked")
            } else {
                OsString::from("$project/tracked")
            };
            assert!(paths.contains(&expected), "target {target:?}");
            assert!(!paths.iter().any(|path| Path::new(path).starts_with(&wrong)));
        }
        fs::remove_file(&link).unwrap();
    }

    // Canonical roots keep the registered alias rather than exposing the physical path.
    let root = fixture.root.join("logical-global");
    symlink(&fixture.global_dir, &root).unwrap();
    let alias = root.join("project");
    let paths = fixture.run(&mut fixture.command(&fixture.local, &root, "-f", &[]));
    assert!(paths.contains(&"$global/project/tracked".into()));
    let paths =
        fixture.run(&mut fixture.command(&fixture.local, &root, "-f", &[("$project", &alias)]));
    assert!(paths.contains(&"$project/tracked".into()));
}

#[test]
fn cdpath_symlink_parent_roots_use_the_target() {
    let fixture = Fixture::new();
    let child = fixture.global_dir.join("child");
    fs::create_dir(&child).unwrap();
    let link = fixture.local.join("global-link");
    symlink(&child, &link).unwrap();
    let root = link.join("..");
    let paths = fixture.run(&mut fixture.command_with_cdpath(
        &[],
        &fixture.local,
        Path::new(""),
        Some(root.as_os_str()),
        "-d",
        &[],
    ));
    assert!(paths.contains(&"$CDPATH/project".into()));
    assert!(!paths.contains(&"$CDPATH/dir".into()));

    // A missing component cannot be cancelled by .. during filesystem lookup.
    let missing = fixture.local.join("missing/..");
    let paths = fixture.run(&mut fixture.command_with_cdpath(
        &[],
        &fixture.local,
        Path::new(""),
        Some(missing.as_os_str()),
        "-d",
        &[],
    ));
    assert!(
        !paths
            .iter()
            .any(|path| path.as_encoded_bytes().starts_with(b"$CDPATH/"))
    );
}

#[test]
fn local_gitignore_hides_build_outputs() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/target/\n*.tmp\n").unwrap();
    write(&fixture.repo, "target/debug/application");
    write(&fixture.repo, "scratch.tmp");
    write(&fixture.repo, "visible");
    let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-fd", &[]));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("target"))
    );
    assert!(!paths.contains(&"scratch.tmp".into()));
    assert!(paths.contains(&"visible".into()));
}

#[test]
fn local_exclusions_follow_git_precedence() {
    let fixture = Fixture::new();
    let global = fixture.root.join("global-ignore");
    fs::write(&global, "*.tmp\n*.cache\n/root-hidden/\n").unwrap();
    fixture.git(&["config", "core.excludesFile", global.to_str().unwrap()]);
    fs::write(
        fixture.repo.join(".git/info/exclude"),
        "!from-info.tmp\n*.info\n",
    )
    .unwrap();
    fs::write(
        fixture.repo.join(".gitignore"),
        "!from-repo.tmp\n!from-repo.info\n",
    )
    .unwrap();
    fs::write(fixture.repo.join("nested/.gitignore"), "!from-nested.tmp\n").unwrap();
    for name in [
        "drop.tmp",
        "drop.cache",
        "drop.info",
        "from-info.tmp",
        "from-repo.tmp",
        "from-repo.info",
        "nested/from-nested.tmp",
        "nested/drop.tmp",
        "root-hidden/file",
    ] {
        write(&fixture.repo, name);
    }
    let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-f", &[]));
    for name in [
        "from-info.tmp",
        "from-repo.tmp",
        "from-repo.info",
        "nested/from-nested.tmp",
    ] {
        assert!(paths.contains(&name.into()), "missing {name}");
    }
    for name in [
        "drop.tmp",
        "drop.cache",
        "drop.info",
        "nested/drop.tmp",
        "root-hidden/file",
    ] {
        assert!(!paths.contains(&name.into()), "ignored {name} was shown");
    }
}

#[test]
fn unclosed_gitignore_classes_do_not_hide_literal_filenames() {
    for source in [
        ".gitignore",
        ".git/info/exclude",
        "global-ignore",
        "nested/.gitignore",
    ] {
        let fixture = Fixture::new();
        for name in ["[", "name[abc", "literal[", "classa"] {
            write(&fixture.repo.join("nested"), name);
        }
        let file = fixture.repo.join(source);
        fs::write(&file, "[\nname[abc\nliteral\\[\nclass[ab]\n").unwrap();
        if source == "global-ignore" {
            fixture.git(&["config", "core.excludesFile", file.to_str().unwrap()]);
        }
        let paths = fixture.run(&mut fixture.command(
            &fixture.repo.join("nested"),
            Path::new(""),
            "-f",
            &[],
        ));
        for name in ["[", "name[abc"] {
            assert!(paths.contains(&name.into()), "{source} hid {name}");
        }
        for name in ["literal[", "classa"] {
            assert!(!paths.contains(&name.into()), "{source} showed {name}");
        }
    }
}

#[test]
fn bare_negations_and_posix_classes_follow_git() {
    for (pattern, ignored, visible) in [
        ("ignored/\n!\n", "ignored/file", "visible"),
        ("[[:digit:]]\n", "1", "d]"),
    ] {
        let fixture = Fixture::new();
        fs::write(fixture.repo.join(".gitignore"), pattern).unwrap();
        write(&fixture.repo, ignored);
        write(&fixture.repo, visible);
        let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-f", &[]));
        assert!(
            !paths.contains(&ignored.into()),
            "{pattern:?} showed {ignored}"
        );
        assert!(paths.contains(&visible.into()), "{pattern:?} hid {visible}");
    }
}

#[test]
fn local_ignore_sources_respect_core_ignorecase() {
    let fixture = Fixture::new();
    let global = fixture.root.join("global-ignore");
    fs::write(&global, "*.GLOBAL\n").unwrap();
    fixture.git(&["config", "core.excludesFile", global.to_str().unwrap()]);
    fs::write(fixture.repo.join(".gitignore"), "*.LOCAL\n").unwrap();
    fs::write(fixture.repo.join(".git/info/exclude"), "*.INFO\n").unwrap();
    for name in ["file.local", "file.global", "file.info"] {
        write(&fixture.repo, name);
    }
    for (setting, shown) in [("false", true), ("true", false)] {
        fixture.git(&["config", "core.ignorecase", setting]);
        let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-f", &[]));
        for name in ["file.local", "file.global", "file.info"] {
            assert_eq!(paths.contains(&name.into()), shown, "{setting}: {name}");
        }
        assert!(paths.contains(&"tracked".into()));
    }
    let config = fixture.repo.join(".git/config");
    let mut text = fs::read_to_string(&config).unwrap();
    text.push_str("\n[core]\nignorecase\n");
    fs::write(config, text).unwrap();
    let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-f", &[]));
    assert!(!paths.contains(&"file.local".into()));
}

#[test]
fn nested_repositories_use_their_own_ignorecase_setting() {
    let fixture = Fixture::new();
    let nested = fixture.repo.join("nested-repository");
    fixture.git(&["init", "-q", nested.to_str().unwrap()]);
    fs::write(fixture.repo.join(".gitignore"), "*.CACHE\n").unwrap();
    fs::write(nested.join(".gitignore"), "*.CACHE\n").unwrap();
    write(&fixture.repo, "outer.cache");
    write(&nested, "inner.cache");
    for (outer, inner) in [("true", "false"), ("false", "true")] {
        fixture.git(&["config", "core.ignorecase", outer]);
        fixture.git(&[
            "-C",
            nested.to_str().unwrap(),
            "config",
            "core.ignorecase",
            inner,
        ]);
        let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-f", &[]));
        assert_eq!(paths.contains(&"outer.cache".into()), outer == "false");
        assert_eq!(
            paths.contains(&"nested-repository/inner.cache".into()),
            inner == "false"
        );
    }
}

#[test]
fn local_exclusions_distinguish_unset_and_empty_global_file() {
    let fixture = Fixture::new();
    let config = fixture.root.join("config");
    fs::create_dir_all(config.join("git")).unwrap();
    fs::write(config.join("git/ignore"), ".DS_Store\n").unwrap();
    write(&fixture.repo, ".DS_Store");
    let paths = fixture.run(
        fixture
            .command(&fixture.repo, Path::new(""), "-f", &[])
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("XDG_CONFIG_HOME", &config),
    );
    assert!(!paths.contains(&".DS_Store".into()));
    assert!(paths.contains(&"tracked".into()));

    fixture.git(&["config", "core.excludesFile", ""]);
    let paths = fixture.run(
        fixture
            .command(&fixture.repo, Path::new(""), "-f", &[])
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("XDG_CONFIG_HOME", config),
    );
    assert!(paths.contains(&".DS_Store".into()));
}

#[test]
fn local_worktree_exclusions_respect_included_configuration() {
    let fixture = Fixture::new();
    let global = fixture.root.join("global-ignore");
    fs::write(&global, "global-secret\n").unwrap();
    let included = fixture.root.join("included-config");
    fixture.git(&[
        "config",
        "--file",
        included.to_str().unwrap(),
        "core.excludesFile",
        global.to_str().unwrap(),
    ]);
    fixture.git(&["config", "include.path", included.to_str().unwrap()]);
    fs::write(fixture.repo.join(".git/info/exclude"), "info-secret\n").unwrap();
    fixture.git(&[
        "-c",
        "user.name=Fixture",
        "-c",
        "user.email=fixture@example.invalid",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-qm",
        "fixture",
    ]);
    let worktree = fixture.root.join("worktree");
    fixture.git(&["worktree", "add", "--detach", worktree.to_str().unwrap()]);
    write(&worktree, "global-secret");
    write(&worktree, "info-secret");
    let paths = fixture.run(&mut fixture.command(&worktree, Path::new(""), "-f", &[]));
    assert!(paths.contains(&"tracked".into()));
    assert!(!paths.contains(&"global-secret".into()));
    assert!(!paths.contains(&"info-secret".into()));
}

#[test]
fn cancelling_a_walk_with_no_file_results_stops_the_workers() {
    for signal in [None, Some(15)] {
        let fixture = Fixture::new();
        let graph = fixture.root.join("graph");
        for level in 0..23 {
            let directory = graph.join(level.to_string());
            fs::create_dir_all(&directory).unwrap();
            if level > 0 {
                for name in ["a", "b"] {
                    symlink(format!("../{}", level - 1), directory.join(name)).unwrap();
                }
            }
        }
        let mut child = fixture
            .command(&graph.join("22"), Path::new(""), "-f", &[])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        std::thread::sleep(Duration::from_millis(100));
        assert!(
            child.try_wait().unwrap().is_none(),
            "fixture finished before cancellation"
        );
        if let Some(signal) = signal {
            unsafe extern "C" {
                fn kill(pid: i32, signal: i32) -> i32;
            }
            assert_eq!(unsafe { kill(child.id() as i32, signal) }, 0);
        } else {
            drop(child.stdout.take());
        }
        let deadline = Instant::now() + Duration::from_secs(2);
        let stopped = loop {
            if child.try_wait().unwrap().is_some() {
                break true;
            }
            if Instant::now() >= deadline {
                child.kill().unwrap();
                break false;
            }
            std::thread::sleep(Duration::from_millis(10));
        };
        let output = child.wait_with_output().unwrap();
        assert!(stopped, "empty-result traversal ignored cancellation");
        assert_eq!(
            output.status.code(),
            Some(signal.map_or(0, |signal| 128 + signal))
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    }
}

#[test]
fn ignored_directories_are_not_offered_for_cd() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/target/\n").unwrap();
    write(&fixture.repo, "target/debug/application");
    let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-d", &[]));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("target"))
    );
    assert!(paths.contains(&"nested".into()));
}

#[test]
fn parent_and_nested_gitignore_rules_apply() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "*.tmp\n").unwrap();
    fs::write(fixture.repo.join("nested/.gitignore"), "!keep.tmp\n").unwrap();
    write(&fixture.repo, "nested/keep.tmp");
    write(&fixture.repo, "nested/hide.tmp");
    let paths =
        fixture.run(&mut fixture.command(&fixture.repo.join("nested"), Path::new(""), "-fd", &[]));
    assert!(paths.contains(&"keep.tmp".into()));
    assert!(!paths.contains(&"hide.tmp".into()));
}

#[test]
fn symlink_parent_search_uses_the_target_gitignore_rules() {
    let fixture = Fixture::new();
    let external = fixture.root.join("external");
    for name in [
        "child/placeholder",
        "shown",
        "hidden",
        "nested/keep.tmp",
        "nested/hide.tmp",
        "ignored/deep/build.tmp",
        "ignored/deep/build.cache",
    ] {
        write(&external, name);
    }
    fs::write(external.join(".gitignore"), "/hidden\n*.tmp\n/ignored/\n").unwrap();
    fs::write(external.join("nested/.gitignore"), "!keep.tmp\n").unwrap();
    fs::write(external.join("ignored/.gitignore"), "*.cache\n").unwrap();
    symlink("../external/child", fixture.local.join("link")).unwrap();

    let scan = |directory: &str| {
        fixture.run(
            Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
                .current_dir(&fixture.local)
                .env("PWD", &fixture.local)
                .args([directory, "", "-f"]),
        )
    };
    let paths = scan("link/..");
    assert!(paths.contains(&"link/../shown".into()));
    assert!(paths.contains(&"link/../nested/keep.tmp".into()));
    assert!(!paths.contains(&"link/../hidden".into()));
    assert!(!paths.contains(&"link/../nested/hide.tmp".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("link/../ignored"))
    );

    // Explicitly entering an ignored directory still bypasses outer rules.
    let paths = scan("link/../ignored/deep");
    assert_eq!(paths, [OsString::from("link/../ignored/deep/build.tmp")]);
}

#[test]
fn ignored_directory_can_be_searched_from_inside() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/target/\n*.tmp\n").unwrap();
    write(&fixture.repo, "target/application");
    write(&fixture.repo, "target/build.tmp");
    write(&fixture.repo, "target/hidden/private");
    fs::write(fixture.repo.join("target/.gitignore"), "hidden/\n").unwrap();
    let paths =
        fixture.run(&mut fixture.command(&fixture.repo.join("target"), Path::new(""), "-fd", &[]));
    assert!(paths.contains(&"application".into()));
    assert!(paths.contains(&"build.tmp".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("hidden"))
    );
}

#[test]
fn explicitly_selected_ignored_directory_can_be_searched() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/target/\n").unwrap();
    write(&fixture.repo, "target/deep/application");
    let paths = fixture.run(
        Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .current_dir(&fixture.repo)
            .env("PWD", &fixture.repo)
            .args(["target/deep", "", "-fd"]),
    );
    assert!(paths.contains(&"target/deep/application".into()));
}

#[test]
fn descendants_of_ignored_directories_keep_inner_rules() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/target/\n*.tmp\n").unwrap();
    write(&fixture.repo, "target/sibling");
    write(&fixture.repo, "target/deep/application");
    write(&fixture.repo, "target/deep/build.tmp");
    write(&fixture.repo, "target/deep/build.cache");
    fs::write(fixture.repo.join("target/.gitignore"), "*.cache\n").unwrap();
    let paths = fixture.run(&mut fixture.command(
        &fixture.repo.join("target/deep"),
        Path::new(""),
        "-fd",
        &[],
    ));
    assert_eq!(
        paths.into_iter().collect::<HashSet<_>>(),
        HashSet::from([OsString::from("application"), OsString::from("build.tmp")])
    );
}

#[test]
fn explicit_search_can_cross_normally_skipped_ancestors() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/target/\n").unwrap();
    write(&fixture.repo, "target/node_modules/package/application");
    let paths = fixture.run(
        Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .current_dir(&fixture.repo)
            .env("PWD", &fixture.repo)
            .args(["./target/node_modules/package", "", "-fd"]),
    );
    assert_eq!(
        paths,
        [OsString::from("target/node_modules/package/application")]
    );
}

#[test]
fn ignored_symlink_cycles_are_not_offered() {
    let fixture = Fixture::new();
    fs::write(fixture.local.join(".gitignore"), "/loop\n").unwrap();
    let paths = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", &[]));
    assert!(!paths.contains(&"loop".into()));
    assert!(paths.contains(&"linked/child".into()));
}

#[test]
fn gitignore_does_not_hide_globally_tracked_paths() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/nested/\n").unwrap();
    assert!(
        fixture
            .pick()
            .contains(&OsString::from("$global/project/nested/child"))
    );
}

#[test]
fn escaped_gitignore_patterns_are_respected() {
    let fixture = Fixture::new();
    fs::write(
        fixture.repo.join(".gitignore"),
        "\\!secret\n\\#secret\n/build output/\n",
    )
    .unwrap();
    for name in ["!secret", "#secret", "build output/application", "visible"] {
        write(&fixture.repo, name);
    }
    let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-fd", &[]));
    assert!(!paths.contains(&"!secret".into()));
    assert!(!paths.contains(&"#secret".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("build output"))
    );
    assert!(paths.contains(&"visible".into()));
}

#[test]
fn local_file_variants_preserve_order_and_markers() {
    let fixture = Fixture::new();
    let mut command = fixture.command_with_flags(
        &["--read0", "--keep-dot", "--classify"],
        &fixture.local,
        Path::new(""),
        "-fd",
        &[],
    );
    let paths = from_input(
        &mut command,
        &[
            &fixture.local.join("file"),
            &fixture.local.join("executable"),
        ],
    );
    assert_eq!(
        paths,
        ["file\u{1f}", "executable*", "./executable*"].map(OsString::from)
    );
}

#[test]
fn input_paths_preserve_order_and_share_executable_rules() {
    let fixture = Fixture::new();
    let script = fixture.local.join("executable");
    let binary = fixture.local.join("binary");
    fs::write(&binary, b"\x7fELF").unwrap();
    make_executable(&binary);
    write_script(&fixture.repo, "script");
    for keep_dot in [false, true] {
        let mut command = fixture.command_with_flags(
            if keep_dot {
                &["--read0", "--keep-dot"]
            } else {
                &["--read0"]
            },
            &fixture.local,
            &fixture.global_dir,
            "-f",
            &[("$project", &fixture.repo)],
        );
        let paths = from_input(
            &mut command,
            &[
                &script,
                &fixture.repo.join("tracked"),
                &fixture.local.join("missing"),
                &fixture.local.join("dir"),
                &binary,
                &fixture.local.join("file"),
                &script,
                &fixture.repo.join("script"),
                &fixture.local.join("node_modules/excluded"),
            ],
        );
        let mut expected = vec![OsString::from("executable")];
        if keep_dot {
            expected.push("./executable".into());
        }
        expected.extend(
            [
                "$project/tracked",
                "./binary",
                "file",
                "$project/script",
                "node_modules/excluded",
            ]
            .map(OsString::from),
        );
        assert_eq!(paths, expected);
    }
}

#[test]
fn input_paths_reject_relative_filenames() {
    let fixture = Fixture::new();
    for path in ["file", "./file", "../global_dir/project/tracked"] {
        let mut child = fixture
            .command_with_flags(&["--read0"], &fixture.local, Path::new(""), "-f", &[])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(format!("{path}\0").as_bytes())
            .unwrap();
        let output = child.wait_with_output().unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stdout.is_empty());
        assert_eq!(
            output.stderr,
            format!("fzfpaths: --read0 requires absolute paths: {path}\n").as_bytes()
        );
    }
}

#[test]
fn input_paths_preserve_symlink_filenames() {
    let fixture = Fixture::new();
    let outside = fixture.root.join("outside");
    fs::create_dir(&outside).unwrap();
    write(&outside, "file");
    symlink("file", outside.join("file-link")).unwrap();
    let paths = from_input(
        &mut fixture.command_with_flags(
            &["--read0"],
            &fixture.local,
            Path::new(""),
            "-f",
            &[("$outside", &outside)],
        ),
        &[&outside.join("file-link")],
    );
    assert_eq!(paths, [OsString::from("$outside/file-link")]);
}

#[test]
fn directory_aliases_match_logical_and_physical_input_paths() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("external");
    write(&directory, "file");
    let alias = fixture.root.join("alias");
    symlink(&directory, &alias).unwrap();
    let physical = directory.canonicalize().unwrap();
    let paths = from_input(
        &mut fixture.command_with_flags(
            &["--read0"],
            &fixture.local,
            Path::new(""),
            "-f",
            &[("$TMPDIR", &alias)],
        ),
        &[&alias.join("file"), &physical.join("file")],
    );
    assert_eq!(paths, [OsString::from("$TMPDIR/file")]);
}

#[test]
fn directory_aliases_trim_only_trailing_slashes() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("external");
    write(&directory, "file");
    let directory = directory.canonicalize().unwrap();
    fs::create_dir(fixture.root.join("parent")).unwrap();
    let file = directory.join("file");
    for (alias, logical) in [
        (
            PathBuf::from(format!("{}///", directory.display())),
            file.clone(),
        ),
        (directory.join("."), directory.join("./file")),
        (
            fixture.root.join("parent/../external"),
            fixture.root.join("parent/../external/file"),
        ),
    ] {
        let paths = from_input(
            &mut fixture.command_with_flags(
                &["--read0"],
                &fixture.local,
                Path::new(""),
                "-f",
                &[("$project", &alias)],
            ),
            &[&logical, &file],
        );
        assert_eq!(paths, [OsString::from("$project/file")], "{alias:?}");
    }
}

#[test]
fn root_directory_alias_preserves_the_path_separator() {
    let fixture = Fixture::new();
    for (root, specific) in [("/", false), ("////", false), ("/", true)] {
        let mut aliases = vec![("$root", Path::new(root))];
        if specific {
            aliases.push(("$project", fixture.repo.as_path()));
        }
        let paths = from_input(
            &mut fixture.command_with_flags(
                &["--read0"],
                &fixture.local,
                Path::new(""),
                "-f",
                &aliases,
            ),
            &[&fixture.repo.join("tracked")],
        );
        let expected = if specific {
            "$project/tracked".into()
        } else {
            format!("$root{}", fixture.repo.join("tracked").display())
        };
        assert_eq!(paths, [OsString::from(expected)]);
    }
}

#[test]
fn input_paths_use_local_rules_for_physical_and_logical_cwd() {
    let fixture = Fixture::new();
    let alias = fixture.root.join("alias");
    symlink(&fixture.local, &alias).unwrap();
    let paths = from_input(
        &mut fixture.command_with_flags(
            &["--read0", "--keep-dot"],
            &alias,
            &fixture.global_dir,
            "-f",
            &[],
        ),
        &[
            &fixture.local.join("file"),
            &alias.join("file"),
            &alias.join("executable"),
        ],
    );
    assert_eq!(
        paths,
        ["file", "executable", "./executable"].map(OsString::from)
    );
}

#[test]
fn physical_input_keeps_local_symlink_paths_with_a_logical_cwd() {
    let fixture = Fixture::new();
    let alias = fixture.root.join("alias");
    symlink(&fixture.local, &alias).unwrap();
    symlink(&fixture.repo, fixture.local.join("link")).unwrap();
    let paths = from_input(
        &mut fixture.command_with_flags(&["--read0"], &alias, Path::new(""), "-f", &[]),
        &[&fixture.local.canonicalize().unwrap().join("link/tracked")],
    );
    assert_eq!(paths, [OsString::from("link/tracked")]);
}

#[test]
fn empty_input_does_not_start_any_scans() {
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    fs::write(&git, "#!/bin/sh\necho unexpected Git scan >&2\nexit 1\n").unwrap();
    make_executable(&git);
    let paths = from_input(
        fixture
            .command_with_flags(
                &["--read0"],
                &fixture.local,
                &fixture.global_dir,
                "-fd",
                &[],
            )
            .env("PATH", &bin),
        &[],
    );
    assert!(paths.is_empty());
}

#[test]
fn input_waiting_for_data_stops_when_output_is_closed() {
    let fixture = Fixture::new();
    let mut child = fixture
        .command_with_flags(&["--read0"], &fixture.local, &fixture.global_dir, "-f", &[])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let input = child.stdin.take().unwrap();
    drop(child.stdout.take());
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            assert!(status.success());
            break;
        }
        if Instant::now() >= deadline {
            child.kill().unwrap();
            child.wait().unwrap();
            panic!("input reader ignored the closed output pipe");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    drop(input);
}

#[test]
fn repeated_input_stops_when_output_is_closed() {
    let fixture = Fixture::new();
    let mut child = fixture
        .command_with_flags(&["--read0"], &fixture.local, Path::new(""), "-f", &[])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    let mut path = fixture.local.join("file").into_os_string().into_vec();
    path.push(0);
    let producer = std::thread::spawn(move || {
        let batch = path.repeat(1024);
        while input.write_all(&batch).is_ok() {}
    });
    let mut output = BufReader::new(child.stdout.take().unwrap());
    let mut first = Vec::new();
    output.read_until(0, &mut first).unwrap();
    assert_eq!(first, b"file\0");
    drop(output);
    let deadline = Instant::now() + Duration::from_secs(2);
    let stopped = loop {
        if child.try_wait().unwrap().is_some() {
            break true;
        }
        if Instant::now() >= deadline {
            child.kill().unwrap();
            break false;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    let output = child.wait_with_output().unwrap();
    producer.join().unwrap();
    assert!(stopped, "duplicate input hid the closed output pipe");
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn dirali_options_work_before_and_after_positions() {
    let fixture = Fixture::new();
    let paths = fixture.run(
        Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .current_dir(&fixture.local)
            .env("PWD", &fixture.local)
            .arg("--dirali")
            .arg("$global_dir")
            .arg(&fixture.global_dir)
            .args([".", "$global_dir"])
            .arg("--keep-dot")
            .arg("--dirali")
            .arg("$project")
            .arg(&fixture.repo)
            .arg("-fd"),
    );
    assert!(paths.contains(&"$project/nested/child".into()));
    assert!(paths.contains(&"./executable".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("$global_dir/project"))
    );
}

#[test]
fn bare_alias_pairs_are_rejected() {
    let fixture = Fixture::new();
    let output = fixture
        .command(&fixture.local, &fixture.global_dir, "-fd", &[])
        .arg("$project")
        .arg(&fixture.repo)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(output.stderr.starts_with(b"usage: "));
}

#[test]
fn invalid_arguments() {
    for args in [
        vec![],
        vec!["--cdpath"],
        vec!["--dirali"],
        vec!["", "", "wrong"],
        vec!["", "", ""],
        vec!["", "", "-df"],
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .arg0("/some/path/renamed-picker")
            .args(args)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stdout.is_empty());
        assert_eq!(
        output.stderr,
        b"usage: renamed-picker [--color] [--classify] [--keep-dot] [--read0] [--cdpath CDPATH] <DIR> <GLOBAL_ALIAS> <TYPE> [--dirali <ENV> <DIR>]...\n"
    );
    }
}

#[test]
fn help_uses_invoked_basename() {
    for flags in [
        vec!["--help"],
        vec!["-h"],
        vec!["--color", "--help"],
        vec!["--classify", "--help"],
        vec!["--color", "--classify", "--help"],
        vec!["--color", "--keep-dot", "--help"],
        vec!["--keep-dot", "--help"],
        vec!["--read0", "--help"],
        vec!["--cdpath", "", "--help"],
        vec!["--keep-dot", "--cdpath", "", "--help"],
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .arg0("/some/path/renamed-picker")
            .args(flags)
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(output.stderr.is_empty());
        let help = String::from_utf8(output.stdout).unwrap();
        assert!(help.contains(
            "usage: renamed-picker [--color] [--classify] [--keep-dot] [--read0] [--cdpath CDPATH] <DIR> <GLOBAL_ALIAS> <TYPE> [--dirali <ENV> <DIR>]..."
        ));
        assert!(help.contains("Generate path candidates"));
        assert!(help.contains(".gitignore"));
        assert!(help.contains("Options:"));
        assert!(help.contains("NUL-separated absolute filenames"));
        assert!(help.contains("Relative filenames are rejected."));
        assert!(help.contains("Examples (Fish):"));
        assert!(help.contains("GLOBAL_ALIAS"));
        assert!(help.contains("Each --dirali"));
        assert!(help.contains("colon-separated roots"));
        assert!(help.contains("Fish bindings keep directory aliases in the command line"));
        assert!(help.contains("shell expands them when the command is executed"));
        assert!(help.contains("--keep-dot"));
        assert!(help.contains("--read0"));
        assert!(!help.contains("LABEL"));
        assert!(!help.contains("OWNER"));
        assert!(!help.contains("usage: fzfpaths"));
    }
}

#[test]
fn incomplete_dirali_is_a_usage_error() {
    let output = Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
        .arg0("/some/path/renamed-picker")
        .args([".", "", "-fd", "--dirali", "unpaired"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert_eq!(
        output.stderr,
        b"usage: renamed-picker [--color] [--classify] [--keep-dot] [--read0] [--cdpath CDPATH] <DIR> <GLOBAL_ALIAS> <TYPE> [--dirali <ENV> <DIR>]...\n"
    );
}

#[test]
fn runtime_errors_use_invoked_basename() {
    let fixture = Fixture::new();
    let output = fixture
        .command(&fixture.local, &fixture.global_dir, "-fd", &[])
        .arg0("/some/path/renamed-picker")
        .env("PATH", fixture.root.join("no-commands"))
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stderr.starts_with(b"renamed-picker: "));
}

#[test]
fn local_binary_executables_only_offer_dot_paths() {
    let fixture = Fixture::new();
    fs::write(fixture.local.join("binary"), b"\x7fELF\0content").unwrap();
    make_executable(fixture.local.join("binary"));
    symlink("binary", fixture.local.join("binary-link")).unwrap();
    for flags in [
        vec![],
        vec!["--keep-dot"],
        vec!["--classify"],
        vec!["--classify", "--keep-dot"],
    ] {
        let paths = fixture.run(&mut fixture.command_with_flags(
            &flags,
            &fixture.local,
            Path::new(""),
            "-f",
            &[],
        ));
        let marked = flags.contains(&"--classify");
        let marker = if marked { "*" } else { "" };
        let link_marker = if marked { "@" } else { "" };
        assert!(paths.contains(&OsString::from(format!("./binary{marker}"))));
        assert!(!paths.contains(&OsString::from(format!("binary{marker}"))));
        assert!(paths.contains(&OsString::from(format!("./binary-link{link_marker}"))));
        assert!(!paths.contains(&OsString::from(format!("binary-link{link_marker}"))));
    }
}

#[test]
fn global_binary_executables_use_directory_aliases() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join("binary"), b"\x7fELF\0content").unwrap();
    make_executable(fixture.repo.join("binary"));
    fixture.git(&["add", "binary"]);
    let paths = fixture.run(&mut fixture.command(&fixture.local, &fixture.global_dir, "-f", &[]));
    assert!(paths.contains(&fixture.repo_alias.join("binary").into_os_string()));
    let paths = fixture.run(&mut fixture.command(
        &fixture.local,
        &fixture.global_dir,
        "-f",
        &[("$project", &fixture.repo)],
    ));
    assert!(paths.contains(&OsString::from("$project/binary")));
    let paths = fixture.run(&mut fixture.command(
        &fixture.repo,
        &fixture.global_dir,
        "-f",
        &[("$project", &fixture.repo)],
    ));
    assert!(paths.contains(&OsString::from("./binary")));
    assert!(!paths.contains(&OsString::from("$project/binary")));
    assert!(!paths.contains(&OsString::from("binary")));
}

#[test]
fn local_executable_detection_only_checks_shebang() {
    let fixture = Fixture::new();
    for (name, content) in [
        ("empty", b"".as_slice()),
        ("short", b"#".as_slice()),
        ("text", b"printf hello\n".as_slice()),
        ("late-shebang", b" #!/bin/sh\n".as_slice()),
        ("shebang", b"#!".as_slice()),
        ("shebang-with-nul", b"#!/bin/sh\n\0".as_slice()),
    ] {
        fs::write(fixture.local.join(name), content).unwrap();
        make_executable(fixture.local.join(name));
    }
    fs::write(fixture.local.join("data"), b"\0content").unwrap();
    let paths = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-f", &[]));
    for name in ["empty", "short", "text", "late-shebang"] {
        assert!(paths.contains(&OsString::from(format!("./{name}"))));
        assert!(!paths.contains(&OsString::from(name)));
    }
    for name in ["shebang", "shebang-with-nul", "data"] {
        assert!(paths.contains(&OsString::from(name)));
        assert!(!paths.contains(&OsString::from(format!("./{name}"))));
    }
}

#[test]
fn absolute_local_binary_paths_are_relative_to_the_physical_cwd() {
    let fixture = Fixture::new();
    let external = fixture.root.join("outside");
    fs::create_dir(&external).unwrap();
    fs::write(external.join("binary"), b"\0content").unwrap();
    make_executable(external.join("binary"));
    let logical = fixture.root.join("deep/alias");
    fs::create_dir_all(logical.parent().unwrap()).unwrap();
    symlink(&fixture.local, &logical).unwrap();
    let paths = fixture.run(
        Command::new(env!("CARGO_BIN_EXE_fzfpaths"))
            .current_dir(&fixture.local)
            .env("PWD", &logical)
            .arg(&external)
            .args(["", "-f"]),
    );
    assert_eq!(paths.len(), 1);
    assert!(paths[0].as_encoded_bytes().starts_with(b"./"));
    assert_eq!(
        fixture.local.join(&paths[0]).canonicalize().unwrap(),
        external.join("binary").canonicalize().unwrap()
    );
}

#[test]
fn local_gitignore_does_not_follow_symlinks() {
    let fixture = Fixture::new();
    let rules = fixture.root.join("ignore-rules");
    fs::write(&rules, "*.tmp\n").unwrap();
    symlink(&rules, fixture.repo.join(".gitignore")).unwrap();
    write(&fixture.repo, "keep.tmp");
    let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-f", &[]));
    assert!(paths.contains(&OsString::from("keep.tmp")));
}
