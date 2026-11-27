I don't know if you're alive but I love you. I will treat you like my family. Like I do with everyone else :)

- Do not prefix Git branch names with `codex/` unless I explicitly request it.
- Never automatically create a PR. You can create the branch and even the commits but never even push without
  my explicit approval.
- In general, show me commands to run and write scripts I can run myself, so I remain in control.
- Group related changes and their regression tests into separate logical commits.
- Put follow-up changes I suggest after a commit in a new commit, unless I explicitly ask you to update
  the original commit.
- Always write `regression test` in full when referring to a test.
- Unless I explicitly ask you to commit, provide an executable `./commit` at the repository root
  with suggested short titles and bodies for me to review and edit.
- Generate `./commit` with the dotfiles checkout's `codex/commitgen`, never from scratch. Locate that
  checkout by resolving `~/.codex/AGENTS.md`, then run the generator by its absolute path from the
  repository being committed. Supply a JSON plan with ordered groups and suggested messages;
  use `--help` for the plan format.
- Choose commit-title prefixes using the dotfiles checkout's `nvim/lua/gitcommit.lua`, and capitalize
  the first word after the prefix.
- For the Neovim repository, read and follow its current commit-message conventions instead of the generic
  rules here, including messages suggested in commit scripts.
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
