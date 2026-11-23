# Git and GitHub helper regressions; all remote traffic stays in temporary repos.
use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $SOURCE = (
    exists( ( \%ENV )->{"GITHUB_FISH_TEST_SOURCE"} )
    ? ( \%ENV )->{"GITHUB_FISH_TEST_SOURCE"}
    : join_path( ancestors( absolute_path(__FILE__) )->[1], "fish/functions" )
);
my $FISH = which("fish");
my $GIT  = which("git");
if ( ( 0 + ( !($FISH) ) || 0 + ( !($GIT) ) ) ) {
    die "Fish and Git are required to run the regression suite";
}

sub fish_quote {
    my ($value) = @_;
    return ( ( "'" . replace_literal( replace_literal( $value, "\\", "\\\\" ), "'", "\\'" ) ) . "'" );
}

sub setUp {
    my ($self) = @_;
    my ( $key, $value );
    $self->{temporary} = tempdir( "github-commands-" . "XXXXXX", TMPDIR => 1, CLEANUP => 1 );
    $self->{root}      = absolute_path( $self->{temporary} );
    $self->{sandbox}   = join_path( $self->{root}, "sandbox" );
    make_path( $self->{sandbox} );
    $self->{bin} = join_path( $self->{root}, "bin" );
    make_path( $self->{bin} );
    $self->{log}    = join_path( $self->{root}, "calls.log" );
    $self->{remote} = join_path( $self->{root}, "remote.git" );
    $self->{seed}   = join_path( $self->{root}, "seed" );
    $self->{checkout} =
      join_path( join_path( join_path( $self->{sandbox}, "code" ), "test-owner" ), "test-repo" );
    $self->{url} = "https://github.com/test-owner/test-repo";
    $self->{env} = {
        map { my $key = ($_)->[0]; my $value = ($_)->[1]; ( $key => $value ) }
        grep {
            my $key   = ($_)->[0];
            my $value = ($_)->[1];
            0 + ( !( ( index( $key, "GIT_" ) == 0 ) ) )
        } @{ [ map { [ $_, ( \%ENV )->{$_} ] } sort keys %{ ( \%ENV ) } ] }
    };
    do {
        my $updates = {
            "XDG_CONFIG_HOME"         => join_path( $self->{root}, "config" ),
            "XDG_DATA_HOME"           => join_path( $self->{root}, "data" ),
            "XDG_CACHE_HOME"          => join_path( $self->{root}, "cache" ),
            "GIT_CONFIG_GLOBAL"       => "/dev/null",
            "GIT_CONFIG_NOSYSTEM"     => "1",
            "GIT_TERMINAL_PROMPT"     => "0",
            "GIT_ALLOW_PROTOCOL"      => "file",
            "GIT_AUTHOR_NAME"         => "Regression Test",
            "GIT_AUTHOR_EMAIL"        => "test\@example.invalid",
            "GIT_COMMITTER_NAME"      => "Regression Test",
            "GIT_COMMITTER_EMAIL"     => "test\@example.invalid",
            "GIT_EDITOR"              => "true",
            "GIT_PAGER"               => "cat",
            "PAGER"                   => "cat",
            "TEST_REAL_GIT"           => $GIT,
            "TEST_PERL"               => perl_executable(),
            "TEST_CALL_LOG"           => $self->{log},
            "TEST_REMOTE"             => $self->{remote},
            "TEST_GH_RESPONSES"       => "{}",
            "TEST_REPO_CREATE_STDOUT" => (
                $self->{url} . '
'
            ),
            "TEST_REPO_CREATE_STDERR" => "",
            "TEST_REPO_CREATE_STATUS" => "0",
            "TEST_DISPATCH_STATUS"    => "0",
            "TEST_EXTRA_URLS"         => "[]",
            "GH_HOST"                 => "",
            "TEST_OFFLINE"            => "",
            "TEST_CLONE_FAILURE"      => ""
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    _make_mocks($self);
    $self->{env}->{"PATH"}   = ( ( $self->{bin} . ":" ) . ( \%ENV )->{"PATH"} );
    $self->{env}->{"EDITOR"} = join_path( $self->{bin}, "editor" );
    git( $self, undef, [ "init", "--bare", "--initial-branch=main", $self->{remote} ], 1 );
    git( $self, undef, [ "init", "--initial-branch=main", $self->{seed} ], 1 );
    make_path( join_path( $self->{seed}, "dir" ) );
    write_file(
        join_path( $self->{seed}, "file.txt" ), 'first
second
third
fourth
'
    );
    write_file(
        join_path( join_path( $self->{seed}, "dir" ), "nested.txt" ), 'nested
'
    );
    write_file(
        join_path( $self->{seed}, "a b#.txt" ), 'escaped name
'
    );
    write_file(
        join_path( $self->{seed}, ".gitignore" ), 'ignored.txt
'
    );
    symlink( "file.txt",    join_path( $self->{seed}, "linked.txt" ) );
    symlink( "missing.txt", join_path( $self->{seed}, "broken.txt" ) );
    git( $self, $self->{seed}, [ "add", "-A" ], 1 );
    git( $self, $self->{seed}, [ "commit", "-qm", "initial" ], 1 );
    $self->{initial} =
      trim( git( $self, $self->{seed}, [ "rev-parse", "HEAD" ], 1 )->{stdout} );
    git( $self, $self->{seed}, [ "tag", "v1" ], 1 );
    git( $self, $self->{seed}, [ "remote", "add", "origin", $self->{remote} ], 1 );
    publish( $self, [ "main", "refs/tags/v1" ] );
    make_path( dirname( $self->{checkout} ) );
    git( $self, undef, [ "clone", $self->{remote}, $self->{checkout} ], 1 );
    git( $self, $self->{checkout}, [ "remote", "set-url", "origin", ( $self->{url} . ".git" ) ], 1 );
}

sub _make_mocks {
    my ($self) = @_;
    my ( $name, $program, $target, $wrapper );

    # Log arguments in the shell; only transport and gh responses need Perl.
    $wrapper = '#!/bin/sh
set -eu
kind=${0##*/}
printf \'%s\\0\' "$kind" "$#" "$@" >> "$TEST_CALL_LOG"
case "$kind" in
    open|editor) exit 0 ;;
    dispatch) exit "${TEST_DISPATCH_STATUS:-0}" ;;
    git)
        skip=
        command=
        for arg do
            if [ "$skip" ]; then
                skip=
                continue
            fi
            case "$arg" in
                -C|-c|--git-dir|--work-tree) skip=1 ;;
                -*) ;;
                *) command=$arg; break ;;
            esac
        done
        case "$command" in
            clone|fetch|ls-remote|push) ;;
            *) exec "$TEST_REAL_GIT" "$@" ;;
        esac ;;
esac
exec "$TEST_PERL" "${0%/*}/mock.pl" "$kind" "$@"
';
    $program = read_file( join_path( $FindBin::Bin, "mock.pl" ) );
    write_file( join_path( $self->{bin}, "mock.pl" ), $program );
    for $name ( @{ [ "git", "gh", "open", "editor", "dispatch" ] } ) {
        $target = join_path( $self->{bin}, $name );
        write_file( $target, $wrapper );
        chmod( 493, $target );
    }
}

sub git {
    my ( $self, $directory, $args, $check ) = @_;
    my ( $arg, $command );
    $command = [$GIT];
    if ( ( defined($directory) ) ) {
        push( @{$command}, @{ [ "-C", $directory ] } );
    }
    push( @{$command}, @{ [ map { my $arg = $_; $arg } @{$args} ] } );
    return run_command( $command, { "env" => $self->{env}, "check" => $check } );
}

sub publish {
    my ( $self, $refs ) = @_;
    git(
        $self,
        ( [ $self->{seed}, "push", "--quiet", "origin", @{$refs} ] )->[0],
        array_slice( [ $self->{seed}, "push", "--quiet", "origin", @{$refs} ], 1, undef ), 1
    );
}

sub seed_commit {
    my ( $self, $files, $branch, $create ) = @_;
    my ( $args, $content, $name, $revision, $target );
    $args = [ "switch", "--quiet" ];
    if ($create) {
        push( @{$args}, @{ [ "--create", $branch, "main" ] } );
    }
    else {
        push( @{$args}, @{ [$branch] } );
    }
    git(
        $self,
        ( [ $self->{seed}, @{$args} ] )->[0],
        array_slice( [ $self->{seed}, @{$args} ], 1, undef ), 1
    );
    for my $item_233 ( @{ [ map { [ $_, $files->{$_} ] } sort keys %{$files} ] } ) {
        $name    = ($item_233)->[0];
        $content = ($item_233)->[1];
        $target  = join_path( $self->{seed}, $name );
        make_path( dirname($target) );
        write_file( $target, $content );
        git( $self, $self->{seed}, [ "add", "--force", "--", $name ], 1 );
    }
    git( $self, $self->{seed}, [ "commit", "--quiet", "-m", "fixture update" ], 1 );
    $revision =
      trim( git( $self, $self->{seed}, [ "rev-parse", "HEAD" ], 1 )->{stdout} );
    publish( $self, [$branch] );
    return $revision;
}

sub fetch_fixture {
    my ($self) = @_;
    my ($rule);
    $rule = ( ( ( ( "url." . file_uri( $self->{remote} ) ) . ".insteadOf=" ) . $self->{url} ) . ".git" );
    git( $self, $self->{checkout}, [ "-c", $rule, "fetch", "--quiet", "origin" ], 1 );
}

sub calls {
    my ( $self, $kind ) = @_;
    my ( $entries, $entry );
    $entries = read_calls( $self->{log} );
    return [
        map { my $entry = $_; $entry }
        grep {
            my $entry = $_;
            ( ( !defined($kind) ) || ( ( $entry->{"kind"} eq $kind ) ) )
        } @{$entries}
    ];
}

sub clear_calls {
    my ($self) = @_;
    unlink( $self->{log} );
}

sub network_calls {
    my ($self) = @_;
    my ($entry);
    return [
        map { my $entry = $_; $entry }
        grep {
            my $entry = $_;
            ( contains_value( [ "clone", "fetch", "ls-remote" ], $entry->{"command"} ) )
        } @{ calls( $self, "git" ) }
    ];
}

sub run_fish {
    my ( $self, $command, $args, $cwd, $offline, $editor, $responses, $positions ) = @_;
    my ( $arg, $env, $marker, $result, $script, $value );
    clear_calls($self);
    $env = { %{ $self->{env} } };
    $env->{"TEST_OFFLINE"} = ( $offline ? "1" : "" );
    if ( ( defined($responses) ) ) {
        $env->{"TEST_GH_RESPONSES"} = encode_json($responses);
    }
    if ( ( -d $SOURCE ) ) {
        $script = (
            ( "set -gp fish_function_path " . fish_quote($SOURCE) ) . '
'
        );

        # Tests also call the checkout helpers directly and override them.
        $script .= (
            ( "source " . fish_quote( join_path( $SOURCE, "ghe.fish" ) ) ) . '; or exit
'
        );
    }
    else {
        $script = (
            ( "source " . fish_quote($SOURCE) ) . '; or exit
'
        );
    }
    if ( ( defined($editor) ) ) {
        $script .= (
            ( "set -gx EDITOR " . join( " ", @{ [ map { my $arg = $_; fish_quote($arg) } @{$editor} ] } ) )
            . '
'
        );
    }
    if ( ( ( $command eq "ghe" ) ) ) {

        # Exercise real parsing and checkout without redirecting system HOME.
        # The public ghe destination/anchor dispatch is tested separately.
        ( is_deeply( scalar( @{$args} ), 1 ) or die "assertion failed\n" );
        $script .= (
            (
                'set -lx 0 ghe
if set -l parsed $(__gh_parse ' . fish_quote( $args->[0] )
            )
            . ')
'
        );
        $script .= ( "__ghe_checkout \"\$parsed[3]\" " . fish_quote( $self->{checkout} ) );
        $script .= ( " \"\$parsed[2]\" "
              . join( " ", @{ [ map { my $value = $_; fish_quote($value) } @{$positions} ] } ) );
        $script .= '
else
false
end
';
    }
    else {
        if ( ( ( $command eq "ghc" ) ) ) {
            $script .= 'function ghe
command dispatch $argv
end
';
        }
        if ( ( ( $command eq "ghe_dispatch" ) ) ) {
            $script .= 'function __ghe_checkout
command dispatch $argv
end
';
            $command = "ghe";
        }
        if ( ( ( $command eq "gbp" ) ) ) {
            $script .= (
                (
                    'function abbrali
end
source '
                      . fish_quote( join_path( ancestors( absolute_path(__FILE__) )->[1], "fish/git.fish" ) )
                )
                . '; or exit
'
            );
        }
        $script .= (
            ( ( $command . " " ) . join( " ", @{ [ map { my $arg = $_; fish_quote($arg) } @{$args} ] } ) ) . '
'
        );
    }
    $script .= 'set -l result $status
printf "\\x1e%s" "$PWD"
exit $result
';
    $result = run_command(
        [ $FISH, "--no-config", "-c", $script ],
        {
            "cwd"     => ( $cwd || $self->{sandbox} ),
            "env"     => $env,
            "timeout" => 20
        }
    );
    {
        my $tuple = partition_last( $result->{stdout}, "\x{001e}" );
        $result->{stdout}    = ($tuple)->[0];
        $marker              = ($tuple)->[1];
        $result->{directory} = ($tuple)->[2];
    }
    ( ok( ($marker), $result->{stderr} ) or die "assertion failed\n" );
    if ( ( ( $command eq "gho" ) ) ) {
        (
            is_deeply( network_calls($self), [], "gho must never contact the remote" )
              or die "assertion failed\n"
        );
    }
    return $result;
}

sub assert_success {
    my ( $self, $result ) = @_;
    (
        is_deeply( $result->{returncode}, 0, ( $result->{stderr} . $result->{stdout} ) )
          or die "assertion failed\n"
    );
}

sub head {
    my ($self) = @_;
    return trim( git( $self, $self->{checkout}, [ "rev-parse", "HEAD" ], 1 )->{stdout} );
}

sub test_gbp_preserves_live_branch_when_subject_says_gone {
    my ($self) = @_;
    git( $self, $self->{seed}, [ "switch", "--create", "still-live" ], 1 );
    git( $self, $self->{seed}, [ "commit", "--allow-empty", "-qm", "document [origin/old: gone]" ], 1 );
    publish( $self, ["still-live"] );
    fetch_fixture($self);
    git( $self, $self->{checkout}, [ "branch", "--track", "still-live", "origin/still-live" ], 1 );
    assert_success( $self,
        run_fish( $self, "gbp", [], $self->{checkout}, 0, undef, undef, [ "", "", "", "" ] ) );
    git( $self, $self->{checkout}, [ "show-ref", "--verify", "refs/heads/still-live" ], 1 );
}

sub test_gbp_deletes_branch_with_apostrophe {
    my ($self) = @_;
    my ($branch);
    $branch = "quote'branch";
    git( $self, $self->{seed}, [ "branch", $branch ], 1 );
    publish( $self, [$branch] );
    fetch_fixture($self);
    git( $self, $self->{checkout}, [ "branch", "--track", $branch, ( "origin/" . $branch ) ], 1 );
    git( $self, $self->{remote}, [ "update-ref", "-d", ( "refs/heads/" . $branch ) ], 1 );
    assert_success( $self,
        run_fish( $self, "gbp", [], $self->{checkout}, 0, undef, undef, [ "", "", "", "" ] ) );
    (
        ok(
            !equal_values(
                git( $self, $self->{checkout}, [ "show-ref", "--verify", ( "refs/heads/" . $branch ) ], 0 )
                  ->{returncode},
                0
            )
          )
          or die "assertion failed\n"
    );
}

sub test_gbp_skips_branch_checked_out_in_another_worktree {
    my ($self) = @_;
    my ($branch);
    for $branch ( @{ [ "in-worktree", "gone" ] } ) {
        git( $self, $self->{seed}, [ "branch", $branch ], 1 );
        publish( $self, [$branch] );
    }
    fetch_fixture($self);
    git(
        $self,
        $self->{checkout},
        [
            "worktree", "add", "--track", "-b", "in-worktree", join_path( $self->{root}, "worktree" ),
            "origin/in-worktree"
        ],
        1
    );
    git( $self, $self->{checkout}, [ "branch", "--track", "gone", "origin/gone" ], 1 );
    for $branch ( @{ [ "in-worktree", "gone" ] } ) {
        git( $self, $self->{remote}, [ "update-ref", "-d", ( "refs/heads/" . $branch ) ], 1 );
    }
    assert_success( $self,
        run_fish( $self, "gbp", [], $self->{checkout}, 0, undef, undef, [ "", "", "", "" ] ) );
    git( $self, $self->{checkout}, [ "show-ref", "--verify", "refs/heads/in-worktree" ], 1 );
    (
        ok(
            !equal_values(
                git( $self, $self->{checkout}, [ "show-ref", "--verify", "refs/heads/gone" ], 0 )
                  ->{returncode},
                0
            )
          )
          or die "assertion failed\n"
    );
}

sub test_help_lists_modes_without_side_effects {
    my ($self) = @_;
    my ( $command, $flag, $mode, $modes, $name, $result );
    for my $item_345 (
        @{
            [
                [ "ghc", "ghc", [ "OWNER/REPO", "private", "already exists", "--help" ] ],
                [
                    "gho", "gho",
                    [ "PATH", "SYMLINK", "OWNER/REPO", "GITHUB_URL", "SSH_REPOSITORY_URL", "never check" ]
                ],
                [
                    "ghe_dispatch",
                    "ghe",
                    [
                        "/tree/",         "/blob/",
                        "/blame/",        "/raw/",
                        "/edit/",         "raw.githubusercontent.com",
                        "/commit/",       "/commits/",
                        "/releases/tag/", "/releases/latest",
                        "/archive/",      "/pull/NUMBER",
                        "/commits/SHA",   "/files",
                        "/changes",       "/compare",
                        "#L10"
                    ]
                ]
            ]
        }
      )
    {
        $command = ($item_345)->[0];
        $name    = ($item_345)->[1];
        $modes   = ($item_345)->[2];
        for $flag ( @{ [ "--help", "-h" ] } ) {
            {
                $result = run_fish( $self, $command, [$flag], undef, 0, undef, undef, [ "", "", "", "" ] );
                assert_success( $self, $result );
                (
                    ok( ( ( index( $result->{stdout}, ( "Usage: " . $name ) ) == 0 ) ) )
                      or die "assertion failed\n"
                );
                for $mode ( @{$modes} ) {
                    ( ok( contains_value( $result->{stdout}, $mode ) ) or die "assertion failed\n" );
                }
                ( is_deeply( calls( $self, undef ), [] )               or die "assertion failed\n" );
                ( is_deeply( $result->{directory},  $self->{sandbox} ) or die "assertion failed\n" );
            }
        }
    }
}

sub test_ghc_creates_private_repository_and_opens_reported_url {
    my ($self) = @_;
    my ($result);
    $result = run_fish( $self, "ghc", ["Test-Owner/Test-Repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply(
            $result->{stdout},
            (
                $self->{url} . '
'
            )
          )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            calls( $self, undef ),
            [
                {
                    "kind" => "gh",
                    "args" => [ "repo", "create", "--private", "Test-Owner/Test-Repo" ]
                },
                { "kind" => "dispatch", "args" => [ $self->{url} ] }
            ]
          )
          or die "assertion failed\n"
    );
}

sub test_ghc_reuses_existing_repository_without_looking_it_up {
    my ($self) = @_;
    my ( $created, $existing );
    $created = run_fish( $self, "ghc", ["test-owner/test-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $created );
    do {
        my $updates = {
            "TEST_REPO_CREATE_STDOUT" => "",
            "TEST_REPO_CREATE_STDERR" => 'GraphQL: Name already exists on this account (createRepository)
',
            "TEST_REPO_CREATE_STATUS" => "1"
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    $existing =
      run_fish( $self, "ghc", ["test-owner/test-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $existing );
    ( is_deeply( $existing->{stdout}, $created->{stdout} ) or die "assertion failed\n" );
    ( is_deeply( $existing->{stderr}, "" )                 or die "assertion failed\n" );
    (
        is_deeply(
            calls( $self, undef ),
            [
                {
                    "kind" => "gh",
                    "args" => [ "repo", "create", "--private", "test-owner/test-repo" ]
                },
                { "kind" => "dispatch", "args" => [ $self->{url} ] }
            ]
          )
          or die "assertion failed\n"
    );
}

sub test_ghc_uses_configured_host_or_github_default {
    my ($self) = @_;
    my ( $host, $result, $url );
    do {
        my $updates = {
            "TEST_REPO_CREATE_STDOUT" => "",
            "TEST_REPO_CREATE_STDERR" => 'GraphQL: Name already exists on this account (createRepository)
',
            "TEST_REPO_CREATE_STATUS" => "1"
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    for $host ( @{ [ undef, "", "github.com", "github.example.com", "github.example.com:8443" ] } ) {
        {
            if ( ( !defined($host) ) ) {
                delete( $self->{env}->{"GH_HOST"} );
            }
            else {
                $self->{env}->{"GH_HOST"} = $host;
            }
            $url = ( ( "https://" . ( $host || "github.com" ) ) . "/test-owner/test-repo" );
            $result =
              run_fish( $self, "ghc", ["test-owner/test-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            (
                is_deeply(
                    $result->{stdout},
                    (
                        $url . '
'
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( $result->{stderr}, "" ) or die "assertion failed\n" );
            (
                is_deeply(
                    calls( $self, undef ),
                    [
                        {
                            "kind" => "gh",
                            "args" => [ "repo", "create", "--private", "test-owner/test-repo" ]
                        },
                        { "kind" => "dispatch", "args" => [$url] }
                    ]
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_ghc_rejects_invalid_input_before_running_commands {
    my ($self) = @_;
    my ( $args, $arguments, $result );
    $arguments = [
        [],
        [""],
        ["test-repo"],
        [ "test-owner/test-repo", "extra" ],
        [ "--help",               "extra" ],
        [ "-h",                   "test-owner/test-repo" ],
        [ "test-owner/test-repo", "--public" ],
        ["https://github.com/test-owner/test-repo"],
        ["git\@github.com:test-owner/test-repo.git"],
        ["test-owner/test-repo/extra"],
        ["/test-repo"],
        ["test-owner/"],
        ["test-owner/test-repo/"],
        ["test owner/test-repo"],
        ["test-owner/test repo"],
        ["test-owner/."],
        ["test-owner/.."],
        [
            'test-owner/test-repo
'
        ]
    ];
    for $args ( @{$arguments} ) {
        {
            $result = run_fish(
                $self,
                ( [ "ghc", @{$args} ] )->[0],
                array_slice( [ "ghc", @{$args} ], 1, undef ),
                undef, 0, undef, undef, [ "", "", "", "" ]
            );
            ( is_deeply( $result->{returncode}, 1 )  or die "assertion failed\n" );
            ( is_deeply( $result->{stdout},     "" ) or die "assertion failed\n" );
            (
                is_deeply(
                    $result->{stderr}, 'Usage: ghc <OWNER/REPO>
'
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( calls( $self, undef ), [] ) or die "assertion failed\n" );
        }
    }
}

sub test_ghc_preserves_other_creation_errors {
    my ($self) = @_;
    my ( $error, $result );
    $error = 'HTTP 403: Resource not accessible by integration
';
    do {
        my $updates = {
            "TEST_REPO_CREATE_STDOUT" => "",
            "TEST_REPO_CREATE_STDERR" => $error,
            "TEST_REPO_CREATE_STATUS" => "37"
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    $result = run_fish( $self, "ghc", ["test-owner/test-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    ( is_deeply( $result->{returncode}, 37 )     or die "assertion failed\n" );
    ( is_deeply( $result->{stdout},     "" )     or die "assertion failed\n" );
    ( is_deeply( $result->{stderr},     $error ) or die "assertion failed\n" );
    (
        is_deeply(
            calls( $self, undef ),
            [
                {
                    "kind" => "gh",
                    "args" => [ "repo", "create", "--private", "test-owner/test-repo" ]
                }
            ]
          )
          or die "assertion failed\n"
    );
}

sub test_ghc_preserves_creation_warnings {
    my ($self) = @_;
    my ($result);
    $self->{env}->{"TEST_REPO_CREATE_STDERR"} = 'A warning
';
    $result = run_fish( $self, "ghc", ["test-owner/test-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply(
            $result->{stdout},
            (
                $self->{url} . '
'
            )
          )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            $result->{stderr}, 'A warning
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply( calls( $self, "dispatch" ), [ { "kind" => "dispatch", "args" => [ $self->{url} ] } ] )
          or die "assertion failed\n"
    );
}

sub test_ghc_returns_checkout_failure {
    my ($self) = @_;
    my ($result);
    $self->{env}->{"TEST_DISPATCH_STATUS"} = "42";
    $result = run_fish( $self, "ghc", ["test-owner/test-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    ( is_deeply( $result->{returncode}, 42 ) or die "assertion failed\n" );
}

sub test_supported_transports_open_and_enter_the_same_repository {
    my ($self) = @_;
    my ( $inputs, $result, $value );
    $inputs = [
        "test-owner/test-repo",
        ( $self->{url} . ".git" ),
        "https://github.com:443/test-owner/test-repo",
        "http://github.com:80/test-owner/test-repo",
        "github.com:443/test-owner/test-repo",
        "git\@github.com:test-owner/test-repo.git",
        "ssh://git\@github.com:22/test-owner/test-repo.git",
        "ssh://git\@ssh.github.com:443/test-owner/test-repo.git"
    ];
    for $value ( @{$inputs} ) {
        {
            $result = run_fish( $self, "gho", [$value], undef, 0, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            (
                is_deeply( calls( $self, "open" )->[0]->{"args"}, [ $self->{url} ] )
                  or die "assertion failed\n"
            );
            $result = run_fish( $self, "ghe", [$value], undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            ( is_deeply( $result->{directory}, $self->{checkout} ) or die "assertion failed\n" );
            ( is_deeply( network_calls($self), [] )                or die "assertion failed\n" );
        }
    }
}

sub test_ghe_dispatch_uses_configured_host {
    my ($self) = @_;
    my ($result);
    $self->{env}->{"GH_HOST"} = "github.example.com:8443";
    $result =
      run_fish( $self, "ghe_dispatch", ["test-owner/test-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply(
            calls( $self, "dispatch" )->[0]->{"args"}->[0],
            "https://github.example.com:8443/test-owner/test-repo.git"
          )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_ghe_accepts_configured_host_transports {
    my ($self) = @_;
    my ( $host, $hostname, $result, $transport, $transports, $url, $value );
    for $host (
        @{
            [
                "test-owner",             "github.example.com",
                "github.example.com:443", "github.example.com:80",
                "github.example.com:8443"
            ]
        }
      )
    {
        $self->{env}->{"GH_HOST"} = $host;
        $hostname                 = split_literal( $host, ":" )->[0];
        $url                      = ( ( "https://" . $host ) . "/test-owner/test-repo" );
        $transports               = [
            ( $url . ".git" ),
            ( ( "http://" . $host ) . "/test-owner/test-repo.git" ),
            ( ( "git\@" . $hostname ) . ":test-owner/test-repo.git" ),
            ( ( "ssh://git\@" . $hostname ) . ":2222/test-owner/test-repo.git" )
        ];
        $self->{env}->{"TEST_EXTRA_URLS"} = encode_json($transports);
        for $transport ( @{$transports} ) {
            git( $self, $self->{checkout}, [ "remote", "set-url", "origin", $transport ], 1 );
            for $value ( @{ [ "test-owner/test-repo", $transport, ( $url . "/blob/main/file.txt" ) ] } ) {
                {
                    $result = run_fish( $self, "ghe", [$value], undef, 1, undef, undef, [ "", "", "", "" ] );
                    assert_success( $self, $result );
                    ( is_deeply( $result->{directory}, $self->{checkout} ) or die "assertion failed\n" );
                    ( is_deeply( network_calls($self), [] )                or die "assertion failed\n" );
                }
            }
        }
    }
}

sub test_ghe_clones_from_configured_host {
    my ($self) = @_;
    my ( $call, $host, $result, $url );
    $host = "github.example.com";
    $url  = ( ( "https://" . $host ) . "/test-owner/test-repo.git" );
    do {
        my $updates =
          { "GH_HOST" => $host, "TEST_EXTRA_URLS" => encode_json( [$url] ) };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    remove_tree( $self->{checkout} );
    $result = run_fish( $self, "ghe", ["test-owner/test-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "remote", "get-url", "origin" ], 1 )->{stdout} ),
            $url )
          or die "assertion failed\n"
    );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ network_calls($self) } ], ["clone"] )
          or die "assertion failed\n"
    );
    ( is_deeply( $result->{directory}, $self->{checkout} ) or die "assertion failed\n" );
}

sub test_ghe_adds_configured_host_to_checkout_without_remotes {
    my ($self) = @_;
    my ($result);
    $self->{env}->{"GH_HOST"} = "github.example.com";
    git( $self, $self->{checkout}, [ "remote", "remove", "origin" ], 1 );
    $result = run_fish( $self, "ghe", ["test-owner/test-repo"], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "remote", "get-url", "origin" ], 1 )->{stdout} ),
            "https://github.example.com/test-owner/test-repo.git" )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_ghe_distinguishes_repositories_on_different_hosts {
    my ($self) = @_;
    my ( $enterprise, $public, $result );
    $self->{env}->{"GH_HOST"} = "github.example.com";
    $result = run_fish( $self, "ghe", ["test-owner/test-repo"], undef, 1, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                         or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "destination does not match" ) ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] )                                   or die "assertion failed\n" );

    # An explicit public GitHub URL still selects its own host.
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( $result->{directory}, $self->{checkout} ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] )                or die "assertion failed\n" );
    $public = run_fish( $self, "__gh_compare_cache", [ ( $self->{url} . ".git" ), $self->{checkout} ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    $enterprise =
      run_fish( $self, "__gh_compare_cache",
        [ "https://github.example.com/test-owner/test-repo.git", $self->{checkout} ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $public );
    assert_success( $self, $enterprise );
    ( ok( !equal_values( $public->{stdout}, $enterprise->{stdout} ) ) or die "assertion failed\n" );
}

sub test_ghe_api_routes_use_configured_host {
    my ($self) = @_;
    my ( $endpoint, $host, $response, $result, $tail, $url );
    $host = "github.example.com:8443";
    $url  = ( ( "https://" . $host ) . "/test-owner/test-repo" );
    do {
        my $updates = {
            "GH_HOST"         => $host,
            "TEST_EXTRA_URLS" => encode_json( [ ( $url . ".git" ) ] )
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    git( $self, $self->{checkout}, [ "remote", "set-url", "origin", ( $url . ".git" ) ], 1 );
    for my $item_548 (
        @{
            [
                [ "releases/latest", "repos/test-owner/test-repo/releases/latest", "v1" ],
                [
                    "pull/7/files",
                    "repos/test-owner/test-repo/pulls/7",
                    (
                        (
                            $self->{initial} . '
'
                        )
                        . $self->{initial}
                    )
                ]
            ]
        }
      )
    {
        $tail     = ($item_548)->[0];
        $endpoint = ($item_548)->[1];
        $response = ($item_548)->[2];
        {
            $result = run_fish(
                $self, "ghe", [ ( ( $url . "/" ) . $tail ) ],
                undef, 0,     undef,
                { $endpoint => $response },
                [ "", "", "", "" ]
            );
            assert_success( $self, $result );
            (
                is_deeply( array_slice( calls( $self, "gh" )->[0]->{"args"}, undef, 3 ),
                    [ "api", "--hostname", $host ] )
                  or die "assertion failed\n"
            );
        }
    }
    git( $self, $self->{checkout}, [ "remote", "set-url", "origin", ( $self->{url} . ".git" ) ], 1 );
    $endpoint = "repos/test-owner/test-repo/releases/latest";
    $result   = run_fish(
        $self, "ghe", [ ( $self->{url} . "/releases/latest" ) ],
        undef, 0,     undef,
        { $endpoint => "v1" },
        [ "", "", "", "" ]
    );
    assert_success( $self, $result );
    (
        is_deeply( array_slice( calls( $self, "gh" )->[0]->{"args"}, undef, 3 ),
            [ "api", "--hostname", "github.com" ] )
          or die "assertion failed\n"
    );
}

sub test_direct_url_preserves_query_and_fragment {
    my ($self) = @_;
    my ( $result, $value );
    $value  = ( $self->{url} . "/blob/main/a%20b%23.txt?plain=1#L2-L4" );
    $result = run_fish( $self, "gho", [$value], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( calls( $self, "open" )->[0]->{"args"}, [$value] ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self),                  [] )       or die "assertion failed\n" );
}

sub test_gho_opens_unknown_remote_pages_directly {
    my ($self) = @_;
    my ( $call, $opened, $suffix );
    for $suffix (
        @{
            [
                "/tree/not-pushed", "/blob/not-pushed/missing.txt",
                "/pull/999999",     "/issues/999999",
                "/compare/missing...also-missing"
            ]
        }
      )
    {
        {
            $opened = run_fish( $self, "gho", [ ( $self->{url} . $suffix ) ],
                undef, 0, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            (
                is_deeply( calls( $self, "open" )->[0]->{"args"}, [ ( $self->{url} . $suffix ) ] )
                  or die "assertion failed\n"
            );
            ( is_deeply( calls( $self, "git" ), [] ) or die "assertion failed\n" );
        }
    }
    $opened =
      run_fish( $self, "gho", ["unknown-owner/unknown-repo"], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    (
        is_deeply( trim( $opened->{stdout} ), "https://github.com/unknown-owner/unknown-repo" )
          or die "assertion failed\n"
    );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ calls( $self, "git" ) } ], ["ls-files"] )
          or die "assertion failed\n"
    );
}

sub test_rejects_traversal_without_side_effects {
    my ($self) = @_;
    my ( $command, $result );
    for $command ( @{ [ "ghe", "gho" ] } ) {
        {
            $result = run_fish( $self, $command, [ ( $self->{url} . "/blob/main/%2e%2e/escape" ) ],
                undef, 0, undef, undef, [ "", "", "", "" ] );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
            (
                is_deeply( [ @{ calls( $self, "open" ) }, @{ calls( $self, "editor" ) } ], [] )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_rejects_controls_in_configured_host_without_side_effects {
    my ($self) = @_;
    my ( $command, $host, $result );
    for $host (
        @{
            [
                'github.
example.com', "github.example.com\r", "github.\texample.com"
            ]
        }
      )
    {
        $self->{env}->{"GH_HOST"} = $host;
        for $command ( @{ [ "ghe", "gho" ] } ) {
            {
                $result =
                  run_fish( $self, $command, ["test-owner/test-repo"], undef, 0, undef, undef,
                    [ "", "", "", "" ] );
                ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
                (
                    ok( contains_value( $result->{stderr}, "invalid GitHub hostname" ) )
                      or die "assertion failed\n"
                );
                ( is_deeply( $result->{stdout},     "" ) or die "assertion failed\n" );
                ( is_deeply( calls( $self, undef ), [] ) or die "assertion failed\n" );
            }
        }
    }
}

sub test_ghe_rejects_git_metadata_paths {
    my ($self) = @_;
    my ( $result, $suffix );
    git( $self, undef, [ "init", "--quiet", join_path( $self->{checkout}, "nested" ) ], 1 );
    for $suffix ( @{ [ "blob/main/.git/config", "tree/main/nested/%2egit", "raw/main/.GiT/config" ] } ) {
        {
            $result = run_fish( $self, "ghe", [ ( ( $self->{url} . "/" ) . $suffix ) ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "cannot address Git metadata" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( $result->{directory},     $self->{sandbox} ) or die "assertion failed\n" );
            ( is_deeply( calls( $self, "editor" ), [] )               or die "assertion failed\n" );
            ( is_deeply( network_calls($self),     [] )               or die "assertion failed\n" );
        }
    }
}

sub test_local_default_root_and_escaped_file_urls {
    my ($self) = @_;
    my ($result);
    $result = run_fish( $self, "gho", [], $self->{checkout}, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( calls( $self, "open" )->[0]->{"args"}, [ $self->{url} ] ) or die "assertion failed\n" );
    $result = run_fish( $self, "gho", [ join_path( $self->{checkout}, "a b#.txt" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"}, [ ( $self->{url} . "/blob/main/a%20b%23.txt" ) ] )
          or die "assertion failed\n"
    );
}

sub alias_checkout {
    my ( $self, $name ) = @_;
    $self->{checkout} = join_path( join_path( join_path( $self->{sandbox}, "code" ), "test-owner" ), $name );
    git( $self, undef,             [ "clone", "--quiet", $self->{remote}, $self->{checkout} ],       1 );
    git( $self, $self->{checkout}, [ "remote", "set-url", "origin", ( $self->{url} . ".git" ) ],     1 );
    git( $self, $self->{checkout}, [ "update-ref", "--no-deref", "-d", "refs/remotes/origin/HEAD" ], 1 );
}

sub test_alias_writes_preserve_overlapping_loose_and_packed_tracking_refs {
    my ($self) = @_;
    my ( $after, $index, $mappings, $packed, $result, $spec, $tracking, $writer );
    $mappings = [
        [ "+refs/heads/main:refs/remotes/origin/HEAD", "refs/remotes/origin/HEAD" ],
        [ "+refs/heads/*:refs/remotes/origin/HEAD/*",  "refs/remotes/origin/HEAD/main" ],
        [ "+refs/heads/main:refs/remotes/origin",      "refs/remotes/origin" ],
        [ "+refs/heads/main:refs/remotes/origin/head", "refs/remotes/origin/head" ],
        [ "+refs/heads/*:refs/remotes/origin/head/*",  "refs/remotes/origin/head/main" ],
        [ "+refs/heads/main:refs/remotes/Origin",      "refs/remotes/Origin" ]
    ];
    for $writer ( @{ [ "gho", "__ghe_compare_ref" ] } ) {
        for $packed ( @{ [ 0, 1 ] } ) {
            for my $item_638 ( @{ enumerate_list($mappings) } ) {
                $index    = ($item_638)->[0];
                $spec     = ( ($item_638)->[1] )->[0];
                $tracking = ( ($item_638)->[1] )->[1];
                {
                    alias_checkout( $self, sprintf( "overlap-%s-%s-%d", $writer, $packed, $index ) );
                    git( $self, $self->{checkout}, [ "update-ref", "-d", "refs/remotes/origin/main" ], 1 );
                    git( $self, $self->{checkout},
                        [ "config", "--replace-all", "remote.origin.fetch", $spec ], 1 );
                    fetch_fixture($self);
                    if ($packed) {
                        git( $self, $self->{checkout}, [ "pack-refs", "--all", "--prune" ], 1 );
                    }
                    if ( ( ( $writer eq "gho" ) ) ) {
                        $result =
                          run_fish( $self, "gho", [], $self->{checkout}, 0,
                            undef, undef, [ "", "", "", "" ] );
                    }
                    else {
                        $result =
                          run_fish( $self, $writer, [ ( $self->{url} . ".git" ), $self->{checkout}, "HEAD" ],
                            undef, 0, undef, undef, [ "", "", "", "" ] );
                    }
                    assert_success( $self, $result );
                    $after = git( $self, $self->{checkout}, [ "rev-parse", "--verify", $tracking ], 0 );
                    ( is_deeply( $after->{returncode}, 0, $after->{stderr} ) or die "assertion failed\n" );
                    ( is_deeply( trim( $after->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
                    (
                        ok(
                            !equal_values(
                                git( $self, $self->{checkout}, [ "symbolic-ref", "--quiet", $tracking ], 0 )
                                  ->{returncode},
                                0
                            )
                          )
                          or die "assertion failed\n"
                    );
                    fetch_fixture($self);
                    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
                }
            }
        }
    }
}

sub test_alias_writes_preserve_another_remotes_loose_and_packed_tracking_ref {
    my ($self) = @_;
    my ( $after, $index, $packed, $result, $rule, $topic, $tracking, $writer );
    $topic = seed_commit(
        $self,
        {
            "file.txt" => 'another branch
'
        },
        "topic",
        1
    );
    for $writer ( @{ [ "gho", "__ghe_compare_ref" ] } ) {
        for $packed ( @{ [ 0, 1 ] } ) {
            for my $item_664 (
                @{ enumerate_list( [ "refs/remotes/origin/HEAD", "refs/remotes/origin/head" ] ) } )
            {
                $index    = ($item_664)->[0];
                $tracking = ($item_664)->[1];
                {
                    alias_checkout( $self, sprintf( "other-%s-%s-%d", $writer, $packed, $index ) );
                    git( $self, $self->{checkout}, [ "remote", "add", "aaa", ( $self->{url} . ".git" ) ], 1 );
                    git(
                        $self,
                        $self->{checkout},
                        [
                            "config", "--replace-all",
                            "remote.aaa.fetch", ( "+refs/heads/topic:" . $tracking )
                        ],
                        1
                    );
                    $rule = ( ( ( ( "url." . file_uri( $self->{remote} ) ) . ".insteadOf=" ) . $self->{url} )
                        . ".git" );
                    git( $self, $self->{checkout}, [ "-c", $rule, "fetch", "--quiet", "aaa" ], 1 );
                    if ($packed) {
                        git( $self, $self->{checkout}, [ "pack-refs", "--all", "--prune" ], 1 );
                    }
                    if ( ( ( $writer eq "gho" ) ) ) {
                        $result =
                          run_fish( $self, "gho", [], $self->{checkout}, 0,
                            undef, undef, [ "", "", "", "" ] );
                    }
                    else {
                        $result =
                          run_fish( $self, $writer, [ ( $self->{url} . ".git" ), $self->{checkout}, "HEAD" ],
                            undef, 0, undef, undef, [ "", "", "", "" ] );
                    }
                    assert_success( $self, $result );
                    $after = git( $self, $self->{checkout}, [ "rev-parse", "--verify", $tracking ], 0 );
                    ( is_deeply( $after->{returncode}, 0, $after->{stderr} ) or die "assertion failed\n" );
                    ( is_deeply( trim( $after->{stdout} ), $topic ) or die "assertion failed\n" );
                    (
                        ok(
                            !equal_values(
                                git( $self, $self->{checkout}, [ "symbolic-ref", "--quiet", $tracking ], 0 )
                                  ->{returncode},
                                0
                            )
                          )
                          or die "assertion failed\n"
                    );
                    git( $self, $self->{checkout}, [ "-c", $rule, "fetch", "--quiet", "aaa" ], 1 );
                    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
                }
            }
        }
    }
}

sub test_alias_writes_leave_reserved_fetch_destinations_available {
    my ($self) = @_;
    my ( $alias, $cases, $index, $name, $result, $rule, $target, $topic, $writer );
    $topic = seed_commit(
        $self,
        {
            "file.txt" => 'topic branch
'
        },
        "topic",
        1
    );
    $alias = "refs/remotes/origin/HEAD";
    $rule  = ( ( ( ( "url." . file_uri( $self->{remote} ) ) . ".insteadOf=" ) . $self->{url} ) . ".git" );
    $cases = [
        map {
            my $writer = $_;
            map { my $name = $_; [ $writer, $name, $alias ] } @{ [ "origin", "other" ] }
        } @{ [ "gho", "__ghe_compare_ref" ] }
    ];
    push(
        @{$cases},
        @{
            [
                [ "gho", "other", "refs/remotes/origin/head" ],
                [ "__ghe_compare_ref", "origin", ( $alias . "/topic" ) ]
            ]
        }
    );
    for my $item_695 ( @{ enumerate_list($cases) } ) {
        $index  = ($item_695)->[0];
        $writer = ( ($item_695)->[1] )->[0];
        $name   = ( ($item_695)->[1] )->[1];
        $target = ( ($item_695)->[1] )->[2];
        {
            alias_checkout( $self, sprintf( "reserved-%d", $index ) );
            if ( ( ( $name eq "other" ) ) ) {
                git( $self, $self->{checkout}, [ "remote", "add", $name, ( $self->{url} . ".git" ) ], 1 );
                git( $self, $self->{checkout}, [ "config", "--unset-all", "remote.other.fetch" ],     1 );
            }
            git( $self, $self->{checkout},
                [ "config", "--add", ( "remote." . $name . ".fetch" ), ( "+refs/heads/topic:" . $target ) ],
                1 );
            if ( ( ( $writer eq "gho" ) ) ) {
                $result =
                  run_fish( $self, $writer, [], $self->{checkout}, 0, undef, undef, [ "", "", "", "" ] );
            }
            else {
                $result = run_fish( $self, $writer, [ ( $self->{url} . ".git" ), $self->{checkout}, "HEAD" ],
                    undef, 0, undef, undef, [ "", "", "", "" ] );
            }
            assert_success( $self, $result );
            (
                ok(
                    !equal_values(
                        git( $self, $self->{checkout}, [ "show-ref", "--verify", "--quiet", $alias ], 0 )
                          ->{returncode},
                        0
                    )
                  )
                  or die "assertion failed\n"
            );
            git( $self, $self->{checkout}, [ "-c", $rule, "fetch", "--quiet", $name, "topic" ], 1 );
            (
                is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $target ], 1 )->{stdout} ),
                    $topic )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    trim(
                        git( $self, $self->{checkout}, [ "rev-parse", "refs/remotes/origin/main" ], 1 )
                          ->{stdout}
                    ),
                    $self->{initial}
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_default_refresh_releases_a_reserved_existing_symbolic_alias {
    my ($self) = @_;
    my ( $alias, $name, $result, $topic, $tracking );
    $topic = seed_commit(
        $self,
        {
            "file.txt" => 'topic branch
'
        },
        "topic",
        1
    );
    $tracking = "refs/remotes/origin/main";
    for $name ( @{ [ "origin", "aaa" ] } ) {
        {
            alias_checkout( $self, ( "reserved-existing-" . $name ) );
            if ( ( ( $name ne "origin" ) ) ) {
                git( $self, $self->{checkout}, [ "remote", "add", $name, ( $self->{url} . ".git" ) ], 1 );
                git(
                    $self,
                    $self->{checkout},
                    [
                        "config", "--replace-all",
                        ( "remote." . $name . ".fetch" ), ( "+refs/heads/main:" . $tracking )
                    ],
                    1
                );
            }
            $alias = ( "refs/remotes/" . $name . "/HEAD" );
            git( $self, $self->{checkout}, [ "symbolic-ref", $alias, $tracking ], 1 );
            git( $self, $self->{checkout}, [ "remote", "add", "other", file_uri( $self->{seed} ) ], 1 );
            git( $self, $self->{checkout},
                [ "config", "--replace-all", "remote.other.fetch", ( "+refs/heads/topic:" . $alias ) ], 1 );
            (
                is_deeply( trim( git( $self, $self->{checkout}, [ "symbolic-ref", $alias ], 1 )->{stdout} ),
                    $tracking )
                  or die "assertion failed\n"
            );
            git( $self, $self->{checkout}, [ "fetch", "--quiet", "other", "topic" ], 1 );
            (
                is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $tracking ], 1 )->{stdout} ),
                    $topic )
                  or die "assertion failed\n"
            );
            $result = run_fish( $self, "gho", [ join_path( $self->{checkout}, "file.txt" ) ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            (
                is_deeply( calls( $self, "open" )->[0]->{"args"},
                    [ ( $self->{url} . "/blob/main/file.txt" ) ] )
                  or die "assertion failed\n"
            );
            $result =
              run_fish( $self, "__ghe_compare_ref",
                [ ( $self->{url} . ".git" ), $self->{checkout}, "heads/main" ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            $result =
              run_fish( $self, "__ghe_compare_ref",
                [ ( $self->{url} . ".git" ), $self->{checkout}, "HEAD", "cached" ],
                undef, 0, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            ( is_deeply( trim( $result->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $tracking ], 1 )->{stdout} ),
                    $self->{initial} )
                  or die "assertion failed\n"
            );
            (
                ok(
                    !equal_values(
                        git( $self, $self->{checkout}, [ "show-ref", "--verify", "--quiet", $alias ], 0 )
                          ->{returncode},
                        0
                    )
                  )
                  or die "assertion failed\n"
            );
            git( $self, $self->{checkout}, [ "fetch", "--quiet", "other", "topic" ], 1 );
            (
                is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $alias ], 1 )->{stdout} ),
                    $topic )
                  or die "assertion failed\n"
            );
            (
                is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $tracking ], 1 )->{stdout} ),
                    $self->{initial} )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_gho_roots_open_the_homepage_or_branch_without_pr_detection {
    my ($self) = @_;
    my ( $arguments, $branch, $cwd, $expected, $result );
    for my $item_750 ( @{ [ [ "main", $self->{url} ], [ "topic", ( $self->{url} . "/tree/topic" ) ] ] } ) {
        $branch   = ($item_750)->[0];
        $expected = ($item_750)->[1];
        if ( ( ( $branch eq "topic" ) ) ) {
            git( $self, $self->{checkout},
                [ "update-ref", "refs/remotes/origin/topic", $self->{initial} ], 1 );
            git( $self, $self->{checkout},
                [ "switch", "--quiet", "--create", "topic", "--track", "origin/topic" ], 1 );
        }
        for my $item_754 ( @{ [ [ [], $self->{checkout} ], [ [ $self->{checkout} ], $self->{sandbox} ] ] } ) {
            $arguments = ($item_754)->[0];
            $cwd       = ($item_754)->[1];
            {
                $result = run_fish(
                    $self,
                    ( [ "gho", @{$arguments} ] )->[0],
                    array_slice( [ "gho", @{$arguments} ], 1, undef ),
                    $cwd, 1, undef, undef, [ "", "", "", "" ]
                );
                assert_success( $self, $result );
                ( is_deeply( trim( $result->{stdout} ), $expected ) or die "assertion failed\n" );
                (
                    is_deeply( calls( $self, "open" )->[0]->{"args"}, [$expected] )
                      or die "assertion failed\n"
                );
                ( is_deeply( $result->{directory}, $cwd ) or die "assertion failed\n" );
                ( is_deeply( calls( $self, "gh" ), [] )   or die "assertion failed\n" );
                ( is_deeply( network_calls($self), [] )   or die "assertion failed\n" );
            }
        }
    }
}

sub test_gho_local_modes_use_at_most_five_metadata_commands {
    my ($self) = @_;
    my ( $call, $commands, $opened, $target );
    for $target (
        @{
            [
                $self->{checkout},
                join_path( $self->{checkout}, "dir" ),
                join_path( $self->{checkout}, "file.txt" )
            ]
        }
      )
    {
        {
            $opened = run_fish( $self, "gho", [$target], undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            $commands = calls( $self, "git" );
            ( cmp_ok( scalar( @{$commands} ), "<=", 5 ) or die "assertion failed\n" );
            (
                ok(
                    !(
                        grep {
                            !contains_value( [ "rev-parse", "symbolic-ref", "config", "remote", "ls-files" ],
                                $_ )
                        } @{ unique_values( [ map { my $call = $_; $call->{"command"} } @{$commands} ] ) }
                    )
                  )
                  or die "assertion failed\n"
            );
            (
                ok(
                    !(
                        0 + !!(
                            grep { $_ } @{
                                [
                                    map {
                                        my $call = $_;
                                        ( contains_value( $call->{"args"}, "--verify" ) )
                                    } @{$commands}
                                ]
                            }
                        )
                    )
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_gho_handles_unborn_and_detached_roots {
    my ($self) = @_;
    my ( $opened, $unborn );
    $unborn = join_path( $self->{sandbox}, "unborn" );
    git( $self, undef, [ "init", "--quiet", "--initial-branch=main", $unborn ], 1 );
    git( $self, $unborn, [ "remote", "add", "origin", ( $self->{url} . ".git" ) ], 1 );
    $opened = run_fish( $self, "gho", [], $unborn, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    ( is_deeply( trim( $opened->{stdout} ), $self->{url} ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self),      [] )           or die "assertion failed\n" );
    git( $self, $self->{checkout}, [ "switch", "--quiet", "--detach", $self->{initial} ], 1 );
    $opened = run_fish( $self, "gho", [], $self->{checkout}, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    (
        is_deeply( trim( $opened->{stdout} ), ( ( $self->{url} . "/tree/" ) . $self->{initial} ) )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_gho_linked_worktree_uses_its_own_branch_and_shared_default {
    my ($self) = @_;
    my ( $opened, $worktree );
    $worktree = join_path( $self->{sandbox}, "topic-worktree" );
    git( $self, $self->{checkout}, [ "update-ref", "refs/remotes/origin/topic", $self->{initial} ], 1 );
    git( $self, $self->{checkout},
        [ "worktree", "add", "--quiet", "--track", "-b", "topic", $worktree, "origin/topic" ], 1 );
    $opened = run_fish( $self, "gho", [], $worktree, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    ( is_deeply( trim( $opened->{stdout} ), ( $self->{url} . "/tree/topic" ) ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self),      [] )                               or die "assertion failed\n" );
    git( $self, $self->{checkout},
        [ "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/topic" ], 1 );
    $opened = run_fish( $self, "gho", [], $worktree, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    ( is_deeply( trim( $opened->{stdout} ), $self->{url} ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self),      [] )           or die "assertion failed\n" );
    ( cmp_ok( scalar( @{ calls( $self, "git" ) } ), "<=", 5 ) or die "assertion failed\n" );
}

sub test_gho_ignores_overlapping_fetch_mappings {
    my ($self) = @_;
    my ( $expected, $opened, $target );
    git( $self, $self->{checkout}, [ "remote", "add", "origin.extra", ( $self->{url} . ".git" ) ], 1 );
    git(
        $self,
        $self->{checkout},
        [
            "config",                    "--replace-all",
            "remote.origin.extra.fetch", "+refs/heads/topic:refs/remotes/origin/main"
        ],
        1
    );
    git( $self, $self->{checkout},
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:refs/tags/local-copy" ], 1 );
    for my $item_821 (
        @{
            [
                [ $self->{checkout}, $self->{url} ],
                [ join_path( $self->{checkout}, "file.txt" ), ( $self->{url} . "/blob/main/file.txt" ) ]
            ]
        }
      )
    {
        $target   = ($item_821)->[0];
        $expected = ($item_821)->[1];
        {
            $opened = run_fish( $self, "gho", [$target], undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            ( is_deeply( trim( $opened->{stdout} ),             $expected )   or die "assertion failed\n" );
            ( is_deeply( calls( $self, "open" )->[0]->{"args"}, [$expected] ) or die "assertion failed\n" );
        }
    }
}

sub test_gho_rechecks_default_and_fetch_mapping_between_calls {
    my ($self) = @_;
    my ( $call, $opened, $script );
    git( $self, $self->{checkout}, [ "update-ref", "refs/remotes/origin/topic", $self->{initial} ], 1 );
    $script = (
        (
            'gho
command git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/topic
gho
command git config --replace-all remote.origin.fetch +refs/heads/main:refs/cache/origin/main
command git update-ref refs/cache/origin/main ' . $self->{initial}
        )
        . '
command git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
gho'
    );
    $opened = run_fish( $self, $script, [], $self->{checkout}, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    (
        is_deeply( [ split( /\n/, $opened->{stdout} ) ],
            [ $self->{url}, ( $self->{url} . "/tree/main" ), $self->{url} ] )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            [ map { my $call = $_; $call->{"args"} } @{ calls( $self, "open" ) } ],
            [ [ $self->{url} ], [ ( $self->{url} . "/tree/main" ) ], [ $self->{url} ] ]
          )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_gho_does_not_need_cached_commit_objects {
    my ($self) = @_;
    my ( $expected, $opened, $target );
    remove_tree( join_path( join_path( $self->{checkout}, ".git" ), "objects" ) );
    make_path( join_path( join_path( $self->{checkout}, ".git" ), "objects" ) );
    for my $item_850 (
        @{
            [
                [ $self->{checkout}, $self->{url} ],
                [ join_path( $self->{checkout}, "file.txt" ), ( $self->{url} . "/blob/main/file.txt" ) ]
            ]
        }
      )
    {
        $target   = ($item_850)->[0];
        $expected = ($item_850)->[1];
        {
            $opened = run_fish( $self, "gho", [$target], undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            ( is_deeply( trim( $opened->{stdout} ), $expected ) or die "assertion failed\n" );
        }
    }
}

sub test_gho_never_refreshes_a_missing_or_dangling_default_alias {
    my ($self) = @_;
    my ( $alias, $default, $expected, $offline, $opened, $root_url, $target );
    $alias = "refs/remotes/origin/HEAD";
    git( $self, $self->{checkout}, [ "update-ref", "-d", "refs/remotes/origin/main" ], 1 );
    for $default ( @{ [ "", "refs/remotes/origin/master", "refs/remotes/origin/main" ] } ) {
        if ($default) {
            git( $self, $self->{checkout}, [ "symbolic-ref", $alias, $default ], 1 );
        }
        else {
            git( $self, $self->{checkout}, [ "symbolic-ref", "--delete", $alias ], 1 );
        }
        $root_url = (
            ( 0 + ( !($default) ) || ( substr( $default, -length("/main") ) eq "/main" ) )
            ? $self->{url}
            : ( $self->{url} . "/tree/main" )
        );
        for $offline ( @{ [ 0, 1 ] } ) {
            for my $item_867 (
                @{
                    [
                        [ $self->{checkout}, $root_url ],
                        [
                            join_path( $self->{checkout}, "file.txt" ),
                            ( $self->{url} . "/blob/main/file.txt" )
                        ]
                    ]
                }
              )
            {
                $target   = ($item_867)->[0];
                $expected = ($item_867)->[1];
                {
                    $opened =
                      run_fish( $self, "gho", [$target], undef, $offline, undef, undef, [ "", "", "", "" ] );
                    assert_success( $self, $opened );
                    ( is_deeply( trim( $opened->{stdout} ), $expected ) or die "assertion failed\n" );
                    (
                        is_deeply(
                            trim(
                                git( $self, $self->{checkout}, [ "symbolic-ref", "--quiet", $alias ], 0 )
                                  ->{stdout}
                            ),
                            $default
                          )
                          or die "assertion failed\n"
                    );
                }
            }
        }
    }
}

sub test_gho_default_fallback_only_applies_to_main_and_master_roots {
    my ($self) = @_;
    my ( $alias, $branch, $default, $expected, $homepage, $opened, $root_url, $target );
    $alias = "refs/remotes/origin/HEAD";
    for $branch ( @{ [ "main", "master", "topic" ] } ) {
        if ( ( ( $branch ne "main" ) ) ) {
            git( $self, $self->{checkout}, [ "switch", "--quiet", "--create", $branch ], 1 );
        }
        for $default ( @{ [ "", "refs/remotes/origin/develop" ] } ) {
            git( $self, $self->{checkout}, [ "symbolic-ref", "--delete", $alias ], 0 );
            if ($default) {
                git( $self, $self->{checkout}, [ "symbolic-ref", $alias, $default ], 1 );
            }
            $homepage =
              ( 0 + ( !($default) ) && ( contains_value( [ "main", "master" ], $branch ) ) );
            $root_url = (
                  $homepage
                ? $self->{url}
                : ( ( $self->{url} . "/tree/" ) . $branch )
            );
            for my $item_887 (
                @{
                    [
                        [ $self->{checkout}, $root_url ],
                        [
                            join_path( $self->{checkout}, "dir" ),
                            ( ( ( $self->{url} . "/tree/" ) . $branch ) . "/dir" )
                        ],
                        [
                            join_path( $self->{checkout}, "file.txt" ),
                            ( ( ( $self->{url} . "/blob/" ) . $branch ) . "/file.txt" )
                        ]
                    ]
                }
              )
            {
                $target   = ($item_887)->[0];
                $expected = ($item_887)->[1];
                {
                    $opened = run_fish( $self, "gho", [$target], undef, 1, undef, undef, [ "", "", "", "" ] );
                    assert_success( $self, $opened );
                    ( is_deeply( trim( $opened->{stdout} ), $expected ) or die "assertion failed\n" );
                    (
                        is_deeply( calls( $self, "open" )->[0]->{"args"}, [$expected] )
                          or die "assertion failed\n"
                    );
                    (
                        is_deeply(
                            trim(
                                git( $self, $self->{checkout}, [ "symbolic-ref", "--quiet", $alias ], 0 )
                                  ->{stdout}
                            ),
                            $default
                          )
                          or die "assertion failed\n"
                    );
                }
            }
        }
    }
}

sub test_gho_uses_cached_default_name_when_alias_update_was_blocked {
    my ($self) = @_;
    my ( $alias, $compared, $lock, $opened );
    git( $self, $self->{seed}, [ "branch", "topic" ], 1 );
    publish( $self, ["topic"] );
    git( $self, $self->{remote}, [ "symbolic-ref", "HEAD", "refs/heads/topic" ], 1 );
    $alias = "refs/remotes/origin/HEAD";
    $lock =
      join_path( join_path( $self->{checkout}, ".git" ), ( $alias . ".lock" ) );
    write_file(
        $lock, 'held by another process
'
    );
    $compared =
      run_fish( $self, "__ghe_compare_ref", [ ( $self->{url} . ".git" ), $self->{checkout}, "HEAD" ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $compared );
    ( is_deeply( trim( $compared->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "symbolic-ref", $alias ], 1 )->{stdout} ),
            "refs/remotes/origin/main" )
          or die "assertion failed\n"
    );
    $opened = run_fish( $self, "gho", [], $self->{checkout}, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    ( is_deeply( trim( $opened->{stdout} ), $self->{url} ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self),      [] )           or die "assertion failed\n" );
    unlink($lock);
    git( $self, $self->{remote}, [ "symbolic-ref", "HEAD", "refs/heads/main" ], 1 );
    assert_success(
        $self,
        run_fish(
            $self, "__ghe_compare_ref", [ ( $self->{url} . ".git" ), $self->{checkout}, "HEAD" ],
            undef, 0, undef, undef, [ "", "", "", "" ]
        )
    );
    $opened = run_fish( $self, "gho", [], $self->{checkout}, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    ( is_deeply( trim( $opened->{stdout} ), $self->{url} ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self),      [] )           or die "assertion failed\n" );
}

sub test_default_alias_does_not_read_or_replace_a_case_folded_symref {
    my ($self) = @_;
    my ( $alias, $compared, $dangling, $refs, $target, $upper_refs );
    $refs       = join_path( join_path( $self->{checkout}, ".git" ), "refs" );
    $upper_refs = join_path( dirname($refs),                         "REFS" );
    if ( 0 + ( !( ( ( -e $upper_refs ) && same_file( $refs, $upper_refs ) ) ) ) ) {
        plan( skip_all => "requires case-folding ref paths" );
        return;
    }
    seed_commit(
        $self,
        {
            "file.txt" => 'topic branch
'
        },
        "topic",
        1
    );
    fetch_fixture($self);
    git( $self, $self->{checkout}, [ "switch", "--quiet", "--track", "origin/topic" ], 1 );
    git( $self, $self->{checkout}, [ "symbolic-ref", "--delete", "refs/remotes/origin/HEAD" ], 1 );
    $alias    = "refs/remotes/origin/head";
    $dangling = "refs/remotes/origin/missing";
    for $target ( @{ [ "refs/remotes/origin/topic", $dangling ] } ) {
        {
            git( $self, $self->{checkout}, [ "symbolic-ref", $alias, $target ], 1 );
            $compared =
              run_fish( $self, "__ghe_compare_ref", [ ( $self->{url} . ".git" ), $self->{checkout}, "HEAD" ],
                undef, 0, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $compared );
            ( is_deeply( trim( $compared->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply( trim( git( $self, $self->{checkout}, [ "symbolic-ref", $alias ], 1 )->{stdout} ),
                    $target )
                  or die "assertion failed\n"
            );
        }
    }
    git( $self, $self->{checkout},
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/topic:refs/remotes/origin/topic" ],
        1 );
    $compared =
      run_fish( $self, "__ghe_compare_ref", [ ( $self->{url} . ".git" ), $self->{checkout}, "HEAD" ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $compared );
    ( is_deeply( trim( $compared->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "symbolic-ref", $alias ], 1 )->{stdout} ),
            $dangling )
          or die "assertion failed\n"
    );
}

sub test_gho_uses_configured_upstream_without_a_tracking_ref {
    my ($self) = @_;
    my ( $expected, $opened, $publish_url, $target );
    git( $self, $self->{checkout}, [ "switch", "--quiet", "--create", "local-topic" ], 1 );
    $publish_url = "https://github.com/test-owner/published";
    git( $self, $self->{checkout}, [ "remote", "add", "publish", ( $publish_url . ".git" ) ],            1 );
    git( $self, $self->{checkout}, [ "config", "branch.local-topic.remote", "publish" ],                 1 );
    git( $self, $self->{checkout}, [ "config", "branch.local-topic.merge",  "refs/heads/review/topic" ], 1 );
    git(
        $self,
        $self->{checkout},
        [
            "config", "--replace-all", "remote.publish.fetch",
            "+refs/heads/other:refs/remotes/publish/shared"
        ],
        1
    );

    for my $item_959 (
        @{
            [
                [ $self->{checkout}, ( $publish_url . "/tree/review/topic" ) ],
                [
                    join_path( $self->{checkout}, "file.txt" ),
                    ( $publish_url . "/blob/review/topic/file.txt" )
                ]
            ]
        }
      )
    {
        $target   = ($item_959)->[0];
        $expected = ($item_959)->[1];
        {
            $opened = run_fish( $self, "gho", [$target], undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            ( is_deeply( trim( $opened->{stdout} ), $expected ) or die "assertion failed\n" );
        }
    }
}

sub test_gho_prefers_origin_then_the_only_remote_without_an_upstream {
    my ($self) = @_;
    my ($opened);
    git( $self, $self->{checkout}, [ "switch", "--quiet", "--create", "local-topic" ], 1 );
    git( $self, $self->{checkout}, [ "remote", "rename",  "origin",   "publish" ],     1 );
    $opened = run_fish( $self, "gho", [ $self->{checkout} ], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    (
        is_deeply( trim( $opened->{stdout} ), ( $self->{url} . "/tree/local-topic" ) )
          or die "assertion failed\n"
    );
    git( $self, $self->{checkout},
        [ "remote", "add", "origin", "https://github.com/test-owner/other.git" ], 1 );
    $opened = run_fish( $self, "gho", [ $self->{checkout} ], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $opened );
    (
        is_deeply( trim( $opened->{stdout} ), "https://github.com/test-owner/other/tree/local-topic" )
          or die "assertion failed\n"
    );
}

sub test_tracking_destination_shared_by_different_remotes_is_not_trusted {
    my ($self) = @_;
    my ( $args, $other, $result, $spec, $target, $topic, $tracking );
    $topic = seed_commit(
        $self,
        {
            "topic-only.txt" => 'origin topic
'
        },
        "topic",
        1
    );
    write_file(
        join_path( $self->{seed}, "other-only.txt" ), 'other topic
'
    );
    git( $self, $self->{seed}, [ "add", "other-only.txt" ], 1 );
    git( $self, $self->{seed}, [ "commit", "-qm", "other remote only" ], 1 );
    $other =
      trim( git( $self, $self->{seed}, [ "rev-parse", "HEAD" ], 1 )->{stdout} );
    $spec     = "+refs/heads/*:refs/remotes/shared/*";
    $tracking = "refs/remotes/shared/topic";
    git( $self, $self->{checkout}, [ "config", "--replace-all", "remote.origin.fetch", $spec ],       1 );
    git( $self, $self->{checkout}, [ "remote", "add",           "other", file_uri( $self->{seed} ) ], 1 );
    git( $self, $self->{checkout}, [ "config", "--replace-all", "remote.other.fetch", $spec ],        1 );
    git( $self, $self->{checkout}, [ "fetch",  "--quiet",       "other",              "topic" ],      1 );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $tracking ], 1 )->{stdout} ), $other )
          or die "assertion failed\n"
    );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/topic/other-only.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( head($self),              $self->{initial} ) or die "assertion failed\n" );
    ( is_deeply( calls( $self, "editor" ), [] )               or die "assertion failed\n" );
    $args =
      [ ( $self->{url} . ".git" ), $self->{checkout}, "refs/heads/topic" ];
    $result = run_fish(
        $self,
        ( [ "__ghe_compare_ref", @{$args} ] )->[0],
        array_slice( [ "__ghe_compare_ref", @{$args} ], 1, undef ),
        undef, 1, undef, undef, [ "", "", "", "" ]
    );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    $result = run_fish(
        $self,
        ( [ "__ghe_compare_ref", @{$args} ] )->[0],
        array_slice( [ "__ghe_compare_ref", @{$args} ], 1, undef ),
        undef, 0, undef, undef, [ "", "", "", "" ]
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $topic ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $tracking ], 1 )->{stdout} ), $other )
          or die "assertion failed\n"
    );
    git( $self, $self->{checkout}, [ "switch", "--quiet", "--create", "topic" ], 1 );
    git( $self, $self->{checkout}, [ "config", "branch.topic.remote", "origin" ],           1 );
    git( $self, $self->{checkout}, [ "config", "branch.topic.merge",  "refs/heads/topic" ], 1 );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/topic/topic-only.txt" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( head($self), $topic ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $tracking ], 1 )->{stdout} ), $other )
          or die "assertion failed\n"
    );
    $target = join_path( $self->{checkout}, "other-only.txt" );
    write_file(
        $target, 'local only
'
    );
    $result = run_fish( $self, "gho", [$target], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"},
            [ ( $self->{url} . "/blob/topic/other-only.txt" ) ] )
          or die "assertion failed\n"
    );
    $result = run_fish( $self, "gho", [ $self->{checkout} ], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"}, [ ( $self->{url} . "/tree/topic" ) ] )
          or die "assertion failed\n"
    );
    git( $self, $self->{checkout}, [ "config", "--remove-section", "remote.other" ], 1 );
    git( $self, $self->{checkout}, [ "update-ref", $tracking, $topic ], 1 );
    git( $self, $self->{checkout},
        [ "remote", "add", "mirror", "git\@github.com:TEST-OWNER/TEST-REPO.git" ], 1 );
    git( $self, $self->{checkout}, [ "config", "--replace-all", "remote.mirror.fetch", $spec ], 1 );
    $result = run_fish( $self, "gho", [ join_path( $self->{checkout}, "topic-only.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"},
            [ ( $self->{url} . "/blob/topic/topic-only.txt" ) ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_gho_opens_local_only_files_and_directories {
    my ($self) = @_;
    my ( $kind, $name, $opened );
    write_file(
        join_path( $self->{checkout}, "new-local.txt" ), 'not pushed
'
    );
    git( $self, $self->{checkout}, [ "add", "-A" ], 1 );
    git( $self, $self->{checkout}, [ "commit", "-qm", "local commit" ], 1 );
    write_file(
        join_path( $self->{checkout}, "untracked.txt" ), 'not committed
'
    );
    make_path( join_path( $self->{checkout}, "untracked-dir" ) );

    for my $item_1037 (
        @{
            [
                [ "file.txt",      "blob" ],
                [ "new-local.txt", "blob" ],
                [ "untracked.txt", "blob" ],
                [ "untracked-dir", "tree" ]
            ]
        }
      )
    {
        $name = ($item_1037)->[0];
        $kind = ($item_1037)->[1];
        {
            $opened = run_fish( $self, "gho", [ join_path( $self->{checkout}, $name ) ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            (
                is_deeply( trim( $opened->{stdout} ), ( $self->{url} . ( "/" . $kind . "/main/" . $name ) ) )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_gho_does_not_validate_fetch_destinations {
    my ($self) = @_;
    my ( $opened, $tracking );
    for $tracking ( @{ [ "refs/heads/main", "refs/tags/local-copy" ] } ) {
        {
            git( $self, $self->{checkout},
                [ "config", "--replace-all", "remote.origin.fetch", ( "+refs/heads/main:" . $tracking ) ],
                1 );
            $opened = run_fish( $self, "gho", [ join_path( $self->{checkout}, "file.txt" ) ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            (
                is_deeply( trim( $opened->{stdout} ), ( $self->{url} . "/blob/main/file.txt" ) )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_gho_opens_deleted_tracked_files {
    my ($self) = @_;
    my ( $cwd, $opened, $target );
    unlink( join_path( $self->{checkout}, "file.txt" ) );
    for my $item_1055 (
        @{
            [
                [ "file.txt",                                 $self->{checkout} ],
                [ join_path( $self->{checkout}, "file.txt" ), $self->{sandbox} ]
            ]
        }
      )
    {
        $target = ($item_1055)->[0];
        $cwd    = ($item_1055)->[1];
        {
            $opened = run_fish( $self, "gho", [$target], $cwd, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            (
                is_deeply( trim( $opened->{stdout} ), ( $self->{url} . "/blob/main/file.txt" ) )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_gho_opens_deleted_file_in_a_deleted_directory {
    my ($self) = @_;
    my ( $cwd, $opened, $target );
    remove_tree( join_path( $self->{checkout}, "dir" ) );
    for my $item_1063 (
        @{
            [
                [ "dir/nested.txt",                                 $self->{checkout} ],
                [ join_path( $self->{checkout}, "dir/nested.txt" ), $self->{sandbox} ]
            ]
        }
      )
    {
        $target = ($item_1063)->[0];
        $cwd    = ($item_1063)->[1];
        {
            $opened = run_fish( $self, "gho", [$target], $cwd, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $opened );
            (
                is_deeply( trim( $opened->{stdout} ), ( $self->{url} . "/blob/main/dir/nested.txt" ) )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_implicit_head_mapping_cannot_prove_topic_tracking {
    my ($self) = @_;
    my ( $result, $tracking );
    seed_commit(
        $self,
        {
            "file.txt" => 'topic branch
'
        },
        "topic",
        1
    );
    $tracking = "refs/remotes/origin/topic";
    git( $self, $self->{checkout},
        [ "config", "--replace-all", "remote.origin.fetch", ( "+:" . $tracking ) ], 1 );
    fetch_fixture($self);
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", $tracking ], 1 )->{stdout} ),
            $self->{initial} )
          or die "assertion failed\n"
    );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/topic/file.txt" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "mapped from another branch or ref: HEAD" ) )
          or die "assertion failed\n"
    );
    ( is_deeply( calls( $self, "editor" ), [] )               or die "assertion failed\n" );
    ( is_deeply( head($self),              $self->{initial} ) or die "assertion failed\n" );
    git( $self, $self->{checkout}, [ "switch", "--quiet", "--create", "topic" ], 1 );
    $result = run_fish( $self, "gho", [ join_path( $self->{checkout}, "file.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"}, [ ( $self->{url} . "/blob/topic/file.txt" ) ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_gho_uses_the_git_tree_spelling_for_a_decomposed_filename {
    my ($self) = @_;
    my ( $local_name, $name, $result, $target, $temporary );
    $name       = "Café.txt";
    $local_name = "Café.txt";
    seed_commit(
        $self,
        {
            $name => 'unicode filename
'
        },
        "main",
        0
    );
    fetch_fixture($self);
    git( $self, $self->{checkout}, [ "merge", "--ff-only", "origin/main" ], 1 );
    $temporary = join_path( $self->{checkout}, "temporary-name" );
    rename( join_path( $self->{checkout}, $name ), $temporary );
    $target = join_path( $self->{checkout}, $local_name );
    rename( $temporary, $target );
    if (
        (
            (
                git( $self, $self->{checkout},
                    [ "ls-tree", "-z", "--name-only", "origin/main", "--", $local_name ], 1 )->{stdout} ne
                ( $name . "\x{0000}" )
            )
        )
      )
    {
        plan( skip_all => "requires Git to precompose the path argument" );
        return;
    }
    $result = run_fish( $self, "gho", [$target], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"}, [ ( $self->{url} . "/blob/main/Caf%C3%A9.txt" ) ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_gho_opens_unpublished_branches_and_paths {
    my ($self) = @_;
    my ( $arguments, $cwd, $opened, $suffix );
    git( $self, $self->{checkout}, [ "switch", "--quiet", "--create", "unpublished" ], 1 );
    for my $item_1110 (
        @{
            [
                [ [],                                        $self->{checkout}, "/tree/unpublished" ],
                [ [ $self->{checkout} ],                     $self->{sandbox},  "/tree/unpublished" ],
                [ [ join_path( $self->{checkout}, "dir" ) ], $self->{sandbox},  "/tree/unpublished/dir" ],
                [
                    [ join_path( $self->{checkout}, "file.txt" ) ], $self->{sandbox},
                    "/blob/unpublished/file.txt"
                ]
            ]
        }
      )
    {
        $arguments = ($item_1110)->[0];
        $cwd       = ($item_1110)->[1];
        $suffix    = ($item_1110)->[2];
        {
            $opened = run_fish(
                $self,
                ( [ "gho", @{$arguments} ] )->[0],
                array_slice( [ "gho", @{$arguments} ], 1, undef ),
                $cwd, 1, undef, undef, [ "", "", "", "" ]
            );
            assert_success( $self, $opened );
            ( is_deeply( $opened->{stderr}, "" ) or die "assertion failed\n" );
            (
                is_deeply(
                    $opened->{stdout},
                    (
                        ( $self->{url} . $suffix ) . '
'
                    )
                  )
                  or die "assertion failed\n"
            );
            (
                is_deeply( calls( $self, "open" )->[0]->{"args"}, [ ( $self->{url} . $suffix ) ] )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_tracked_symlinks_open_the_link_and_installed_links_resolve {
    my ($self) = @_;
    my ( $installed, $name, $result );
    for $name ( @{ [ "linked.txt", "broken.txt" ] } ) {
        {
            $result = run_fish( $self, "gho", [ join_path( $self->{checkout}, $name ) ],
                undef, 0, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            (
                is_deeply(
                    calls( $self, "open" )->[0]->{"args"},
                    [ ( ( $self->{url} . "/blob/main/" ) . $name ) ]
                  )
                  or die "assertion failed\n"
            );
        }
    }
    $installed = join_path( $self->{sandbox}, "installed.txt" );
    symlink( join_path( $self->{checkout}, "file.txt" ), $installed );
    $result = run_fish( $self, "gho", [$installed], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"}, [ ( $self->{url} . "/blob/main/file.txt" ) ] )
          or die "assertion failed\n"
    );
}

sub test_submodule_root_opens_the_submodule_repository {
    my ($self) = @_;
    my ( $result, $sub );
    $sub = join_path( $self->{checkout}, "submodule" );
    git( $self, $self->{checkout}, [ "submodule", "add", "--quiet", $self->{remote}, "submodule" ],     1 );
    git( $self, $sub, [ "remote", "set-url", "origin", "https://github.com/test-owner/submodule.git" ], 1 );
    git( $self, $sub, [ "switch", "--quiet", "main" ],                                                  1 );
    git( $self, $sub, [ "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main" ],       1 );
    $result = run_fish( $self, "gho", [$sub], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"}, ["https://github.com/test-owner/submodule"] )
          or die "assertion failed\n"
    );
}

sub test_existing_file_and_directory_open_offline_without_network {
    my ($self) = @_;
    my ($result);
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/main/file.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"}, [ join_path( $self->{checkout}, "file.txt" ) ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/tree/main/dir" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( $result->{directory}, join_path( $self->{checkout}, "dir" ) ) or die "assertion failed\n" );
    ( is_deeply( calls( $self, "editor" ), [] )                                or die "assertion failed\n" );
    ( is_deeply( network_calls($self),     [] )                                or die "assertion failed\n" );
}

sub test_current_branch_urls_batch_checks_without_scanning_local_changes {
    my ($self) = @_;
    my ( $call, $result, $tail );

    # The case-insensitive listing must still resolve URL components exactly.
    git( $self, $self->{checkout}, [ "tag", "MAIN/file.txt" ], 1 );
    write_file(
        join_path( $self->{checkout}, "file.txt" ), 'keep local edit
'
    );
    write_file(
        join_path( $self->{checkout}, "untracked.txt" ), 'keep untracked file
'
    );
    for $tail ( @{ [ "tree/main", "blob/main/file.txt", "tree/main/dir" ] } ) {
        {
            $result = run_fish( $self, "ghe", [ ( ( $self->{url} . "/" ) . $tail ) ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            ( cmp_ok( scalar( @{ calls( $self, "git" ) } ), "<=", 3 ) or die "assertion failed\n" );
            (
                ok(
                    !(
                        scalar(
                            @{
                                [
                                    grep {
                                        contains_value(
                                            unique_values(
                                                [
                                                    map {
                                                        my $call = $_;
                                                        $call->{"command"}
                                                    } @{ calls( $self, "git" ) }
                                                ]
                                            ),
                                            $_
                                        )
                                    } @{ [ "status", "switch" ] }
                                ]
                            }
                        )
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( network_calls($self), [] )               or die "assertion failed\n" );
            ( is_deeply( head($self),          $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply(
                    read_file( join_path( $self->{checkout}, "file.txt" ) ),
                    'keep local edit
'
                  )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    read_file( join_path( $self->{checkout}, "untracked.txt" ) ),
                    'keep untracked file
'
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_current_branch_checkout_uses_linked_worktree_refs {
    my ($self) = @_;
    my ( $result, $worktree );
    $worktree = join_path( $self->{sandbox}, "topic-worktree" );
    git( $self, $self->{checkout},
        [ "worktree", "add", "--quiet", "--track", "-b", "topic", $worktree, "origin/main" ], 1 );
    $self->{checkout} = $worktree;
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/topic/file.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"}, [ join_path( $worktree, "file.txt" ) ] )
          or die "assertion failed\n"
    );
    ( cmp_ok( scalar( @{ calls( $self, "git" ) } ), "<=", 3 ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_current_branch_open_survives_missing_objects_in_ref_listing {
    my ($self) = @_;
    my ( $broken, $result );

    # Git's ref pattern includes descendants, but this tag cannot match the URL.
    $broken = join_path( $self->{checkout}, ".git/refs/tags/main/file.txt/broken" );
    make_path( dirname($broken) );
    write_file(
        $broken,
        (
            ( "1" x 40 ) . '
'
        )
    );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/main/file.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( $result->{stderr}, "" ) or die "assertion failed\n" );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"}, [ join_path( $self->{checkout}, "file.txt" ) ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_current_branch_open_rejects_dangling_case_alias_over_packed_ref {
    my ($self) = @_;
    my ( $refs, $result, $upper_refs );
    $refs       = join_path( $self->{checkout}, ".git/refs" );
    $upper_refs = join_path( dirname($refs),    "REFS" );
    if ( 0 + ( !( ( ( -e $upper_refs ) && same_file( $refs, $upper_refs ) ) ) ) ) {
        plan( skip_all => "requires case-folding ref paths" );
        return;
    }
    git( $self, $self->{checkout}, [ "pack-refs",    "--all",           "--prune" ],            1 );
    git( $self, $self->{checkout}, [ "symbolic-ref", "refs/heads/Main", "refs/heads/missing" ], 1 );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/main/file.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "local branch conflicts with a differently spelled ref" ) )
          or die "assertion failed\n"
    );
    ( is_deeply( calls( $self, "editor" ), [] ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self),     [] ) or die "assertion failed\n" );
}

sub test_repository_url_batches_remote_checks_but_honors_rewrites {
    my ($self) = @_;
    my ($result);
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( $result->{directory}, $self->{checkout} ) or die "assertion failed\n" );
    ( cmp_ok( scalar( @{ calls( $self, "git" ) } ), "<=", 2 ) or die "assertion failed\n" );
    git( $self, $self->{checkout},
        [ "config", "url.https://github.com/other-owner/.insteadOf", "https://github.com/test-owner/" ], 1 );
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 1, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                         or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "destination does not match" ) ) or die "assertion failed\n" );
    ( is_deeply( $result->{directory}, $self->{sandbox} )                     or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] )                                   or die "assertion failed\n" );
}

sub test_existing_checkout_without_remotes_adds_origin {
    my ($self) = @_;
    my ( $result, $tail );
    for $tail ( @{ [ "", "/blob/main/file.txt" ] } ) {
        {
            git( $self, $self->{checkout}, [ "remote", "remove", "origin" ], 1 );
            $result = run_fish( $self, "ghe", [ ( $self->{url} . $tail ) ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            (
                is_deeply( [ split( /\n/, git( $self, $self->{checkout}, ["remote"], 1 )->{stdout} ) ],
                    ["origin"] )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    trim( git( $self, $self->{checkout}, [ "remote", "get-url", "origin" ], 1 )->{stdout} ),
                    ( $self->{url} . ".git" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( $result->{directory}, $self->{checkout} ) or die "assertion failed\n" );
            ( is_deeply( head($self),          $self->{initial} )  or die "assertion failed\n" );
            ( is_deeply( network_calls($self), [] )                or die "assertion failed\n" );
            (
                is_deeply( 0 + !!( scalar( @{ calls( $self, "editor" ) } ) ), 0 + !!($tail) )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_unborn_checkout_without_remotes_adds_origin {
    my ($self) = @_;
    my ( $before, $note, $result );
    $self->{checkout} = join_path( $self->{sandbox}, "unborn" );
    git( $self, undef, [ "init", "--quiet", "--initial-branch=master", $self->{checkout} ], 1 );
    $note = join_path( $self->{checkout}, "note.txt" );
    write_file(
        $note, 'keep this local file
'
    );
    $before =
      git( $self, $self->{checkout}, [ "status", "--porcelain" ], 1 )->{stdout};
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( $result->{directory}, $self->{checkout} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "remote", "get-url", "origin" ], 1 )->{stdout} ),
            ( $self->{url} . ".git" ) )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ),
            "master" )
          or die "assertion failed\n"
    );
    (
        is_deeply( git( $self, $self->{checkout}, [ "status", "--porcelain" ], 1 )->{stdout}, $before )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            read_file($note), 'keep this local file
'
          )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_checkout_with_only_a_different_remote_is_not_reassigned {
    my ($self) = @_;
    my ( $other_url, $result );
    git( $self, $self->{checkout}, [ "remote", "rename", "origin", "upstream" ], 1 );
    $other_url = "https://github.com/other-owner/other-repo.git";
    git( $self, $self->{checkout}, [ "remote", "set-url", "upstream", $other_url ], 1 );
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 1, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                         or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "destination does not match" ) ) or die "assertion failed\n" );
    (
        is_deeply(
            [ split( /\n/, git( $self, $self->{checkout}, ["remote"], 1 )->{stdout} ) ], ["upstream"]
          )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "remote", "get-url", "upstream" ], 1 )->{stdout} ),
            $other_url )
          or die "assertion failed\n"
    );
    ( is_deeply( $result->{directory}, $self->{sandbox} ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] )               or die "assertion failed\n" );
}

sub test_repository_url_does_not_use_git_config_override_for_remote_identity {
    my ($self) = @_;
    my ( $config, $result );
    $config = join_path( $self->{root}, "override.config" );
    write_file(
        $config,
        (
            '[remote "origin"]
    url = ' . $self->{url} . '.git
    fetch = +refs/heads/*:refs/remotes/origin/*
'
        )
    );
    git( $self, $self->{checkout},
        [ "remote", "set-url", "origin", "https://github.com/other-owner/test-repo.git" ], 1 );
    $self->{env}->{"GIT_CONFIG"} = $config;
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 1, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                         or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "destination does not match" ) ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] )                                   or die "assertion failed\n" );
}

sub test_comparison_of_local_commit_ids_skips_remote_metadata {
    my ($self) = @_;
    my ( $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'comparison content
'
        },
        "main",
        0
    );
    fetch_fixture($self);
    $result =
      run_fish( $self, "ghe", [ ( $self->{url} . "/compare/" . $self->{initial} . ".." . $revision ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        ok(
            contains_value(
                $result->{stdout}, '+comparison content
'
            )
          )
          or die "assertion failed\n"
    );
    ( cmp_ok( scalar( @{ calls( $self, "git" ) } ), "<=", 5 ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_longer_cached_branch_wins_over_a_shorter_local_ref {
    my ($self) = @_;
    my ( $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'long branch
'
        },
        "topic/long",
        1
    );
    git( $self, $self->{checkout}, [ "tag", "topic" ], 1 );
    fetch_fixture($self);
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/topic/long/file.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ),
            "topic/long" )
          or die "assertion failed\n"
    );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"}, [ join_path( $self->{checkout}, "file.txt" ) ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_local_tag_wins_over_a_cached_branch_with_the_same_name {
    my ($self) = @_;
    my ($result);
    seed_commit(
        $self,
        {
            "file.txt" => 'branch version
'
        },
        "topic",
        1
    );
    git( $self, $self->{checkout}, [ "tag", "topic" ], 1 );
    fetch_fixture($self);
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/topic/file.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ), "" )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_url_does_not_traverse_a_symlink_in_its_path {
    my ($self) = @_;
    my ( $link, $outside, $result );
    $outside = join_path( dirname( $self->{checkout} ), "outside" );
    make_path( join_path( $outside, "subdir" ) );
    $link = join_path( $self->{checkout}, "linked-dir" );
    symlink( "../outside", $link );
    git( $self, $self->{checkout}, [ "add", "linked-dir" ], 1 );
    git( $self, $self->{checkout}, [ "commit", "-qm", "add directory symlink" ], 1 );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/tree/main/linked-dir/subdir" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ), $result->{directory} ) or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "path traverses a symlink" ) ) or die "assertion failed\n" );
    ( is_deeply( $result->{directory}, $self->{sandbox} )                   or die "assertion failed\n" );
    ( is_deeply( calls( $self, "editor" ), [] )                             or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] )                                 or die "assertion failed\n" );
}

sub test_new_clone_is_not_fetched_again {
    my ($self) = @_;
    my ( $call, $result );
    remove_tree( $self->{checkout} );
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( $result->{directory}, $self->{checkout} ) or die "assertion failed\n" );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ network_calls($self) } ], ["clone"] )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "remote", "get-url", "origin" ], 1 )->{stdout} ),
            ( $self->{url} . ".git" ) )
          or die "assertion failed\n"
    );
}

sub assert_clone_failed_without_changing_directory {
    my ( $self, $result ) = @_;
    my ($call);
    ( is_deeply( $result->{returncode}, 37, $result->{stderr} ) or die "assertion failed\n" );
    ( is_deeply( $result->{directory}, $self->{sandbox} )       or die "assertion failed\n" );
    ( ok( !( ( -e $self->{checkout} ) ) )                       or die "assertion failed\n" );
    ( is_deeply( calls( $self, "editor" ), [] )                 or die "assertion failed\n" );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ network_calls($self) } ], ["clone"] )
          or die "assertion failed\n"
    );
}

sub test_failed_clone_removes_new_empty_organization_directory {
    my ($self) = @_;
    my ($result);
    remove_tree( dirname( $self->{checkout} ) );
    $self->{env}->{"TEST_CLONE_FAILURE"} = "empty";
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_clone_failed_without_changing_directory( $self, $result );
    ( ok( !( ( -e dirname( $self->{checkout} ) ) ) ) or die "assertion failed\n" );
    ( ok( ( ( -d dirname( dirname( $self->{checkout} ) ) ) ) ) or die "assertion failed\n" );
}

sub test_failed_clone_retains_preexisting_empty_organization_directory {
    my ($self) = @_;
    my ($result);
    remove_tree( $self->{checkout} );
    $self->{env}->{"TEST_CLONE_FAILURE"} = "empty";
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_clone_failed_without_changing_directory( $self, $result );
    ( ok( ( ( -d dirname( $self->{checkout} ) ) ) ) or die "assertion failed\n" );
    ( is_deeply( directory_entries( dirname( $self->{checkout} ) ), [] ) or die "assertion failed\n" );
}

sub test_organization_creation_race_preserves_the_other_directory {
    my ($self) = @_;
    my ( $mkdir, $program, $result );
    remove_tree( dirname( $self->{checkout} ) );
    $self->{env}->{"TEST_CLONE_FAILURE"} = "empty";
    $self->{env}->{"TEST_ORG_DIR"}       = dirname( $self->{checkout} );
    $self->{env}->{"TEST_REAL_MKDIR"}    = which("mkdir");
    $program                             = 'use strict;
use warnings;
use File::Path qw(make_path);
if ($ARGV[-1] eq $ENV{TEST_ORG_DIR}) {
    make_path($ARGV[-1]);
}
exec {$ENV{TEST_REAL_MKDIR}} $ENV{TEST_REAL_MKDIR}, @ARGV;
die $!;
';
    $mkdir = join_path( $self->{bin}, "mkdir" );
    write_file(
        $mkdir,
        (
            (
                ( "#!" . perl_executable() ) . '
'
            )
            . $program
        )
    );
    chmod( 493, $mkdir );
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 0, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                    or die "assertion failed\n" );
    ( is_deeply( $result->{directory}, $self->{sandbox} )                or die "assertion failed\n" );
    ( ok( ( ( -d dirname( $self->{checkout} ) ) ) )                      or die "assertion failed\n" );
    ( is_deeply( directory_entries( dirname( $self->{checkout} ) ), [] ) or die "assertion failed\n" );
}

sub test_failed_clone_retains_new_nonempty_organization_and_clone_exit_status {
    my ($self) = @_;
    my ($result);
    remove_tree( dirname( $self->{checkout} ) );
    $self->{env}->{"TEST_CLONE_FAILURE"} = "nonempty";
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_clone_failed_without_changing_directory( $self, $result );
    (
        is_deeply(
            read_file( join_path( dirname( $self->{checkout} ), "unrelated.txt" ) ),
            'keep unrelated file
'
          )
          or die "assertion failed\n"
    );
    ( ok( contains_value( $result->{stderr}, "rmdir:" ) )                     or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, dirname( $self->{checkout} ) ) ) or die "assertion failed\n" );
}

sub test_successful_clone_retains_new_organization_directory {
    my ($self) = @_;
    my ( $call, $result );
    remove_tree( dirname( $self->{checkout} ) );
    $result = run_fish( $self, "ghe", [ $self->{url} ], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( ok( ( ( -d dirname( $self->{checkout} ) ) ) )           or die "assertion failed\n" );
    ( ok( ( ( -d join_path( $self->{checkout}, ".git" ) ) ) ) or die "assertion failed\n" );
    ( is_deeply( $result->{directory}, $self->{checkout} )    or die "assertion failed\n" );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ network_calls($self) } ], ["clone"] )
          or die "assertion failed\n"
    );
}

sub test_clean_missing_path_pulls_before_opening {
    my ($self) = @_;
    my ( $call, $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "new-upstream.txt" => 'upstream
'
        },
        "main",
        0
    );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/main/new-upstream.txt" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    (
        is_deeply(
            read_file( join_path( $self->{checkout}, "new-upstream.txt" ) ),
            'upstream
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"},
            [ join_path( $self->{checkout}, "new-upstream.txt" ) ] )
          or die "assertion failed\n"
    );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ network_calls($self) } ], ["fetch"] )
          or die "assertion failed\n"
    );
}

sub test_dirty_missing_path_does_not_pull {
    my ($self) = @_;
    my ($result);
    seed_commit(
        $self,
        {
            "new-upstream.txt" => 'upstream
'
        },
        "main",
        0
    );
    write_file(
        join_path( $self->{checkout}, "file.txt" ), 'keep local edit
'
    );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/main/new-upstream.txt" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply(
            read_file( join_path( $self->{checkout}, "file.txt" ) ),
            'keep local edit
'
          )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "checkout has local changes; skipping pull" ) )
          or die "assertion failed\n"
    );
}

sub test_dirty_checkout_keeps_current_branch_when_visiting_another_ref {
    my ($self) = @_;
    my ($result);
    seed_commit(
        $self,
        {
            "file.txt" => 'feature
'
        },
        "feature",
        1
    );
    fetch_fixture($self);
    write_file(
        join_path( $self->{checkout}, "file.txt" ), 'keep local edit
'
    );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/tree/feature" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( ok( contains_value( $result->{stderr}, "keeping the current ref" ) ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ),
            "main" )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            read_file( join_path( $self->{checkout}, "file.txt" ) ),
            'keep local edit
'
          )
          or die "assertion failed\n"
    );
}

sub test_dirty_existing_path_does_not_fetch_uncached_short_commit {
    my ($self) = @_;
    my ( $call, $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'upstream change
'
        },
        "main",
        0
    );
    (
        ok(
            !equal_values(
                git( $self, $self->{checkout}, [ "cat-file", "-e", $revision ], 0 )->{returncode}, 0
            )
          )
          or die "assertion failed\n"
    );
    write_file(
        join_path( $self->{checkout}, "file.txt" ), 'keep local edit
'
    );
    $result =
      run_fish( $self, "ghe",
        [ ( ( ( $self->{url} . "/blob/" ) . string_slice( $revision, undef, 10 ) ) . "/file.txt" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( ok( contains_value( $result->{stderr}, "keeping the current ref" ) ) or die "assertion failed\n" );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ),
            "main" )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            read_file( join_path( $self->{checkout}, "file.txt" ) ),
            'keep local edit
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"}, [ join_path( $self->{checkout}, "file.txt" ) ] )
          or die "assertion failed\n"
    );
    (
        ok(
            !contains_value(
                [ map { my $call = $_; $call->{"command"} } @{ network_calls($self) } ], "fetch"
            )
          )
          or die "assertion failed\n"
    );
}

sub test_ignored_file_is_not_overwritten_by_switch {
    my ($self) = @_;
    my ($result);
    seed_commit(
        $self,
        {
            "ignored.txt" => 'tracked upstream
'
        },
        "feature",
        1
    );
    fetch_fixture($self);
    write_file(
        join_path( $self->{checkout}, "ignored.txt" ), 'keep ignored file
'
    );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/tree/feature" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply(
            read_file( join_path( $self->{checkout}, "ignored.txt" ) ),
            'keep ignored file
'
          )
          or die "assertion failed\n"
    );
}

sub test_ignored_file_is_not_overwritten_by_pull {
    my ($self) = @_;
    my ($result);
    seed_commit(
        $self,
        {
            "ignored.txt" => 'tracked upstream
', "new-upstream.txt" => 'upstream
'
        },
        "main",
        0
    );
    write_file(
        join_path( $self->{checkout}, "ignored.txt" ), 'keep ignored file
'
    );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/main/new-upstream.txt" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply(
            read_file( join_path( $self->{checkout}, "ignored.txt" ) ),
            'keep ignored file
'
          )
          or die "assertion failed\n"
    );
    ( ok( !( ( -e join_path( $self->{checkout}, "new-upstream.txt" ) ) ) ) or die "assertion failed\n" );
}

sub test_missing_path_pull_does_not_merge_diverged_history {
    my ($self) = @_;
    my ( $before, $result );
    seed_commit(
        $self,
        {
            "new-upstream.txt" => 'upstream
'
        },
        "main",
        0
    );
    write_file(
        join_path( $self->{checkout}, "local.txt" ), 'local commit
'
    );
    git( $self, $self->{checkout}, [ "add", "local.txt" ], 1 );
    git( $self, $self->{checkout}, [ "commit", "-qm", "local divergence" ], 1 );
    $before = head($self);
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/main/new-upstream.txt" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( head($self), $before ) or die "assertion failed\n" );
    (
        is_deeply(
            read_file( join_path( $self->{checkout}, "local.txt" ) ),
            'local commit
'
          )
          or die "assertion failed\n"
    );
    ( ok( !( ( -e join_path( $self->{checkout}, "new-upstream.txt" ) ) ) ) or die "assertion failed\n" );
}

sub test_line_column_and_selection_arguments_reach_the_editor {
    my ($self) = @_;
    my ( $cases, $editor, $position, $positions, $result );
    $cases = [
        [ [ "2", "",  "", "" ], "+2" ],
        [ [ "2", "3", "", "" ], "+call cursor(2, 3)" ],
        [
            [ "2", "", "4", "" ],
            "+set selection=inclusive | call cursor(2, 1) | execute 'normal! V' | call cursor(4, 1)"
        ],
        [
            [ "2", "2", "4", "" ],
"+set selection=inclusive | call cursor(2, 2) | execute 'normal! v' | call cursor(4, max([1, strlen(getline(4))]))"
        ],
        [
            [ "2", "", "4", "3" ],
            "+set selection=inclusive | call cursor(2, 1) | execute 'normal! v' | call cursor(4, 3)"
        ]
    ];
    $editor = [ join_path( $self->{bin}, "editor" ), "--wait", "two words" ];
    for my $item_1494 ( @{$cases} ) {
        $positions = ($item_1494)->[0];
        $position  = ($item_1494)->[1];
        {
            $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/main/file.txt" ) ],
                undef, 0, $editor, undef, $positions );
            assert_success( $self, $result );
            (
                is_deeply( calls( $self, "editor" )->[0]->{"args"},
                    [ "--wait", "two words", $position, join_path( $self->{checkout}, "file.txt" ) ] )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_editor_list_is_preserved_when_position_arguments_are_appended {
    my ($self) = @_;
    my ( $editor, $editor_dir, $executable, $result, $script, $target );
    $editor_dir = join_path( $self->{root}, "editor dir" );
    make_path($editor_dir);
    $executable = join_path( $editor_dir, "editor" );
    copy_preserve( join_path( $self->{bin}, "editor" ), $executable );
    $editor = [ $executable, "--wait", "two words" ];
    $target = join_path( $self->{checkout}, "file.txt" );
    $script = (
        ( "__ghe_open " . fish_quote($target) ) . ' 2
'
    );
    $script .= 'set -l opened $status
printf "%s\\n" $EDITOR
test "$opened" -eq 0';
    $result = run_fish( $self, $script, [], undef, 0, $editor, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"}, [ "--wait", "two words", "+2", $target ] )
          or die "assertion failed\n"
    );
    ( is_deeply( [ split( /\n/, $result->{stdout} ) ], $editor ) or die "assertion failed\n" );
}

sub test_public_ghe_dispatches_destination_and_normalized_anchors_without_writing {
    my ($self) = @_;
    my ( $expected_destination, $result );
    $result = run_fish( $self, "ghe_dispatch", [ ( $self->{url} . "/blob/main/file.txt#L002C03-L004C05" ) ],
        undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    $expected_destination =
      join_path( join_path( join_path( $ENV{HOME}, "code" ), "test-owner" ), "test-repo" );
    (
        is_deeply( calls( $self, "dispatch" )->[0]->{"args"},
            [ ( $self->{url} . ".git" ), $expected_destination, "blob/main/file.txt", "2", "3", "4", "5" ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self),     [] ) or die "assertion failed\n" );
    ( is_deeply( calls( $self, "editor" ), [] ) or die "assertion failed\n" );
}

sub test_raw_edit_release_and_archive_routes {
    my ($self) = @_;
    my ( $branch, $cases, $detached, $edit, $result, $value );
    $cases = [
        [ ( $self->{url} . "/raw/main/file.txt" ),                                           1, 0 ],
        [ ( $self->{url} . "/edit/main/file.txt" ),                                          1, 0 ],
        [ "https://raw.githubusercontent.com/test-owner/test-repo/main/file.txt",            1, 0 ],
        [ "https://raw.githubusercontent.com/test-owner/test-repo/refs/heads/main/file.txt", 1, 0 ],
        [ "https://raw.githubusercontent.com/test-owner/test-repo/refs/tags/v1/file.txt",    1, 1 ],
        [ ( $self->{url} . "/releases/tag/v1" ),                                             0, 1 ],
        [ ( $self->{url} . "/archive/refs/heads/main.zip" ),                                 0, 0 ],
        [ ( $self->{url} . "/archive/refs/tags/v1.tar.gz" ),                                 0, 1 ],
        [ ( ( ( $self->{url} . "/archive/" ) . $self->{initial} ) . ".zip" ),                0, 1 ]
    ];
    for my $item_1538 ( @{$cases} ) {
        $value    = ($item_1538)->[0];
        $edit     = ($item_1538)->[1];
        $detached = ($item_1538)->[2];
        {
            git( $self, $self->{checkout}, [ "switch", "--quiet", "main" ], 1 );
            $result = run_fish( $self, "ghe", [$value], undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            (
                is_deeply( 0 + !!( scalar( @{ calls( $self, "editor" ) } ) ), $edit )
                  or die "assertion failed\n"
            );
            ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
            $branch = trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} );
            ( is_deeply( $branch,              ( $detached ? "" : "main" ) ) or die "assertion failed\n" );
            ( is_deeply( network_calls($self), [] )                          or die "assertion failed\n" );
        }
    }
}

sub test_explicit_ref_namespaces_in_file_and_tree_urls {
    my ($self) = @_;
    my ( $branch, $branch_tip, $expected, $namespace, $page, $result, $tail );
    $branch_tip = seed_commit(
        $self,
        {
            "file.txt" => 'branch with the tag name
'
        },
        "topic",
        1
    );
    git( $self, $self->{seed}, [ "tag", "topic", $self->{initial} ], 1 );
    publish( $self, ["refs/tags/topic"] );
    fetch_fixture($self);
    for $page ( @{ [ "blob", "tree", "blame", "commits" ] } ) {
        for my $item_1555 ( @{ [ [ "heads", $branch_tip, "topic" ], [ "tags", $self->{initial}, "" ] ] } ) {
            $namespace = ($item_1555)->[0];
            $expected  = ($item_1555)->[1];
            $branch    = ($item_1555)->[2];
            {
                $tail = ( ( ( $page eq "tree" ) ) ? "dir" : "file.txt" );
                $result =
                  run_fish( $self, "ghe",
                    [ ( $self->{url} . "/" . $page . "/refs/" . $namespace . "/topic/" . $tail ) ],
                    undef, 1, undef, undef, [ "", "", "", "" ] );
                assert_success( $self, $result );
                ( is_deeply( head($self), $expected ) or die "assertion failed\n" );
                (
                    is_deeply(
                        trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ),
                        $branch
                      )
                      or die "assertion failed\n"
                );
                ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
            }
        }
    }
}

sub test_gho_opens_qualified_branch_names_directly {
    my ($self) = @_;
    my ( $branch, $result );
    $branch = "refs/heads/main";
    git( $self, $self->{seed}, [ "switch", "--quiet", "--create", $branch ], 1 );
    write_file(
        join_path( $self->{seed}, "qualified.txt" ), 'only on the nested branch
'
    );
    git( $self, $self->{seed}, [ "add", "qualified.txt" ], 1 );
    git( $self, $self->{seed}, [ "commit", "--quiet", "-m", "fixture update" ], 1 );
    publish( $self, [ ( "refs/heads/" . $branch ) ] );
    fetch_fixture($self);
    git( $self, $self->{checkout},
        [ "switch", "--quiet", "--create", $branch, "--track", ( "origin/" . $branch ) ], 1 );
    $result = run_fish( $self, "gho", [ join_path( $self->{checkout}, "qualified.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"},
            [ ( $self->{url} . "/blob/refs/heads/main/qualified.txt" ) ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
    git( $self, $self->{checkout},
        [ "config", "--add", "remote.origin.fetch", ( "+refs/heads/main:refs/remotes/origin/" . $branch ) ],
        1 );
    $result = run_fish( $self, "gho", [ $self->{checkout} ], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "open" )->[0]->{"args"}, [ ( $self->{url} . "/tree/refs/heads/main" ) ] )
          or die "assertion failed\n"
    );
}

sub test_latest_release_uses_mocked_api_and_checks_out_its_tag {
    my ($self) = @_;
    my ( $endpoint, $result );
    $endpoint = "repos/test-owner/test-repo/releases/latest";
    $result   = run_fish(
        $self, "ghe", [ ( $self->{url} . "/releases/latest" ) ],
        undef, 0,     undef,
        { $endpoint => "v1" },
        [ "", "", "", "" ]
    );
    assert_success( $self, $result );
    ( is_deeply( scalar( @{ calls( $self, "gh" ) } ), 1 )                    or die "assertion failed\n" );
    ( ok( contains_value( calls( $self, "gh" )->[0]->{"args"}, $endpoint ) ) or die "assertion failed\n" );
    ( is_deeply( head($self), $self->{initial} )                             or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ), "" )
          or die "assertion failed\n"
    );
}

sub test_release_checkout_caches_the_fetched_annotated_tag {
    my ($self) = @_;
    my ( $cache, $result, $revision, $tag, $url );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'new release
'
        },
        "main",
        0
    );
    git( $self, $self->{seed}, [ "tag", "--annotate", "--message", "Release v2", "v2" ], 1 );
    publish( $self, ["refs/tags/v2"] );
    $tag = trim( git( $self, $self->{seed}, [ "rev-parse", "refs/tags/v2" ], 1 )->{stdout} );
    $url = ( $self->{url} . "/releases/tag/v2" );
    assert_success( $self, run_fish( $self, "ghe", [$url], undef, 0, undef, undef, [ "", "", "", "" ] ) );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    $cache =
      git( $self, $self->{checkout}, [ "for-each-ref", "--format=%(objectname)", "refs/gh/compare" ], 1 );
    ( is_deeply( trim( $cache->{stdout} ), $tag ) or die "assertion failed\n" );
    (
        ok(
            !equal_values(
                git( $self, $self->{checkout}, [ "show-ref", "--verify", "--quiet", "refs/tags/v2" ], 0 )
                  ->{returncode},
                0
            )
          )
          or die "assertion failed\n"
    );
    assert_success( $self, run_fish( $self, "ghe", [$url], undef, 1, undef, undef, [ "", "", "", "" ] ) );
    ( is_deeply( head($self),          $revision ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] )        or die "assertion failed\n" );
    $result = run_fish( $self, "ghe", [ ( $self->{url} . "/blob/refs/tags/v2/file.txt" ) ],
        undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"}, [ join_path( $self->{checkout}, "file.txt" ) ] )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_exact_tag_checkout_uses_packed_ref_despite_loose_case_alias {
    my ($self) = @_;
    my ( $expected, $newer, $result, $tag );
    git( $self, $self->{seed}, [ "tag", "Release" ], 1 );
    publish( $self, ["refs/tags/Release"] );
    fetch_fixture($self);
    git( $self, $self->{checkout}, [ "pack-refs", "--all", "--prune" ], 1 );
    $newer = seed_commit(
        $self,
        {
            "file.txt" => 'other version
'
        },
        "feature",
        1
    );
    fetch_fixture($self);
    git( $self, $self->{checkout}, [ "update-ref", "refs/tags/release", $newer ], 1 );
    for my $item_1625 ( @{ [ [ "Release", $self->{initial} ], [ "release", $newer ] ] } ) {
        $tag      = ($item_1625)->[0];
        $expected = ($item_1625)->[1];
        {
            $result = run_fish( $self, "ghe", [ ( $self->{url} . "/releases/tag/" . $tag ) ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            ( is_deeply( head($self),          $expected ) or die "assertion failed\n" );
            ( is_deeply( network_calls($self), [] )        or die "assertion failed\n" );
            $result =
              run_fish( $self, "__ghe_compare_ref",
                [ ( $self->{url} . ".git" ), $self->{checkout}, ( "tags/" . $tag ) ],
                undef, 1, undef, undef, [ "", "", "", "" ] );
            assert_success( $self, $result );
            ( is_deeply( trim( $result->{stdout} ), $expected ) or die "assertion failed\n" );
        }
    }
}

sub test_release_checkout_caches_a_tag_at_an_existing_commit {
    my ($self) = @_;
    my ( $call, $url );
    git( $self, $self->{seed}, [ "tag", "v2" ], 1 );
    publish( $self, ["refs/tags/v2"] );
    $url = ( $self->{url} . "/releases/tag/v2" );
    assert_success( $self, run_fish( $self, "ghe", [$url], undef, 0, undef, undef, [ "", "", "", "" ] ) );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ network_calls($self) } ], ["ls-remote"] )
          or die "assertion failed\n"
    );
    assert_success( $self, run_fish( $self, "ghe", [$url], undef, 1, undef, undef, [ "", "", "", "" ] ) );
    ( is_deeply( network_calls($self), [] )               or die "assertion failed\n" );
    ( is_deeply( head($self),          $self->{initial} ) or die "assertion failed\n" );
}

sub test_release_checkout_succeeds_when_its_cache_is_blocked {
    my ($self) = @_;
    my ($revision);
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'new release
'
        },
        "main",
        0
    );
    git( $self, $self->{seed}, [ "tag", "--annotate", "--message", "Release v2", "v2" ], 1 );
    publish( $self, ["refs/tags/v2"] );
    git( $self, $self->{checkout}, [ "update-ref", "refs/gh/compare", $self->{initial} ], 1 );
    assert_success(
        $self,
        run_fish(
            $self, "ghe", [ ( $self->{url} . "/releases/tag/v2" ) ],
            undef, 0,     undef, undef, [ "", "", "", "" ]
        )
    );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    (
        is_deeply(
            trim(
                git( $self, $self->{checkout}, [ "show-ref", "--hash", "--verify", "refs/gh/compare" ], 1 )
                  ->{stdout}
            ),
            $self->{initial}
          )
          or die "assertion failed\n"
    );
}

sub test_release_checkout_uses_its_own_fetch_result {
    my ($self) = @_;
    my ( $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'new release
'
        },
        "main",
        0
    );
    git( $self, $self->{seed}, [ "tag", "--annotate", "--message", "Release v2", "v2" ], 1 );
    publish( $self, ["refs/tags/v2"] );
    $result = run_fish(
        $self, 'function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- refs/tags/v2 $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin refs/tags/v1
    end
end
__ghe_checkout',
        [
            ( $self->{url} . ".git" ),
            $self->{checkout}, "releases/tag/v2", "", "", "", ""
        ],
        undef, 0, undef, undef,
        [ "", "", "", "" ]
    );
    assert_success( $self, $result );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", "FETCH_HEAD" ], 1 )->{stdout} ),
            $self->{initial} )
          or die "assertion failed\n"
    );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    assert_success(
        $self,
        run_fish(
            $self, "ghe", [ ( $self->{url} . "/releases/tag/v2" ) ],
            undef, 1,     undef, undef, [ "", "", "", "" ]
        )
    );
}

sub test_pull_request_head_and_offline_cache {
    my ($self) = @_;
    my ( $call, $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'pull request
'
        },
        "feature",
        1
    );
    publish( $self, [ ( $revision . ":refs/pull/7/head" ) ] );
    $result =
      run_fish( $self, "ghe", [ ( $self->{url} . "/pull/7" ) ], undef, 0, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ), "" )
          or die "assertion failed\n"
    );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ network_calls($self) } ], ["fetch"] )
          or die "assertion failed\n"
    );
    $result =
      run_fish( $self, "ghe", [ ( $self->{url} . "/pull/7" ) ], undef, 1, undef, undef, [ "", "", "", "" ] );
    assert_success( $self, $result );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
}

sub test_pull_request_checkout_succeeds_when_its_cache_is_blocked {
    my ($self) = @_;
    my ($revision);
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'pull request
'
        },
        "feature",
        1
    );
    publish( $self, [ ( $revision . ":refs/pull/7/head" ) ] );
    git( $self, $self->{checkout}, [ "update-ref", "refs/gh/pull", $self->{initial} ], 1 );
    assert_success(
        $self,
        run_fish(
            $self, "ghe", [ ( $self->{url} . "/pull/7" ) ], undef, 0, undef, undef, [ "", "", "", "" ]
        )
    );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    (
        is_deeply(
            trim(
                git( $self, $self->{checkout}, [ "show-ref", "--hash", "--verify", "refs/gh/pull" ], 1 )
                  ->{stdout}
            ),
            $self->{initial}
          )
          or die "assertion failed\n"
    );
}

sub test_pull_request_checkout_uses_its_own_fetch_result {
    my ($self) = @_;
    my ( $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'pull request
'
        },
        "feature",
        1
    );
    publish( $self, [ ( $revision . ":refs/pull/7/head" ) ] );
    $result = run_fish(
        $self, 'function git
    command git $argv; or return
    if contains -- refs/pull/7/head $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin refs/heads/main
    end
end
__ghe_checkout',
        [
            ( $self->{url} . ".git" ),
            $self->{checkout}, "pull/7", "", "", "", ""
        ],
        undef, 0, undef, undef,
        [ "", "", "", "" ]
    );
    assert_success( $self, $result );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", "FETCH_HEAD" ], 1 )->{stdout} ),
            $self->{initial} )
          or die "assertion failed\n"
    );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    assert_success(
        $self,
        run_fish(
            $self, "ghe", [ ( $self->{url} . "/pull/7" ) ], undef, 1, undef, undef, [ "", "", "", "" ]
        )
    );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
}

sub test_missing_file_pull_uses_its_own_fetch_result {
    my ($self) = @_;
    my ( $result, $revision );
    git( $self, $self->{seed}, [ "branch", "other" ], 1 );
    publish( $self, ["other"] );
    $revision = seed_commit(
        $self,
        {
            "new.txt" => 'new upstream file
'
        },
        "main",
        0
    );
    $result = run_fish(
        $self, 'function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- refs/heads/main $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin refs/heads/other
    end
end
__ghe_checkout',
        [
            ( $self->{url} . ".git" ),
            $self->{checkout}, "blob/main/new.txt", "", "", "", ""
        ],
        undef, 0, undef, undef,
        [ "", "", "", "" ]
    );
    assert_success( $self, $result );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", "FETCH_HEAD" ], 1 )->{stdout} ),
            $self->{initial} )
          or die "assertion failed\n"
    );
    ( is_deeply( head($self), $revision ) or die "assertion failed\n" );
    (
        is_deeply( calls( $self, "editor" )->[0]->{"args"}, [ join_path( $self->{checkout}, "new.txt" ) ] )
          or die "assertion failed\n"
    );
}

sub test_missing_file_pull_stops_if_the_checked_out_branch_changes {
    my ($self) = @_;
    my ( $result, $revision );
    git( $self, $self->{checkout}, [ "branch", "side" ], 1 );
    $revision = seed_commit(
        $self,
        {
            "new.txt" => 'new upstream file
'
        },
        "main",
        0
    );
    $result = run_fish(
        $self, 'function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- refs/heads/main $argv
        command git -C "$argv[2]" switch --quiet side; or return
        printf \'%s\\n\' \'side worktree file\' > "$argv[2]/new.txt"
    end
end
__ghe_checkout',
        [
            ( $self->{url} . ".git" ),
            $self->{checkout}, "blob/main/new.txt", "", "", "", ""
        ],
        undef, 0, undef, undef,
        [ "", "", "", "" ]
    );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "checkout branch changed while fetching" ) )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ),
            "side" )
          or die "assertion failed\n"
    );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", "main" ], 1 )->{stdout} ),
            $self->{initial} )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", "origin/main" ], 1 )->{stdout} ),
            $revision )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            read_file( join_path( $self->{checkout}, "new.txt" ) ),
            'side worktree file
'
          )
          or die "assertion failed\n"
    );
    ( is_deeply( calls( $self, "editor" ), [] ) or die "assertion failed\n" );
}

sub test_missing_file_pull_stops_if_the_branch_tip_changes {
    my ($self) = @_;
    my ( $result, $revision );
    seed_commit(
        $self,
        {
            "middle.txt" => 'intermediate commit
'
        },
        "main",
        0
    );
    fetch_fixture($self);
    git( $self, $self->{checkout}, [ "merge", "--ff-only", "origin/main" ], 1 );
    $revision = seed_commit(
        $self,
        {
            "new.txt" => 'new upstream file
'
        },
        "main",
        0
    );
    $result = run_fish(
        $self,
        (
            "set -g original "
              . $self->{initial} . '
function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- refs/heads/main $argv
        command git -C "$argv[2]" reset --quiet --hard "$original"
    end
end
__ghe_checkout'
        ),
        [ ( $self->{url} . ".git" ), $self->{checkout}, "blob/main/new.txt", "", "", "", "" ],
        undef,
        0,
        undef,
        undef,
        [ "", "", "", "" ]
    );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "checkout commit changed while fetching" ) )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ),
            "main" )
          or die "assertion failed\n"
    );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", "origin/main" ], 1 )->{stdout} ),
            $revision )
          or die "assertion failed\n"
    );
    ( is_deeply( calls( $self, "editor" ), [] ) or die "assertion failed\n" );
}

sub test_missing_file_pull_stops_if_the_worktree_becomes_dirty {
    my ($self) = @_;
    my ( $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "new.txt" => 'new upstream file
'
        },
        "main",
        0
    );
    $result = run_fish(
        $self, 'function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- refs/heads/main $argv
        echo "worktree edit during fetch" >> "$argv[2]/file.txt"
    end
end
__ghe_checkout',
        [
            ( $self->{url} . ".git" ),
            $self->{checkout}, "blob/main/new.txt", "", "", "", ""
        ],
        undef, 0, undef, undef,
        [ "", "", "", "" ]
    );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "checkout has local changes; skipping pull" ) )
          or die "assertion failed\n"
    );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "rev-parse", "origin/main" ], 1 )->{stdout} ),
            $revision )
          or die "assertion failed\n"
    );
    (
        ok(
            contains_value(
                read_file( join_path( $self->{checkout}, "file.txt" ) ),
                "worktree edit during fetch"
            )
          )
          or die "assertion failed\n"
    );
    ( is_deeply( calls( $self, "editor" ), [] ) or die "assertion failed\n" );
}

sub test_pull_request_files_uses_mocked_api_without_switching {
    my ($self) = @_;
    my ( $endpoint, $result, $revision );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'pull request
'
        },
        "feature",
        1
    );
    fetch_fixture($self);
    $endpoint = "repos/test-owner/test-repo/pulls/7";
    $result   = run_fish(
        $self, "ghe",
        [ ( $self->{url} . "/pull/7/files" ) ],
        undef, 0, undef,
        {
            $endpoint => (
                (
                    $self->{initial} . '
'
                )
                . $revision
            )
        },
        [ "", "", "", "" ]
    );
    assert_success( $self, $result );
    ( ok( contains_value( $result->{stdout}, "+pull request" ) ) or die "assertion failed\n" );
    ( is_deeply( head($self), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "branch", "--show-current" ], 1 )->{stdout} ),
            "main" )
          or die "assertion failed\n"
    );
    ( is_deeply( network_calls($self), [] ) or die "assertion failed\n" );
}

sub test_shallow_pull_request_files_uses_a_cached_merge_base {
    my ($self) = @_;
    my ( $base, $endpoint, $result, $revision );
    $base = seed_commit(
        $self,
        {
            "file.txt" => 'base
'
        },
        "main",
        0
    );
    $revision = seed_commit(
        $self,
        {
            "file.txt" => 'pull request
'
        },
        "feature",
        1
    );
    git( $self, $self->{checkout},
        [ "fetch", "--depth=2", file_uri( $self->{remote} ), "refs/heads/feature" ], 1 );
    (
        is_deeply(
            trim( git( $self, $self->{checkout}, [ "rev-parse", "--is-shallow-repository" ], 1 )->{stdout} ),
            "true"
          )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $self->{checkout}, [ "merge-base", $base, $revision ], 1 )->{stdout} ),
            $base )
          or die "assertion failed\n"
    );
    $endpoint = "repos/test-owner/test-repo/pulls/7";
    $result   = run_fish(
        $self, "ghe",
        [ ( $self->{url} . "/pull/7/files" ) ],
        undef, 1, undef,
        {
            $endpoint => (
                (
                    $base . '
'
                )
                . $revision
            )
        },
        [ "", "", "", "" ]
    );
    assert_success( $self, $result );
    ( ok( contains_value( $result->{stdout}, "+pull request" ) ) or die "assertion failed\n" );
    ( is_deeply( head($self),          $self->{initial} ) or die "assertion failed\n" );
    ( is_deeply( network_calls($self), [] )               or die "assertion failed\n" );
}

run_cases(
    {
        "test_gbp_preserves_live_branch_when_subject_says_gone" =>
          \&test_gbp_preserves_live_branch_when_subject_says_gone,
        "test_gbp_deletes_branch_with_apostrophe"               => \&test_gbp_deletes_branch_with_apostrophe,
        "test_gbp_skips_branch_checked_out_in_another_worktree" =>
          \&test_gbp_skips_branch_checked_out_in_another_worktree,
        "test_help_lists_modes_without_side_effects" => \&test_help_lists_modes_without_side_effects,
        "test_ghc_creates_private_repository_and_opens_reported_url" =>
          \&test_ghc_creates_private_repository_and_opens_reported_url,
        "test_ghc_reuses_existing_repository_without_looking_it_up" =>
          \&test_ghc_reuses_existing_repository_without_looking_it_up,
        "test_ghc_uses_configured_host_or_github_default" =>
          \&test_ghc_uses_configured_host_or_github_default,
        "test_ghc_rejects_invalid_input_before_running_commands" =>
          \&test_ghc_rejects_invalid_input_before_running_commands,
        "test_ghc_preserves_other_creation_errors" => \&test_ghc_preserves_other_creation_errors,
        "test_ghc_preserves_creation_warnings"     => \&test_ghc_preserves_creation_warnings,
        "test_ghc_returns_checkout_failure"        => \&test_ghc_returns_checkout_failure,
        "test_supported_transports_open_and_enter_the_same_repository" =>
          \&test_supported_transports_open_and_enter_the_same_repository,
        "test_ghe_dispatch_uses_configured_host"      => \&test_ghe_dispatch_uses_configured_host,
        "test_ghe_accepts_configured_host_transports" => \&test_ghe_accepts_configured_host_transports,
        "test_ghe_clones_from_configured_host"        => \&test_ghe_clones_from_configured_host,
        "test_ghe_adds_configured_host_to_checkout_without_remotes" =>
          \&test_ghe_adds_configured_host_to_checkout_without_remotes,
        "test_ghe_distinguishes_repositories_on_different_hosts" =>
          \&test_ghe_distinguishes_repositories_on_different_hosts,
        "test_ghe_api_routes_use_configured_host"      => \&test_ghe_api_routes_use_configured_host,
        "test_direct_url_preserves_query_and_fragment" => \&test_direct_url_preserves_query_and_fragment,
        "test_gho_opens_unknown_remote_pages_directly" => \&test_gho_opens_unknown_remote_pages_directly,
        "test_rejects_traversal_without_side_effects"  => \&test_rejects_traversal_without_side_effects,
        "test_rejects_controls_in_configured_host_without_side_effects" =>
          \&test_rejects_controls_in_configured_host_without_side_effects,
        "test_ghe_rejects_git_metadata_paths"           => \&test_ghe_rejects_git_metadata_paths,
        "test_local_default_root_and_escaped_file_urls" => \&test_local_default_root_and_escaped_file_urls,
        "test_alias_writes_preserve_overlapping_loose_and_packed_tracking_refs" =>
          \&test_alias_writes_preserve_overlapping_loose_and_packed_tracking_refs,
        "test_alias_writes_preserve_another_remotes_loose_and_packed_tracking_ref" =>
          \&test_alias_writes_preserve_another_remotes_loose_and_packed_tracking_ref,
        "test_alias_writes_leave_reserved_fetch_destinations_available" =>
          \&test_alias_writes_leave_reserved_fetch_destinations_available,
        "test_default_refresh_releases_a_reserved_existing_symbolic_alias" =>
          \&test_default_refresh_releases_a_reserved_existing_symbolic_alias,
        "test_gho_roots_open_the_homepage_or_branch_without_pr_detection" =>
          \&test_gho_roots_open_the_homepage_or_branch_without_pr_detection,
        "test_gho_local_modes_use_at_most_five_metadata_commands" =>
          \&test_gho_local_modes_use_at_most_five_metadata_commands,
        "test_gho_handles_unborn_and_detached_roots" => \&test_gho_handles_unborn_and_detached_roots,
        "test_gho_linked_worktree_uses_its_own_branch_and_shared_default" =>
          \&test_gho_linked_worktree_uses_its_own_branch_and_shared_default,
        "test_gho_ignores_overlapping_fetch_mappings" => \&test_gho_ignores_overlapping_fetch_mappings,
        "test_gho_rechecks_default_and_fetch_mapping_between_calls" =>
          \&test_gho_rechecks_default_and_fetch_mapping_between_calls,
        "test_gho_does_not_need_cached_commit_objects" => \&test_gho_does_not_need_cached_commit_objects,
        "test_gho_never_refreshes_a_missing_or_dangling_default_alias" =>
          \&test_gho_never_refreshes_a_missing_or_dangling_default_alias,
        "test_gho_default_fallback_only_applies_to_main_and_master_roots" =>
          \&test_gho_default_fallback_only_applies_to_main_and_master_roots,
        "test_gho_uses_cached_default_name_when_alias_update_was_blocked" =>
          \&test_gho_uses_cached_default_name_when_alias_update_was_blocked,
        "test_default_alias_does_not_read_or_replace_a_case_folded_symref" =>
          \&test_default_alias_does_not_read_or_replace_a_case_folded_symref,
        "test_gho_uses_configured_upstream_without_a_tracking_ref" =>
          \&test_gho_uses_configured_upstream_without_a_tracking_ref,
        "test_gho_prefers_origin_then_the_only_remote_without_an_upstream" =>
          \&test_gho_prefers_origin_then_the_only_remote_without_an_upstream,
        "test_tracking_destination_shared_by_different_remotes_is_not_trusted" =>
          \&test_tracking_destination_shared_by_different_remotes_is_not_trusted,
        "test_gho_opens_local_only_files_and_directories" =>
          \&test_gho_opens_local_only_files_and_directories,
        "test_gho_does_not_validate_fetch_destinations" => \&test_gho_does_not_validate_fetch_destinations,
        "test_gho_opens_deleted_tracked_files"          => \&test_gho_opens_deleted_tracked_files,
        "test_gho_opens_deleted_file_in_a_deleted_directory" =>
          \&test_gho_opens_deleted_file_in_a_deleted_directory,
        "test_implicit_head_mapping_cannot_prove_topic_tracking" =>
          \&test_implicit_head_mapping_cannot_prove_topic_tracking,
        "test_gho_uses_the_git_tree_spelling_for_a_decomposed_filename" =>
          \&test_gho_uses_the_git_tree_spelling_for_a_decomposed_filename,
        "test_gho_opens_unpublished_branches_and_paths" => \&test_gho_opens_unpublished_branches_and_paths,
        "test_tracked_symlinks_open_the_link_and_installed_links_resolve" =>
          \&test_tracked_symlinks_open_the_link_and_installed_links_resolve,
        "test_submodule_root_opens_the_submodule_repository" =>
          \&test_submodule_root_opens_the_submodule_repository,
        "test_existing_file_and_directory_open_offline_without_network" =>
          \&test_existing_file_and_directory_open_offline_without_network,
        "test_current_branch_urls_batch_checks_without_scanning_local_changes" =>
          \&test_current_branch_urls_batch_checks_without_scanning_local_changes,
        "test_current_branch_checkout_uses_linked_worktree_refs" =>
          \&test_current_branch_checkout_uses_linked_worktree_refs,
        "test_current_branch_open_survives_missing_objects_in_ref_listing" =>
          \&test_current_branch_open_survives_missing_objects_in_ref_listing,
        "test_current_branch_open_rejects_dangling_case_alias_over_packed_ref" =>
          \&test_current_branch_open_rejects_dangling_case_alias_over_packed_ref,
        "test_repository_url_batches_remote_checks_but_honors_rewrites" =>
          \&test_repository_url_batches_remote_checks_but_honors_rewrites,
        "test_existing_checkout_without_remotes_adds_origin" =>
          \&test_existing_checkout_without_remotes_adds_origin,
        "test_unborn_checkout_without_remotes_adds_origin" =>
          \&test_unborn_checkout_without_remotes_adds_origin,
        "test_checkout_with_only_a_different_remote_is_not_reassigned" =>
          \&test_checkout_with_only_a_different_remote_is_not_reassigned,
        "test_repository_url_does_not_use_git_config_override_for_remote_identity" =>
          \&test_repository_url_does_not_use_git_config_override_for_remote_identity,
        "test_comparison_of_local_commit_ids_skips_remote_metadata" =>
          \&test_comparison_of_local_commit_ids_skips_remote_metadata,
        "test_longer_cached_branch_wins_over_a_shorter_local_ref" =>
          \&test_longer_cached_branch_wins_over_a_shorter_local_ref,
        "test_local_tag_wins_over_a_cached_branch_with_the_same_name" =>
          \&test_local_tag_wins_over_a_cached_branch_with_the_same_name,
        "test_url_does_not_traverse_a_symlink_in_its_path" =>
          \&test_url_does_not_traverse_a_symlink_in_its_path,
        "test_new_clone_is_not_fetched_again"                        => \&test_new_clone_is_not_fetched_again,
        "test_failed_clone_removes_new_empty_organization_directory" =>
          \&test_failed_clone_removes_new_empty_organization_directory,
        "test_failed_clone_retains_preexisting_empty_organization_directory" =>
          \&test_failed_clone_retains_preexisting_empty_organization_directory,
        "test_organization_creation_race_preserves_the_other_directory" =>
          \&test_organization_creation_race_preserves_the_other_directory,
        "test_failed_clone_retains_new_nonempty_organization_and_clone_exit_status" =>
          \&test_failed_clone_retains_new_nonempty_organization_and_clone_exit_status,
        "test_successful_clone_retains_new_organization_directory" =>
          \&test_successful_clone_retains_new_organization_directory,
        "test_clean_missing_path_pulls_before_opening" => \&test_clean_missing_path_pulls_before_opening,
        "test_dirty_missing_path_does_not_pull"        => \&test_dirty_missing_path_does_not_pull,
        "test_dirty_checkout_keeps_current_branch_when_visiting_another_ref" =>
          \&test_dirty_checkout_keeps_current_branch_when_visiting_another_ref,
        "test_dirty_existing_path_does_not_fetch_uncached_short_commit" =>
          \&test_dirty_existing_path_does_not_fetch_uncached_short_commit,
        "test_ignored_file_is_not_overwritten_by_switch" => \&test_ignored_file_is_not_overwritten_by_switch,
        "test_ignored_file_is_not_overwritten_by_pull"   => \&test_ignored_file_is_not_overwritten_by_pull,
        "test_missing_path_pull_does_not_merge_diverged_history" =>
          \&test_missing_path_pull_does_not_merge_diverged_history,
        "test_line_column_and_selection_arguments_reach_the_editor" =>
          \&test_line_column_and_selection_arguments_reach_the_editor,
        "test_editor_list_is_preserved_when_position_arguments_are_appended" =>
          \&test_editor_list_is_preserved_when_position_arguments_are_appended,
        "test_public_ghe_dispatches_destination_and_normalized_anchors_without_writing" =>
          \&test_public_ghe_dispatches_destination_and_normalized_anchors_without_writing,
        "test_raw_edit_release_and_archive_routes"           => \&test_raw_edit_release_and_archive_routes,
        "test_explicit_ref_namespaces_in_file_and_tree_urls" =>
          \&test_explicit_ref_namespaces_in_file_and_tree_urls,
        "test_gho_opens_qualified_branch_names_directly" => \&test_gho_opens_qualified_branch_names_directly,
        "test_latest_release_uses_mocked_api_and_checks_out_its_tag" =>
          \&test_latest_release_uses_mocked_api_and_checks_out_its_tag,
        "test_release_checkout_caches_the_fetched_annotated_tag" =>
          \&test_release_checkout_caches_the_fetched_annotated_tag,
        "test_exact_tag_checkout_uses_packed_ref_despite_loose_case_alias" =>
          \&test_exact_tag_checkout_uses_packed_ref_despite_loose_case_alias,
        "test_release_checkout_caches_a_tag_at_an_existing_commit" =>
          \&test_release_checkout_caches_a_tag_at_an_existing_commit,
        "test_release_checkout_succeeds_when_its_cache_is_blocked" =>
          \&test_release_checkout_succeeds_when_its_cache_is_blocked,
        "test_release_checkout_uses_its_own_fetch_result" =>
          \&test_release_checkout_uses_its_own_fetch_result,
        "test_pull_request_head_and_offline_cache" => \&test_pull_request_head_and_offline_cache,
        "test_pull_request_checkout_succeeds_when_its_cache_is_blocked" =>
          \&test_pull_request_checkout_succeeds_when_its_cache_is_blocked,
        "test_pull_request_checkout_uses_its_own_fetch_result" =>
          \&test_pull_request_checkout_uses_its_own_fetch_result,
        "test_missing_file_pull_uses_its_own_fetch_result" =>
          \&test_missing_file_pull_uses_its_own_fetch_result,
        "test_missing_file_pull_stops_if_the_checked_out_branch_changes" =>
          \&test_missing_file_pull_stops_if_the_checked_out_branch_changes,
        "test_missing_file_pull_stops_if_the_branch_tip_changes" =>
          \&test_missing_file_pull_stops_if_the_branch_tip_changes,
        "test_missing_file_pull_stops_if_the_worktree_becomes_dirty" =>
          \&test_missing_file_pull_stops_if_the_worktree_becomes_dirty,
        "test_pull_request_files_uses_mocked_api_without_switching" =>
          \&test_pull_request_files_uses_mocked_api_without_switching,
        "test_shallow_pull_request_files_uses_a_cached_merge_base" =>
          \&test_shallow_pull_request_files_uses_a_cached_merge_base,
    },
    \&setUp
);
