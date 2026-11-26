use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my ($postexec) = read_file("$root/fish/config.fish") =~ /^(function aqsnow_postexec\b.*?^end\n)/msg;
die "Missing Fish function aqsnow_postexec\n" unless defined $postexec;

sub setup {
    my ($self) = @_;
    $self->{temporary} = absolute_path( tempdir( 'commit-push-XXXXXX', TMPDIR => 1, CLEANUP => 1 ) );
    $self->{target}    = "$self->{temporary}/target space";
    make_path( $self->{target} );
    for my $directory ( $self->{temporary}, $self->{target} ) {
        write_file( "$directory/commit", "#!/bin/sh\nexit \"\${TEST_STATUS:-0}\"\n" );
        chmod 0755, "$directory/commit" or die $!;
    }
    $self->{env} = {
        %ENV,
        TEST_TARGET  => $self->{target},
        TEST_CDC     => "$root/fish/functions/cdc.fish",
        TEST_LOG     => "$self->{temporary}/pushes",
        TEST_STATUS  => 0,
        TERM_PROGRAM => '',
        CMD_DURATION => 0,
    };
}

sub run_line {
    my ( $self, $line ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', $postexec . <<'FISH', '--', $line ],
source "$TEST_CDC"
function git
    if test "$argv[1]" = push
        printf 'push\t%s\n' "$PWD" >> "$TEST_LOG"
    else if test "$argv[1]" = commit
        return "$TEST_STATUS"
    end
end
function gpf
    printf 'force\t%s\n' "$PWD" >> "$TEST_LOG"
end
function gcm
    git commit $argv
end
function gacm
    git commit $argv
end
function gcma
    git commit --amend $argv
end
function gacma
    git commit --amend $argv
end
function gacmp
    git commit $argv
end
function gcmf
    git commit --fixup $argv
end
function gcm-extra
    return 0
end
function aqsnow_run_requested
    return 0
end
function return_status
    return "$argv[1]"
end
function target
    set -g target_calls "$(math "$target_calls + 1")"
    printf '%s\n' "$TEST_TARGET"
end
set -g target_calls 0
eval "$argv[1]"
set -l code "$status"
return_status "$code"
aqsnow_postexec "$argv[1]"
printf 'outside:%s\ntarget-calls:%s\n' "$PWD" "$target_calls"
FISH
        { cwd => $self->{temporary}, env => $self->{env} }
    );
}

sub pushed {
    my ( $self, $line, $kind, $directory ) = @_;
    unlink $self->{env}{TEST_LOG};
    my $result = run_line( $self, $line );
    is( $result->{returncode},               0,                     $result->{stderr} );
    is( read_file( $self->{env}{TEST_LOG} ), "$kind\t$directory\n", "$line pushes in the right directory" );
    like( $result->{stdout}, qr/^outside:\Q$self->{temporary}\E$/m, 'the caller directory is restored' );
    return $result;
}

sub plain_and_wrapped_commit_forms {
    my ($self) = @_;
    for my $case (
        [ 'git commit',                   'push' ],
        [ 'git commit;',                  'push' ],
        [ 'git commit --amend --no-edit', 'force' ],
        [ 'git commit -m "--amend"',      'push' ],
        [ '"git" "commit"',               'push' ],
        [ 'gcm',                          'push' ],
        [ 'gcm --amend --no-edit',        'force' ],
        [ 'gacm',                         'push' ],
        [ 'gcma -m message',              'force' ],
        [ 'gacma -m message',             'force' ],
        [ 'gacmp',                        'push' ],
        [ 'gcmf HEAD',                    'push' ],
        [ './commit argument',            'push' ],
        [ './commit --amend',             'push' ],
      )
    {
        pushed( $self, $case->[0],                         $case->[1], $self->{temporary} );
        pushed( $self, 'cdc "$TEST_TARGET" ' . $case->[0], $case->[1], $self->{target} );
    }
}

sub wrapped_sequences_reuse_the_raw_prefix {
    my ($self) = @_;
    pushed( $self, 'true; and cdc "$TEST_TARGET" git commit', 'push', $self->{target} );
    pushed( $self, 'false; or cdc "$TEST_TARGET" git commit -m "literal ; and gcma"',
        'push', $self->{target} );
    my $result =
      pushed( $self, 'cdc "$(target)" git commit -m "message with spaces"', 'push', $self->{target} );
    like( $result->{stdout}, qr/^target-calls:2$/m,
        'the reused cdc prefix evaluates the target expression again' );
    pushed( $self, 'cdc "$TEST_TARGET" true; and git commit', 'push', $self->{temporary} );
}

sub amend_flags_are_distinguished_from_values {
    my ($self) = @_;
    for my $case (
        [ 'git commit --no-edit --amend',      'force' ],
        [ 'git commit -m message --amend',     'force' ],
        [ 'gcm -qam message --amend',          'force' ],
        [ 'gacm path --amend',                 'force' ],
        [ 'git commit -am "--amend"',          'push' ],
        [ 'git commit -qam "--amend"',         'push' ],
        [ 'git commit --message=--amend',      'push' ],
        [ 'git commit --file --amend',         'push' ],
        [ 'git commit --file --amend --amend', 'force' ],
        [ 'git commit -- --amend',             'push' ],
      )
    {
        pushed( $self, $case->[0],                         $case->[1], $self->{temporary} );
        pushed( $self, 'cdc "$TEST_TARGET" ' . $case->[0], $case->[1], $self->{target} );
    }
}

sub failed_or_unrelated_commands_do_not_push {
    my ($self) = @_;
    $self->{env}{TEST_STATUS} = 23;
    for my $line ( 'git commit', 'cdc "$TEST_TARGET" git commit', 'cdc "$TEST_TARGET" gcma' ) {
        my $result = run_line( $self, $line );
        is( $result->{returncode}, 0, $result->{stderr} );
        ok( !-e $self->{env}{TEST_LOG}, 'a failed commit does not push' );
        like( $result->{stdout}, qr/outside:\Q$self->{temporary}\E/,
            'failure restores the caller directory' );
    }
    $self->{env}{TEST_STATUS} = 0;
    my $result = run_line( $self, 'cdc "$TEST_TARGET" git commit; and true' );
    is( $result->{returncode}, 0, $result->{stderr} );
    ok( !-e $self->{env}{TEST_LOG}, 'an unrelated final command does not reuse the wrapped commit' );
}

sub only_command_tokens_trigger_a_push {
    my ($self) = @_;
    for my $line (
        q{echo 'git commit'},
        q{printf '%s\n' gcm},
        q{git status 'git commit'},
        q{git commitment},
        q{gcm-extra}, q{cdc "$TEST_TARGET" gcm-extra},
        q{true;},     q{# comment}, '',
      )
    {
        my $result = run_line( $self, $line );
        is( $result->{returncode}, 0, $result->{stderr} );
        ok( !-e $self->{env}{TEST_LOG}, "$line does not push" );
    }
}

run_cases(
    {
        plain_and_wrapped_commit_forms            => \&plain_and_wrapped_commit_forms,
        wrapped_sequences_reuse_the_raw_prefix    => \&wrapped_sequences_reuse_the_raw_prefix,
        amend_flags_are_distinguished_from_values => \&amend_flags_are_distinguished_from_values,
        failed_or_unrelated_commands_do_not_push  => \&failed_or_unrelated_commands_do_not_push,
        only_command_tokens_trigger_a_push        => \&only_command_tokens_trigger_a_push,
    },
    \&setup
);
