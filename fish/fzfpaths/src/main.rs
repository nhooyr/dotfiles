use ignore::Match;
use ignore::gitignore::{Gitignore, GitignoreBuilder};
use lscolors::{Indicator, LsColors, Style};
use std::collections::HashSet;
use std::env;
use std::ffi::{OsStr, OsString, c_int};
use std::fs::{self, Metadata};
use std::io::{self, BufRead, BufReader, BufWriter, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::{ffi::OsStrExt, ffi::OsStringExt, fs::MetadataExt, process::CommandExt};
use std::path::{Component, Path, PathBuf};
use std::process::{self, Child, ChildStdout, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

fn print_help(name: &str) {
    println!(
        "\
Generate path candidates for fzf from local files and Git repositories.

usage: {name} [--color] [--classify] [--keep-dot] [--read0] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]...

Scan <DIR>, Git repositories directly under <GLOBAL_DIR>, and optional CDPATH
roots concurrently. Stream results as they are found; paths from the three
searches may interleave, with no guaranteed order between them.

Local directories and global Git repositories are each scanned by a bounded
pool of workers. Local paths have no guaranteed traversal order. Within each
repository, global paths follow Git's order, with parent directories added as
needed; different repositories may interleave. Tracked paths (including
submodules) are followed by untracked paths that are not ignored by Git.
Untracked files inside submodules are omitted from global scans to avoid extra
Git processes. Search from inside the submodule to include them in the local
scan. fzf may reorder sorted matches.

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
path. Collisions are resolved the same way, preferring the first different
match in CDPATH order. Local selections stay relative.
Typing / on the Fish command line selects only global and CDPATH sources.
An explicit ./ token disables global and CDPATH searches. Ctrl-T (files) and
Alt-C (directories) use the parsed local query without ./; only Alt-V (files
and directories) keeps ./ in the query to find local executable paths.

The local scan respects .gitignore files, including nested rules and negations,
the repository's info/exclude, and Git's configured global ignore file.
Starting inside an ignored directory makes that directory searchable: ignore
rules above the ignored directory are bypassed, while rules inside still apply.
Directories named .git and node_modules are skipped unless they are <DIR> itself.
File searches also include special files and broken symlinks. With an empty
command line, the Fish widgets follow symlink targets and open multiple
directories, regular files, or scripts together with nvim --. Special files,
or multiple selections containing binary executables, use file --.
Executables without a shebang run directly;
scripts with a shebang also run when selected with their explicit ./ form.
At command start, an absolute-path query also runs selected executable scripts,
using the longest matching directory alias when available.

Options:
  -h, --help        Show this help.
  --color           Color alias prefixes cyan. Use fzf --ansi to display them
                    and strip the color escapes from selected paths.
  --classify        Append ls-style markers: / directories, * executables,
                    @ symlinks, | FIFOs, = sockets, and > doors where supported.
                    Other files get an invisible ASCII Unit Separator (0x1f).
                    With --color, basenames and markers use LS_COLORS.
                    The Fish widgets remove the final marker.
  --keep-dot        Also offer ./ paths for local scripts with a shebang.
  --read0           Read NUL-separated absolute filenames instead of scanning.
                    Relative filenames are rejected.
                    Keep input order, skipping missing files and directories.
                    Files under the working directory use local path rules;
                    other files use absolute paths or directory aliases.
  --cdpath CDPATH   Include directories from these colon-separated roots.
  --dirali ENV DIR  Abbreviate paths using ENV for DIR. May be repeated.

Arguments:
  <DIR>         Directory to search locally. Use . for the current directory.
  <GLOBAL_DIR>  Dir containing additional Git repositories.
                Use an empty string to skip global Git repositories.
  <TYPE>        -fd   Files and directories.
                -f    Files only, including special files and broken symlinks.
                -d    Directories only.

Each --dirali maps a directory to an alias, such as '$dotfiles' /path/to/dotfiles.
Each env must be unique. The longest matching directory wins.

For example, --dirali '$code' /code --dirali '$dotfiles' /code/dotfiles
turns /code/dotfiles/install.sh into $dotfiles/install.sh, since /code/dotfiles
is the longer matching prefix.

Output:
  Unique, NUL-separated paths. Filenames may contain spaces.
  With --classify, each path ends in one indicator. Ordinary files use an invisible
  ASCII Unit Separator (0x1f). Removing exactly one indicator preserves literal
  trailing stars, spaces, and separators in filenames.
  Local binary executables are offered only as ./ paths, even without --keep-dot.
  The local scan reads only the first two bytes of each executable. Files without
  a #! shebang, including executable text files, are treated as binary, as are
  unreadable files. The Fish widgets use the same check for selected executables.
  Other local paths omit a leading ./. With --keep-dot, scripts also get
  a ./ form. The Fish bindings enable this only when completing a command name.
  Global binary executables keep their normal absolute or directory-alias forms.
  Global scans do not read executable contents.
  Global paths use a matching env when available; otherwise they are absolute.
  For tracked paths, global directory scans (-d, used by Alt-C) use Git's
  indexed file types. If you replace a tracked regular file with a symlink
  to a directory, that symlink is omitted until you stage the change with
  git add. Local scans see the change immediately.
  Global paths inside <DIR>, including <DIR> itself, are skipped regardless of
  directory-alias spelling. The local scan owns that directory, so its ignore
  rules also apply to tracked files there. Global paths outside <DIR> continue
  streaming without waiting for the local scan. Directory aliases only
  abbreviate output; they do not expand the directory excluded globally.
  Identical output strings are emitted only once.
  The Fish bindings keep directory aliases in the command line.
  The shell expands them when the command is executed.

Examples (Fish):
  {name} --cdpath \"$CDPATH\" . \"$nhooyr\" -fd --dirali '$dotfiles' \"$dotfiles\" | fzf --read0
  {name} --cdpath \"$CDPATH\" . '' -d | fzf --read0
  {name} --keep-dot . '' -f | fzf --read0"
    );
}

fn usage_error(name: &str) -> ! {
    eprintln!(
        "usage: {name} [--color] [--classify] [--keep-dot] [--read0] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]..."
    );
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
    let mut color = false;
    let mut classify = false;
    let mut keep_dot = false;
    let mut read0 = false;
    let mut cdpath = None;
    while let Some(arg) = arguments.next() {
        if arg == "--color" {
            color = true;
        } else if arg == "--classify" {
            classify = true;
        } else if arg == "--keep-dot" {
            keep_dot = true;
        } else if arg == "--read0" {
            read0 = true;
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
    if args.len() != 3 || !matches!(args[2].to_str(), Some("-f" | "-d" | "-fd")) {
        usage_error(&name);
    }
    args.extend(aliases);
    let result = install_signal_handlers()
        .and_then(|()| run(&args, keep_dot, cdpath, color, classify, read0));
    let signal = TERMINATING_SIGNAL.load(Ordering::Relaxed);
    if signal != 0 {
        process::exit(128 + signal);
    }
    if let Err(error) = result
        && error.kind() != io::ErrorKind::BrokenPipe
    {
        eprintln!("{name}: {error}");
        process::exit(1);
    }
}

fn run(
    args: &[OsString],
    keep_dot: bool,
    cdpath: Option<OsString>,
    color: bool,
    classify: bool,
    read0: bool,
) -> io::Result<()> {
    let cwd = working_directory()?;
    let mut seen_envs = HashSet::new();
    let mut env_dirs = Vec::new();
    for [name, directory] in args[3..].as_chunks::<2>().0 {
        let env = name.as_bytes();
        if !seen_envs.insert(env) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("duplicate env: {}", name.to_string_lossy()),
            ));
        }
        let directory = Path::new(directory);
        if !directory.is_absolute() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!(
                    "directory alias {} requires an absolute path: {}",
                    name.to_string_lossy(),
                    directory.display()
                ),
            ));
        }
        let mut directory = directory.as_os_str().as_bytes();
        while directory.len() > 1 && directory.ends_with(b"/") {
            directory = &directory[..directory.len() - 1];
        }
        let directory = PathBuf::from(OsStr::from_bytes(directory));
        if let Ok(physical) = directory.canonicalize()
            && physical.as_os_str() != directory.as_os_str()
        {
            env_dirs.push((env.to_vec(), physical.into_os_string().into_vec()));
        }
        env_dirs.push((env.to_vec(), directory.into_os_string().into_vec()));
    }
    env_dirs.sort_by_key(|(_, dir)| std::cmp::Reverse(dir.len()));
    let colors = (color && classify).then(|| {
        Arc::new(
            LsColors::from_env()
                .unwrap_or_else(|| LsColors::from_string("di=34:ln=36:so=32:pi=32:ex=35")),
        )
    });
    let mut picker = Picker {
        color,
        classify,
        keep_dot,
        physical_cwd: env::current_dir()?,
        env_dirs,
        shown: HashSet::new(),
        output: BufWriter::new(CancellableStdout::new(io::stdout().as_raw_fd())?),
    };
    let (sender, receiver) = mpsc::sync_channel(256);
    let git = Arc::new(Mutex::new(GitScans::default()));
    let cancelled = Arc::new(AtomicBool::new(false));
    let scanner = Scanner {
        cwd,
        local_root: Path::new(&args[0]).canonicalize().ok(),
        files_only: args[2] == "-f",
        directories_only: args[2] == "-d",
        classify,
        colors,
        sender,
        git: Arc::clone(&git),
        cancelled: Arc::clone(&cancelled),
    };
    thread::scope(|scope| {
        let local = scanner.clone();
        let mut scans = vec![scope.spawn(move || {
            if read0 {
                local.input_paths()
            } else {
                local.walk(PathBuf::from(&args[0]))
            }
        })];
        if !read0 && !args[1].is_empty() {
            let global = scanner.clone();
            scans.push(scope.spawn(move || global.global_paths(PathBuf::from(&args[1]))));
        }
        if let Some(cdpath) =
            cdpath.filter(|value| !read0 && !value.is_empty() && !scanner.files_only)
        {
            let cd = scanner.clone();
            scans.push(scope.spawn(move || cd.cdpath(cdpath)));
        }
        drop(scanner);
        let result: io::Result<()> = (|| {
            let mut last_reap = Instant::now();
            loop {
                check_signal()?;
                // Registering a new Git process also reaps finished children;
                // this periodic sweep handles idle readers without locking for
                // every small output batch.
                if last_reap.elapsed() >= Duration::from_millis(50) {
                    if output_closed() {
                        return Err(io::ErrorKind::BrokenPipe.into());
                    }
                    git.lock().unwrap().reap_finished()?;
                    last_reap = Instant::now();
                }
                let candidate = match receiver.recv_timeout(Duration::from_millis(50)) {
                    Ok(candidate) => candidate,
                    Err(RecvTimeoutError::Disconnected) => break,
                    Err(RecvTimeoutError::Timeout) if output_closed() => {
                        return Err(io::ErrorKind::BrokenPipe.into());
                    }
                    Err(RecvTimeoutError::Timeout) => continue,
                };
                for candidate in std::iter::once(candidate)
                    .chain(receiver.try_iter())
                    .take(256)
                {
                    check_signal()?;
                    match candidate {
                        Candidate::Path { path, local, style } => {
                            picker.emit_path(path, local, style)?;
                        }
                        Candidate::Cdpath(path, style) => {
                            picker.emit(
                                [b"$CDPATH/", path.as_os_str().as_bytes()].concat(),
                                false,
                                &style,
                            )?;
                        }
                    }
                }
                // Never wait for a slower scan with local results still buffered.
                picker.output.flush()?;
            }
            Ok(())
        })();
        cancelled.store(true, Ordering::Relaxed);
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

static TERMINATING_SIGNAL: AtomicI32 = AtomicI32::new(0);

fn install_signal_handlers() -> io::Result<()> {
    extern "C" fn record_signal(signal: c_int) {
        // Cleanup runs outside the handler, which must not take locks.
        TERMINATING_SIGNAL.store(signal, Ordering::Relaxed);
    }
    unsafe extern "C" {
        fn signal(signal: c_int, handler: extern "C" fn(c_int)) -> usize;
    }
    const SIGHUP: c_int = 1;
    const SIGINT: c_int = 2;
    const SIGTERM: c_int = 15;
    for signum in [SIGHUP, SIGINT, SIGTERM] {
        if unsafe { signal(signum, record_signal) } == usize::MAX {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

fn check_signal() -> io::Result<()> {
    if TERMINATING_SIGNAL.load(Ordering::Relaxed) == 0 {
        Ok(())
    } else {
        Err(io::ErrorKind::Interrupted.into())
    }
}

// Check for a closed picker even when a scan has no new paths to write.
fn output_closed() -> bool {
    let mut fd = libc::pollfd {
        fd: io::stdout().as_raw_fd(),
        events: libc::POLLOUT, // macOS reports pipe hangups only when writing is requested.
        revents: 0,
    };
    unsafe {
        libc::poll(&mut fd, 1, 0) > 0
            && fd.revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
    }
}

struct CancellableStdout {
    fd: c_int,
    restore_blocking: bool,
}

impl CancellableStdout {
    fn new(fd: c_int) -> io::Result<Self> {
        let mut metadata = unsafe { std::mem::zeroed::<libc::stat>() };
        if unsafe { libc::fstat(fd, &mut metadata) } < 0 {
            return Err(io::Error::last_os_error());
        }
        // Leave terminal and regular-file descriptors unchanged.
        let mut restore_blocking = false;
        if metadata.st_mode & libc::S_IFMT == libc::S_IFIFO {
            let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
            if flags < 0 {
                return Err(io::Error::last_os_error());
            }
            if flags & libc::O_NONBLOCK == 0 {
                if unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
                    return Err(io::Error::last_os_error());
                }
                restore_blocking = true;
            }
        }
        Ok(Self {
            fd,
            restore_blocking,
        })
    }
}

impl Write for CancellableStdout {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        loop {
            // BufWriter retries Interrupted errors, so cancellation must stop it.
            check_signal().map_err(io::Error::other)?;
            let written = unsafe { libc::write(self.fd, buffer.as_ptr().cast(), buffer.len()) };
            if written >= 0 {
                return Ok(written as usize);
            }
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::WouldBlock {
                let mut fd = libc::pollfd {
                    fd: self.fd,
                    events: libc::POLLOUT,
                    revents: 0,
                };
                if unsafe { libc::poll(&mut fd, 1, 50) } < 0 {
                    let error = io::Error::last_os_error();
                    if error.kind() != io::ErrorKind::Interrupted {
                        return Err(error);
                    }
                }
            } else if error.kind() != io::ErrorKind::Interrupted {
                return Err(error);
            }
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl Drop for CancellableStdout {
    fn drop(&mut self) {
        if self.restore_blocking {
            let flags = unsafe { libc::fcntl(self.fd, libc::F_GETFL) };
            if flags >= 0 {
                unsafe { libc::fcntl(self.fd, libc::F_SETFL, flags & !libc::O_NONBLOCK) };
            }
        }
    }
}

#[derive(Default)]
struct GitScans {
    cancelled: bool,
    children: Vec<GitChild>,
    failed: Option<ExitStatus>,
}

struct GitChild {
    child: Child,
    output_open: Arc<AtomicBool>,
}

struct GitOutput {
    stdout: ChildStdout,
    open: Arc<AtomicBool>,
}

impl Read for GitOutput {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        self.stdout.read(buffer)
    }
}

impl Drop for GitOutput {
    fn drop(&mut self) {
        self.open.store(false, Ordering::Release);
    }
}

fn child_has_exited(child: &Child) -> io::Result<bool> {
    loop {
        let mut info = unsafe { std::mem::zeroed::<libc::siginfo_t>() };
        let result = unsafe {
            libc::waitid(
                libc::P_PID,
                child.id() as libc::id_t,
                &mut info,
                libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
            )
        };
        if result == 0 {
            return Ok(info.si_signo != 0);
        }
        let error = io::Error::last_os_error();
        if error.kind() != io::ErrorKind::Interrupted {
            return Err(error);
        }
    }
}

fn kill_group(child: &Child) {
    unsafe { libc::kill(-(child.id() as libc::pid_t), libc::SIGKILL) };
}

impl GitScans {
    fn register(&mut self, mut child: Child) -> io::Result<GitOutput> {
        let open = Arc::new(AtomicBool::new(true));
        let output = GitOutput {
            stdout: child.stdout.take().unwrap(),
            open: Arc::clone(&open),
        };
        self.children.push(GitChild {
            child,
            output_open: open,
        });
        if self.cancelled {
            self.cancel();
            return Err(io::ErrorKind::BrokenPipe.into());
        }
        if let Err(error) = self.reap_finished() {
            self.cancel();
            return Err(error);
        }
        Ok(output)
    }

    fn reap_finished(&mut self) -> io::Result<()> {
        let mut index = 0;
        while index < self.children.len() {
            let entry = &mut self.children[index];
            // A descendant can still be writing after the Git leader exits.
            if entry.output_open.load(Ordering::Acquire) || !child_has_exited(&entry.child)? {
                index += 1;
                continue;
            }
            // WNOWAIT keeps the leader's PID reserved until its remaining group
            // members are killed. Never retain a process-group ID after reaping:
            // cancellation could otherwise signal an unrelated reused ID.
            kill_group(&entry.child);
            let status = entry.child.wait()?;
            self.children.swap_remove(index);
            if !self.cancelled && !status.success() {
                self.failed = Some(status);
            }
        }
        Ok(())
    }

    fn cancel(&mut self) {
        self.cancelled = true;
        for entry in &self.children {
            // Registered children are always unreaped, so these IDs are reserved.
            kill_group(&entry.child);
        }
    }

    fn wait(&mut self) -> io::Result<()> {
        while !self.children.is_empty() {
            self.reap_finished()?;
            // Git may close stdout before exiting; keep signals responsive then too.
            if !self.cancelled
                && (TERMINATING_SIGNAL.load(Ordering::Relaxed) != 0 || output_closed())
            {
                self.cancel();
            }
            if !self.children.is_empty() {
                thread::sleep(Duration::from_millis(1));
            }
        }
        if !self.cancelled
            && let Some(status) = self.failed
        {
            return Err(io::Error::other(format!("git failed: {status}")));
        }
        Ok(())
    }
}

#[derive(Clone)]
struct LocalIgnores {
    matchers: Vec<Arc<Gitignore>>,
    case_insensitive: bool,
}

fn ignored(path: &Path, directory: bool, ignores: &LocalIgnores) -> bool {
    for matcher in ignores.matchers.iter().rev() {
        match matcher.matched(path, directory) {
            Match::Ignore(_) => return true,
            Match::Whitelist(_) => return false,
            Match::None => {}
        }
    }
    false
}

fn add_ignore_file(directory: &Path, ignores: &mut LocalIgnores) {
    let path = directory.join(".gitignore");
    if !path
        .symlink_metadata()
        .is_ok_and(|metadata| metadata.is_file())
    {
        return;
    }
    add_excludes(directory, &path, ignores);
}

fn add_excludes(root: &Path, path: &Path, ignores: &mut LocalIgnores) {
    let mut builder = GitignoreBuilder::new(root);
    builder.allow_unclosed_class(false);
    builder.case_insensitive(ignores.case_insensitive).unwrap();
    builder.add(path);
    if let Ok(matcher) = builder.build()
        && !matcher.is_empty()
    {
        ignores.matchers.push(Arc::new(matcher));
    }
}

fn config_home() -> Option<PathBuf> {
    env::var_os("XDG_CONFIG_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
}

fn global_ignores(root: &Path) -> io::Result<Gitignore> {
    let mut builder = GitignoreBuilder::new(root);
    builder.allow_unclosed_class(false);
    if let Some(path) = config_home().map(|config| config.join("fzfpaths/ignore"))
        && path.try_exists()?
        && let Some(error) = builder.add(path)
    {
        return Err(io::Error::other(error));
    }
    builder.build().map_err(io::Error::other)
}

fn working_directory() -> io::Result<PathBuf> {
    let cwd = env::current_dir()?;
    if let Some(pwd) = env::var_os("PWD").map(PathBuf::from)
        && pwd.is_absolute()
        && let (Ok(a), Ok(b)) = (pwd.metadata(), cwd.metadata())
        && (a.dev(), a.ino()) == (b.dev(), b.ino())
    {
        return Ok(pwd);
    }
    Ok(cwd)
}

fn normalize(path: &Path) -> PathBuf {
    let has_parent = path.components().any(|part| part == Component::ParentDir);
    if has_parent && !path.is_dir() {
        return path.to_path_buf();
    }
    let mut result = PathBuf::new();
    for part in path.components() {
        if part == Component::ParentDir {
            // Resolve only links crossed by ..; keep other spellings for aliases.
            while let Ok(target) = result.read_link() {
                result.pop();
                result.push(target);
                result = normalize(&result);
            }
            result.pop();
        } else {
            result.push(part);
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
            scope.spawn(|| {
                loop {
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
                }
            });
        }
    });
    queue.into_inner().unwrap().error.map_or(Ok(()), Err)
}

struct FileInfo {
    metadata: Metadata,
    target: Option<Metadata>,
}

impl FileInfo {
    fn new(path: &Path) -> Option<Self> {
        let metadata = path.symlink_metadata().ok()?;
        let target = metadata
            .is_symlink()
            .then(|| path.metadata().ok())
            .flatten();
        Some(Self { metadata, target })
    }

    fn followed(&self) -> &Metadata {
        self.target.as_ref().unwrap_or(&self.metadata)
    }
}

struct PathStyle {
    indicator: u8,
    executable: bool,
    binary_executable: bool,
    color: Option<Style>,
}

impl PathStyle {
    fn plain(indicator: u8) -> Self {
        Self {
            indicator,
            executable: indicator == b'*',
            binary_executable: false,
            color: None,
        }
    }
}

fn file_indicator(mode: u32) -> u8 {
    match mode & 0o170000 {
        0o040000 => b'/',
        0o120000 => b'@',
        0o010000 => b'|',
        0o140000 => b'=',
        0o150000 => b'>', // Doors on Solaris/illumos.
        0o100000 if mode & 0o111 != 0 => b'*',
        _ => b'\x1f', // Unit Separator: no visible suffix, but still unambiguous.
    }
}

fn has_shebang(path: &Path) -> io::Result<bool> {
    let mut header = [0; 2];
    fs::File::open(path)?.read_exact(&mut header)?;
    Ok(header == *b"#!")
}

struct Picker {
    color: bool,
    classify: bool,
    keep_dot: bool,
    physical_cwd: PathBuf,
    env_dirs: Vec<(Vec<u8>, Vec<u8>)>,
    shown: HashSet<Vec<u8>>,
    output: BufWriter<CancellableStdout>,
}

impl Picker {
    fn emit(&mut self, mut path: Vec<u8>, literal: bool, style: &PathStyle) -> io::Result<()> {
        if literal && matches!(path.first(), Some(b'$' | b'~' | b'-')) {
            path.splice(..0, b"./".iter().copied());
        }
        if !self.shown.insert(path.clone()) {
            return Ok(());
        }
        let mut path = path.as_slice();
        if self.color && !literal {
            let end = path
                .iter()
                .position(|&byte| byte == b'/')
                .unwrap_or(path.len());
            self.output.write_all(b"\x1b[36m")?;
            self.output.write_all(&path[..end])?;
            self.output.write_all(b"\x1b[0m")?;
            path = &path[end..];
        }
        let color = style.color.as_ref().map(Style::to_nu_ansi_term_style);
        if let Some(color) = color {
            let basename = path
                .iter()
                .rposition(|&byte| byte == b'/')
                .map_or(0, |i| i + 1);
            self.output.write_all(&path[..basename])?;
            write!(self.output, "{}", color.prefix())?;
            path = &path[basename..];
        }
        self.output.write_all(path)?;
        if self.classify {
            self.output.write_all(&[style.indicator])?;
        }
        if let Some(color) = color {
            write!(self.output, "{}", color.suffix())?;
        }
        self.output.write_all(b"\0")?;
        if self.shown.len() == 1 {
            self.output.flush()?;
        }
        Ok(())
    }

    fn emit_path(&mut self, path: PathBuf, local: bool, style: PathStyle) -> io::Result<()> {
        if local && style.binary_executable {
            let mut relative = PathBuf::from(".");
            if path.is_absolute() {
                for ancestor in self.physical_cwd.ancestors() {
                    if let Ok(rest) = path.strip_prefix(ancestor) {
                        relative.push(rest);
                        break;
                    }
                    relative.push("..");
                }
            } else {
                relative.push(path.strip_prefix(".").unwrap_or(&path));
            }
            return self.emit(relative.into_os_string().into_vec(), true, &style);
        }
        let mut path = path.into_os_string().into_vec();
        if path.starts_with(b"./") {
            path.drain(..2);
        }
        if local {
            if self.keep_dot
                && style.executable
                && !path.starts_with(b"/")
                && !path.starts_with(b"./")
            {
                self.emit(path.clone(), true, &style)?;
                path.splice(..0, b"./".iter().copied());
            }
            return self.emit(path, true, &style);
        }
        if let Some((env, dir)) = self.env_dirs.iter().find(|(_, dir)| {
            path.starts_with(dir)
                && (dir == b"/" || path.len() == dir.len() || path.get(dir.len()) == Some(&b'/'))
        }) {
            let prefix = if dir == b"/" && path.len() > 1 {
                0
            } else {
                dir.len()
            };
            path.splice(..prefix, env.iter().copied());
            self.emit(path, false, &style)
        } else {
            self.emit(path, true, &style)
        }
    }
}

enum Candidate {
    Path {
        path: PathBuf,
        local: bool,
        style: PathStyle,
    },
    Cdpath(PathBuf, PathStyle),
}

#[derive(Clone)]
struct Scanner {
    cwd: PathBuf,
    local_root: Option<PathBuf>,
    files_only: bool,
    directories_only: bool,
    classify: bool,
    colors: Option<Arc<LsColors>>,
    sender: SyncSender<Candidate>,
    git: Arc<Mutex<GitScans>>,
    cancelled: Arc<AtomicBool>,
}

impl Scanner {
    fn input_paths(&self) -> io::Result<()> {
        let physical_cwd = env::current_dir()?;
        let mut input = io::stdin().lock();
        let mut pending = Vec::new();
        let mut buffer = [0; 8192];
        loop {
            self.check_cancelled()?;
            let mut fd = libc::pollfd {
                fd: input.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            };
            match unsafe { libc::poll(&mut fd, 1, 50) } {
                0 => continue,
                -1 => {
                    let error = io::Error::last_os_error();
                    if error.kind() == io::ErrorKind::Interrupted {
                        continue;
                    }
                    return Err(error);
                }
                _ => {}
            }
            let length = input.read(&mut buffer)?;
            if length == 0 {
                return self.input_path(&pending, &physical_cwd);
            }
            for part in buffer[..length].split_inclusive(|byte| *byte == 0) {
                pending.extend_from_slice(part);
                if pending.last() == Some(&0) {
                    pending.pop();
                    self.input_path(&pending, &physical_cwd)?;
                    pending.clear();
                }
            }
        }
    }

    fn input_path(&self, bytes: &[u8], physical_cwd: &Path) -> io::Result<()> {
        if bytes.is_empty() {
            return Ok(());
        }
        let absolute = PathBuf::from(OsStr::from_bytes(bytes));
        if !absolute.is_absolute() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("--read0 requires absolute paths: {}", absolute.display()),
            ));
        }
        let Some(info) = FileInfo::new(&absolute) else {
            return Ok(());
        };
        if !info.followed().is_file() {
            return Ok(());
        }
        let relative = absolute
            .strip_prefix(&self.cwd)
            .or_else(|_| absolute.strip_prefix(physical_cwd))
            .map(Path::to_path_buf)
            .ok()
            .or_else(|| {
                // Resolve directory aliases without replacing a symlink's filename.
                let physical = absolute
                    .parent()?
                    .canonicalize()
                    .ok()?
                    .join(absolute.file_name()?);
                physical
                    .strip_prefix(physical_cwd)
                    .map(Path::to_path_buf)
                    .ok()
            });
        let local = relative.is_some();
        let path = relative.unwrap_or(absolute);
        self.candidate(path, local, Some(info))
    }

    fn check_cancelled(&self) -> io::Result<()> {
        if self.cancelled.load(Ordering::Relaxed) {
            return Err(io::ErrorKind::BrokenPipe.into());
        }
        check_signal()
    }

    fn git_output(
        &self,
        directory: &Path,
        args: impl IntoIterator<Item = impl AsRef<OsStr>>,
    ) -> io::Result<Vec<u8>> {
        self.check_cancelled()?;
        let child = Command::new("git")
            .arg("-C")
            .arg(directory)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .process_group(0)
            .spawn()?;
        let mut stdout = self.git.lock().unwrap().register(child)?;
        let mut output = Vec::new();
        stdout.read_to_end(&mut output)?;
        Ok(output)
    }

    fn local_ignores(&self, directory: &Path) -> io::Result<LocalIgnores> {
        let git_root = directory
            .ancestors()
            .find(|parent| parent.join(".git").exists());
        let root = git_root.unwrap_or(directory);
        let case_insensitive = self.git_output(
            root,
            [
                "config",
                "--null",
                "--bool",
                "--default",
                "false",
                "--get",
                "core.ignorecase",
            ],
        )? == b"true\0";
        let mut ignores = LocalIgnores {
            matchers: Vec::new(),
            case_insensitive,
        };
        let default = config_home()
            .map(|config| config.join("git/ignore"))
            .unwrap_or_default();
        let mut args = ["config", "--null", "--path", "--default"]
            .map(OsString::from)
            .to_vec();
        args.push(default.into_os_string());
        args.extend(["--get", "core.excludesFile"].map(OsString::from));
        let mut global = self.git_output(root, args)?;
        global.pop(); // Git terminates the path with NUL, even when explicitly empty.
        if !global.is_empty() {
            add_excludes(root, &root.join(OsString::from_vec(global)), &mut ignores);
        }
        if let Some(root) = git_root {
            let git_dir = root.join(".git");
            let exclude = if git_dir.is_dir() {
                git_dir.join("info/exclude")
            } else {
                let mut path = self.git_output(
                    root,
                    [
                        "rev-parse",
                        "--path-format=absolute",
                        "--git-path",
                        "info/exclude",
                    ],
                )?;
                path.pop(); // rev-parse terminates the path with one newline.
                PathBuf::from(OsString::from_vec(path))
            };
            add_excludes(root, &exclude, &mut ignores);
        }
        let mut ancestors = Vec::new();
        for parent in directory.ancestors() {
            ancestors.push(parent);
            if Some(parent) == git_root {
                break;
            }
        }
        for parent in ancestors.into_iter().rev() {
            if ignored(parent, true, &ignores) {
                // An explicit search inside an ignored directory starts fresh here.
                ignores.matchers.clear();
            }
            add_ignore_file(parent, &mut ignores);
        }
        Ok(ignores)
    }

    fn send(&self, candidate: Candidate) -> io::Result<()> {
        self.sender
            .send(candidate)
            .map_err(|_| io::ErrorKind::BrokenPipe.into())
    }

    fn emit_path(&self, path: PathBuf, local: bool, style: PathStyle) -> io::Result<()> {
        self.send(Candidate::Path { path, local, style })
    }

    fn style(&self, path: &Path, info: &FileInfo) -> PathStyle {
        let indicator = file_indicator(info.metadata.mode());
        let color = self.colors.as_ref().and_then(|colors| {
            if indicator == b'>' {
                colors.style_for_indicator(Indicator::Door)
            } else {
                colors.style_for_path_with_metadata(path, Some(&info.metadata))
            }
        });
        let followed = info.followed();
        let executable = followed.is_file() && followed.mode() & 0o111 != 0;
        PathStyle {
            indicator,
            executable,
            binary_executable: false,
            color: color.cloned(),
        }
    }

    fn candidate(&self, path: PathBuf, local: bool, info: Option<FileInfo>) -> io::Result<()> {
        let Some(info) = info.or_else(|| FileInfo::new(&path)) else {
            return Ok(());
        };
        let metadata = info.followed();
        let wanted = if metadata.is_dir() {
            !self.files_only
        } else {
            !self.directories_only
        };
        if !wanted {
            return Ok(());
        }
        let mut style = self.style(&path, &info);
        if local && style.executable {
            style.binary_executable = !has_shebang(&path).unwrap_or(false);
        }
        self.emit_path(path, local, style)
    }

    fn global_candidate(
        &self,
        path: PathBuf,
        absolute: PathBuf,
        ignores: &Gitignore,
    ) -> io::Result<()> {
        if self
            .local_root
            .as_ref()
            .is_some_and(|root| absolute.starts_with(root))
        {
            return Ok(());
        }
        let Some(info) = FileInfo::new(&path) else {
            return Ok(());
        };
        if ignores
            .matched_path_or_any_parents(&path, info.followed().is_dir())
            .is_ignore()
        {
            return Ok(());
        }
        self.candidate(path, false, Some(info))
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
        let ignores = self.local_ignores(&absolute)?;
        let ancestors = vec![(metadata.dev(), metadata.ino())];
        parallel(
            vec![(path, absolute, ancestors, ignores)],
            parallelism(),
            |(path, absolute, ancestors, ignores)| {
                self.check_cancelled()?;
                let mut directories = Vec::new();
                let Ok(entries) = fs::read_dir(path) else {
                    return Ok(directories);
                };
                for entry in entries.flatten() {
                    self.check_cancelled()?;
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
                    let Some(info) = FileInfo::new(&path) else {
                        continue;
                    };
                    let metadata = info.followed();
                    let is_directory = metadata.is_dir();
                    if ignored(&absolute, is_directory, &ignores) {
                        continue;
                    }
                    let identity = (metadata.dev(), metadata.ino());
                    self.candidate(path.clone(), true, Some(info))?;
                    if is_directory && !ancestors.contains(&identity) {
                        let mut ancestors = ancestors.clone();
                        ancestors.push(identity);
                        let ignores = if absolute.join(".git").exists() {
                            self.local_ignores(&absolute)?
                        } else {
                            let mut ignores = ignores.clone();
                            add_ignore_file(&absolute, &mut ignores);
                            ignores
                        };
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
            self.check_cancelled()?;
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
                    self.check_cancelled()?;
                    let name = entry.file_name();
                    if name == ".git" || name == "node_modules" {
                        continue;
                    }
                    let path = entry.path();
                    let Ok(kind) = entry.file_type() else {
                        continue;
                    };
                    if !kind.is_dir() && !kind.is_symlink() {
                        continue;
                    }
                    let style = if self.classify {
                        let Some(info) = FileInfo::new(&path) else {
                            continue;
                        };
                        if !info.followed().is_dir() {
                            continue;
                        }
                        self.style(&path, &info)
                    } else {
                        if kind.is_symlink() && !path.is_dir() {
                            continue;
                        }
                        PathStyle::plain(b'/')
                    };
                    let child = relative.join(name);
                    self.send(Candidate::Cdpath(child.clone(), style))?;
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
        let ignores = global_ignores(&global_dir)?;
        let repos: Vec<_> = fs::read_dir(&global_dir)?
            .flatten()
            .filter(|entry| !entry.file_name().as_bytes().starts_with(b"."))
            .map(|entry| entry.path())
            .filter(|repo| repo.join(".git").exists())
            .filter(|repo| !ignores.matched_path_or_any_parents(repo, true).is_ignore())
            .collect();
        let workers = parallelism().min(repos.len());
        parallel(repos, workers, |repo| {
            self.check_cancelled()?;
            let physical_repo = repo.canonicalize()?;
            if self
                .local_root
                .as_ref()
                .is_some_and(|root| physical_repo.starts_with(root))
            {
                return Ok(Vec::new());
            }
            if !self.files_only {
                self.global_candidate(repo.clone(), physical_repo.clone(), &ignores)?;
            }
            let mut parents = HashSet::new();
            // --recurse-submodules cannot be combined with --others.
            for tracked in [true, false] {
                let indexed_modes = tracked && self.directories_only;
                let mut git = Command::new("git");
                git.arg("-C")
                    .arg(&repo)
                    .args(["ls-files", "--sparse", "-z"]);
                if tracked {
                    git.arg("--recurse-submodules");
                    if indexed_modes {
                        git.arg("--format=%(objectmode) %(path)");
                    }
                } else {
                    git.args(["--others", "--exclude-standard"]);
                }
                let child = git
                    .stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .process_group(0)
                    .spawn()?;
                let stdout = self.git.lock().unwrap().register(child)?;
                for file in BufReader::new(stdout).split(0) {
                    self.check_cancelled()?;
                    let file = file?;
                    // Git's indexed modes let directory scans skip regular files.
                    let regular_file = indexed_modes && file.starts_with(b"100");
                    let path = if indexed_modes {
                        file.splitn(2, |&byte| byte == b' ')
                            .nth(1)
                            .unwrap_or_default()
                    } else {
                        &file
                    };
                    let file = Path::new(OsStr::from_bytes(path));
                    if !regular_file {
                        self.global_candidate(repo.join(file), physical_repo.join(file), &ignores)?;
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
                            self.global_candidate(
                                repo.join(parent),
                                physical_repo.join(parent),
                                &ignores,
                            )?;
                        }
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
    use std::os::fd::{AsFd, FromRawFd};
    use std::time::{Duration, Instant};

    #[derive(Default)]
    struct TestScans(GitScans);

    impl Drop for TestScans {
        fn drop(&mut self) {
            self.0.cancel();
            for entry in &self.0.children {
                entry.output_open.store(false, Ordering::Release);
            }
            let _ = self.0.wait();
        }
    }

    fn exited_git(script: &str) -> Child {
        let mut child = Command::new("/bin/sh")
            .args(["-c", script])
            .stdout(Stdio::piped())
            .process_group(0)
            .spawn()
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while !child_has_exited(&child).unwrap() {
            if Instant::now() >= deadline {
                kill_group(&child);
                let _ = child.wait();
                panic!("Git fixture did not exit");
            }
            thread::sleep(Duration::from_millis(1));
        }
        child
    }

    #[test]
    fn completed_git_children_are_reaped_while_scans_continue() {
        let mut scans = TestScans::default();
        let mut previous = None;
        for _ in 0..32 {
            let child = exited_git("exit 0");
            let pid = child.id();
            drop(scans.0.register(child).unwrap());
            assert_eq!(scans.0.children.len(), 1);
            if let Some(pid) = previous {
                assert_eq!(
                    unsafe { libc::waitpid(pid, std::ptr::null_mut(), libc::WNOHANG) },
                    -1
                );
                assert_eq!(
                    io::Error::last_os_error().raw_os_error(),
                    Some(libc::ECHILD)
                );
            }
            previous = Some(pid as libc::pid_t);
        }
        scans.0.reap_finished().unwrap();
        assert!(scans.0.children.is_empty());
        scans.0.wait().unwrap();
    }

    #[test]
    fn reaped_git_failures_are_reported_after_other_scans_finish() {
        let mut scans = TestScans::default();
        drop(scans.0.register(exited_git("exit 7")).unwrap());
        drop(scans.0.register(exited_git("exit 0")).unwrap());
        assert_eq!(scans.0.children.len(), 1);
        assert_eq!(
            scans.0.wait().unwrap_err().to_string(),
            "git failed: exit status: 7"
        );
    }

    #[test]
    fn exited_git_leaders_preserve_output_and_cleanup_their_descendants() {
        for cancel in [false, true] {
            let mut scans = TestScans::default();
            let output = scans.0.register(exited_git("sleep 30 & exit 0")).unwrap();
            let pipe = output.stdout.as_fd().try_clone_to_owned().unwrap();
            scans.0.reap_finished().unwrap();
            assert_eq!(scans.0.children.len(), 1, "output is still being read");
            if cancel {
                scans.0.cancel();
            }
            drop(output);
            scans.0.reap_finished().unwrap();
            assert!(scans.0.children.is_empty());
            let mut poll = libc::pollfd {
                fd: pipe.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            };
            assert!(unsafe { libc::poll(&mut poll, 1, 1000) } > 0);
            assert_ne!(poll.revents & libc::POLLHUP, 0, "descendant survived");
        }
    }

    #[test]
    fn file_type_indicators_match_ls() {
        for (mode, expected) in [
            (0o040755, b'/'),
            (0o100755, b'*'),
            (0o100644, b'\x1f'),
            (0o120777, b'@'),
            (0o010644, b'|'),
            (0o140755, b'='),
            (0o150755, b'>'),
            (0o060644, b'\x1f'),
            (0o020644, b'\x1f'),
        ] {
            assert_eq!(file_indicator(mode), expected, "mode {mode:o}");
        }
    }

    #[test]
    fn output_restores_pipe_flags_after_success_and_error() {
        for (close_reader, nonblocking) in [(false, false), (true, false), (false, true)] {
            let mut fds = [0; 2];
            assert_eq!(unsafe { libc::pipe(fds.as_mut_ptr()) }, 0);
            for fd in fds {
                assert_eq!(
                    unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) },
                    0
                );
            }
            let mut reader = Some(unsafe { fs::File::from_raw_fd(fds[0]) });
            let writer = unsafe { fs::File::from_raw_fd(fds[1]) };
            let fd = writer.as_raw_fd();
            if nonblocking {
                assert_eq!(
                    unsafe { libc::fcntl(fd, libc::F_SETFL, libc::O_NONBLOCK) },
                    0
                );
            }
            let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
            let expected;
            {
                let mut output = CancellableStdout::new(fd).unwrap();
                assert_eq!(
                    unsafe { libc::fcntl(fd, libc::F_GETFL) },
                    flags | libc::O_NONBLOCK
                );
                if close_reader {
                    drop(reader.take());
                    assert_eq!(
                        output.write(b"x").unwrap_err().kind(),
                        io::ErrorKind::BrokenPipe
                    );
                } else {
                    assert_eq!(output.write(b"x").unwrap(), 1);
                }
                expected = (unsafe { libc::fcntl(fd, libc::F_GETFL) } & !libc::O_NONBLOCK)
                    | (flags & libc::O_NONBLOCK);
            }
            assert_eq!(unsafe { libc::fcntl(fd, libc::F_GETFL) }, expected);
        }
        let file = fs::File::open(env::current_exe().unwrap()).unwrap();
        let flags = unsafe { libc::fcntl(file.as_raw_fd(), libc::F_GETFL) };
        let _output = CancellableStdout::new(file.as_raw_fd()).unwrap();
        assert_eq!(
            unsafe { libc::fcntl(file.as_raw_fd(), libc::F_GETFL) },
            flags
        );
    }

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
