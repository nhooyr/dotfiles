use ignore::gitignore::Gitignore;
use ignore::Match;
use std::collections::HashSet;
use std::env;
use std::ffi::{c_int, c_short, OsStr, OsString};
use std::fs::{self, Metadata};
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::os::fd::AsRawFd;
use std::os::unix::{ffi::OsStrExt, ffi::OsStringExt, fs::MetadataExt, process::CommandExt};
use std::path::{Component, Path, PathBuf};
use std::process::{self, Child, ChildStdout, Command, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::Duration;

fn print_help(name: &str) {
    println!(
        "\
Generate path candidates for fzf from local files and Git repositories.

usage: {name} [--keep-dot] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]...

Scan <DIR>, Git repositories directly under <GLOBAL_DIR>, and optional CDPATH
roots concurrently. Stream results as they are found; paths from the three
searches may interleave, with no guaranteed order between them.

Local directories and global Git repositories are each scanned by a bounded
pool of workers. Local paths have no guaranteed traversal order. Within each
repository, global paths follow Git's order, with parent directories added as
needed; different repositories may interleave. fzf may reorder sorted matches.

With --cdpath, directory modes (-d and -fd) list directories up to two levels
below each colon-separated root, such as $CDPATH/junegunn/fzf. Missing roots
are skipped. These choices use the display prefix $CDPATH/; the Fish widgets
resolve them as described below. Duplicate relative paths are emitted once.
Directories named .git and node_modules are skipped at both levels.

Alt-C and Alt-V enable CDPATH for any command.
Selecting multiple directories at command start opens them with nvim --.
For nvim and other commands, $CDPATH paths become absolute, abbreviated with
the most specific dirali when available.
For cd/cdc, $CDPATH choices use the bare name unless it collides with a local
directory. Collisions are resolved the same way, preferring the first different
match in CDPATH order. Local selections stay relative.
An explicit ./ token disables global and CDPATH searches. Ctrl-T (files) and
Alt-C (directories) use the parsed local query without ./; only Alt-V (files
and directories) keeps ./ in the query to find local executable paths.

The local scan respects .gitignore files, including nested rules and negations.
Starting inside an ignored directory makes that directory searchable: ignore
rules above the ignored directory are bypassed, while rules inside still apply.
Directories named .git and node_modules are skipped unless they are <DIR> itself.

Options:
  -h, --help        Show this help.
  --keep-dot        Also offer ./ paths for local executable files.
  --cdpath CDPATH   Include directories from these colon-separated roots.
  --dirali ENV DIR  Abbreviate paths using ENV for DIR. May be repeated.

Arguments:
  <DIR>         Directory to search locally. Use . for the current directory.
  <GLOBAL_DIR>  Dir containing additional Git repositories.
                Use an empty string to skip global Git repositories.
  <TYPE>        -fd   Files and directories.
                -f    Files only.
                -d    Directories only.

Each --dirali maps a directory to an alias, such as '$dotfiles' /path/to/dotfiles.
Each env must be unique. The longest matching directory wins.

For example, --dirali '$code' /code --dirali '$dotfiles' /code/dotfiles
turns /code/dotfiles/init.sh into $dotfiles/init.sh, since /code/dotfiles
is the longer matching prefix.

Output:
  Unique, NUL-separated paths. Filenames may contain spaces or newlines.
  Local paths omit a leading ./. With --keep-dot, local executables also get
  a ./ form. The Fish bindings enable this only when completing a command name.
  Global paths use a matching env when available; otherwise they are absolute.
  Global directory scans (-d, used by Alt-C) use Git's indexed file types. If
  you replace a tracked regular file with a symlink to a directory, that
  symlink is omitted until you stage the change with git add. Local scans
  see the change immediately.
  A file may appear as both a short local path and a global path; identical
  output strings are emitted only once.
  The Fish bindings keep directory aliases in the command line.
  The shell expands them when the command is executed.

Examples (Fish):
  {name} --cdpath \"$CDPATH\" . \"$nhooyr\" -fd --dirali '$dotfiles' \"$dotfiles\" | fzf --read0
  {name} --cdpath \"$CDPATH\" . '' -d | fzf --read0
  {name} --keep-dot . '' -f | fzf --read0"
    );
}

fn usage_error(name: &str) -> ! {
    eprintln!("usage: {name} [--keep-dot] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]...");
    process::exit(1);
}

fn main() {
    let mut arguments = env::args_os();
    let invoked = arguments.next().unwrap_or_default();
    let name = Path::new(&invoked)
        .file_name()
        .unwrap_or(&invoked)
        .to_string_lossy();
    let mut args = Vec::new();
    let mut aliases = Vec::new();
    let mut keep_dot = false;
    let mut cdpath = None;
    while let Some(arg) = arguments.next() {
        if arg == "--keep-dot" {
            keep_dot = true;
        } else if arg == "--cdpath" {
            cdpath = Some(arguments.next().unwrap_or_else(|| usage_error(&name)));
        } else if arg == "--dirali" {
            aliases.push(arguments.next().unwrap_or_else(|| usage_error(&name)));
            aliases.push(arguments.next().unwrap_or_else(|| usage_error(&name)));
        } else if arg == "--help" || arg == "-h" {
            print_help(&name);
            return;
        } else if arg == "--" {
            args.extend(arguments);
            break;
        } else {
            args.push(arg);
        }
    }
    if args.len() != 3 {
        usage_error(&name);
    }
    args.extend(aliases);
    if let Err(error) = run(&args, keep_dot, cdpath) {
        if error.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("{name}: {error}");
            process::exit(1);
        }
    }
}

fn run(args: &[OsString], keep_dot: bool, cdpath: Option<OsString>) -> io::Result<()> {
    let mut seen_envs = HashSet::new();
    let mut env_dirs = Vec::new();
    for pair in args[3..].chunks_exact(2) {
        let env = pair[0].as_bytes();
        if !seen_envs.insert(env) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("duplicate env: {}", pair[0].to_string_lossy()),
            ));
        }
        env_dirs.push((env.to_vec(), pair[1].as_bytes().to_vec()));
    }
    env_dirs.sort_by_key(|(_, dir)| std::cmp::Reverse(dir.len()));
    let mut picker = Picker {
        keep_dot,
        env_dirs,
        shown: HashSet::new(),
        output: BufWriter::new(io::stdout()),
    };
    let (sender, receiver) = mpsc::sync_channel(256);
    let git = Arc::new(Mutex::new(GitScans::default()));
    let scanner = Scanner {
        cwd: working_directory()?,
        files_only: args[2] == "-f",
        directories_only: args[2] == "-d",
        keep_dot,
        sender,
        git: Arc::clone(&git),
    };
    thread::scope(|scope| {
        let local = scanner.clone();
        let mut scans = vec![scope.spawn(move || local.walk(PathBuf::from(&args[0])))];
        if !args[1].is_empty() {
            let global = scanner.clone();
            scans.push(scope.spawn(move || global.global_paths(PathBuf::from(&args[1]))));
        }
        if let Some(cdpath) = cdpath.filter(|value| !value.is_empty() && !scanner.files_only) {
            let cd = scanner.clone();
            scans.push(scope.spawn(move || cd.cdpath(cdpath)));
        }
        drop(scanner);
        let result = (|| {
            loop {
                let candidate = match receiver.recv_timeout(Duration::from_millis(50)) {
                    Ok(candidate) => candidate,
                    Err(RecvTimeoutError::Disconnected) => break,
                    Err(RecvTimeoutError::Timeout) if output_closed() => {
                        return Err(io::ErrorKind::BrokenPipe.into());
                    }
                    Err(RecvTimeoutError::Timeout) => continue,
                };
                for candidate in std::iter::once(candidate).chain(receiver.try_iter()) {
                    let flush = match candidate {
                        Candidate::Path {
                            path,
                            local,
                            executable,
                        } => {
                            picker.emit_path(path, local, executable)?;
                            !local
                        }
                        Candidate::Cdpath(path) => {
                            picker
                                .emit([b"$CDPATH/", path.as_os_str().as_bytes()].concat(), false)?;
                            true
                        }
                    };
                    if flush {
                        picker.output.flush()?;
                    }
                }
                // Never wait for a slower scan with local results still buffered.
                picker.output.flush()?;
            }
            picker.output.flush()
        })();
        // Release blocked senders before joining if writing to fzf failed.
        drop(receiver);
        if result.is_err() {
            git.lock().unwrap().cancel();
        }
        let results: Vec<_> = scans.into_iter().map(|scan| scan.join().unwrap()).collect();
        let waited = git.lock().unwrap().wait();
        result?;
        waited?;
        for result in results {
            result?;
        }
        Ok(())
    })
}

// Check for a closed picker even when a scan has no new paths to write.
fn output_closed() -> bool {
    #[repr(C)]
    struct PollFd {
        fd: c_int,
        events: c_short,
        revents: c_short,
    }
    #[cfg(any(target_os = "linux", target_os = "android"))]
    type Nfds = usize;
    #[cfg(not(any(target_os = "linux", target_os = "android")))]
    type Nfds = u32;
    extern "C" {
        fn poll(fds: *mut PollFd, nfds: Nfds, timeout: c_int) -> c_int;
    }
    const POLLOUT: c_short = 4;
    const POLLERR: c_short = 8;
    const POLLHUP: c_short = 16;
    const POLLNVAL: c_short = 32;
    let mut fd = PollFd {
        fd: io::stdout().as_raw_fd(),
        events: POLLOUT, // macOS reports pipe hangups only when writing is requested.
        revents: 0,
    };
    unsafe { poll(&mut fd, 1, 0) > 0 && fd.revents & (POLLERR | POLLHUP | POLLNVAL) != 0 }
}

#[derive(Default)]
struct GitScans {
    cancelled: bool,
    children: Vec<Child>,
}

impl GitScans {
    fn register(&mut self, mut child: Child) -> io::Result<ChildStdout> {
        let stdout = child.stdout.take().unwrap();
        self.children.push(child);
        if self.cancelled {
            self.cancel();
            return Err(io::ErrorKind::BrokenPipe.into());
        }
        Ok(stdout)
    }

    fn cancel(&mut self) {
        self.cancelled = true;
        extern "C" {
            fn kill(pid: c_int, signal: c_int) -> c_int;
        }
        const SIGKILL: c_int = 9;
        for child in &self.children {
            // Kill each private process group, including any Git subprocesses.
            // Children stay unreaped until wait(), so their IDs cannot be reused.
            unsafe { kill(-(child.id() as c_int), SIGKILL) };
        }
    }

    fn wait(&mut self) -> io::Result<()> {
        for mut child in self.children.drain(..) {
            child.wait()?;
        }
        Ok(())
    }
}

fn ignored(path: &Path, directory: bool, ignores: &[Arc<Gitignore>]) -> bool {
    for matcher in ignores.iter().rev() {
        match matcher.matched(path, directory) {
            Match::Ignore(_) => return true,
            Match::Whitelist(_) => return false,
            Match::None => {}
        }
    }
    false
}

fn add_ignore_file(directory: &Path, ignores: &mut Vec<Arc<Gitignore>>) {
    let path = directory.join(".gitignore");
    if !path.is_file() {
        return;
    }
    let (matcher, _) = Gitignore::new(path);
    if !matcher.is_empty() {
        ignores.push(Arc::new(matcher));
    }
}

fn local_ignores(directory: &Path) -> Vec<Arc<Gitignore>> {
    let mut ignores = Vec::new();
    if !directory.join(".git").exists() {
        if let Some(parent) = directory.parent() {
            ignores = local_ignores(parent);
        }
    }
    if ignored(directory, true, &ignores) {
        // An explicit search inside an ignored directory starts fresh here.
        ignores.clear();
    }
    add_ignore_file(directory, &mut ignores);
    ignores
}

fn working_directory() -> io::Result<PathBuf> {
    let cwd = env::current_dir()?;
    if let Some(pwd) = env::var_os("PWD").map(PathBuf::from) {
        if let (Ok(a), Ok(b)) = (pwd.metadata(), cwd.metadata()) {
            if pwd.is_absolute() && (a.dev(), a.ino()) == (b.dev(), b.ino()) {
                return Ok(pwd);
            }
        }
    }
    Ok(cwd)
}

fn normalize(path: &Path) -> PathBuf {
    let mut result = PathBuf::new();
    for component in path.components() {
        if component == Component::ParentDir {
            result.pop();
        } else {
            result.push(component);
        }
    }
    result
}

fn parallelism() -> usize {
    // Filesystem and Git work can overlap even on a single CPU.
    thread::available_parallelism().map_or(2, |count| count.get().max(2))
}

fn parallel<T: Send>(
    jobs: Vec<T>,
    workers: usize,
    visit: impl Fn(T) -> io::Result<Vec<T>> + Sync,
) -> io::Result<()> {
    struct Queue<T> {
        jobs: Vec<T>,
        active: usize,
        error: Option<io::Error>,
    }
    let queue = Mutex::new(Queue {
        jobs,
        active: 0,
        error: None,
    });
    let ready = Condvar::new();
    thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| loop {
                let job = {
                    let mut queue = queue.lock().unwrap();
                    loop {
                        if queue.error.is_some() {
                            return;
                        }
                        if let Some(job) = queue.jobs.pop() {
                            queue.active += 1;
                            break job;
                        }
                        if queue.active == 0 {
                            return;
                        }
                        queue = ready.wait(queue).unwrap();
                    }
                };
                let result = visit(job);
                let mut queue = queue.lock().unwrap();
                queue.active -= 1;
                match result {
                    Ok(jobs) => queue.jobs.extend(jobs),
                    Err(error) => queue.error = Some(error),
                }
                ready.notify_all();
            });
        }
    });
    queue.into_inner().unwrap().error.map_or(Ok(()), Err)
}

struct Picker {
    keep_dot: bool,
    env_dirs: Vec<(Vec<u8>, Vec<u8>)>,
    shown: HashSet<Vec<u8>>,
    output: BufWriter<io::Stdout>,
}

impl Picker {
    fn emit(&mut self, mut path: Vec<u8>, literal: bool) -> io::Result<()> {
        if literal && matches!(path.first(), Some(b'$' | b'~')) {
            path.splice(..0, b"./".iter().copied());
        }
        if self.shown.insert(path.clone()) {
            self.output.write_all(&path)?;
            self.output.write_all(b"\0")?;
            if self.shown.len() == 1 {
                self.output.flush()?;
            }
        }
        Ok(())
    }

    fn emit_path(&mut self, path: PathBuf, local: bool, executable: bool) -> io::Result<()> {
        let mut path = path.into_os_string().into_vec();
        if path.starts_with(b"./") {
            path.drain(..2);
        }
        if local {
            self.emit(path.clone(), true)?;
            if self.keep_dot && executable && !path.starts_with(b"/") && !path.starts_with(b"./") {
                self.emit([b"./", path.as_slice()].concat(), true)?;
            }
        }
        if let Some((env, dir)) = self.env_dirs.iter().find(|(_, dir)| {
            path.starts_with(dir) && (path.len() == dir.len() || path.get(dir.len()) == Some(&b'/'))
        }) {
            path.splice(..dir.len(), env.iter().copied());
            self.emit(path, false)?;
        } else if !local {
            self.emit(path, true)?;
        }
        Ok(())
    }
}

enum Candidate {
    Path {
        path: PathBuf,
        local: bool,
        executable: bool,
    },
    Cdpath(PathBuf),
}

#[derive(Clone)]
struct Scanner {
    cwd: PathBuf,
    files_only: bool,
    directories_only: bool,
    keep_dot: bool,
    sender: SyncSender<Candidate>,
    git: Arc<Mutex<GitScans>>,
}

impl Scanner {
    fn send(&self, candidate: Candidate) -> io::Result<()> {
        self.sender
            .send(candidate)
            .map_err(|_| io::ErrorKind::BrokenPipe.into())
    }

    fn emit_path(&self, path: PathBuf, local: bool, executable: bool) -> io::Result<()> {
        self.send(Candidate::Path {
            path,
            local,
            executable,
        })
    }

    fn candidate(&self, path: PathBuf, local: bool, metadata: Option<Metadata>) -> io::Result<()> {
        let Some(metadata) = metadata.or_else(|| path.metadata().ok()) else {
            return Ok(());
        };
        if (self.files_only && !metadata.is_file())
            || (!metadata.is_dir() && (self.directories_only || !metadata.is_file()))
        {
            return Ok(());
        }
        self.emit_path(
            path,
            local,
            metadata.is_file() && metadata.mode() & 0o111 != 0,
        )
    }

    fn walk(&self, path: PathBuf) -> io::Result<()> {
        let Ok(metadata) = path.metadata() else {
            return Ok(());
        };
        if !metadata.is_dir() {
            return Ok(());
        }
        // Resolve symlinks before .. so ignore rules match the directory we scan.
        let Ok(absolute) = path.canonicalize() else {
            return Ok(());
        };
        let ignores = local_ignores(&absolute);
        let ancestors = vec![(metadata.dev(), metadata.ino())];
        parallel(
            vec![(path, absolute, ancestors, ignores)],
            parallelism(),
            |(path, absolute, ancestors, ignores)| {
                let mut directories = Vec::new();
                let Ok(entries) = fs::read_dir(path) else {
                    return Ok(directories);
                };
                for entry in entries.flatten() {
                    let name = entry.file_name();
                    if name == ".git" || name == "node_modules" {
                        continue;
                    }
                    let regular_file = entry.file_type().is_ok_and(|kind| kind.is_file());
                    if self.directories_only && regular_file {
                        continue;
                    }
                    let path = entry.path();
                    let absolute = absolute.join(name);
                    if regular_file && !self.keep_dot {
                        if !ignored(&absolute, false, &ignores) {
                            self.emit_path(path, true, false)?;
                        }
                        continue;
                    }
                    let Ok(metadata) = path.metadata() else {
                        continue;
                    };
                    let is_directory = metadata.is_dir();
                    if ignored(&absolute, is_directory, &ignores) {
                        continue;
                    }
                    let identity = (metadata.dev(), metadata.ino());
                    self.candidate(path.clone(), true, Some(metadata))?;
                    if is_directory && !ancestors.contains(&identity) {
                        let mut ancestors = ancestors.clone();
                        ancestors.push(identity);
                        let mut ignores = ignores.clone();
                        add_ignore_file(&absolute, &mut ignores);
                        directories.push((path, absolute, ancestors, ignores));
                    }
                }
                Ok(directories)
            },
        )
    }

    fn cdpath(&self, cdpath: OsString) -> io::Result<()> {
        let mut roots = HashSet::new();
        for root in env::split_paths(&cdpath) {
            let root = normalize(&self.cwd.join(root));
            if !roots.insert(root.clone()) {
                continue;
            }
            let mut directories = vec![(root, PathBuf::new())];
            while let Some((directory, relative)) = directories.pop() {
                let Ok(entries) = fs::read_dir(directory) else {
                    continue;
                };
                for entry in entries.flatten() {
                    let name = entry.file_name();
                    if name == ".git" || name == "node_modules" {
                        continue;
                    }
                    let path = entry.path();
                    if !path.is_dir() {
                        continue;
                    }
                    let child = relative.join(name);
                    self.send(Candidate::Cdpath(child.clone()))?;
                    if relative.as_os_str().is_empty() {
                        directories.push((path, child));
                    }
                }
            }
        }
        Ok(())
    }

    fn global_paths(&self, global_dir: PathBuf) -> io::Result<()> {
        if !global_dir.is_dir() {
            return Ok(());
        }
        let global_dir = normalize(&self.cwd.join(global_dir));
        let repos: Vec<_> = fs::read_dir(global_dir)?
            .flatten()
            .filter(|entry| !entry.file_name().as_bytes().starts_with(b"."))
            .map(|entry| entry.path())
            .filter(|repo| repo.join(".git").exists())
            .collect();
        let workers = parallelism().min(repos.len());
        parallel(repos, workers, |repo| {
            if !self.files_only {
                self.candidate(repo.clone(), false, None)?;
            }
            let mut git = Command::new("git");
            git.arg("-C")
                .arg(&repo)
                .args(["ls-files", "--recurse-submodules", "-z"]);
            if self.directories_only {
                git.arg("--format=%(objectmode) %(path)");
            }
            let child = git
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .process_group(0)
                .spawn()?;
            let stdout = self.git.lock().unwrap().register(child)?;
            let mut parents = HashSet::new();
            for file in BufReader::new(stdout).split(0) {
                let file = file?;
                // Git's indexed modes let directory scans skip regular files.
                let regular_file = self.directories_only && file.starts_with(b"100");
                let path = if self.directories_only {
                    file.splitn(2, |&byte| byte == b' ')
                        .nth(1)
                        .unwrap_or_default()
                } else {
                    &file
                };
                let file = Path::new(OsStr::from_bytes(path));
                if !regular_file {
                    self.candidate(repo.join(file), false, None)?;
                }
                if !self.files_only {
                    for parent in file
                        .ancestors()
                        .skip(1)
                        .filter(|p| !p.as_os_str().is_empty())
                    {
                        if !parents.insert(parent.to_path_buf()) {
                            break;
                        }
                        self.candidate(repo.join(parent), false, None)?;
                    }
                }
            }
            Ok(Vec::new())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn discovered_directories_can_run_concurrently() {
        let (started, running) = mpsc::sync_channel(1);
        let running = Mutex::new(running);
        let (release, finish) = mpsc::sync_channel(1);
        let finish = Mutex::new(finish);
        parallel(vec![0], 2, |job| {
            let wait = |receiver: &Mutex<mpsc::Receiver<()>>| {
                receiver
                    .lock()
                    .unwrap()
                    .recv_timeout(Duration::from_secs(5))
                    .map_err(|_| io::Error::from(io::ErrorKind::TimedOut))
            };
            match job {
                0 => return Ok(vec![1, 2]),
                1 => {
                    started.send(()).unwrap();
                    wait(&finish)?;
                }
                2 => {
                    wait(&running)?;
                    release.send(()).unwrap();
                }
                _ => unreachable!(),
            }
            Ok(Vec::new())
        })
        .expect("one directory blocked its sibling");
    }
}
