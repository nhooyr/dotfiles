function git_prompt
    # Inspect the worktree when browsing its Git metadata.
    if set -l worktree "$(string replace -r -- '/\.git(/.*)?$' / "$PWD")"
        cd -- "$worktree"; or return
    end
    fish_git_prompt
end

set -g __fish_git_prompt_showdirtystate 1
set -g __fish_git_prompt_showuntrackedfiles 1
set -g __fish_git_prompt_showupstream informative
set -g __fish_git_prompt_showstashstate 1
set -g __fish_git_prompt_color_branch --underline
set -g __fish_git_prompt_color_flags cyan
set -g __fish_git_prompt_color_upstream cyan
set -g __fish_git_prompt_color_merging --italics
