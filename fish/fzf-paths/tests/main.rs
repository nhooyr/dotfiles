use std::collections::HashSet;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{self, BufRead, BufReader};
use std::os::unix::{ffi::OsStringExt, fs::symlink, fs::PermissionsExt, process::CommandExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc;
use std::time::Duration;

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
        let mut command = Command::new(env!("CARGO_BIN_EXE_fzf-paths"));
        command
            .current_dir(cwd)
            .env("PWD", cwd)
            .args(flags)
            .arg(".")
            .arg(global_dir)
            .arg(kind);
        for (env, path) in env_dirs {
            command.arg(env).arg(path);
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
fn local_subdirectories_are_scanned_depth_first() {
    let fixture = Fixture::new();
    write(&fixture.local, "first/deep/leaf");
    write(&fixture.local, "second/deep/leaf");
    let paths = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", &[]));
    let index = |name: &str| paths.iter().position(|path| path == name).unwrap();
    let first = (index("first/deep"), index("first/deep/leaf"));
    let second = (index("second/deep"), index("second/deep/leaf"));
    assert!(first.1 < second.0 || second.1 < first.0);
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
fn local_scan_resumes_after_global_paths_at_one_thousand_results() {
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
        let first_global = paths.iter().position(|path| path == &fixture.repo).unwrap();
        assert_eq!(first_global, 1000);
        let last_global = paths
            .iter()
            .rposition(|path| Path::new(path).is_absolute())
            .unwrap();
        assert!(paths[first_global..=last_global]
            .iter()
            .all(|path| Path::new(path).is_absolute()));
        let local_paths: HashSet<_> = paths[..first_global]
            .iter()
            .chain(&paths[last_global + 1..])
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
    let raw = paths.iter().position(|p| p == "nested/child").unwrap();
    let env = paths
        .iter()
        .position(|p| p == "$project/nested/child")
        .unwrap();
    assert!(raw < env);
    assert!(!paths
        .iter()
        .any(|path| Path::new(path).starts_with("$global_dir/project")));
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
fn executable_only_filter_offers_both_local_forms() {
    let fixture = Fixture::new();
    let paths = fixture.run(&mut fixture.command_with_flags(
        &["--keep-dot"],
        &fixture.local,
        &fixture.global_dir,
        "-fdx",
        &[],
    ));
    assert!(paths.contains(&"executable".into()));
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
    assert!(!paths
        .iter()
        .any(|path| Path::new(path).starts_with("loop") && path != "loop"));
}

#[test]
fn empty_or_missing_global_dir() {
    let fixture = Fixture::new();
    let empty = fixture.run(&mut fixture.command(&fixture.local, Path::new(""), "-fd", &[]));
    let missing =
        fixture.run(&mut fixture.command(&fixture.local, &fixture.root.join("absent"), "-fd", &[]));
    assert_eq!(empty, missing);
}

#[test]
fn logical_working_directory() {
    let fixture = Fixture::new();
    let link = fixture.root.join("logical");
    symlink(&fixture.local, &link).unwrap();
    let mut command = fixture.command(&fixture.local, &fixture.global_dir, "-fd", &[]);
    command.env("PWD", link);
    assert_eq!(fixture.pick(), fixture.run(&mut command));
}

#[test]
fn local_gitignore_hides_build_outputs() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/target/\n*.tmp\n").unwrap();
    write(&fixture.repo, "target/debug/application");
    write(&fixture.repo, "scratch.tmp");
    write(&fixture.repo, "visible");
    let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-fd", &[]));
    assert!(!paths
        .iter()
        .any(|path| Path::new(path).starts_with("target")));
    assert!(!paths.contains(&"scratch.tmp".into()));
    assert!(paths.contains(&"visible".into()));
}

#[test]
fn ignored_directories_are_not_offered_for_cd() {
    let fixture = Fixture::new();
    fs::write(fixture.repo.join(".gitignore"), "/target/\n").unwrap();
    write(&fixture.repo, "target/debug/application");
    let paths = fixture.run(&mut fixture.command(&fixture.repo, Path::new(""), "-d", &[]));
    assert!(!paths
        .iter()
        .any(|path| Path::new(path).starts_with("target")));
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
    assert!(!paths
        .iter()
        .any(|path| Path::new(path).starts_with("hidden")));
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
    assert!(fixture
        .pick()
        .contains(&fixture.repo.join("nested/child").into_os_string()));
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
    assert!(!paths
        .iter()
        .any(|path| Path::new(path).starts_with("build output")));
    assert!(paths.contains(&"visible".into()));
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
        b"usage: renamed-picker [--keep-dot] <DIR> <GLOBAL_DIR> <TYPE> [<ENV> <DIR>]...\n"
    );
}

#[test]
fn help_uses_invoked_basename() {
    for flags in [vec!["--help"], vec!["-h"], vec!["--keep-dot", "--help"]] {
        let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
            .arg0("/some/path/renamed-picker")
            .args(flags)
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(output.stderr.is_empty());
        let help = String::from_utf8(output.stdout).unwrap();
        assert!(help.contains(
            "usage: renamed-picker [--keep-dot] <DIR> <GLOBAL_DIR> <TYPE> [<ENV> <DIR>]..."
        ));
        assert!(help.contains("Generate path candidates"));
        assert!(help.contains(".gitignore"));
        assert!(help.contains("Options:"));
        assert!(help.contains("NUL-separated"));
        assert!(help.contains("Examples (Fish):"));
        assert!(help.contains("emit local paths first"));
        assert!(help.contains("1,000 unique local results"));
        assert!(help.contains("Then resume any remaining local paths."));
        assert!(help.contains("streamed directly in Git's order"));
        assert!(help.contains("GLOBAL_DIR"));
        assert!(help.contains("Repeated <ENV> <DIR> pairs"));
        assert!(help.contains("Fish bindings keep directory aliases in the command line"));
        assert!(help.contains("shell expands them when the command is executed"));
        assert!(help.contains("--keep-dot"));
        assert!(!help.contains("LABEL"));
        assert!(!help.contains("OWNER"));
        assert!(!help.contains("usage: fzf-paths"));
    }
}

#[test]
fn unpaired_env_is_a_usage_error() {
    let output = Command::new(env!("CARGO_BIN_EXE_fzf-paths"))
        .arg0("/some/path/renamed-picker")
        .args([".", "", "-fd", "unpaired"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert_eq!(
        output.stderr,
        b"usage: renamed-picker [--keep-dot] <DIR> <GLOBAL_DIR> <TYPE> [<ENV> <DIR>]...\n"
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
