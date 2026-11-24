- Do not prefix Git branch names with `codex/` unless I explicitly request it.
- Never automatically create a PR. You can create the branch and even the commits but never even push without
  my explicit approval.
- Group related changes and their regression tests into separate logical commits.
- Unless I explicitly ask you to commit, provide a Fish script that stages one group at a time and opens
  `git commit` with a suggested short title and body, so I can review and edit each message.
- Choose title prefixes using `nvim/lua/gitcommit.lua`: a single file's path, otherwise the deepest shared
  directory, otherwise the most common alphanumeric path word appearing in at least two files (excluding
  file extensions; first occurrence wins ties). Use rename/copy destinations, and omit the prefix if none applies.
- Validate the commit sequence in a temporary checkout first. Preserve the worktree and unrelated changes,
  and stop the script on failure.
- Scripts must be idempotent and automatically resumable: rerunning after success must be a no-op, and rerunning after interruption must safely continue from the current state without repeating completed work.
- Use `$(...)` instead of `(...)` for Fish command substitutions.
- Quote scalar variable expansions in shell code wherever possible.
- Prefer single quotes. Use double quotes only when variable expansion or escaping requires them.
- Do not add compatibility code (including shims and fallbacks) without my explicit approval.
- Do not report or change automatic commit-push behavior unless I explicitly ask.
- Do not report or change tracking of Alfred's machine-local preferences unless I explicitly ask.
- Assume file paths never contain newlines. Do not report, fix, or test newline-containing paths; NUL-delimited path transport is for performance only.
- Prefer Perl over Python for scripting.
- Never create or modify `README.md` or other documentation without my explicit permission.
