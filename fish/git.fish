function git
    command git $argv
    set -l code $status
    # Ignore SIGPIPE. See intro commit.
    test "$code" -eq 141; and return 0
    return "$code"
end
abbrali g git
abbrali grv 'git rev-parse --abbrev-ref HEAD | pbc'
abbrali grvs 'git rev-parse --short HEAD | pbc'
abbrali gsh git show
abbrali gshs git show --stat
abbrali gsht 'git show -s --format=%s | pbc'
abbrali gshb 'git show -s --format=%b | pbc'
abbrali ga git add -A
abbrali gap git add -p
abbrali gai git add -i
abbrali gp git push
abbrali gpf git push --force-with-lease
abbrali gcm git commit
abbr -a gacm 'ga; and gcm'
function gacm
    ga; and gcm $argv
end
abbr -a gacmp 'ga; and gcm; and gp'
function gacmp
    ga; and gcm $argv; and gp
end
abbrali gcma git commit --amend
abbr -a gacma 'ga; and gcma'
abbr -a fcm 'ga; and gcma'
function gacma
    ga; and gcma $argv
end
abbrali gcmf git commit --fixup
abbrali grb git rebase
abbrali grbi git rebase -i
abbrali grbr git rebase -i --root
abbrali grbc git rebase --continue
abbrali grba git rebase --abort
abbrali gs git status
abbrali gd git diff
abbrali grt git reset
abbrali grtp git reset -p
abbrali grth git reset --hard
abbrali gdc git diff --cached
abbrali gdcs git diff --cached --stat
abbrali grm git rm
abbrali grmr git rm -r
abbrali grmf git rm -f
abbrali grmrf git rm -rf
abbrali grmc git rm --cached
abbrali grmcr git rm --cached -r
abbrali grmcrf git rm --cached -rf
abbrali gl git log
abbrali glp git log -p
abbrali glss git log --show-signature
abbrali gls git ls-files
abbrali gcl git clone
abbrali gpl git pull
abbrali gf git fetch
abbrali gfa git fetch --all
abbrali gfp git fetch --prune-tags
abbrali gro git remote -v
abbrali groa git remote add
abbrali gros git remote set-url
abbrali grou git remote get-url
abbrali gror git remote rename
abbrali grod git remote remove
abbrali gb git branch -vv
abbrali gbm git branch -vvm
abbrali gbu git branch -vvu
abbrali gba git branch -vva
abbrali gbr git branch -vvr
function gbp
    argparse --max-args 0 f/force -- $argv; or return
    set -l delete_flag -d
    set -q _flag_force; and set delete_flag -D
    for branch in main master
        if git show-ref --verify --quiet "refs/heads/$branch"
            if test "$(git symbolic-ref --quiet HEAD)" != "refs/heads/$branch"
                git switch "$branch"; or return
            end
            break
        end
    end
    git fetch --prune
    and git branch -vv | awk '/: gone]/{print $1}' | xargs -r git branch $delete_flag
end
abbrali gst git stash push -u
abbrali gstk git stash push -u --keep-index
abbrali gsta git stash apply
abbrali gsts git stash show
abbrali gstp git stash pop
abbrali gstl git stash list
abbrali gstd git diff stash@{0}
abbrali gstdd git stash drop
abbrali gbl git blame
abbrali gch git checkout
abbrali gchb git checkout -b
abbrali gt git tag
abbrali grs git restore
abbrali grsp git restore -p
abbrali grss git restore -S
abbrali grsw git restore -W
abbrali grssw git restore -SW
abbrali gcln git clean -ndX
abbrali gclx git clean -fdX

function gcd
    set -l git_root "$(git rev-parse --show-toplevel)"; or return 1
    cd -- "$git_root"
end
function scd
    set -l super_root "$(git rev-parse --show-superproject-working-tree)"; or return 1
    # Git prints nothing, and still succeeds, outside a submodule.
    if test -z "$super_root"
        printf '%s: not inside a submodule\n' "$(status function)" >&2
        return 1
    end
    cd -- "$super_root"
end
function gg --wraps 'git grep -IE --recurse-submodules'
    set -l ignore_case $(__grep_smart_case $argv); or return
    git grep -IE --recurse-submodules $ignore_case $argv
end
abbrali ggf gg -F
abbrali app git apply
function papp --wraps 'git apply' --description 'git apply from clipboard'
    pbpaste | perl -pe 's/\n?\z/\n/' | git apply $argv
end

alias gh='NO_COLOR=1 command gh'
abbrali ghf 'gh repo fork --remote; and gh repo set-default upstream'
abbrali ghch gh pr checkout
abbrali ghop gh pr view --web
abbrali ghep gh pr create --web --fill-verbose
abbrali ghl gh repo list --visibility public --source --no-archived --json url --jq '.[].url'

abbrali tabt column -ts '\t'
abbrali dt dirt
alias dirt='_dirt | tabt'
function _dirt --description 'List repos with dirt'
    for gitdir in ~/code/*/.git ~/code/*/*/.git
        set -l dir "$(path dirname -- "$gitdir")"
        if contains -- "$dir" $dirt_ignore
            continue
        end
        set -l prompt "$(cdc "$dir" fish_git_prompt '%s')"; or continue
        set -l flags "$(string split --max 1 --fields 2 -- ' ' "$prompt")"
        if test -n "$flags"
            set -l name "$(string replace ~/code/ '' "$dir")"
            printf '%s\t%s\n' "$name" "$flags"
        end
    end
end

abbrali imps "ga; and gcm -em 'imps'"

abbrali glfs git lfs
abbrali gfr git filter-repo --invert-paths --path
function gbins --description 'Print staged or committed binary files'
    set -l empty_tree "$(git hash-object -t tree /dev/null)"; or return
    git diff --numstat --cached "$empty_tree" | awk -F '\t' '$1 == "-" {print $3}'
end

abbrali gsub git submodule
abbrali gsubu git submodule update --init --recursive
abbrali grl git reflog
