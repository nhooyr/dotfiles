use super::*;
use std::path::Component;

pub(super) fn read_recent_dirs() -> io::Result<Vec<PathBuf>> {
    let mut paths = Vec::new();
    read_input_paths(
        || {
            if output_closed() {
                return Err(io::ErrorKind::BrokenPipe.into());
            }
            check_signal()
        },
        |bytes| {
            let path = Path::new(OsStr::from_bytes(bytes));
            if path.is_absolute() && path.is_dir() {
                paths.push(path.to_path_buf());
            }
            Ok(())
        },
    )?;
    Ok(paths)
}

fn relative_to<'a>(path: &'a Path, root: &Path, physical: &Path) -> Option<&'a Path> {
    let relative = path
        .strip_prefix(root)
        .or_else(|_| path.strip_prefix(physical))
        .ok()?;
    relative
        .components()
        .all(|part| matches!(part, Component::Normal(_)))
        .then_some(relative)
}

fn excluded(path: &Path) -> bool {
    path.components()
        .any(|part| matches!(part.as_os_str().as_bytes(), b".git" | b"node_modules"))
}

struct Directory {
    ignores: LocalIgnores,
    ancestors: Vec<(u64, u64)>,
}

pub(super) struct LocalPaths<'a> {
    scanner: &'a Scanner,
    path: &'a Path,
    logical_root: PathBuf,
    root: &'a Path,
    configured: &'a Gitignore,
    directories: HashMap<PathBuf, Option<Directory>>,
}

impl<'a> LocalPaths<'a> {
    pub(super) fn new(
        scanner: &'a Scanner,
        path: &'a Path,
        root: &'a Path,
        ignores: &LocalIgnores,
        configured: &'a Gitignore,
        ancestors: &[(u64, u64)],
    ) -> Self {
        Self {
            scanner,
            path,
            logical_root: scanner.cwd.join(path),
            root,
            configured,
            directories: HashMap::from([(
                root.to_path_buf(),
                Some(Directory {
                    ignores: ignores.clone(),
                    ancestors: ancestors.to_vec(),
                }),
            )]),
        }
    }

    fn directory(&mut self, path: &Path) -> io::Result<Option<&Directory>> {
        if !self.directories.contains_key(path) {
            let directory = self.read_directory(path)?;
            self.directories.insert(path.to_path_buf(), directory);
        }
        Ok(self.directories[path].as_ref())
    }

    fn read_directory(&mut self, path: &Path) -> io::Result<Option<Directory>> {
        let scanner = self.scanner;
        let configured = self.configured;
        let Some(parent) = self.directory(path.parent().unwrap())? else {
            return Ok(None);
        };
        let Ok(info) = path.metadata() else {
            return Ok(None);
        };
        let identity = (info.dev(), info.ino());
        if !info.is_dir()
            || parent.ancestors.contains(&identity)
            || !local_entry_allowed(path, true, &parent.ignores, configured)
        {
            return Ok(None);
        }
        let mut ancestors = parent.ancestors.clone();
        ancestors.push(identity);
        Ok(Some(Directory {
            ignores: scanner.subdirectory_ignores(path, &parent.ignores)?,
            ancestors,
        }))
    }

    fn candidate(&mut self, relative: &Path) -> io::Result<Option<Candidate>> {
        if relative.as_os_str().is_empty() || excluded(relative) {
            return Ok(None);
        }
        let absolute = self.root.join(relative);
        let path = self.path.join(relative);
        let scanner = self.scanner;
        let configured = self.configured;
        let Some(parent) = self.directory(absolute.parent().unwrap())? else {
            return Ok(None);
        };
        let Some(info) = FileInfo::new(&path) else {
            return Ok(None);
        };
        if !local_entry_allowed(
            &absolute,
            info.followed().is_dir(),
            &parent.ignores,
            configured,
        ) {
            return Ok(None);
        }
        Ok(scanner.path_candidate(path, true, Some(info)))
    }

    pub(super) fn recent(&mut self, directories: &[PathBuf]) -> io::Result<DirectoryMatches> {
        let mut matches = Vec::new();
        for (rank, path) in directories.iter().enumerate() {
            self.scanner.check_cancelled()?;
            if let Some(relative) = relative_to(path, &self.logical_root, self.root)
                && let Some(candidate) = self.candidate(relative)?
            {
                matches.push((rank, candidate));
            }
        }
        Ok(matches)
    }

    pub(super) fn emit_changes(
        &mut self,
        mut changes: Changes<'_>,
    ) -> io::Result<HashSet<PathBuf>> {
        let mut status = Vec::new();
        changes.stdout.read_to_end(&mut status)?;
        drop(changes.stdout);
        let mut shown = HashSet::new();
        let levels = if self.scanner.files_only {
            1
        } else {
            usize::MAX
        };
        for path in status.split(|&byte| byte == 0).filter_map(status_path) {
            let changed = changes.root.join(path);
            for path in changed.ancestors().take(levels) {
                self.scanner.check_cancelled()?;
                let Ok(relative) = path.strip_prefix(self.root) else {
                    break;
                };
                if relative.as_os_str().is_empty() {
                    break;
                }
                if !shown.contains(path)
                    && let Some(candidate) = self.candidate(relative)?
                {
                    self.scanner.send(candidate)?;
                    shown.insert(path.to_path_buf());
                    if shown.len() == PRIORITY_LIMIT {
                        return Ok(shown);
                    }
                }
            }
        }
        Ok(shown)
    }
}

pub(super) struct Changes<'a> {
    root: &'a Path,
    stdout: GitOutput,
}

pub(super) fn start_changes<'a>(
    scanner: &Scanner,
    directory: &'a Path,
) -> io::Result<Option<Changes<'a>>> {
    let Some(root) = worktree_root(directory) else {
        return Ok(None);
    };
    Ok(Some(Changes {
        root,
        stdout: git_status(scanner, directory)?,
    }))
}

fn worktree_root(directory: &Path) -> Option<&Path> {
    directory.ancestors().find(|ancestor| {
        let git = ancestor.join(".git");
        git.is_file() || git.join("HEAD").is_file()
    })
}

fn git_status(scanner: &Scanner, directory: &Path) -> io::Result<GitOutput> {
    scanner.spawn_git(
        directory,
        [
            "--no-optional-locks",
            "status",
            "--porcelain=v1",
            "-z",
            "--no-renames",
            "--untracked-files=all",
            "--",
            ".",
        ],
    )
}

fn status_path(row: &[u8]) -> Option<&Path> {
    // Porcelain v1 starts each record with two status bytes and a space.
    (row.len() > 3).then(|| Path::new(OsStr::from_bytes(&row[3..])))
}

pub(super) fn git_recents(
    scanner: &Scanner,
    directory: &Path,
    mut visit: impl FnMut(PathBuf) -> io::Result<()>,
) -> io::Result<()> {
    let Some(root) = worktree_root(directory) else {
        return Ok(());
    };
    let mut seen = HashSet::new();
    for row in BufReader::new(git_status(scanner, root)?).split(0) {
        scanner.check_cancelled()?;
        let row = row?;
        let Some(path) = status_path(&row) else {
            continue;
        };
        let changed = root.join(path);
        for path in changed.ancestors().take_while(|&path| path != root) {
            if !seen.insert(path.to_path_buf()) {
                break;
            }
            visit(path.to_path_buf())?;
        }
    }
    Ok(())
}

pub(super) fn global(
    scanner: &Scanner,
    repos: &[PathBuf],
    root: &Path,
    physical: &Path,
    ignores: &Gitignore,
    recent: &[PathBuf],
) -> io::Result<DirectoryMatches> {
    let mut requests = HashMap::<_, HashMap<PathBuf, usize>>::new();
    for (rank, path) in recent.iter().enumerate() {
        let Some(relative) = relative_to(path, root, physical) else {
            continue;
        };
        let Some(name) = relative.components().next() else {
            continue;
        };
        let path = relative.strip_prefix(name.as_os_str()).unwrap();
        requests
            .entry(physical.join(name.as_os_str()))
            .or_default()
            .entry(path.to_path_buf())
            .or_insert(rank);
    }
    let targets: Vec<_> = repos
        .iter()
        .filter_map(|repo| requests.remove(repo).map(|paths| (repo, paths)))
        .collect();
    let results = Mutex::new(Vec::new());
    let workers = parallelism().min(targets.len());
    parallel(targets, workers, |(repo, mut wanted)| {
        let physical_repo = repo.canonicalize()?;
        if scanner
            .local_root
            .as_ref()
            .is_some_and(|root| physical_repo.starts_with(root))
        {
            return Ok(Vec::new());
        }
        let mut hits = Vec::new();
        let mut visit = |wanted: &mut HashMap<PathBuf, usize>, path: &Path| {
            if let Some(rank) = wanted.remove(path)
                && let Some(candidate) = scanner.global_path_candidate(
                    repo.join(path),
                    &physical_repo.join(path),
                    ignores,
                )
            {
                hits.push((rank, candidate));
            }
        };
        visit(&mut wanted, Path::new(""));
        for tracked in [true, false] {
            if wanted.is_empty() {
                break;
            }
            let specs: Vec<_> = wanted.keys().cloned().collect();
            scanner.repo_files(repo, tracked, &specs, |file, regular| {
                if !regular {
                    visit(&mut wanted, file);
                }
                for parent in file
                    .ancestors()
                    .skip(1)
                    .filter(|path| !path.as_os_str().is_empty())
                {
                    visit(&mut wanted, parent);
                }
                Ok(())
            })?;
        }
        results.lock().unwrap().extend(hits);
        Ok(Vec::new())
    })?;
    Ok(results.into_inner().unwrap())
}

pub(super) fn cdpath(
    scanner: &Scanner,
    roots: &[(PathBuf, PathBuf)],
    recent: &[PathBuf],
) -> io::Result<DirectoryMatches> {
    let mut shown = HashSet::new();
    let mut matches = Vec::new();
    for (rank, absolute) in recent.iter().enumerate() {
        scanner.check_cancelled()?;
        for (index, (logical, root)) in roots.iter().enumerate() {
            let Some(relative) = relative_to(absolute, logical, root) else {
                continue;
            };
            if !(1..=2).contains(&relative.components().count())
                || excluded(relative)
                || shown.contains(relative)
            {
                continue;
            }
            // The widget interprets a colliding name according to its command context.
            if scanner.cwd.join(relative).exists()
                || roots[..index]
                    .iter()
                    .any(|(_, earlier)| earlier.join(relative).is_dir())
            {
                continue;
            }
            let path = root.join(relative);
            let Some(info) = FileInfo::new(&path).filter(|info| info.followed().is_dir()) else {
                continue;
            };
            matches.push((
                rank,
                Candidate::Cdpath(relative.to_path_buf(), scanner.style(&path, &info)),
            ));
            shown.insert(relative.to_path_buf());
        }
    }
    Ok(matches)
}
