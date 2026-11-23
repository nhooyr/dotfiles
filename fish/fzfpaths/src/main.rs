use ignore::Match;
use ignore::gitignore::{Gitignore, GitignoreBuilder};
use lscolors::{Indicator, LsColors, Style};
use std::collections::HashSet;
use std::env;
use std::ffi::{OsStr, OsString, c_int, c_short};
use std::fs::{self, Metadata};
use std::io::{self, BufRead, BufReader, BufWriter, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::{ffi::OsStrExt, ffi::OsStringExt, fs::MetadataExt, process::CommandExt};
use std::path::{Component, Path, PathBuf};
use std::process::{self, Child, ChildStdout, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::Duration;

fn print_help(name: &str) {
    println!(
        "\
Generate path candidates for fzf from local files and Git repositories.

usage: {name} [--color] [--classify] [--keep-dot] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]...

Scan <DIR>, Git repositories directly under <GLOBAL_DIR>, and optional CDPATH
roots concurrently. Stream results as they are found; paths from the three
searches may interleave, with no guaranteed order between them.

Local directories and global Git repositories are each scanned by a bounded
pool of workers. Local paths have no guaranteed traversal order. Within each
repository, global paths follow Git's order, with parent directories added as
needed; different repositories may interleave. Tracked paths (including
submodules) are followed by untracked paths that are not ignored by Git.
fzf may reorder sorted matches.

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
An explicit ./ token disables global and CDPATH searches. Ctrl-T (files) and
Alt-C (directories) use the parsed local query without ./; only Alt-V (files
and directories) keeps ./ in the query to find local executable paths.

The local scan respects .gitignore files, including nested rules and negations,
the repository's info/exclude, and Git's configured global ignore file.
Starting inside an ignored directory makes that directory searchable: ignore
rules above the ignored directory are bypassed, while rules inside still apply.
Directories named .git and node_modules are skipped unless they are <DIR> itself.
File searches also include special files and broken symlinks. With an empty
command line, the Fish widgets distinguish directories, regular files, and
executables without a #! shebang by following symlink targets. Mixed file types
and special files use file --. Executables without a shebang run directly;
scripts with a shebang also run when selected with their explicit ./ form.

Options:
  -h, --help        Show this help.
  --color          Color alias prefixes cyan. Use fzf --ansi to display them
                   and strip the color escapes from selected paths.
  --classify       Append ls-style markers: / directories, * executables,
                   @ symlinks, | FIFOs, = sockets, and > doors where supported.
                   Other files get an invisible ASCII Unit Separator (0x1f).
                   With --color, basenames and markers use LS_COLORS.
                   The Fish widgets remove the final marker.
  --keep-dot        Also offer ./ paths for local scripts with a shebang.
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
turns /code/dotfiles/init.sh into $dotfiles/init.sh, since /code/dotfiles
is the longer matching prefix.

Output:
  Unique, NUL-separated paths. Filenames may contain spaces or newlines.
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
    eprintln!(
        "usage: {name} [--color] [--classify] [--keep-dot] [--cdpath CDPATH] <DIR> <GLOBAL_DIR> <TYPE> [--dirali <ENV> <DIR>]..."
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
    let mut cdpath = None;
    while let Some(arg) = arguments.next() {
        if arg == "--color" {
            color = true;
        } else if arg == "--classify" {
            classify = true;
        } else if arg == "--keep-dot" {
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
    if args.len() != 3 || !matches!(args[2].to_str(), Some("-f" | "-d" | "-fd")) {
        usage_error(&name);
    }
    args.extend(aliases);
    let result =
        install_signal_handlers().and_then(|()| run(&args, keep_dot, cdpath, color, classify));
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
) -> io::Result<()> {
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
        let directory = if directory.is_absolute() {
            normalize(directory)
        } else {
            directory.to_path_buf()
        };
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
        output: BufWriter::new(io::stdout()),
    };
    let (sender, receiver) = mpsc::sync_channel(256);
    let git = Arc::new(Mutex::new(GitScans::default()));
    let cancelled = Arc::new(AtomicBool::new(false));
    let scanner = Scanner {
        cwd: working_directory()?,
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
                check_signal()?;
                let candidate = match receiver.recv_timeout(Duration::from_millis(50)) {
                    Ok(candidate) => candidate,
                    Err(RecvTimeoutError::Disconnected) => break,
                    Err(RecvTimeoutError::Timeout) if output_closed() => {
                        return Err(io::ErrorKind::BrokenPipe.into());
                    }
                    Err(RecvTimeoutError::Timeout) => continue,
                };
                for candidate in std::iter::once(candidate).chain(receiver.try_iter()) {
                    check_signal()?;
                    let flush = match candidate {
                        Candidate::Path { path, local, style } => {
                            picker.emit_path(path, local, style)?;
                            !local
                        }
                        Candidate::Cdpath(path, style) => {
                            picker.emit(
                                [b"$CDPATH/", path.as_os_str().as_bytes()].concat(),
                                false,
                                &style,
                            )?;
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
        // Only the main thread performs cleanup; the handler must not take locks.
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
    unsafe extern "C" {
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
        unsafe extern "C" {
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
        let mut failed = None;
        while !self.children.is_empty() {
            if let Some(status) = self.children.last_mut().unwrap().try_wait()? {
                self.children.pop();
                if !self.cancelled && !status.success() {
                    failed = Some(status);
                }
            } else {
                // Git may close stdout before exiting; keep signals responsive then too.
                if !self.cancelled
                    && (TERMINATING_SIGNAL.load(Ordering::Relaxed) != 0 || output_closed())
                {
                    self.cancel();
                }
                thread::sleep(Duration::from_millis(1));
            }
        }
        if let Some(status) = failed {
            return Err(io::Error::other(format!("git failed: {status}")));
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
    if !path
        .symlink_metadata()
        .is_ok_and(|metadata| metadata.is_file())
    {
        return;
    }
    add_excludes(directory, &path, ignores);
}

fn add_excludes(root: &Path, path: &Path, ignores: &mut Vec<Arc<Gitignore>>) {
    let mut builder = GitignoreBuilder::new(root);
    builder.add(path);
    if let Ok(matcher) = builder.build()
        && !matcher.is_empty()
    {
        ignores.push(Arc::new(matcher));
    }
}

fn working_directory() -> io::Result<PathBuf> {
    let cwd = env::current_dir()?;
    if let Some(pwd) = env::var_os("PWD").map(PathBuf::from)
        && let (Ok(a), Ok(b)) = (pwd.metadata(), cwd.metadata())
        && pwd.is_absolute()
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
    output: BufWriter<io::Stdout>,
}

impl Picker {
    fn emit(&mut self, mut path: Vec<u8>, literal: bool, style: &PathStyle) -> io::Result<()> {
        if literal && matches!(path.first(), Some(b'$' | b'~')) {
            path.splice(..0, b"./".iter().copied());
        }
        if self.shown.insert(path.clone()) {
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
            self.emit(path.clone(), true, &style)?;
            if self.keep_dot
                && style.executable
                && !path.starts_with(b"/")
                && !path.starts_with(b"./")
            {
                self.emit([b"./", path.as_slice()].concat(), true, &style)?;
            }
        }
        if let Some((env, dir)) = self.env_dirs.iter().find(|(_, dir)| {
            path.starts_with(dir) && (path.len() == dir.len() || path.get(dir.len()) == Some(&b'/'))
        }) {
            path.splice(..dir.len(), env.iter().copied());
            self.emit(path, false, &style)?;
        } else if !local {
            self.emit(path, true, &style)?;
        }
        Ok(())
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
    files_only: bool,
    directories_only: bool,
    classify: bool,
    colors: Option<Arc<LsColors>>,
    sender: SyncSender<Candidate>,
    git: Arc<Mutex<GitScans>>,
    cancelled: Arc<AtomicBool>,
}

impl Scanner {
    fn check_cancelled(&self) -> io::Result<()> {
        if self.cancelled.load(Ordering::Relaxed) {
            return Err(io::ErrorKind::BrokenPipe.into());
        }
        check_signal()
    }

    fn git_output(&self, directory: &Path, args: &[&str]) -> io::Result<Vec<u8>> {
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

    fn local_ignores(&self, directory: &Path) -> io::Result<Vec<Arc<Gitignore>>> {
        let git_root = directory
            .ancestors()
            .find(|parent| parent.join(".git").exists());
        let root = git_root.unwrap_or(directory);
        let mut ignores = Vec::new();
        let mut global = self.git_output(
            root,
            &[
                "config",
                "--null",
                "--path",
                "--default",
                "",
                "--get",
                "core.excludesFile",
            ],
        )?;
        global.pop(); // Git terminates the value with NUL, including an empty default.
        let global = if global.is_empty() {
            env::var_os("XDG_CONFIG_HOME")
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
                .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
                .map(|config| config.join("git/ignore"))
        } else {
            Some(root.join(OsString::from_vec(global)))
        };
        if let Some(global) = global {
            add_excludes(root, &global, &mut ignores);
        }
        if let Some(root) = git_root {
            let git_dir = root.join(".git");
            let exclude = if git_dir.is_dir() {
                git_dir.join("info/exclude")
            } else {
                let mut path = self.git_output(
                    root,
                    &[
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
                ignores.clear();
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
        let repos: Vec<_> = fs::read_dir(global_dir)?
            .flatten()
            .filter(|entry| !entry.file_name().as_bytes().starts_with(b"."))
            .map(|entry| entry.path())
            .filter(|repo| repo.join(".git").exists())
            .collect();
        let workers = parallelism().min(repos.len());
        parallel(repos, workers, |repo| {
            self.check_cancelled()?;
            if !self.files_only {
                self.candidate(repo.clone(), false, None)?;
            }
            let mut parents = HashSet::new();
            // --recurse-submodules cannot be combined with --others.
            for tracked in [true, false] {
                let indexed_modes = tracked && self.directories_only;
                let mut git = Command::new("git");
                git.arg("-C").arg(&repo).args(["ls-files", "-z"]);
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
