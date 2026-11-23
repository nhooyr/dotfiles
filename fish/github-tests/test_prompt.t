use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $dotfiles = absolute_path("$FindBin::Bin/../..");
my $fish = which('fish');
my $git = which('git');
my $source = "$dotfiles/fish/functions/aqsnow_vcs_prompt_update.fish";

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir('fish-prompt-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    $self->{root} = absolute_path($self->{temporary});
    $self->{repo} = "$self->{root}/repo";
    $self->{other} = "$self->{root}/other";
    $self->{plain} = "$self->{root}/plain";
    make_path($self->{plain});
    $self->{env} = {%ENV, GIT_CONFIG_GLOBAL => '/dev/null', GIT_CONFIG_NOSYSTEM => 1,
        GIT_AUTHOR_NAME => 'Prompt Test', GIT_AUTHOR_EMAIL => 'test@example.invalid',
        GIT_COMMITTER_NAME => 'Prompt Test', GIT_COMMITTER_EMAIL => 'test@example.invalid',
        XDG_CONFIG_HOME => "$self->{root}/config", XDG_DATA_HOME => "$self->{root}/data",
        TEST_SOURCE => $source, TEST_DOTFILES => $dotfiles, TEST_REPO => $self->{repo},
        TEST_OTHER => $self->{other}, TEST_PLAIN => $self->{plain}, TEST_ROOT => $self->{root}};
    for my $entry ([$self->{repo}, 'main'], [$self->{other}, 'other-branch']) {
        run_command([$git, 'init', '--quiet', '--initial-branch', $entry->[1], $entry->[0]], {env => $self->{env}, check => 1});
    }
}

sub shell {
    my ($self, $body, $cwd) = @_;
    my $script = <<'FISH';
set -g dotfiles "$TEST_DOTFILES"
source "$TEST_SOURCE"
function aqsnow_init_rendezvous
    set -g __aqsnow_rendezvous_dir "$TEST_ROOT/rendezvous"
    command mkdir -p -- "$__aqsnow_rendezvous_dir"
end
FISH
    return run_command([$fish, '--no-config', '-c', $script . $body],
        {cwd => $cwd // $self->{repo}, env => $self->{env}, timeout => 10});
}

sub output {
    my ($result) = @_;
    is($result->{returncode}, 0, $result->{stderr});
    is($result->{stderr}, '', 'no diagnostics');
    return $result->{stdout};
}

sub stage_completion {
    my ($value, $status) = @_;
    return 'set -g __aqsnow_vcs_request_directory "$PWD"' . "\n"
        . 'set -g __aqsnow_vcs_request_root "$__aqsnow_vcs_root"' . "\n"
        . 'set -g __aqsnow_vcs_request_generation "$__aqsnow_vcs_generation"' . "\n"
        . 'set -g __aqsnow_vcs_file "$TEST_ROOT/result"' . "\n"
        . 'printf %s ' . shell_quote($value) . ' > "$__aqsnow_vcs_file"' . "\n"
        . 'printf %s ' . shell_quote($status) . ' > "$__aqsnow_vcs_file.status"' . "\n";
}

sub fake_completion {
    return stage_completion(@_) . "aqsnow_vcs_prompt_done\n";
}

sub wait_for_refresh {
    return <<'FISH';
for i in $(seq 1 100)
    set -q __aqsnow_vcs_pending; or break
    command sleep 0.03
end
set -q __aqsnow_vcs_pending; and exit 2
FISH
}

sub fake_dotfiles {
    my ($self, $prompt) = @_;
    my $fixture = "$self->{root}/dotfiles";
    make_path("$fixture/fish");
    write_file("$fixture/fish/prompt.fish", $prompt);
    symlink "$dotfiles/fish/git_prompt_worker.pl", "$fixture/fish/git_prompt_worker.pl"
        or die "link prompt supervisor: $!";
    $self->{env}{TEST_DOTFILES} = $fixture;
    return $fixture;
}

sub wait_for_marker {
    my ($marker) = @_;
    return <<"FISH";
for i in \$(seq 1 150)
    test -f "\$TEST_ROOT/$marker"; and break
    command sleep 0.02
end
test -f "\$TEST_ROOT/$marker"; or exit 3
FISH
}

sub wait_for_retired_process {
    return <<'FISH';
for i in $(seq 1 150)
    command kill -0 "$retired_process" 2>/dev/null; or break
    command sleep 0.02
end
command kill -0 "$retired_process" 2>/dev/null; and exit 4
FISH
}

sub cached_first_render {
    my ($self) = @_;
    my $cached = " (\e[4mmain\e[0m +*)";
    write_file("$self->{repo}/.fish_git_prompt", $cached);
    make_path("$self->{root}/bin");
    write_file("$self->{root}/bin/git", "#!/bin/sh\nprintf called >> \"\$TEST_ROOT/git-called\"\nexit 99\n");
    chmod 0755, "$self->{root}/bin/git";
    $self->{env}{PATH} = "$self->{root}/bin:$ENV{PATH}";
    for (1 .. 2) {
        my $result = shell($self, <<'FISH');
set -g __aqsnow_vcs_pending 1
aqsnow_vcs_prompt_update
printf '%s\n%s\n' "$__aqsnow_vcs_prompt" "$AQSNOW_FISH_GIT_PROMPT"
FISH
        is(output($result), "$cached\n (main +*)\n", 'a fresh Fish session immediately restores styled/plain cache');
    }
    ok(!-e "$self->{root}/git-called", 'restoring cache runs no Git command');
}

sub head_identity_without_cache {
    my ($self) = @_;
    my $result = shell($self, <<'FISH');
set -g __aqsnow_vcs_pending 1
aqsnow_vcs_prompt_update
printf '%s\n%s\n' "$__aqsnow_vcs_prompt" "$AQSNOW_FISH_GIT_PROMPT"
FISH
    is(output($result), " (main)\n (main)\n", 'unborn HEAD supplies identity immediately');
    run_command([$git, '-C', $self->{repo}, 'commit', '--quiet', '--allow-empty', '-m', 'initial'], {env => $self->{env}, check => 1});
    my $head = trim(run_command([$git, '-C', $self->{repo}, 'rev-parse', '--short=7', 'HEAD'], {env => $self->{env}, check => 1})->{stdout});
    run_command([$git, '-C', $self->{repo}, 'checkout', '--quiet', '--detach'], {env => $self->{env}, check => 1});
    $result = shell($self, <<'FISH');
set -g __aqsnow_vcs_pending 1
aqsnow_vcs_prompt_update
printf '%s\n' "$__aqsnow_vcs_prompt"
FISH
    is(output($result), " ($head)\n", 'detached HEAD supplies identity without full status');
}

sub subdirectories_and_metadata {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (cached-main)');
    make_path("$self->{repo}/nested/deep");
    for my $directory ("$self->{repo}/nested/deep", "$self->{repo}/.git/objects") {
        my $result = shell($self, <<'FISH', $directory);
set -g __aqsnow_vcs_pending 1
aqsnow_vcs_prompt_update
printf '%s\n%s\n' "$__aqsnow_vcs_root" "$__aqsnow_vcs_prompt"
FISH
        is(output($result), "$self->{repo}\n (cached-main)\n", 'subdirectories share the worktree cache');
    }
}

sub linked_worktrees {
    my ($self) = @_;
    run_command([$git, '-C', $self->{repo}, 'commit', '--quiet', '--allow-empty', '-m', 'initial'], {env => $self->{env}, check => 1});
    my $linked = "$self->{root}/linked worktree";
    run_command([$git, '-C', $self->{repo}, 'worktree', 'add', '--quiet', '-b', 'linked-branch', $linked], {env => $self->{env}, check => 1});
    write_file("$self->{repo}/.fish_git_prompt", ' (main-only)');
    my $result = shell($self, <<'FISH', $linked);
set -g __aqsnow_vcs_pending 1
aqsnow_vcs_prompt_update
printf '%s\n%s\n' "$__aqsnow_vcs_root" "$__aqsnow_vcs_prompt"
FISH
    is(output($result), "$linked\n (linked-branch)\n", 'linked worktree reads its own HEAD');
    write_file("$linked/.fish_git_prompt", ' (linked-cached)');
    $result = shell($self, <<'FISH', $linked);
set -g __aqsnow_vcs_pending 1
aqsnow_vcs_prompt_update
printf '%s\n' "$__aqsnow_vcs_prompt"
FISH
    is(output($result), " (linked-cached)\n", 'linked worktree has a separate persistent cache');
}

sub directory_switch_while_pending {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (main-cached)');
    write_file("$self->{other}/.fish_git_prompt", ' (other-cached)');
    my $result = shell($self, <<'FISH');
set -g __aqsnow_vcs_pending 1
aqsnow_vcs_prompt_update
set -g __aqsnow_vcs_request_directory "$PWD"
set -g __aqsnow_vcs_request_root "$__aqsnow_vcs_root"
set -g __aqsnow_vcs_request_generation "$__aqsnow_vcs_generation"
set -g __aqsnow_vcs_file "$TEST_ROOT/result"
cd -- "$TEST_OTHER"
aqsnow_vcs_prompt_update
printf '%s\n' "$__aqsnow_vcs_prompt"
printf %s ' (main-refreshed)' > "$__aqsnow_vcs_file"
printf 0 > "$__aqsnow_vcs_file.status"
aqsnow_vcs_prompt_done
printf '%s\n%s\n' "$__aqsnow_vcs_prompt" "$AQSNOW_FISH_GIT_PROMPT"
cd -- "$TEST_PLAIN"
aqsnow_vcs_prompt_restore
printf '<%s>\n<%s>\n' "$__aqsnow_vcs_prompt" "$AQSNOW_FISH_GIT_PROMPT"
FISH
    is(output($result), " (other-cached)\n (other-cached)\n (other-cached)\n<>\n<>\n", 'pending old repository cannot repaint new repository or non-Git directory');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (main-refreshed)', 'old repository still receives its refreshed cache');
    is(read_file("$self->{other}/.fish_git_prompt"), ' (other-cached)', 'other repository cache is untouched');
}

sub initialized_repository_in_same_directory {
    my ($self) = @_;
    my $result = shell($self, <<'FISH' . wait_for_refresh() . <<'FISH', $self->{plain});
set -g __aqsnow_vcs_pending 1
aqsnow_vcs_prompt_update
printf '<%s>\n' "$AQSNOW_FISH_GIT_PROMPT"
set -e __aqsnow_vcs_pending
command git init --quiet --initial-branch fresh .
aqsnow_vcs_prompt_invalidate
printf '%s\n' "$__aqsnow_vcs_root" "$AQSNOW_FISH_GIT_PROMPT"
aqsnow_vcs_prompt_update
FISH
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
exit 0
FISH
    like(output($result), qr/^<>\n\Q$self->{plain}\E\n \(fresh\)\n \(fresh[^\n]*\)\n$/,
        'git init discovers the new root and keeps an immediate branch while refreshing');
    like(read_file("$self->{plain}/.fish_git_prompt"), qr/\(.*fresh/,
        'new repository receives a persistent cache without changing directory');
}

sub nested_repository_during_refresh {
    my ($self) = @_;
    my $nested = "$self->{repo}/nested";
    make_path($nested);
    write_file("$self->{repo}/.fish_git_prompt", ' (parent-cached)');
    my $result = shell($self, "set -g __aqsnow_vcs_pending 1\naqsnow_vcs_prompt_update\n"
        . stage_completion(' (wrong-parent-result)', '0') . <<'FISH' . wait_for_refresh() . <<'FISH', $nested);
command git init --quiet --initial-branch nested .
# Another process can create the repository before this shell gets a postexec event.
aqsnow_vcs_prompt_done
aqsnow_vcs_prompt_update
printf '%s\n%s\n' "$__aqsnow_vcs_root" "$AQSNOW_FISH_GIT_PROMPT"
FISH
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
exit 0
FISH
    like(output($result), qr/^\Q$nested\E\n \(nested\)\n \(nested[^\n]*\)\n$/,
        'nested git init discards the old request and refreshes its own branch');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (parent-cached)',
        'in-flight result cannot overwrite the parent repository cache');
    like(read_file("$nested/.fish_git_prompt"), qr/\(.*nested/,
        'nested repository receives its own persistent cache');
}

sub removed_repository_during_refresh {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (last-known)');
    my $result = shell($self, "set -g __aqsnow_vcs_pending 1\naqsnow_vcs_prompt_update\n"
        . stage_completion(' (obsolete)', '0') . <<'FISH');
command rm -rf -- .git
aqsnow_vcs_prompt_invalidate
aqsnow_vcs_prompt_done
printf '<%s>\n<%s>\n' "$__aqsnow_vcs_root" "$AQSNOW_FISH_GIT_PROMPT"
FISH
    is(output($result), "<>\n<>\n", 'removing .git clears the branch without changing directory');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (last-known)',
        'removed repository rejects its obsolete in-flight result');
}

sub replaced_repository_during_foreground_command {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (last-known)');
    my $result = shell($self, "set -g __aqsnow_vcs_pending 1\naqsnow_vcs_prompt_update\n"
        . stage_completion(' (obsolete)', '0') . <<'FISH' . wait_for_refresh() . <<'FISH');
aqsnow_vcs_prompt_preexec
command rm -rf -- .git
command git init --quiet --initial-branch replacement .
# Completion can arrive before fish_postexec observes the replacement.
aqsnow_vcs_prompt_done
printf '%s\n' "$(string collect < .fish_git_prompt)"
aqsnow_vcs_prompt_invalidate
aqsnow_vcs_prompt_update
FISH
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
exit 0
FISH
    like(output($result), qr/^ \(last-known\)\n \(replacement[^\n]*\)\n$/,
        'replacement during a foreground command retains the cache until a fresh result');
    like(read_file("$self->{repo}/.fish_git_prompt"), qr/\(.*replacement/,
        'same-path replacement ultimately caches the new repository prompt');
}

sub resourcing_keeps_generations_monotonic {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (last-known)');
    my $result = shell($self, "aqsnow_vcs_prompt_restore\nset -g __aqsnow_vcs_pending 1\n"
        . stage_completion(' (obsolete-before-source)', '0') . <<'FISH');
aqsnow_vcs_prompt_preexec
set -l invalidated_generation "$__aqsnow_vcs_generation"
source "$TEST_SOURCE"
test "$__aqsnow_vcs_generation" -gt "$invalidated_generation"
printf 'advanced=%s\n' "$status"
aqsnow_vcs_prompt_done
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
FISH
    is(output($result), "advanced=0\n (last-known)\n",
        're-sourcing advances the generation and cannot revive a pre-command result');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (last-known)',
        're-sourcing does not persist an obsolete result');
}

sub result_requires_ready_status {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (last-known)');
    my $result = shell($self, "aqsnow_vcs_prompt_restore\nset -g __aqsnow_vcs_pending 1\n"
        . stage_completion(' (complete-result)', '0') . <<'FISH');
command rm -- "$__aqsnow_vcs_file.status"
aqsnow_vcs_prompt_done
set -q __aqsnow_vcs_pending
printf 'pending=%s\n%s\n' "$status" "$AQSNOW_FISH_GIT_PROMPT"
printf '0\n' > "$__aqsnow_vcs_file.status"
aqsnow_vcs_prompt_done
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
FISH
    is(output($result), "pending=0\n (last-known)\n (complete-result)\n",
        'a premature signal retains the request until the status marker is ready');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (complete-result)',
        'the completed request is persisted after its status marker arrives');
}

sub dead_supervisor_is_recovered {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (last-known)');
    fake_dotfiles($self, <<'FISH');
function aqsnow_vcs_prompt
    if not test -e "$TEST_ROOT/first-worker"
        printf started > "$TEST_ROOT/first-worker"
        command sleep 20
    end
    printf ' (recovered)'
end
FISH
    my $result = shell($self, "aqsnow_vcs_prompt_update\n" . wait_for_marker('first-worker') . <<'FISH' . wait_for_retired_process() . <<'FISH' . wait_for_refresh() . <<'FISH');
set -l retired_process "$__aqsnow_vcs_process"
command kill -KILL -- "-$retired_process"
FISH
aqsnow_vcs_prompt_update
test "$__aqsnow_vcs_process" != "$retired_process"
printf 'restarted=%s\n' "$status"
FISH
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
exit 0
FISH
    is(output($result), "restarted=0\n (recovered)\n",
        'a dead supervisor is replaced on the next update without losing cached text');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (recovered)', 'recovered worker updates disk cache');
}

sub missing_control_is_recovered {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (last-known)');
    fake_dotfiles($self, <<'FISH');
function aqsnow_vcs_prompt
    if not test -e "$TEST_ROOT/first-worker"
        printf started > "$TEST_ROOT/first-worker"
        command sleep 20
    end
    printf ' (recovered-control)'
end
FISH
    my $result = shell($self, "aqsnow_vcs_prompt_update\n" . wait_for_marker('first-worker') . <<'FISH' . wait_for_refresh() . <<'FISH' . wait_for_retired_process() . "exit 0\n");
set -l retired_process "$__aqsnow_vcs_process"
command rm -- "$__aqsnow_rendezvous_dir/vcs-alive"
aqsnow_vcs_prompt_update
test "$__aqsnow_vcs_process" != "$retired_process"
printf 'restarted=%s\n' "$status"
FISH
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
FISH
    is(output($result), "restarted=0\n (recovered-control)\n",
        'missing ownership control immediately permits a replacement and retires the old supervisor');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (recovered-control)', 'replacement result reaches disk cache');
}

sub obsolete_worker_does_not_block_new_directory {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (main-cached)');
    write_file("$self->{other}/.fish_git_prompt", ' (other-cached)');
    fake_dotfiles($self, <<'FISH');
function aqsnow_vcs_prompt
    if test "$PWD" = "$TEST_REPO"
        printf started > "$TEST_ROOT/old-worker"
        command sleep 20
        printf ' (obsolete-main)'
    else
        printf ' (other-fresh)'
    end
end
FISH
    my $result = shell($self, "aqsnow_vcs_prompt_update\n" . wait_for_marker('old-worker') . <<'FISH' . wait_for_refresh() . <<'FISH' . wait_for_retired_process() . "exit 0\n");
set -l retired_process "$__aqsnow_vcs_process"
aqsnow_vcs_prompt_preexec
cd -- "$TEST_OTHER"
aqsnow_vcs_prompt_invalidate
aqsnow_vcs_prompt_update
test "$__aqsnow_vcs_process" != "$retired_process"
printf 'new-worker=%s\n%s\n' "$status" "$AQSNOW_FISH_GIT_PROMPT"
FISH
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
FISH
    is(output($result), "new-worker=0\n (other-cached)\n (other-fresh)\n",
        'a new directory starts its own refresh while the obsolete slow worker is retired');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (main-cached)', 'obsolete repository cache is untouched');
    is(read_file("$self->{other}/.fish_git_prompt"), ' (other-fresh)', 'current repository gets the fresh result');
}

sub external_repository_replacement_is_rejected {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (last-known)');
    fake_dotfiles($self, <<'FISH');
function aqsnow_vcs_prompt
    set -l branch "$(command git symbolic-ref --short HEAD)"
    printf started > "$TEST_ROOT/identity-worker"
    while not test -e "$TEST_ROOT/release-worker"
        command sleep 0.02
    end
    printf ' (%s)' "$branch"
end
FISH
    my $result = shell($self, "aqsnow_vcs_prompt_update\n" . wait_for_marker('identity-worker') . <<'FISH' . wait_for_refresh() . <<'FISH' . wait_for_refresh() . <<'FISH');
# No preexec/postexec event: model another process replacing this repository.
command mv .git "$TEST_ROOT/original.git"
command git init --quiet --initial-branch replacement .
printf release > "$TEST_ROOT/release-worker"
FISH
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT" "$(string collect < .fish_git_prompt)"
aqsnow_vcs_prompt_update
FISH
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
exit 0
FISH
    is(output($result), " (last-known)\n (last-known)\n (replacement)\n",
        'an actual worker rejects an old repository identity and retries the replacement');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (replacement)', 'only the replacement result is cached');
}

sub failed_refresh_keeps_display {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (last-known)');
    for my $case (['', '0'], [' (partial)', '1']) {
        my $result = shell($self, "set -g __aqsnow_vcs_pending 1\naqsnow_vcs_prompt_update\n"
            . fake_completion(@$case) . 'printf "%s\n%s\n" "$__aqsnow_vcs_prompt" "$AQSNOW_FISH_GIT_PROMPT"' . "\n");
        is(output($result), " (last-known)\n (last-known)\n", 'empty or failed result keeps the display');
        is(read_file("$self->{repo}/.fish_git_prompt"), ' (last-known)', 'empty or failed result keeps the persistent cache');
    }
}

sub successful_refresh_is_atomic {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (old)');
    my $fresh = " (\e[4mmain\e[0m +3)";
    my $result = shell($self, "set -g __aqsnow_vcs_pending 1\naqsnow_vcs_prompt_update\n"
        . fake_completion($fresh, '0') . 'printf "%s\n%s\n" "$__aqsnow_vcs_prompt" "$AQSNOW_FISH_GIT_PROMPT"' . "\n");
    is(output($result), "$fresh\n (main +3)\n", 'successful result updates display and exported plain text');
    is(read_file("$self->{repo}/.fish_git_prompt"), $fresh, 'successful result is persisted');
    ok(!grep(/\.fish_git_prompt\..*\.tmp\z/, @{directory_entries($self->{repo})}), 'atomic write leaves no temporary files');
    ok(!-e "$self->{root}/result" && !-e "$self->{root}/result.status", 'rendezvous results are cleaned');
}

sub unchanged_cache_is_not_rewritten {
    my ($self) = @_;
    my $cache = "$self->{repo}/.fish_git_prompt";
    write_file($cache, ' (unchanged)');
    utime(1700000000, 1700000000, $cache) or die $!;
    my $before = (stat $cache)[9];
    my $result = shell($self, "set -g __aqsnow_vcs_pending 1\naqsnow_vcs_prompt_update\n"
        . fake_completion(' (unchanged)', '0') . 'printf "%s\\n" "$AQSNOW_FISH_GIT_PROMPT"' . "\n");
    is(output($result), " (unchanged)\n", 'unchanged refresh retains the displayed value');
    is((stat $cache)[9], $before, 'unchanged refresh preserves cache modification time');
    ok(!grep(/\/\.fish-prompt-/, @{directory_entries($self->{repo})}), 'unchanged refresh needs no staging directory');
}

sub staging_file_uses_cache_ignore_pattern {
    my ($self) = @_;
    write_file("$self->{repo}/.git/info/exclude", ".fish_git_prompt\n");
    write_file("$self->{repo}/.fish_git_prompt", ' (old)');
    make_path("$self->{root}/bin");
    write_file("$self->{root}/bin/mv", <<'SHELL');
#!/bin/sh
set -eu
"$TEST_REAL_GIT" -C "$TEST_REPO" status --porcelain --untracked-files=all > "$TEST_ROOT/staging-status"
for argument do
    case "$argument" in
        */.fish_git_prompt) printf '%s\n' "$argument" >> "$TEST_ROOT/staging-paths" ;;
    esac
done
exec "$TEST_REAL_MV" "$@"
SHELL
    chmod 0755, "$self->{root}/bin/mv";
    $self->{env}{TEST_REAL_GIT} = $git;
    $self->{env}{TEST_REAL_MV} = which('mv');
    $self->{env}{PATH} = "$self->{root}/bin:$ENV{PATH}";
    my $result = shell($self, "set -g __aqsnow_vcs_pending 1\naqsnow_vcs_prompt_update\n"
        . fake_completion(' (fresh)', '0') . 'printf "%s\\n" "$AQSNOW_FISH_GIT_PROMPT"' . "\n");
    is(output($result), " (fresh)\n", 'staged refresh completes normally');
    is(read_file("$self->{root}/staging-status"), '', 'ordinary cache ignore pattern also hides the staged replacement');
    my ($temporary) = split /\n/, read_file("$self->{root}/staging-paths");
    like($temporary, qr{\Q$self->{repo}\E/\.fish-prompt-[^/]+/\.fish_git_prompt\z}, 'replacement stays on the worktree filesystem');
    ok(!-d dirname($temporary), 'successful refresh removes its staging directory');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (fresh)', 'atomic replacement persists fresh content');
}

sub real_async_refresh {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (cached)');
    fake_dotfiles($self, <<'FISH');
function aqsnow_vcs_prompt
    test "$GIT_OPTIONAL_LOCKS" = 0; or return 1
    command sleep 0.2
    printf %s ' (async-refreshed)'
end
FISH
    my $result = shell($self, <<'FISH');
aqsnow_vcs_prompt_update
printf '%s\n' "$__aqsnow_vcs_prompt"
for i in $(seq 1 100)
    set -q __aqsnow_vcs_pending; or break
    command sleep 0.03
end
printf '%s\n%s\n' "$__aqsnow_vcs_prompt" "$AQSNOW_FISH_GIT_PROMPT"
set -q __aqsnow_vcs_pending; and exit 2
exit 0
FISH
    is(output($result), " (cached)\n (async-refreshed)\n (async-refreshed)\n", 'the supervisor retains the cache until the real worker completes');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (async-refreshed)', 'real worker completion persists the result');
    ok(!-e "$self->{root}/rendezvous/vcs-alive", 'Fish exit cleans supervisor liveness');
}

sub real_git_refresh {
    my ($self) = @_;
    my $result = shell($self, <<'FISH');
aqsnow_vcs_prompt_update
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
for i in $(seq 1 100)
    set -q __aqsnow_vcs_pending; or break
    command sleep 0.03
end
printf '%s\n' "$AQSNOW_FISH_GIT_PROMPT"
set -q __aqsnow_vcs_pending; and exit 2
exit 0
FISH
    like(output($result), qr/^ \(main\)\n \(main[^\n]*\)\n$/, 'actual Git refresh follows immediate HEAD identity');
    ok(-s "$self->{repo}/.fish_git_prompt", 'actual Git result is persisted');
}

sub unwritable_cache_keeps_display {
    my ($self) = @_;
    write_file("$self->{repo}/.fish_git_prompt", ' (saved)');
    chmod 0500, $self->{repo} or die $!;
    my $result = shell($self, "set -g __aqsnow_vcs_pending 1\naqsnow_vcs_prompt_update\n"
        . fake_completion(' (fresh)', '0') . 'printf "%s\n" "$AQSNOW_FISH_GIT_PROMPT"' . "\n");
    chmod 0700, $self->{repo} or die $!;
    is(output($result), " (fresh)\n", 'unwritable cache does not break refreshed display');
    is(read_file("$self->{repo}/.fish_git_prompt"), ' (saved)', 'unwritable saved cache remains intact');
}

run_cases({
    cached_first_render => \&cached_first_render,
    head_identity_without_cache => \&head_identity_without_cache,
    subdirectories_and_metadata => \&subdirectories_and_metadata,
    linked_worktrees => \&linked_worktrees,
    directory_switch_while_pending => \&directory_switch_while_pending,
    initialized_repository_in_same_directory => \&initialized_repository_in_same_directory,
    nested_repository_during_refresh => \&nested_repository_during_refresh,
    removed_repository_during_refresh => \&removed_repository_during_refresh,
    replaced_repository_during_foreground_command => \&replaced_repository_during_foreground_command,
    resourcing_keeps_generations_monotonic => \&resourcing_keeps_generations_monotonic,
    result_requires_ready_status => \&result_requires_ready_status,
    dead_supervisor_is_recovered => \&dead_supervisor_is_recovered,
    missing_control_is_recovered => \&missing_control_is_recovered,
    obsolete_worker_does_not_block_new_directory => \&obsolete_worker_does_not_block_new_directory,
    external_repository_replacement_is_rejected => \&external_repository_replacement_is_rejected,
    failed_refresh_keeps_display => \&failed_refresh_keeps_display,
    successful_refresh_is_atomic => \&successful_refresh_is_atomic,
    unchanged_cache_is_not_rewritten => \&unchanged_cache_is_not_rewritten,
    staging_file_uses_cache_ignore_pattern => \&staging_file_uses_cache_ignore_pattern,
    real_async_refresh => \&real_async_refresh,
    real_git_refresh => \&real_git_refresh,
    unwritable_cache_keeps_display => \&unwritable_cache_keeps_display,
}, \&setup);
