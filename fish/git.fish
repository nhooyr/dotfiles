abbrali g git
abbrali gsh git show
abbrali ga git add -A
abbrali gap git add -p
abbrali gp git push
abbrali gpf git push --force-with-lease
abbrali gcm git commit
abbrali gcp gcm "&&" gp
abbrali gacp ga "&&" gcp
abbrali gcma git commit --amend
abbrali gcpa gcma "&&" gp
abbrali gcmf git commit --fixup
abbrali grb git rebase
abbrali grbi git rebase -i
abbrali grbc git rebase --continue
abbrali grba git rebase --abort
abbrali gs git status
abbrali gd git diff
abbrali grt git reset
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
abbrali glsf git ls-files
abbrali gcl git clone
abbrali gpl git pull
abbrali gf git fetch
abbrali gfa git fetch --all
abbrali gro git remote -v
abbrali gb git branch -vv
abbrali gba git branch -avv
abbrali gbr git branch -rvv
abbrali gst git stash push -u
abbrali gsta git stash apply
abbrali gsts git stash show
abbrali gstp git stash pop
abbrali gstl git stash list
abbrali gstd git stash drop
abbrali gds git diff stash@{0}
abbrali gbl git blame
abbrali gshort git rev-parse --short
abbrali gch git checkout
function gcd
    set -l git_root "$(git rev-parse --show-toplevel)"; or return 1
    cd "$git_root"
end
function scd
    set -l super_root "$(git rev-parse --show-superproject-working-tree)"; or return 1
    # Git prints nothing, and still succeeds, outside a submodule.
    if test -z "$super_root"
        echo "scd: not inside a submodule" >&2
        return 1
    end
    cd "$super_root"
end
function gg --wraps 'git grep'
    git grep -iIE --recurse-submodules $argv
end
function gapply --wraps 'git apply'
    pbpaste | perl -pe 's/\n?\z/\n/' | git apply $argv
end
