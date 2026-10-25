fish_add_path --path /opt/homebrew/share/git-core/contrib/diff-highlight
abbrali g git
abbrali gsh git show
abbrali ga git add -A
abbrali gap git add -p
abbrali gp git push
abbrali gpf git push --force-with-lease
abbrali gcm git commit
alias gcp='gcm && gp'
alias gacp='ga && gcp'
abbrali gcma git commit --amend
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
abbrali grm git rm
abbrali grmr git rm -r
abbrali grmf git rm -rf
abbrali grmc git rm --cached
abbrali grmcr git rm --cached -r
abbrali gl git log
abbrali glsf git ls-files
abbrali gcl git clone
abbrali gpl git pull
abbrali gro git remote -v
abbrali gb git branch -vv
abbrali gba git branch -avv
abbrali gbr git branch -rvv
abbrali gst git stash push -u
abbrali gsts git stash show
abbrali gstsp git stash show -p
abbrali gstp git stash pop
abbrali gstl git stash list
abbrali gstd git stash drop
abbrali gbl git blame
function gcd
    set -l git_root "$(git rev-parse --show-toplevel)"; or return 1
    cd "$git_root"
end
abbrali gg git grep -iIE
