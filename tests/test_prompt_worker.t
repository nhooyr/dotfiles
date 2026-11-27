use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $dotfiles = absolute_path("$FindBin::Bin/..");
my $fish     = which('fish');

sub setup {
    my ($self) = @_;
    $self->{root}    = absolute_path( tempdir( 'prompt-worker-XXXXXX', TMPDIR => 1, CLEANUP => 1 ) );
    $self->{work}    = "$self->{root}/work";
    $self->{fixture} = "$self->{root}/dotfiles";
    make_path( "$self->{work}/.git", "$self->{fixture}/fish", "$self->{fixture}/bin" );
    write_file( "$self->{work}/.git/HEAD", "ref: refs/heads/main\n" );
    symlink "$dotfiles/bin/super", "$self->{fixture}/bin/super" or die $!;
    symlink "$dotfiles/fish/git_prompt_cache.fish", "$self->{fixture}/fish/git_prompt_cache.fish"
      or die $!;
    $self->{env} = {
        %ENV,
        TEST_ROOT          => $self->{root},
        TEST_SOURCE        => "$dotfiles/fish/functions/git_prompt_ensure_enqueue.fish",
        TEST_DOTFILES      => $self->{fixture},
        GIT_OPTIONAL_LOCKS => '1',
        XDG_CONFIG_HOME    => "$self->{root}/config",
        XDG_DATA_HOME      => "$self->{root}/data",
    };
}

sub prompt {
    my ( $self, $body ) = @_;
    write_file( "$self->{fixture}/fish/prompt.fish", "function aqsnow_vcs_prompt\n$body\nend\n" );
}

sub run_prompt {
    my ( $self, $during ) = @_;
    my $script = <<'FISH';
set -g dotfiles "$TEST_DOTFILES"
source "$TEST_SOURCE"
functions --copy aqsnow_vcs_prompt_done complete_prompt
function aqsnow_vcs_prompt_done
    set -g reported_status "$argv[1]"
    complete_prompt $argv
end
function wait_for_ready
    for i in $(seq 1 150)
        test -f "$TEST_ROOT/ready"; and return
        command sleep 0.01
    end
    exit 2
end
function start_prompt
    block --local
    git_prompt_ensure_enqueue
    printf '%s\n' "$__aqsnow_vcs_dir" >> "$TEST_ROOT/worker-directories"
end
FISH
    $script .= "\nstart_prompt\n" . ( $during // '' ) . <<'FISH';

for i in $(seq 1 150)
    set -q __aqsnow_vcs_pending; or break
    command sleep 0.01
end
set -q __aqsnow_vcs_pending; and exit 3
set -q __aqsnow_vcs_dir; and exit 4
set -q __aqsnow_vcs_file; and exit 5
printf '%s\n' "$__aqsnow_vcs_prompt" "$reported_status"
set -q __aqsnow_vcs_dirty; and printf 'dirty\n'
true
FISH
    my $result = run_command(
        [ $fish, '--no-config', '-c', $script ],
        {
            cwd     => $self->{work},
            env     => $self->{env},
            timeout => 10,
        }
    );
    is( $result->{returncode}, 0,  $result->{stderr} );
    is( $result->{stderr},     '', 'prompt supervisor has no diagnostics' );
    my @directories = split /\n/, read_file("$self->{root}/worker-directories");
    ok( !grep( { -e $_ } @directories ), 'finished request removes its temporary directory' );
    return $result->{stdout};
}

sub successful_prompt_and_optional_locks {
    my ($self) = @_;
    prompt( $self, q{printf ' (fresh:%s)' "$GIT_OPTIONAL_LOCKS"} );
    is(
        run_prompt($self),
        " (fresh:0)\n0\n",
        'successful completion uses its exit status and disables optional Git locks'
    );
    is( read_file("$self->{work}/.fish_git_prompt"), ' (fresh:0)', 'fresh prompt is cached' );
}

sub failed_prompt_keeps_previous_value {
    my ($self) = @_;
    prompt( $self, "printf ' (partial)'\nreturn 7" );
    is( run_prompt($self), " (main)\n7\n", 'nonzero command status rejects partial output' );
    ok( !-e "$self->{work}/.fish_git_prompt", 'failed prompt is not cached' );
}

sub source_failure_finishes_request {
    my ($self) = @_;
    write_file( "$self->{fixture}/fish/prompt.fish", "function aqsnow_vcs_prompt\n" );
    is(
        run_prompt($self),
        " (main)\n\ndirty\n",
        'invalid prompt source clears the request and permits a retry'
    );
    ok( !-e "$self->{work}/.fish_git_prompt", 'invalid source cannot populate the cache' );
}

sub delayed_prompt {
    my ($self) = @_;
    prompt( $self, <<'FISH' );
printf ready > "$TEST_ROOT/ready"
while not test -f "$TEST_ROOT/release"
    command sleep 0.01
end
printf ' (fresh)'
FISH
}

sub replaced_git_directory_rejects_result {
    my ($self) = @_;
    delayed_prompt($self);
    my $during = <<'FISH';
wait_for_ready
command mv -- .git .git-old
command mkdir -- .git
printf 'ref: refs/heads/main\n' > .git/HEAD
printf go > "$TEST_ROOT/release"
FISH
    is(
        run_prompt( $self, $during ),
        " (main)\n0\ndirty\n",
        'repository replacement invalidates a successful calculation'
    );
    ok( !-e "$self->{work}/.fish_git_prompt", 'old repository result is not cached in the replacement' );
}

sub retargeted_git_file_rejects_result {
    my ($self) = @_;
    rename "$self->{work}/.git", "$self->{root}/old.git" or die $!;
    make_path("$self->{root}/new.git");
    write_file( "$self->{work}/.git", "gitdir: ../old.git\n" );
    my $inode = ( stat "$self->{work}/.git" )[1];
    delayed_prompt($self);
    my $during = <<'FISH';
wait_for_ready
printf 'gitdir: ../new.git\n' > .git
printf go > "$TEST_ROOT/release"
FISH
    is(
        run_prompt( $self, $during ),
        " (main)\n0\ndirty\n",
        'retargeting the Git file invalidates the result'
    );
    is( ( stat "$self->{work}/.git" )[1], $inode, 'Git file itself retains its inode' );
    ok( !-e "$self->{work}/.fish_git_prompt", 'result for the previous target is not cached' );
}

sub unchanged_git_file_keeps_result {
    my ($self) = @_;
    rename "$self->{work}/.git", "$self->{root}/actual.git" or die $!;
    prompt( $self, q{printf ' (fresh)'} );
    for my $target ( '../actual.git', "$self->{root}/actual.git" ) {
        write_file( "$self->{work}/.git", "gitdir: $target\n" );
        is(
            run_prompt($self),
            " (fresh)\n0\n",
            'unchanged relative or absolute gitdir target accepts the result'
        );
    }
    is( read_file("$self->{work}/.fish_git_prompt"), ' (fresh)', 'unchanged gitdir result is cached' );
}

run_cases(
    {
        successful_prompt_and_optional_locks  => \&successful_prompt_and_optional_locks,
        failed_prompt_keeps_previous_value    => \&failed_prompt_keeps_previous_value,
        source_failure_finishes_request       => \&source_failure_finishes_request,
        replaced_git_directory_rejects_result => \&replaced_git_directory_rejects_result,
        retargeted_git_file_rejects_result    => \&retargeted_git_file_rejects_result,
        unchanged_git_file_keeps_result       => \&unchanged_git_file_keeps_result,
    },
    \&setup
);
