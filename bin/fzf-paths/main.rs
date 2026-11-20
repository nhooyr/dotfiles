use std::collections::HashSet;
use std::env;
use std::ffi::{c_char, c_int, CString, OsString};
use std::fs::{self, Metadata};
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::os::unix::{ffi::OsStrExt, ffi::OsStringExt, fs::MetadataExt};
use std::path::{Component, Path, PathBuf};
use std::process::{self, Command, Stdio};

extern "C" {
    fn access(path: *const c_char, mode: c_int) -> c_int;
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
    aliases: Vec<(Vec<u8>, Vec<u8>)>,
    seen: HashSet<(bool, PathBuf)>,
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
            self.output.flush()?;
        }
        Ok(())
    }

    fn candidate(
        &mut self,
        path: PathBuf,
        local: bool,
        metadata: Option<Metadata>,
    ) -> io::Result<()> {
        if !self.seen.insert((local, self.cwd.join(&path))) {
            return Ok(());
        }
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
        let mut path = path.into_os_string().into_vec();
        if !self.keep_dot && path.starts_with(b"./") {
            path.drain(..2);
        }
        if local {
            self.emit(path.clone(), true)?;
        }
        let cwd_prefix = [self.cwd.as_os_str().as_bytes(), b"/"].concat();
        if self.keep_dot && path.starts_with(&cwd_prefix) {
            path.splice(..cwd_prefix.len(), b"./".iter().copied());
        } else if let Some((label, base)) = self.aliases.iter().find(|(_, base)| {
            path.starts_with(base)
                && (path.len() == base.len() || path.get(base.len()) == Some(&b'/'))
        }) {
            path.splice(..base.len(), label.iter().copied());
            return self.emit(path, false);
        } else if self.aliases.is_empty() && path.starts_with(&cwd_prefix) {
            path.drain(..cwd_prefix.len());
        }
        self.emit(path, true)
    }

    fn walk(
        &mut self,
        path: PathBuf,
        root: bool,
        ancestors: &mut HashSet<(u64, u64)>,
    ) -> io::Result<()> {
        let Ok(metadata) = path.metadata() else {
            return Ok(());
        };
        if !root {
            self.candidate(path.clone(), true, Some(metadata.clone()))?;
        }
        let identity = (metadata.dev(), metadata.ino());
        if metadata.is_dir() && ancestors.insert(identity) {
            if let Ok(entries) = fs::read_dir(path) {
                for entry in entries.flatten() {
                    if entry.file_name() != ".git" && entry.file_name() != "node_modules" {
                        self.walk(entry.path(), false, ancestors)?;
                    }
                }
            }
            ancestors.remove(&identity);
        }
        Ok(())
    }

    fn repositories(&mut self, owner: &Path) -> io::Result<()> {
        if owner.as_os_str().is_empty() || !owner.is_dir() {
            return Ok(());
        }
        let owner = normalize(&self.cwd.join(owner));
        let mut repos: Vec<_> = fs::read_dir(owner)?
            .flatten()
            .filter(|entry| !entry.file_name().as_bytes().starts_with(b"."))
            .map(|entry| entry.path())
            .collect();
        repos.sort();
        for repo in repos {
            if !repo.join(".git").exists() {
                continue;
            }
            self.candidate(repo.clone(), false, None)?;
            let mut git = Command::new("git")
                .arg("-C")
                .arg(&repo)
                .args(["ls-files", "--recurse-submodules", "-z"])
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .spawn()?;
            for file in BufReader::new(git.stdout.take().unwrap()).split(0) {
                let file = PathBuf::from(OsString::from_vec(file?));
                for relative in file.ancestors().filter(|p| !p.as_os_str().is_empty()) {
                    self.candidate(repo.join(relative), false, None)?;
                }
            }
            git.wait()?;
        }
        Ok(())
    }
}

fn run() -> io::Result<()> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() < 4 || (args.len() - 4) % 2 != 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "usage: fzf-paths DIR OWNER TYPE KEEP_DOT [LABEL DIRECTORY]...",
        ));
    }
    let mut aliases: Vec<_> = args[4..]
        .chunks_exact(2)
        .map(|pair| (pair[0].as_bytes().to_vec(), pair[1].as_bytes().to_vec()))
        .collect();
    aliases.sort_by_key(|(_, base)| std::cmp::Reverse(base.len()));
    let mut picker = Picker {
        cwd: working_directory()?,
        directories_only: args[2] == "-d",
        executable_only: args[2] == "-fdx",
        keep_dot: args[3] == "true",
        aliases,
        seen: HashSet::new(),
        shown: HashSet::new(),
        output: BufWriter::new(io::stdout()),
    };
    picker.walk(PathBuf::from(&args[0]), true, &mut HashSet::new())?;
    picker.repositories(Path::new(&args[1]))
}

fn main() {
    if let Err(error) = run() {
        if error.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("fzf-paths: {error}");
            process::exit(1);
        }
    }
}
