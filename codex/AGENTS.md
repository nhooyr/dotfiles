- Do not prefix Git branch names with `codex/` unless I explicitly request it.
- Never automatically create a PR. You can create the branch and even the commits but never even push without
  my explicit approval.
- Group related changes and their regression tests into separate logical commits.
- Always write `regression test` in full when referring to a test.
- Unless I explicitly ask you to commit, provide a Fish script that stages one group at a time and opens
  `git commit` with a suggested short title and body, so I can review and edit each message.
- Print each commit-script step heading in bold, such as `Step 2/2: 02-fish-prompt-aliases.patch`,
  and reset formatting immediately afterward.
- Choose title prefixes using `nvim/lua/gitcommit.lua`: a single file's path, otherwise the deepest directory
  shared by all files, otherwise the deepest directory shared by more than half the files, otherwise the
  longest path chunk shared by at least two files (including extensions).
  Break length ties by the number of files sharing the chunk, then first occurrence. Use rename/copy
  destinations, and fall back to the first file's path if no shared chunk exists.
- Validate the commit sequence in a temporary checkout first. Preserve the worktree and unrelated changes,
  and stop the script on failure.
- Scripts must be idempotent and automatically resumable: rerunning after success must be a no-op, and rerunning after interruption must safely continue from the current state without repeating completed work.
- Use `$(...)` instead of `(...)` for Fish command substitutions.
- Quote scalar variable expansions in shell code wherever possible.
- Prefer single quotes. Use double quotes only when variable expansion or escaping requires them.
- Do not add compatibility code (including shims and fallbacks) without my explicit approval.
- Do not report or change automatic commit-push behavior unless I explicitly ask.
- Do not report or change tracking of Alfred's machine-local preferences unless I explicitly ask.
- Assume file paths never contain control characters, including newlines. Do not report such cases or add
  tests or code to handle them; NUL-delimited path transport is for performance only.
- Prefer Perl over Python for scripting.
- Never create or modify `README.md` or other documentation without my explicit permission.
