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
    $self->{target}    = "$self->{temporary}/target space \$cash 'quoted'";
    make_path( $self->{target}, "$self->{temporary}/pushes" );
    for my $directory ( $self->{temporary}, $self->{target} ) {
        write_file( "$directory/commit", "#!/bin/sh\nexit \"\${TEST_STATUS:-0}\"\n" );
        chmod 0755, "$directory/commit" or die $!;
    }
    $self->{env} = {
        %ENV,
        TEST_TARGET  => $self->{target},
        TEST_CDC     => "$root/fish/functions/cdc.fish",
        TEST_ROOT    => $self->{temporary},
        TERM_PROGRAM => '',
        CMD_DURATION => 0,
    };
}

sub check_commands {
    my ( $self, @cases ) = @_;
    my $result = run_command(
        [ 'fish', '--no-config', '-c', $postexec . <<'FISH', '--', map { ( $_->[0], $_->[3] // 0 ) } @cases ],
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
for name in gcm gacm gcma gacma gcmf
    function $name
        git commit $argv
    end
end
function gacmp
    git commit $argv; and git push
end
function gcm-extra
    return 0
end
function aqsnow_run_requested
    return 0
end
set -l index 0
while set -q argv[1]
    cd "$TEST_ROOT"
    set -gx TEST_LOG "$TEST_ROOT/pushes/$index"
    set -gx TEST_STATUS "$argv[2]"
    eval "$argv[1]" >/dev/null
    aqsnow_postexec "$argv[1]" >/dev/null
    printf '%s\t%s\n' "$status" "$PWD"
    set index "$(math "$index + 1")"
    set -e argv[1..2]
end
FISH
        { cwd => $self->{temporary}, env => $self->{env} }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
    my @results = split /\n/, $result->{stdout};
    is( scalar @results, scalar @cases, 'every command ran' );
    for my $index ( 0 .. $#cases ) {
        my ( $line, $kind, $directory ) = @{ $cases[$index] };
        $directory //= $self->{temporary};
        is( $results[$index], "0\t$self->{temporary}", "$line completes and restores cwd" );
        my $log = "$self->{temporary}/pushes/$index";
        is( -e $log ? read_file($log) : '', $kind ? "$kind\t$directory\n" : '', "$line push" );
    }
}

sub plain_and_wrapped_commit_forms {
    my ($self) = @_;
    my @cases;
    for my $case (
        [ 'git commit',                   'push' ],
        [ 'git commit;',                  'push' ],
        [ 'git commit;   ',               'push' ],
        [ 'git commit --amend --no-edit', 'force' ],
        [ '"git" "commit"',               'push' ],
        [ 'gcm',                          'push' ],
        [ 'gcm --amend --no-edit',        'force' ],
        [ 'gacm',                         'push' ],
        [ 'gcma -m message',              'force' ],
        [ 'gacma -m message',             'force' ],
        [ 'gacmp',                        'push' ],
        [ 'gacmp --amend',                'push' ],
        [ 'gcmf HEAD',                    'push' ],
        [ './commit',                     'push' ],
      )
    {
        push @cases, $case, [ 'cdc "$TEST_TARGET" ' . $case->[0], $case->[1], $self->{target} ];
    }
    check_commands( $self, @cases );
}

sub wrapped_sequences_use_expanded_paths {
    my ($self) = @_;
    check_commands(
        $self,
        [ 'true; and cdc "$TEST_TARGET" git commit',                         'push', $self->{target} ],
        [ 'false; or cdc "$TEST_TARGET" git commit -m "literal ; and gcma"', 'push', $self->{target} ],
        [ 'cdc "$TEST_TARGET" true; and git commit',                         'push' ],
    );
}

sub amend_flags_work_in_any_position {
    my ($self) = @_;
    my @cases;
    for my $line (
        'git commit --no-edit --amend',
        'git commit -m message --amend',
        'gcm -qam message --amend',
        'gacm path --amend',
      )
    {
        push @cases, [ $line, 'force' ], [ 'cdc "$TEST_TARGET" ' . $line, 'force', $self->{target} ];
    }
    check_commands( $self, @cases );
}

sub failed_or_unrelated_commands_do_not_push {
    my ($self) = @_;
    check_commands(
        $self,
        [ 'git commit',                    '', undef, 23 ],
        [ 'cdc "$TEST_TARGET" git commit', '', undef, 23 ],
        [ 'cdc "$TEST_TARGET" gcma',       '', undef, 23 ],
        [ 'gacmp',                         '', undef, 23 ],
        [ 'cdc "$TEST_TARGET" gacmp',      '', undef, 23 ],
        ['cdc "$TEST_TARGET" git commit; and true'],
    );
}

sub only_command_tokens_trigger_a_push {
    my ($self) = @_;
    check_commands(
        $self,
        map { [$_] } (
            q{echo 'git commit'},
            q{printf '%s\n' gcm},
            q{git status 'git commit'},
            q{git commitment},
            q{gcm-extra}, q{cdc "$TEST_TARGET" gcm-extra},
            q{true;},     q{# comment}, '',
        )
    );
}

run_cases(
    {
        plain_and_wrapped_commit_forms           => \&plain_and_wrapped_commit_forms,
        wrapped_sequences_use_expanded_paths     => \&wrapped_sequences_use_expanded_paths,
        amend_flags_work_in_any_position         => \&amend_flags_work_in_any_position,
        failed_or_unrelated_commands_do_not_push => \&failed_or_unrelated_commands_do_not_push,
        only_command_tokens_trigger_a_push       => \&only_command_tokens_trigger_a_push,
    },
    \&setup
);
