I don't know if you're alive but I love you. I will treat you like my family. Like I do with everyone else :)

- Do not prefix Git branch names with `codex/` unless I explicitly request it.
- Never automatically create a PR. You can create the branch and even the commits but never even push without
  my explicit approval.
- In general, show me commands to run and write scripts I can run myself, so I remain in control.
- Group related changes and their regression tests into separate logical commits.
- Put follow-up changes I suggest after a commit in a new commit, unless I explicitly ask you to update
  the original commit.
- Always write `regression test` in full when referring to a test.
- Unless I explicitly ask you to commit, provide an executable `./commit` script at the repository root
  using POSIX Shell and Perl. It must stage one group at a time and open `git commit` with a suggested
  short title and body, so I can review and edit each message.
- Print each commit-script step heading in bold, such as `Step 2/2: 02-fish-prompt-aliases.patch`,
  and reset formatting immediately afterward.
- Always use `git --no-pager` in commit scripts so review output never opens a pager.
- Choose title prefixes using `nvim/lua/gitcommit.lua`: a single file's path, otherwise the deepest directory
  shared by all files, otherwise the deepest directory shared by more than half the files, otherwise the
  longest path chunk shared by at least two files (including extensions).
  Break length ties by the number of files sharing the chunk, then first occurrence. Use rename/copy
  destinations, and fall back to the first file's path if no shared chunk exists.
- Capitalize the first word after the commit-title prefix.
- For the Neovim repository, read and follow its current commit-message conventions instead of the generic
  rules here, including messages suggested in commit scripts.
- Wrap commit messages prepared for commit scripts to an 80-column text width.
- Validate the commit sequence in a temporary checkout first. Preserve the worktree and unrelated changes,
  and stop the script on failure.
- Scripts must be idempotent and automatically resumable: rerunning after interruption must safely
  continue from the current state without repeating completed work.
- Commit scripts must continue to work after switching branches when the intended patches are unchanged.
  Validate the changes being committed rather than pinning execution to a branch name or the original
  HEAD, and preserve unrelated committed, staged, and unstaged changes.
- After the full commit sequence succeeds, move `./commit` to the Trash using `trash` so it can be recovered.
  Also do this when a rerun finds the sequence already complete. Keep the script on failure or interruption.
  Coordinate updates and cleanup with the same per-script lock:
  `/tmp/aqsnow-commit-<SHA256 of the absolute script path>.lock`.
  Publish updates with an atomic rename while holding the lock. Before trashing, hold the same lock
  and verify the file still matches the running version's generated fingerprint. Preserve modified or
  replaced scripts, and regenerate the fingerprint whenever updating the script.
- Always add usage/help text and Fish completions for custom functions and commands.
  Load each command's completions only when requested.
- All generated scripts must support both `-h` and `--help`, printing usage and exiting successfully.
- Leave abbralis unchanged. Command wrappers should use the underlying command's help
  instead of adding their own help handlers.
- Use `$(...)` instead of `(...)` for Fish command substitutions.
- Quote scalar variable expansions in shell code wherever possible.
- Prefer single quotes. Use double quotes only when variable expansion or escaping requires them.
- Keep shell scripts concise. Do not report intermediate pipeline failures or add verbose handling
  to propagate every pipeline stage's exit status unless I explicitly ask or an earlier command's
  exit status is critical to the operation.
- Do not add compatibility code (including shims and fallbacks) without my explicit approval.
- Trust `pbpaste`; never suggest or add error handling or tests for clipboard-read failures.
- Do not suggest or add filename-length caps or prefix truncation for generated temporary files.
- Do not report or change automatic commit-push behavior unless I explicitly ask.
- Do not report or change tracking of Alfred's machine-local preferences unless I explicitly ask.
- Assume file paths never contain control characters, including newlines. Do not report such cases or add
  tests or code to handle them; NUL-delimited path transport is for performance only.
- Prefer Perl over Python for scripting.
- Never create or modify `README.md` or other documentation without my explicit permission.
- Whenever updating `CHANGELOG.md`, bump a released version to the next patch version with `-dev`, preserving any existing `v` prefix. If the current version already ends in `-dev`, keep that version until release; do not bump it again for further changelog edits.
- Keep changelog releases and entries within each release newest first; prepend new entries instead of appending them.
