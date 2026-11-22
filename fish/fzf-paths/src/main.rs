use ignore::gitignore::Gitignore;
use ignore::Match;
use std::collections::{HashSet, VecDeque};
use std::env;
use std::ffi::{c_char, c_int, CString, OsStr, OsString};
use std::fs::{self, Metadata};
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::os::unix::{ffi::OsStrExt, ffi::OsStringExt, fs::MetadataExt};
use std::path::{Component, Path, PathBuf};
use std::process::{self, Command, Stdio};
use std::rc::Rc;

extern "C" {
    fn access(path: *const c_char, mode: c_int) -> c_int;
}

fn print_help(name: &str) {
    println!(
        "\
Generate path candidates for fzf from local files and Git repositories.

usage: {name} [--keep-dot] <DIR> <GLOBAL_DIR> <TYPE> [<ENV> <DIR>]...

Scan <DIR> in breadth-first order and emit local paths first, streaming them
as they are found. After 1,000 unique local results (or when the local scan
finishes), scan Git repositories directly under <GLOBAL_DIR> for tracked files
and their parent directories. Then resume any remaining local paths.

The local scan shows shallow paths before deeper paths. Global tracked paths
are streamed directly in Git's order, with their parent directories added as
needed. The 1,000-result limit counts output paths, including extra ./ forms
from --keep-dot; it limits results, not elapsed time.
fzf may reorder matches when sorting is enabled.

The local scan respects .gitignore files, including nested rules and negations.
Starting inside an ignored directory makes that directory searchable: ignore
rules above the ignored directory are bypassed, while rules inside still apply.
Directories named .git and node_modules are skipped unless they are <DIR> itself.

Options:
  -h, --help  Show this help.
  --keep-dot  Also offer ./ paths for local executable files.

Arguments:
  <DIR>         Directory to search locally. Use . for the current directory.
  <GLOBAL_DIR>  Dir containing additional Git repositories.
                Use an empty string to search only <DIR>.
  <TYPE>        -fd   Files and directories.
                -d    Directories only.
                -fdx  Executable files and searchable directories.
  <ENV> <DIR>
                Repeated <ENV> <DIR> pairs, such as '$dotfiles' /path/to/dotfiles.
                Each env must be unique. The longest matching directory wins.

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
  {name} . \"$nhooyr\" -fd '$dotfiles' \"$dotfiles\" | fzf --read0
  {name} . '' -d | fzf --read0
  {name} --keep-dot . '' -fdx | fzf --read0"
    );
}

fn main() {
    let mut arguments = env::args_os();
    let invoked = arguments.next().unwrap_or_default();
    let name = Path::new(&invoked)
        .file_name()
        .unwrap_or(&invoked)
        .to_string_lossy();
    let args: Vec<_> = arguments.collect();
    let (keep_dot, args) = if args.first().is_some_and(|arg| arg == "--keep-dot") {
        (true, &args[1..])
    } else {
        (false, args.as_slice())
    };
    let help = args.len() == 1 && (args[0] == "--help" || args[0] == "-h");
    if help {
        print_help(&name);
        return;
    }
    if args.len() < 3 || (args.len() - 3) % 2 != 0 {
        eprintln!("usage: {name} [--keep-dot] <DIR> <GLOBAL_DIR> <TYPE> [<ENV> <DIR>]...");
        process::exit(1);
    }
    if let Err(error) = run(args, keep_dot) {
        if error.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("{name}: {error}");
            process::exit(1);
        }
    }
}

fn run(args: &[OsString], keep_dot: bool) -> io::Result<()> {
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
        cwd: working_directory()?,
        directories_only: args[2] == "-d",
        executable_only: args[2] == "-fdx",
        keep_dot,
        env_dirs,
        shown: HashSet::new(),
        global_dir: Some(PathBuf::from(&args[1])),
        output: BufWriter::new(io::stdout()),
    };
    picker.walk(PathBuf::from(&args[0]))?;
    picker.repositories()
}

fn ignored(path: &Path, directory: bool, ignores: &[Rc<Gitignore>]) -> bool {
    for matcher in ignores.iter().rev() {
        match matcher.matched(path, directory) {
            Match::Ignore(_) => return true,
            Match::Whitelist(_) => return false,
            Match::None => {}
        }
    }
    false
}

fn add_ignore_file(directory: &Path, ignores: &mut Vec<Rc<Gitignore>>) {
    let (matcher, _) = Gitignore::new(directory.join(".gitignore"));
    if !matcher.is_empty() {
        ignores.push(Rc::new(matcher));
    }
}

fn local_ignores(directory: &Path) -> Vec<Rc<Gitignore>> {
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

struct Picker {
    cwd: PathBuf,
    directories_only: bool,
    executable_only: bool,
    keep_dot: bool,
    env_dirs: Vec<(Vec<u8>, Vec<u8>)>,
    shown: HashSet<Vec<u8>>,
    global_dir: Option<PathBuf>,
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
            if self.shown.len() == 1000 {
                // Pause local output for global results, then resume here.
                self.output.flush()?;
                self.repositories()?;
            }
        }
        Ok(())
    }

    fn candidate(
        &mut self,
        path: PathBuf,
        local: bool,
        metadata: Option<Metadata>,
    ) -> io::Result<()> {
        let Some(metadata) = metadata.or_else(|| path.metadata().ok()) else {
            return Ok(());
        };
        if !metadata.is_dir() && (self.directories_only || !metadata.is_file()) {
            return Ok(());
        }
        if self.executable_only {
            let name = CString::new(path.as_os_str().as_bytes()).unwrap();
            if unsafe { access(name.as_ptr(), 1) } != 0 {
                return Ok(());
            }
        }
        self.emit_path(
            path,
            local,
            metadata.is_file() && metadata.mode() & 0o111 != 0,
        )
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
        if local {
            self.output.flush()?;
        }
        Ok(())
    }

    fn walk(&mut self, path: PathBuf) -> io::Result<()> {
        let Ok(metadata) = path.metadata() else {
            return Ok(());
        };
        if !metadata.is_dir() {
            return Ok(());
        }
        let absolute = normalize(&self.cwd.join(&path));
        let ignores = local_ignores(&absolute);
        let ancestors = vec![(metadata.dev(), metadata.ino())];
        let mut directories = VecDeque::from([(path, absolute, ancestors, ignores)]);
        while let Some((path, absolute, ancestors, ignores)) = directories.pop_front() {
            let Ok(entries) = fs::read_dir(path) else {
                continue;
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
                if regular_file && !self.keep_dot && !self.executable_only {
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
                    directories.push_back((path, absolute, ancestors, ignores));
                }
            }
        }
        Ok(())
    }

    fn repositories(&mut self) -> io::Result<()> {
        // Take this before emitting so global output cannot restart the scan.
        let Some(global_dir) = self.global_dir.take() else {
            return Ok(());
        };
        if global_dir.as_os_str().is_empty() || !global_dir.is_dir() {
            return Ok(());
        }
        let global_dir = normalize(&self.cwd.join(global_dir));
        let repos: Vec<_> = fs::read_dir(global_dir)?
            .flatten()
            .filter(|entry| !entry.file_name().as_bytes().starts_with(b"."))
            .map(|entry| entry.path())
            .filter(|repo| repo.join(".git").exists())
            .collect();
        for repo in &repos {
            self.candidate(repo.clone(), false, None)?;
            self.output.flush()?;
        }
        let jobs = std::thread::available_parallelism().map_or(1, |count| count.get());
        for repos in repos.chunks(jobs) {
            let scans = repos
                .iter()
                .map(|repo| {
                    let mut git = Command::new("git");
                    git.arg("-C")
                        .arg(repo)
                        .args(["ls-files", "--recurse-submodules", "-z"]);
                    if self.directories_only {
                        git.arg("--format=%(objectmode) %(path)");
                    }
                    git.stdin(Stdio::null()).stdout(Stdio::piped()).spawn()
                })
                .collect::<io::Result<Vec<_>>>()?;
            for (repo, mut scan) in repos.iter().zip(scans) {
                let mut parents = HashSet::new();
                for file in BufReader::new(scan.stdout.take().unwrap()).split(0) {
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
                    self.output.flush()?;
                }
                scan.wait()?;
            }
        }
        Ok(())
    }
}
