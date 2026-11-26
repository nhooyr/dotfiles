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
abbrali gps git push
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
abbrali grb git_rebase
abbrali grbi git_rebase -i
abbrali grbr git_rebase -i --root
abbrali grbc git_rebase --continue
abbrali grba git_rebase --abort
abbrali gs git status
abbrali gd git diff --patch-with-stat
abbrali grt git reset
abbrali grtp git reset -p
abbrali grth git reset --hard
abbrali gdc git diff --patch-with-stat --cached
abbr -a --command git diffc diff --patch-with-stat --cached
abbrali gdcs git diff --cached --patch-with-stat
abbrali grm git rm
abbrali grmr git rm -r
abbrali grmf git rm -f
abbrali grmrf git rm -rf
abbrali grmc git rm --cached
abbrali grmcr git rm --cached -r
abbrali grmcrf git rm --cached -rf
abbrali gl git_log
abbrali glp git_log -p
abbrali glo git_log --oneline
abbrali glol git_log --oneline \| wc -l
abbrali glss git_log --show-signature
abbrali gls git ls-files
abbrali gcl git clone
function gcld
    git clone $argv; and cd "$(path basename -- $argv[-1])"
end
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

abbrali .co 'gcd && ./commit'
abbrali .fmt 'gcd && ./ci/fmt.sh'
abbrali .lint 'gcd && ./ci/lint.sh'
abbrali .test 'gcd && ./ci/test.sh'
abbrali .run 'gcd && ./ci/run.sh'
abbrali app git apply

alias gh='NO_COLOR=1 command gh'
abbrali ghgp ghg -p
abbrali ghf 'gh repo fork --remote; and gh repo set-default upstream'
abbrali ghch gh pr checkout
abbrali ghop gh pr view --web
abbrali ghep gh pr create --web --fill-verbose
abbrali ghl gh repo list --visibility public --source --no-archived --json url --jq '.[].url'

abbrali tabt column -ts '\t'
abbrali dt dirt
abbrali dtb dirtb
abbrali dtc dirtci
abbrali dtci dirtci

abbrali imps "ga; and gcm -em 'imps'"

abbrali glfs git lfs
abbrali gfr git filter-repo --invert-paths --path

abbrali gsub git submodule
abbrali gsubu git submodule update --init --recursive
abbrali grl git reflog
abbrali gcp git cherry-pick
abbrali gmb git merge-base HEAD origin
