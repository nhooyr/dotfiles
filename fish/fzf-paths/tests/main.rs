use std::collections::HashSet;
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, BufRead, BufReader};
use std::os::unix::{ffi::OsStringExt, fs::PermissionsExt, fs::symlink, process::CommandExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc;
use std::time::{Duration, Instant};

static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(0);

struct Fixture {
    root: PathBuf,
    global_dir: PathBuf,
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

fn make_executable(path: impl AsRef<Path>) {
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
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
            global_dir: root.join("global_dir"),
            repo: root.join("global_dir/project"),
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
        make_executable(fixture.local.join("executable"));
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
        let mut command = Command::new(env!("CARGO_BIN_EXE_fzf-paths"));
        command.current_dir(cwd).env("PWD", cwd).args(flags);
        if let Some(cdpath) = cdpath {
            command.arg("--cdpath").arg(cdpath);
        }
        command.arg(".").arg(global_dir).arg(kind);
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
    assert!(paths.contains(&fixture.repo.clone().into_os_string()));
    assert_eq!(paths.len(), paths.iter().collect::<HashSet<_>>().len());
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
        .filter(|path| path.starts_with(&fixture.global_dir) && path.is_file())
        .collect();
    let expected: Vec<_> = [
        fixture.repo.join(".hidden"),
        fixture.repo.join("line\nbreak/end"),
        fixture.repo.join("nested/child"),
        fixture.repo.join("node_modules/tracked"),
        fixture.repo.join("tracked"),
    ]
    .into();
    assert_eq!(files, expected);
}

#[test]
fn first_local_result_arrives_before_global_scan_finishes() {
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    fs::create_dir(&bin).unwrap();
    let git = bin.join("git");
    fs::write(
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
    assert!(fixture.local.join(first).is_file());
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
    fs::write(
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
    fs::write(
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
    fs::write(
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
    let wanted = fixture
        .repo
        .join("nested/child")
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
    fs::write(
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
    let wanted = other.join("tracked").into_os_string().into_vec();
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
        write(&local, &name);
        make_executable(local.join(name));
    }
    for flags in [&[][..], &["--keep-dot"][..]] {
        let paths = fixture.run(&mut fixture.command_with_flags(
            flags,
            &local,
            &fixture.global_dir,
            "-fd",
            &[],
        ));
        assert!(paths.contains(&fixture.repo.clone().into_os_string()));
        let local_paths: HashSet<_> = paths
            .iter()
            .filter(|path| !Path::new(path).is_absolute())
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
    fs::write(
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
    fs::write(
        &git,
        "#!/bin/sh\nprintf 'simulated Git failure\\n' >&2\nexit 7\n",
    )
    .unwrap();
    make_executable(&git);
    let path = env::join_paths(
        std::iter::once(bin).chain(env::split_paths(&env::var_os("PATH").unwrap())),
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
        .current_dir(&fixture.local)
        .env("PATH", path)
        .arg("")
        .arg(&fixture.global_dir)
        .arg("-f")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    let error = String::from_utf8(output.stderr).unwrap();
    assert!(error.contains("simulated Git failure"), "{error}");
    assert!(
        error.contains("git ls-files failed: exit status: 7"),
        "{error}"
    );
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
fn longest_env_and_raw_local_copy() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(
        &fixture.repo,
        &fixture.global_dir,
        "-fd",
        &[
            ("$global_dir", &fixture.global_dir),
            ("$project", &fixture.repo),
        ],
    ));
    assert!(paths.contains(&"nested/child".into()));
    assert!(paths.contains(&"$project/nested/child".into()));
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
        assert!(colored.contains(&OsString::from(format!("{prefix}/line\nbreak/end"))));
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
    let raw = fixture.pick();
    let colored = fixture.run(&mut fixture.command_with_flags(
        &["--color"],
        &fixture.local,
        &fixture.global_dir,
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
    fs::create_dir_all(directory.join("folder space/child 'with\nnewlines")).unwrap();
    let colored = fixture.run(&mut fixture.command_with_cdpath(
        &["--color"],
        &fixture.local,
        Path::new(""),
        Some(directory.as_os_str()),
        "-d",
        &[],
    ));
    assert!(colored.contains(&"\x1b[36m$CDPATH\x1b[0m/folder space".into()));
    assert!(colored.contains(&"\x1b[36m$CDPATH\x1b[0m/folder space/child 'with\nnewlines".into()));
    assert!(colored.contains(&"dir".into()));
    assert!(colored.iter().all(|path| {
        let path = path.to_str().unwrap();
        !path.contains('\x1b') || path.starts_with("\x1b[36m$CDPATH\x1b[0m/")
    }));
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
    let colored = fixture.run(&mut fixture.command_with_flags(
        &["--color"],
        &fixture.local,
        &fixture.global_dir,
        "-f",
        &[("$project", fixture.repo.as_path())],
    ));
    assert!(colored.contains(&OsString::from_vec(
        b"\x1b[36m$project\x1b[0m/name-\xff".to_vec()
    )));
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
            assert!(paths.contains(&fixture.repo.join(name).into_os_string()));
        }
        assert!(paths.iter().all(|path| fixture.local.join(path).is_file()));
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
fn cdpath_labels_are_independent_of_aliases_and_global_repositories() {
    let fixture = Fixture::new();
    let directory = fixture.root.join("cdpath with spaces");
    fs::create_dir_all(directory.join("child\nwith spaces")).unwrap();
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
        assert!(paths.contains(&"$CDPATH/child\nwith spaces".into()));
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
    assert!(paths.contains(&fixture.repo.join("tracked").into_os_string()));
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
    assert!(paths.iter().all(|path| fixture.local.join(path).is_file()));
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
    assert!(paths.contains(&fixture.repo.clone().into_os_string()));
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
        let mut command = Command::new(env!("CARGO_BIN_EXE_fzf-paths"));
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
        command.arg(".").arg(&fixture.global_dir).arg("-fd");
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
    assert!(paths.contains(&fixture.repo.join("nested").into_os_string()));
    assert!(paths.iter().all(|path| fixture.local.join(path).is_dir()));
}

#[test]
fn global_directories_include_symlinks_and_submodules() {
    let fixture = Fixture::new();
    for (name, target) in [
        ("directory link\t\n", "nested"),
        ("file-link", "tracked"),
        ("broken-link", "absent"),
    ] {
        symlink(target, fixture.repo.join(name)).unwrap();
    }
    fixture.git(&[
        "add",
        "--",
        "directory link\t\n",
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
        .filter(|path| Path::new(path).starts_with(&fixture.repo))
        .collect();
    let expected = [
        "",
        "nested",
        "line\nbreak",
        "node_modules",
        "directory link\t\n",
        "module",
    ]
    .map(|path| fixture.repo.join(path));
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
    let name = "run with\nspaces";
    write(&fixture.local, name);
    make_executable(fixture.local.join(name));
    symlink(
        fixture.local.join(name),
        fixture.local.join("linked-executable"),
    )
    .unwrap();
    for directory in [".", "./"] {
        let paths = fixture.run(
            Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
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
    write(&fixture.local, "fzf-paths/install.sh");
    make_executable(fixture.local.join("fzf-paths/install.sh"));
    for directory in [".", "fzf-paths"] {
        let paths = fixture.run(
            Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
                .current_dir(&fixture.local)
                .env("PWD", &fixture.local)
                .args(["--keep-dot", directory, "", "-fd"]),
        );
        assert!(paths.contains(&"fzf-paths/install.sh".into()));
        assert!(paths.contains(&"./fzf-paths/install.sh".into()));
    }
}

#[test]
fn executable_choices_preserve_plain_paths_and_env_dirs() {
    let fixture = Fixture::new();
    make_executable(fixture.repo.join("tracked"));
    let paths = fixture.run(&mut fixture.command_with_flags(
        &["--keep-dot"],
        &fixture.repo,
        &fixture.global_dir,
        "-fd",
        &[("$project", fixture.repo.as_path())],
    ));
    assert!(paths.contains(&"tracked".into()));
    assert!(paths.contains(&"./tracked".into()));
    assert!(paths.contains(&"$project/tracked".into()));
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
            executable.clone().into_os_string()
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
fn global_paths_stay_absolute_inside_the_current_repository() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(&fixture.repo, &fixture.global_dir, "-fd", &[]));
    assert!(paths.contains(&"tracked".into()));
    assert!(paths.contains(&fixture.repo.join("tracked").into_os_string()));
}

#[test]
fn literal_prefixes_are_escaped() {
    let paths = Fixture::new().pick();
    assert!(paths.contains(&"./$literal".into()));
    assert!(paths.contains(&"./~literal".into()));
}

#[test]
fn executable_literal_prefixes_are_not_duplicated_or_expanded() {
    let fixture = Fixture::new();
    for name in ["$literal", "~literal"] {
        make_executable(fixture.local.join(name));
    }
    let paths = fixture.pick();
    for name in ["$literal", "~literal"] {
        let escaped = OsString::from(format!("./{name}"));
        assert_eq!(paths.iter().filter(|path| *path == &escaped).count(), 1);
        assert!(!paths.contains(&OsString::from(name)));
        assert!(!paths.contains(&OsString::from(format!("././{name}"))));
    }
}

#[test]
fn ignored_directories_broken_links_and_cycles() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", &[]));
    for absent in ["node_modules", ".git", "broken"] {
        assert!(!paths.contains(&absent.into()));
    }
    assert!(paths.contains(&"linked/child".into()));
    assert!(paths.contains(&"loop".into()));
    assert!(
        !paths
            .iter()
            .any(|path| Path::new(path).starts_with("loop") && path != "loop")
    );
}

#[test]
fn empty_or_missing_global_dir() {
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
            Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
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
        Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
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
        Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
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
            .contains(&fixture.repo.join("nested/child").into_os_string())
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
fn dirali_options_work_before_and_after_positions() {
    let fixture = Fixture::new();
    let paths = fixture.run(
        Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
            .current_dir(&fixture.local)
            .env("PWD", &fixture.local)
            .arg("--dirali")
            .arg("$global_dir")
            .arg(&fixture.global_dir)
            .arg(".")
            .arg(&fixture.global_dir)
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
        let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
            .arg0("/some/path/renamed-picker")
            .args(args)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(output.stdout.is_empty());
        assert_eq!(
        output.stderr,
        b"usage: renamed-picker [--color] [--keep-dot] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]...\n"
    );
    }
}

#[test]
fn help_uses_invoked_basename() {
    for flags in [
        vec!["--help"],
        vec!["-h"],
        vec!["--color", "--help"],
        vec!["--color", "--keep-dot", "--help"],
        vec!["--keep-dot", "--help"],
        vec!["--cdpath", "", "--help"],
        vec!["--keep-dot", "--cdpath", "", "--help"],
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
            .arg0("/some/path/renamed-picker")
            .args(flags)
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(output.stderr.is_empty());
        let help = String::from_utf8(output.stdout).unwrap();
        assert!(help.contains(
            "usage: renamed-picker [--color] [--keep-dot] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]..."
        ));
        assert!(help.contains("Generate path candidates"));
        assert!(help.contains(".gitignore"));
        assert!(help.contains("Options:"));
        assert!(help.contains("NUL-separated"));
        assert!(help.contains("Examples (Fish):"));
        assert!(help.contains("GLOBAL_DIR"));
        assert!(help.contains("Each --dirali"));
        assert!(help.contains("colon-separated roots"));
        assert!(help.contains("Fish bindings keep directory aliases in the command line"));
        assert!(help.contains("shell expands them when the command is executed"));
        assert!(help.contains("--keep-dot"));
        assert!(!help.contains("LABEL"));
        assert!(!help.contains("OWNER"));
        assert!(!help.contains("usage: fzf-paths"));
    }
}

#[test]
fn incomplete_dirali_is_a_usage_error() {
    let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
        .arg0("/some/path/renamed-picker")
        .args([".", "", "-fd", "--dirali", "unpaired"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert_eq!(
        output.stderr,
        b"usage: renamed-picker [--color] [--keep-dot] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]...\n"
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
