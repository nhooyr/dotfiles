# Git regressions; run individual tests in parallel with ./ci/test.sh.
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
my $GIT         = which("git");
my $FISH        = which("fish");
my $URL         = "https://github.com/example/project.git";
my $GIT_WRAPPER = '#!/bin/sh
set -eu
skip=
command=
for arg do
    if [ "$skip" ]; then
        skip=
        continue
    fi
    case "$arg" in
        -C|-c|--git-dir|--work-tree|--namespace|--config-env) skip=1 ;;
        -*) ;;
        *) command=$arg; break ;;
    esac
done
case "$command" in
    fetch|ls-remote|clone|pull|push)
        printf \'%s\\0\' git "$#" "$@" >> "$GITHUB_TEST_TRANSPORT_LOG"
        if [ "$command" = push ]; then
            printf \'%s\\n\' \'Tests must not push.\' >&2
            exit 98
        fi
        if [ "${GITHUB_TEST_OFFLINE:-0}" = 1 ]; then
            printf \'%s\\n\' \'Fixture transport is offline.\' >&2
            exit 99
        fi
        exec "$GITHUB_TEST_REAL_GIT" @REWRITES@ "$@" ;;
    *) exec "$GITHUB_TEST_REAL_GIT" "$@" ;;
esac
';

if ( ( 0 + ( !($GIT) ) || 0 + ( !($FISH) ) ) ) {
    die "Fish and Git are required to run the regression suite";
}

sub setUp {
    my ($self) = @_;
    my ( $key, $value, $wrapper );
    $self->{temporary} = tempdir( "dotfiles-github-refs-" . "XXXXXX", TMPDIR => 1, CLEANUP => 1 );
    $self->{directory} = absolute_path( $self->{temporary} );
    $self->{bin}       = join_path( $self->{directory}, "bin" );
    make_path( $self->{bin} );
    $wrapper = join_path( $self->{bin}, "git" );
    write_file( $wrapper, replace_literal( $GIT_WRAPPER, "\@REWRITES\@", "" ) );
    chmod( 493, $wrapper );
    $self->{log}     = join_path( $self->{directory}, "transport.log" );
    $self->{urls}    = {};
    $self->{counter} = 0;
    $self->{env}     = {
        map { my $key = ($_)->[0]; my $value = ($_)->[1]; ( $key => $value ) }
        grep {
            my $key   = ($_)->[0];
            my $value = ($_)->[1];
            0 + ( !( ( index( $key, "GIT_" ) == 0 ) ) )
        } @{ [ map { [ $_, ( \%ENV )->{$_} ] } sort keys %{ ( \%ENV ) } ] }
    };
    do {
        my $updates = {
            "PATH" => (
                ( $self->{bin} . ":" )
                . (
                    exists( ( \%ENV )->{"PATH"} )
                    ? ( \%ENV )->{"PATH"}
                    : "/usr/bin:/bin"
                )
            ),
            "GIT_CONFIG_NOSYSTEM"       => "1",
            "GIT_CONFIG_SYSTEM"         => "/dev/null",
            "GIT_CONFIG_GLOBAL"         => "/dev/null",
            "GIT_TERMINAL_PROMPT"       => "0",
            "GIT_ALLOW_PROTOCOL"        => "file",
            "GIT_AUTHOR_NAME"           => "Dotfiles tests",
            "GIT_AUTHOR_EMAIL"          => "dotfiles-tests\@example.invalid",
            "GIT_COMMITTER_NAME"        => "Dotfiles tests",
            "GIT_COMMITTER_EMAIL"       => "dotfiles-tests\@example.invalid",
            "GH_HOST"                   => "",
            "GITHUB_TEST_REAL_GIT"      => $GIT,
            "GITHUB_TEST_TRANSPORT_LOG" => $self->{log},
            "XDG_CONFIG_HOME"           => join_path( $self->{directory}, "config" ),
            "XDG_DATA_HOME"             => join_path( $self->{directory}, "data" ),
            "XDG_CACHE_HOME"            => join_path( $self->{directory}, "cache" ),
            "LC_ALL"                    => "C"
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    $self->{source}  = new_repository( $self, "source" );
    $self->{initial} = commit(
        $self, $self->{source}, 'initial
', "file.txt"
    );
    $self->{urls}->{$URL} = file_uri( $self->{source} );
}

sub git {
    my ( $self, $repository, $args, $check, $input ) = @_;
    my ($result);
    $result = run_command( [ $GIT, "-C", $repository, @{$args} ],
        { "env" => $self->{env}, "input" => $input, "timeout" => 20 } );
    if ($check) {
        ( is_deeply( $result->{returncode}, 0, $result->{stderr} ) or die "assertion failed\n" );
    }
    return $result;
}

sub new_repository {
    my ( $self, $name ) = @_;
    my ($repository);
    $self->{counter} += 1;
    $repository = join_path( $self->{directory}, ( $name . $self->{counter} ) );
    make_path($repository);
    git( $self, $repository, [ "init", "--quiet", "--initial-branch=main", "--object-format=sha1" ],
        1, undef );
    return $repository;
}

sub commit {
    my ( $self, $repository, $contents, $filename ) = @_;
    my ($path);
    $path = join_path( $repository, $filename );
    make_path( dirname($path) );
    write_file( $path, $contents );
    git( $self, $repository, [ "add", "--", $filename ], 1, undef );
    git( $self, $repository, [ "commit", "--quiet", "--message", "Fixture change" ], 1, undef );
    return oid( $self, $repository, "HEAD" );
}

sub empty_root_commit {
    my ( $self, $repository, $message ) = @_;
    my ( $identity, $text, $tree );
    $tree =
      trim( git( $self, $repository, [ "hash-object", "-w", "-t", "tree", "--stdin" ], 1, "" )->{stdout} );
    $identity = "Dotfiles tests <dotfiles-tests\@example.invalid> 0 +0000";
    $text     = sprintf(
        'tree %s
author %s
committer %s

%s
', $tree, $identity, $identity, $message
    );
    return trim(
        git( $self, $repository, [ "hash-object", "-w", "-t", "commit", "--stdin" ], 1, $text )->{stdout} );
}

sub colliding_hex_commit {
    my ( $self, $repository, $with_paths ) = @_;
    my ( $blob, $identity, $subtree, $text, $tree );
    if ( 0 + ( !($with_paths) ) ) {
        return empty_root_commit( $self, $repository, "hex branch 6984" );
    }
    $blob = trim(
        git(
            $self, $repository, [ "hash-object", "-w", "--stdin" ], 1,
            'unrelated file
'
        )->{stdout}
    );
    $subtree = trim(
        git(
            $self,
            $repository,
            ["mktree"],
            1,
            sprintf(
                '100644 blob %s	file.txt
', $blob
            )
        )->{stdout}
    );
    $tree = trim(
        git(
            $self,
            $repository,
            ["mktree"],
            1,
            sprintf(
                '100644 blob %s	file.txt
040000 tree %s	fix
', $blob, $subtree
            )
        )->{stdout}
    );
    $identity = "Dotfiles tests <dotfiles-tests\@example.invalid> 0 +0000";

    # Fixed tree and message produce 20269db4..., with file.txt and fix/file.txt.
    $text = sprintf(
        'tree %s
author %s
committer %s

hex path 35985
', $tree, $identity, $identity
    );
    return trim(
        git( $self, $repository, [ "hash-object", "-w", "-t", "commit", "--stdin" ], 1, $text )->{stdout} );
}

sub oid {
    my ( $self, $repository, $ref ) = @_;
    return trim( git( $self, $repository, [ "rev-parse", "--verify", $ref ], 1, undef )->{stdout} );
}

sub clone {
    my ( $self, $single_branch, $depth, $object_filter ) = @_;
    my ( $destination, $options );
    $self->{counter} += 1;
    $destination =
      join_path( $self->{directory}, ( "checkout" . $self->{counter} ) );
    $options = ( $single_branch ? [ "--quiet", "--no-tags" ] : ["--quiet"] );
    if ($single_branch) {
        push( @{$options}, @{ [ "--single-branch", "--branch=main" ] } );
    }
    if ($depth) {
        push( @{$options}, ( "--depth=" . $depth ) );
    }
    if ($object_filter) {
        push( @{$options}, ( "--filter=" . $object_filter ) );
    }
    git(
        $self,
        ( [ $self->{directory}, "clone", @{$options}, file_uri( $self->{source} ), $destination ] )->[0],
        array_slice(
            [ $self->{directory}, "clone", @{$options}, file_uri( $self->{source} ), $destination ],
            1, undef
        ),
        1, undef
    );
    git( $self, $destination, [ "remote", "set-url", "origin", $URL ], 1, undef );
    return $destination;
}

sub empty_checkout {
    my ($self) = @_;
    my ($destination);
    $destination = new_repository( $self, "empty" );
    git( $self, $destination, [ "remote", "add", "origin", $URL ], 1, undef );
    return $destination;
}

sub matching_remote {
    my ( $self, $destination, $name, $tracking ) = @_;
    $tracking = ( $tracking || ( ( "refs/remotes/" . $name ) . "/main" ) );
    git( $self, $destination, [ "remote", "add", $name, $URL ], 1, undef );
    git(
        $self,
        $destination,
        [
            "config", "--replace-all",
            ( ( "remote." . $name ) . ".fetch" ), ( "+refs/heads/main:" . $tracking )
        ],
        1, undef
    );
    git(
        $self,
        $destination,
        [
            "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
            "fetch", "--quiet", $name
        ],
        1, undef
    );
    git( $self, $destination, [ "symbolic-ref", ( ( "refs/remotes/" . $name ) . "/HEAD" ), $tracking ],
        1, undef );
    return $tracking;
}

sub fish {
    my ( $self, $body, $args, $offline ) = @_;
    my ( $call, $env, $github_url, $local_url, $result, $rewrites, $script );
    write_file( $self->{log}, "" );
    $rewrites = [];
    for my $item_178 ( @{ [ map { [ $_, $self->{urls}->{$_} ] } sort keys %{ $self->{urls} } ] } ) {
        $github_url = ($item_178)->[0];
        $local_url  = ($item_178)->[1];
        push( @{$rewrites}, @{ [ "-c", ( ( ( "url." . $local_url ) . ".insteadOf=" ) . $github_url ) ] } );
    }
    write_file( join_path( $self->{bin}, "git" ),
        replace_literal( $GIT_WRAPPER, "\@REWRITES\@", join( " ", map { shell_quote($_) } @{$rewrites} ) ) );
    $env = {
        %{ $self->{env} },
        %{
            {
                "GITHUB_TEST_OFFLINE" => ( $offline ? "1" : "0" ),
                "EDITOR"              => "__test_editor"
            }
        }
    };
    $script = (
        (
            (
                ( -d $SOURCE )
                ? 'set -gp fish_function_path "$argv[1]"
source "$argv[1]/ghe.fish"; or exit
source "$argv[1]/gho.fish"; or exit
'
                : 'source "$argv[1]"; or exit
'
            ) . '
set -e argv[1]
set -lx 0 test
function __test_editor
    return 0
end
function open
    return 0
end
'
        )
        . $body
    );
    $result = run_command(
        [ $FISH, "--no-config", "-c", $script, $SOURCE, @{$args} ],
        { "cwd" => $self->{directory}, "env" => $env, "timeout" => 30 }
    );
    $self->{transport} = [
        map {
            my $call = $_;
            { "command" => $call->{"command"}, "args" => $call->{"args"} }
        } @{ read_calls( $self->{log} ) }
    ];
    return $result;
}

sub compare_ref {
    my ( $self, $destination, $ref, $offline, $url ) = @_;
    return fish(
        $self,
        "__ghe_compare_ref \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\"",
        [ $url, $destination, $ref ], $offline
    );
}

sub checkout {
    my ( $self, $destination, $tail, $offline ) = @_;
    return fish(
        $self,
        "__ghe_checkout \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\" '' '' '' ''",
        [ $URL, $destination, $tail ], $offline
    );
}

sub assert_success {
    my ( $self, $result ) = @_;
    (
        is_deeply( $result->{returncode}, 0, ( $result->{stdout} . $result->{stderr} ) )
          or die "assertion failed\n"
    );
}

sub assert_resolves {
    my ( $self, $destination, $ref, $oid, $offline ) = @_;
    my ($result);
    $result = compare_ref( $self, $destination, $ref, $offline, $URL );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $oid ) or die "assertion failed\n" );
    if ($offline) {
        (
            ok( ( scalar( @{ $self->{transport} } ) ), "Named comparison did not try to refresh" )
              or die "assertion failed\n"
        );
        ( ok( contains_value( $result->{stderr}, "cached" ) ) or die "assertion failed\n" );
    }
}

sub test_commit_ref_avoids_a_redundant_revision_lookup {
    my ($self) = @_;
    my ($result);
    $result = fish(
        $self, 'function git
    if contains -- rev-parse $argv
        printf \'unexpected revision lookup\\n\' >&2
        return 99
    end
    command git $argv
end
__gh_commit "$argv[1]" refs/heads/main', [ $self->{source} ], 1
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
    ( is_deeply( $self->{transport},        [] )               or die "assertion failed\n" );
}

sub test_commit_ref_preserves_tag_peeling_and_direct_ref_checks {
    my ($self) = @_;
    my ( $cases, $mode, $ref, $result, $succeeds, $tree );
    git( $self, $self->{source}, [ "tag", "--annotate", "--message", "Release", "release" ], 1, undef );
    $tree = oid( $self, $self->{source}, "HEAD^{tree}" );
    git( $self, $self->{source}, [ "update-ref",   "refs/tags/tree",   $tree ],             1, undef );
    git( $self, $self->{source}, [ "symbolic-ref", "refs/cache/alias", "refs/heads/main" ], 1, undef );
    $cases = [
        [ "refs/tags/release", "",       1 ],
        [ $self->{initial},    "",       1 ],
        [ "refs/cache/alias",  "",       1 ],
        [ "refs/cache/alias",  "direct", 0 ],
        [ "refs/tags/tree",    "",       0 ]
    ];
    for my $item_259 ( @{$cases} ) {
        $ref      = ($item_259)->[0];
        $mode     = ($item_259)->[1];
        $succeeds = ($item_259)->[2];
        {
            $result = fish(
                $self,
                "__gh_commit \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\"",
                [ $self->{source}, $ref, $mode ], 1
            );
            if ($succeeds) {
                assert_success( $self, $result );
                ( is_deeply( trim( $result->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
            }
            else {
                ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
                ( is_deeply( $result->{stdout}, "" ) or die "assertion failed\n" );
            }
            ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
        }
    }
}

sub test_remote_matching_handles_filters_multiple_urls_and_rewrites {
    my ($self) = @_;
    my ( $configuration, $destination, $other_url, $result );
    $other_url = "https://github.com/other/project.git";
    for $configuration ( @{ [ "promisor", "multiple_urls", "push_url", "rewrite" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            if ( ( ( $configuration eq "promisor" ) ) ) {
                git( $self, $destination, [ "config", "remote.origin.promisor", "true" ], 1, undef );
                git( $self, $destination, [ "config", "remote.origin.partialclonefilter", "blob:none" ],
                    1, undef );
            }
            else {
                if ( ( ( $configuration eq "multiple_urls" ) ) ) {
                    git( $self, $destination, [ "config", "--add", "remote.origin.url", $other_url ],
                        1, undef );
                }
                else {
                    if ( ( ( $configuration eq "push_url" ) ) ) {
                        git( $self, $destination, [ "config", "remote.origin.pushurl", $other_url ],
                            1, undef );
                    }
                    else {
                        git( $self, $destination, [ "remote", "set-url", "origin", "gh-test:project.git" ],
                            1, undef );
                        git( $self, $destination,
                            [ "config", "url.https://github.com/example/.insteadOf", "gh-test:" ],
                            1, undef );
                    }
                }
            }
            $result = fish( $self, "__gh_remotes \"\$argv[1]\" \"\$argv[2]\"", [ $URL, $destination ], 1 );
            assert_success( $self, $result );
            (
                is_deeply(
                    $result->{stdout}, 'origin
'
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
            $result =
              fish( $self, "__gh_remotes \"\$argv[1]\" \"\$argv[2]\"", [ $other_url, $destination ], 1 );
            assert_success( $self, $result );
            ( is_deeply( $result->{stdout},  "" ) or die "assertion failed\n" );
            ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
            if ( ( ( $configuration eq "promisor" ) ) ) {
                $result = checkout( $self, $destination, "blob/main/file.txt", 1 );
                assert_success( $self, $result );
                (
                    is_deeply( $self->{transport}, [], "Existing partial-clone path attempted transport" )
                      or die "assertion failed\n"
                );
            }
        }
    }
}

sub test_comparison_cache_handles_unicode_ref_without_filename_expansion {
    my ($self) = @_;
    my ( $destination, $name );
    $name = ( "feature/" . ( "修复" x 20 ) );
    git( $self, $self->{source}, [ "branch", $name ], 1, undef );
    $destination = empty_checkout($self);
    assert_resolves( $self, $destination, $name, $self->{initial}, 0 );
    assert_resolves( $self, $destination, $name, $self->{initial}, 1 );
}

sub test_comparison_cache_survives_ref_hierarchy_replacements {
    my ($self) = @_;
    my ( $destination, $name, $names, $namespace, $ref, $source_ref );
    for $namespace ( @{ [ "heads", "tags" ] } ) {
        for $names ( @{ [ [ "topic", "topic/fix" ], [ "topic/fix", "topic" ] ] } ) {
            {
                $destination = empty_checkout($self);
                for $name ( @{$names} ) {
                    $source_ref =
                      ( ( ( "refs/" . $namespace ) . "/" ) . $name );
                    git( $self, $self->{source}, [ "update-ref", $source_ref, $self->{initial} ], 1, undef );
                    $ref = ( ( $namespace . "/" ) . $name );
                    assert_resolves( $self, $destination, $ref, $self->{initial}, 0 );
                    assert_resolves( $self, $destination, $ref, $self->{initial}, 1 );
                    git( $self, $self->{source}, [ "update-ref", "-d", $source_ref ], 1, undef );
                }
            }
        }
    }
}

sub test_preexisting_comparison_cache_formats_work_offline {
    my ($self) = @_;
    my ( $cache_format, $destination, $identity, $key, $namespace, $source_ref );
    for $namespace ( @{ [ "heads", "tags" ] } ) {
        $source_ref = ( ( "refs/" . $namespace ) . "/Topic" );
        for $cache_format ( @{ [ "hierarchical", "escaped", "hashed" ] } ) {
            {
                $destination = empty_checkout($self);
                git( $self, $destination,
                    [ "fetch", "--quiet", "--no-tags", file_uri( $self->{source} ), "main" ],
                    1, undef );
                $identity = trim(
                    git(
                        $self, $destination, [ "hash-object", "--stdin" ], 1,
                        'example/project
'
                    )->{stdout}
                );
                $key = {
                    "hierarchical" => $source_ref,
                    "escaped"      => ( ( "refs_2F_" . $namespace ) . "_2F_Topic" ),
                    "hashed"       => (
                        "by-ref/" . trim(
                            git(
                                $self,
                                $destination,
                                [ "hash-object", "--stdin" ],
                                1,
                                (
                                    $source_ref . '
'
                                )
                            )->{stdout}
                        )
                    )
                }->{$cache_format};
                git(
                    $self,
                    $destination,
                    [
                        "update-ref", ( ( ( "refs/gh/compare/" . $identity ) . "/" ) . $key ),
                        $self->{initial}
                    ],
                    1, undef
                );
                assert_resolves( $self, $destination, ( $namespace . "/Topic" ), $self->{initial}, 1 );
                (
                    ok(
                        !equal_values(
                            compare_ref( $self, $destination, ( $namespace . "/topic" ), 1, $URL )
                              ->{returncode},
                            0
                        )
                      )
                      or die "assertion failed\n"
                );
            }
        }
    }
}

sub test_comparison_request_cannot_alias_another_cache_key {
    my ($self) = @_;
    my ( $branch, $destination, $identity, $main_key, $result, $tip );
    $main_key = trim(
        git(
            $self, $self->{source}, [ "hash-object", "--stdin" ], 1, 'main
'
        )->{stdout}
    );
    for $branch ( @{ [ ( "by-ref/" . $main_key ), "refs_2F_heads_2F_main" ] } ) {
        {
            git( $self, $self->{source}, [ "switch", "--quiet", "--create", $branch, "main" ], 1, undef );
            $tip = commit(
                $self,
                $self->{source},
                (
                    $branch . '
'
                ),
                "file.txt"
            );
            git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
            $destination = clone( $self, 0, undef, undef );
            assert_success( $self, compare_ref( $self, $destination, "main", 0, $URL ) );
            $identity = trim(
                git(
                    $self, $destination, [ "hash-object", "--stdin" ], 1,
                    'example/project
'
                )->{stdout}
            );

            # Keep an older escaped cache beside the current hashed main cache.
            git(
                $self,
                $destination,
                [
                    "update-ref", ( ( "refs/gh/compare/" . $identity ) . "/refs_2F_heads_2F_main" ),
                    $self->{initial}
                ],
                1, undef
            );
            (
                is_deeply( oid( $self, $destination, ( "refs/remotes/origin/" . $branch ) ), $tip )
                  or die "assertion failed\n"
            );
            $result = compare_ref( $self, $destination, $branch, 1, $URL );
            assert_success( $self, $result );
            ( is_deeply( trim( $result->{stdout} ), $tip ) or die "assertion failed\n" );
        }
    }
}

sub test_fork_comparison_caches_are_repository_specific {
    my ($self) = @_;
    my ( $destination, $expected, $fork, $oid, $owner, $ref, $repository );
    $destination = empty_checkout($self);
    $expected    = {};
    for my $item_360 ( @{ [ [ "alice", "project" ], [ "bob", "other-project" ] ] } ) {
        $owner      = ($item_360)->[0];
        $repository = ($item_360)->[1];
        $fork       = new_repository( $self, $owner );
        $oid        = commit(
            $self, $fork,
            (
                $owner . '
'
            ),
            "file.txt"
        );
        git( $self, $fork, [ "branch", "topic" ], 1, undef );
        $self->{urls}->{ ( ( ( ( "https://github.com/" . $owner ) . "/" ) . $repository ) . ".git" ) } =
          file_uri($fork);
        $ref = (
              ( ( $repository eq "project" ) )
            ? ( $owner . ":topic" )
            : ( ( ( $owner . ":" ) . $repository ) . ":topic" )
        );
        $expected->{$ref} = $oid;
        assert_resolves( $self, $destination, $ref, $oid, 0 );
    }
    ( is_deeply( scalar( @{ unique_values( [ values %{$expected} ] ) } ), 2 ) or die "assertion failed\n" );
    for my $item_369 ( @{ [ map { [ $_, $expected->{$_} ] } sort keys %{$expected} ] } ) {
        $ref = ($item_369)->[0];
        $oid = ($item_369)->[1];
        assert_resolves( $self, $destination, $ref, $oid, 1 );
    }
}

sub test_fork_comparison_does_not_fetch_or_prune_unrelated_tags {
    my ($self) = @_;
    my ( $destination, $fork, $tip );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "tag", "local-only" ], 1, undef );
    git( $self, $destination, [ "config", "fetch.prune",     "true" ], 1, undef );
    git( $self, $destination, [ "config", "fetch.pruneTags", "true" ], 1, undef );
    $fork = new_repository( $self, "alice" );
    commit(
        $self, $fork, 'older tagged commit
', "file.txt"
    );
    git( $self, $fork, [ "tag", "fork-only" ], 1, undef );
    $tip = commit(
        $self, $fork, 'newer branch commit
', "file.txt"
    );
    $self->{urls}->{"https://github.com/alice/project.git"} = file_uri($fork);
    assert_resolves( $self, $destination, "alice:main", $tip, 0 );
    (
        is_deeply(
            git( $self, $destination, ["tag"], 1, undef )->{stdout}, 'local-only
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply( oid( $self, $destination, "refs/tags/local-only" ), $self->{initial} )
          or die "assertion failed\n"
    );
}

sub test_named_comparisons_refresh_and_keep_latest_snapshot_offline {
    my ($self) = @_;
    my ( $call, $contents, $destination, $expected, $offline, $qualified, $ref, $repository, $result, $tip );
    for $qualified ( @{ [ 0, 1 ] } ) {
        {
            git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
            $repository = $self->{source};
            $ref        = "topic";
            if ($qualified) {
                $repository = new_repository( $self, "alice" );
                git( $self, $repository, [ "fetch", "--quiet", file_uri( $self->{source} ), "main" ],
                    1, undef );
                git( $self, $repository, [ "reset", "--hard", "FETCH_HEAD" ], 1, undef );
                $self->{urls}->{"https://github.com/alice/project.git"} =
                  file_uri($repository);
                $ref = "alice:topic";
            }
            git( $self, $repository, [ "branch", "topic" ], 1, undef );
            $destination = clone( $self, 0, undef, undef );
            git( $self, $repository, [ "switch", "--quiet", "topic" ], 1, undef );
            for $contents (
                @{
                    [
                        'first remote version
', 'second remote version
'
                    ]
                }
              )
            {
                $tip = commit( $self, $repository, $contents, "file.txt" );
                $expected =
                  git( $self, $repository, [ "diff", ( ( $self->{initial} . "..." ) . $tip ), "--" ],
                    1, undef )->{stdout};
                for $offline ( @{ [ 0, 1 ] } ) {
                    $result = fish(
                        $self,
                        "__ghe_compare \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\"",
                        [ $URL, $destination, ( "main..." . $ref ) ], $offline
                    );
                    assert_success( $self, $result );
                    ( is_deeply( $result->{stdout}, $expected )   or die "assertion failed\n" );
                    ( ok( ( scalar( @{ $self->{transport} } ) ) ) or die "assertion failed\n" );
                    if ($offline) {
                        ( ok( contains_value( $result->{stderr}, "cached" ) ) or die "assertion failed\n" );
                    }
                    else {
                        (
                            ok(
                                (
                                    0 + !!(
                                        grep { $_ } @{
                                            [
                                                map {
                                                    my $call = $_;
                                                    ( ( $call->{"command"} eq "fetch" ) )
                                                } @{ $self->{transport} }
                                            ]
                                        }
                                    )
                                )
                              )
                              or die "assertion failed\n"
                        );
                    }
                    (
                        is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} )
                          or die "assertion failed\n"
                    );
                    (
                        is_deeply(
                            read_file( join_path( $destination, "file.txt" ) ),
                            'initial
'
                          )
                          or die "assertion failed\n"
                    );
                    (
                        is_deeply(
                            git( $self, $destination, [ "status", "--porcelain" ], 1, undef )->{stdout}, "" )
                          or die "assertion failed\n"
                    );
                }
            }
            git( $self, $repository, [ "switch", "--quiet", "main" ], 1, undef );
        }
    }
}

sub test_named_comparison_rejects_tracking_written_through_a_custom_symref {
    my ($self) = @_;
    my ( $alias, $destination, $foreign, $foreign_tip, $result, $tracking );
    $destination = clone( $self, 0, undef, undef );
    $foreign     = new_repository( $self, "foreign" );
    $foreign_tip = commit(
        $self, $foreign, 'foreign branch
', "file.txt"
    );
    $alias    = "refs/cache/foreign-main";
    $tracking = "refs/remotes/origin/main";
    git( $self, $destination, [ "remote", "add", "other", file_uri($foreign) ], 1, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.other.fetch", ( "+refs/heads/main:" . $alias ) ],
        1, undef );
    git( $self, $destination, [ "symbolic-ref", $alias, $tracking ], 1, undef );
    git( $self, $destination, [ "fetch", "--quiet", "other" ], 1, undef );
    ( is_deeply( oid( $self, $destination, $tracking ), $foreign_tip ) or die "assertion failed\n" );
    $result = compare_ref( $self, $destination, "main", 1, $URL );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( $result->{stdout}, "" ) or die "assertion failed\n" );
    assert_resolves( $self, $destination, "main", $self->{initial}, 0 );
    ( is_deeply( oid( $self, $destination, $tracking ), $self->{initial} ) or die "assertion failed\n" );
    assert_resolves( $self, $destination, "main", $self->{initial}, 1 );
}

sub test_named_comparison_follows_a_synchronized_tracking_ref_offline {
    my ($self) = @_;
    my ( $destination, $newer, $rewrite );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "heads/main", $self->{initial}, 0 );
    $newer = commit(
        $self, $self->{source}, 'fetched outside ghe
', "file.txt"
    );
    $rewrite =
      ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL );
    git( $self, $destination, [ "-c", $rewrite, "fetch", "--quiet", "origin" ], 1, undef );
    assert_resolves( $self, $destination, "main",       $newer, 1 );
    assert_resolves( $self, $destination, "heads/main", $newer, 1 );
    assert_resolves( $self, $destination, "main",       $newer, 0 );
    git( $self, $self->{source}, [ "reset", "--hard", $self->{initial} ], 1, undef );
    git( $self, $destination, [ "-c", $rewrite, "fetch", "--quiet", "origin" ], 1, undef );
    assert_resolves( $self, $destination, "main",       $self->{initial}, 1 );
    assert_resolves( $self, $destination, "heads/main", $self->{initial}, 1 );
    git( $self, $destination, [ "update-ref", "-d", "refs/remotes/origin/main" ], 1, undef );
    assert_resolves( $self, $destination, "main",       $newer, 1 );
    assert_resolves( $self, $destination, "heads/main", $newer, 1 );
}

sub test_bare_comparison_does_not_follow_a_branch_after_selecting_a_same_oid_tag {
    my ($self) = @_;
    my ( $destination, $newer );
    git( $self, $self->{source}, [ "branch", "release" ], 1, undef );
    git( $self, $self->{source}, [ "tag",    "release" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "release", $self->{initial}, 0 );
    git( $self, $self->{source}, [ "branch", "--delete", "release" ], 1, undef );
    assert_resolves( $self, $destination, "release", $self->{initial}, 0 );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "release" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'new release branch
', "file.txt"
    );
    git(
        $self,
        $destination,
        [
            "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
            "fetch", "--quiet", "origin"
        ],
        1, undef
    );
    assert_resolves( $self, $destination, "release",       $self->{initial}, 1 );
    assert_resolves( $self, $destination, "heads/release", $newer,           1 );
}

sub test_offline_comparison_rejects_local_branch_as_a_tracking_snapshot {
    my ($self) = @_;
    my ( $destination, $local, $result );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:refs/heads/main" ],
        1, undef );
    $local = commit(
        $self, $destination, 'unpublished local commit
', "file.txt"
    );
    $result = compare_ref( $self, $destination, "main", 1, $URL );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( $result->{stdout},                  "" )     or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $local ) or die "assertion failed\n" );
    assert_resolves( $self, $destination, "main", $self->{initial}, 0 );
    assert_resolves( $self, $destination, "main", $self->{initial}, 1 );
}

sub test_named_comparison_works_when_a_snapshot_ref_is_locked {
    my ($self) = @_;
    my ( $cache, $destination, $identity, $key, $keys, $lock, $newer, $ref );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "main", $self->{initial}, 0 );
    $newer = commit(
        $self, $self->{source}, 'updated main
', "file.txt"
    );
    $identity = trim(
        git(
            $self, $destination, [ "hash-object", "--stdin" ], 1,
            'example/project
'
        )->{stdout}
    );
    $cache = ( "refs/gh/compare/" . $identity . "/by-ref" );
    $keys  = [
        map {
            my $ref = $_;
            trim(
                git(
                    $self,
                    $destination,
                    [ "hash-object", "--stdin" ],
                    1,
                    (
                        $ref . '
'
                    )
                )->{stdout}
            )
        } @{ [ "main", "refs/heads/main" ] }
    ];
    $lock = join_path( join_path( $destination, ".git" ), ( $cache . "/" . $keys->[1] . ".lock" ) );
    write_file(
        $lock, 'held by another process
'
    );
    assert_resolves( $self, $destination, "main", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
          or die "assertion failed\n"
    );
    for $key ( @{$keys} ) {
        (
            is_deeply( oid( $self, $destination, ( $cache . "/" . $key ) ), $self->{initial} )
              or die "assertion failed\n"
        );
    }
}

sub test_delayed_comparison_keeps_a_newer_tracked_snapshot {
    my ($self) = @_;
    my ( $destination, $first, $ref, $result, $second );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $first = commit(
        $self, $self->{source}, 'first topic tip
', "file.txt"
    );
    $second = commit(
        $self, $self->{source}, 'second topic tip
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    git( $self, $self->{source}, [ "branch", "--force", "topic", $first ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    $result      = fish(
        $self, 'set -g repository "$argv[1]"
set -g checkout "$argv[2]"
set -g source "$argv[3]"
set -g newer "$argv[4]"
function git
    command git $argv; or return
    if not set -q interleaved; and contains -- fetch $argv; and contains -- --stdin $argv
        set -g interleaved true
        command git -C "$source" update-ref refs/heads/topic "$newer"; or return
        __ghe_compare_ref "$repository" "$checkout" topic >/dev/null; or return
    end
end
__ghe_compare_ref "$repository" "$checkout" topic',
        [ $URL, $destination, $self->{source}, $second ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $first ) or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/topic" ), $second )
          or die "assertion failed\n"
    );
    for $ref ( @{ [ "topic", "heads/topic" ] } ) {
        assert_resolves( $self, $destination, $ref, $second, 1 );
    }
}

sub test_delayed_comparison_does_not_replace_a_newer_tag_snapshot {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    git( $self, $self->{source}, [ "tag", "release" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "release", $self->{initial}, 0 );
    $newer = commit(
        $self, $self->{source}, 'moved release tag
', "file.txt"
    );
    $result = fish(
        $self, 'set -g repository "$argv[1]"
set -g checkout "$argv[2]"
set -g source "$argv[3]"
set -g newer "$argv[4]"
function git
    command git $argv; or return
    if not set -q interleaved; and contains -- fetch $argv; and contains -- --stdin $argv
        set -g interleaved true
        command git -C "$source" update-ref refs/tags/release "$newer"; or return
        __ghe_compare_ref "$repository" "$checkout" tags/release >/dev/null; or return
    end
end
__ghe_compare_ref "$repository" "$checkout" release',
        [ $URL, $destination, $self->{source}, $newer ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
    assert_resolves( $self, $destination, "tags/release", $newer, 1 );
}

sub test_delayed_comparison_cannot_restore_a_branch_after_selecting_a_same_oid_tag {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    git( $self, $self->{source}, [ "branch", "release" ], 1, undef );
    git( $self, $self->{source}, [ "tag",    "release" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "release", $self->{initial}, 0 );
    $newer = commit(
        $self, $self->{source}, 'new release branch
', "file.txt"
    );
    $result = fish(
        $self, 'set -g repository "$argv[1]"
set -g checkout "$argv[2]"
set -g source "$argv[3]"
function git
    command git $argv; or return
    if not set -q interleaved; and contains -- fetch $argv; and contains -- --stdin $argv
        set -g interleaved true
        command git -C "$source" branch --delete release >/dev/null; or return
        __ghe_compare_ref "$repository" "$checkout" release >/dev/null; or return
    end
end
__ghe_compare_ref "$repository" "$checkout" release',
        [ $URL, $destination, $self->{source} ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
    git( $self, $self->{source}, [ "branch", "release", $newer ], 1, undef );
    git(
        $self,
        $destination,
        [
            "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
            "fetch", "--quiet", "origin", "refs/heads/release"
        ],
        1, undef
    );
    assert_resolves( $self, $destination, "release",       $self->{initial}, 1 );
    assert_resolves( $self, $destination, "heads/release", $newer,           1 );
}

sub test_moved_tag_and_branch_to_tag_comparison_keep_latest_snapshot {
    my ($self) = @_;
    my ( $destination, $newer );
    git( $self, $self->{source}, [ "tag",    "release" ], 1, undef );
    git( $self, $self->{source}, [ "branch", "release" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    $newer       = commit(
        $self, $self->{source}, 'retagged version
', "file.txt"
    );
    git( $self, $self->{source}, [ "tag", "--force", "release", $newer ], 1, undef );
    assert_resolves( $self, $destination, "tags/release", $newer,           0 );
    assert_resolves( $self, $destination, "tags/release", $newer,           1 );
    assert_resolves( $self, $destination, "release",      $self->{initial}, 0 );
    git( $self, $self->{source}, [ "branch", "--delete", "release" ], 1, undef );
    assert_resolves( $self, $destination, "release", $newer, 0 );
    assert_resolves( $self, $destination, "release", $newer, 1 );
    (
        is_deeply( oid( $self, $destination, "refs/tags/release" ), $self->{initial} )
          or die "assertion failed\n"
    );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
}

sub test_deleted_comparison_ref_does_not_fall_back_to_stale_cache {
    my ($self) = @_;
    my ( $call, $destination, $namespace, $ref, $result, $source_ref );
    for my $item_607 ( @{ [ [ "heads", "topic" ], [ "tags", "tags/topic" ] ] } ) {
        $namespace = ($item_607)->[0];
        $ref       = ($item_607)->[1];
        {
            $source_ref = ( ( "refs/" . $namespace ) . "/topic" );
            git( $self, $self->{source}, [ "update-ref", $source_ref, $self->{initial} ], 1, undef );
            $destination = clone( $self, 0, undef, undef );
            assert_resolves( $self, $destination, $ref, $self->{initial}, 0 );
            git( $self, $self->{source}, [ "update-ref", "-d", $source_ref ], 1, undef );
            $result = compare_ref( $self, $destination, $ref, 0, $URL );
            (
                ok( !equal_values( $result->{returncode}, 0 ), $result->{stdout} )
                  or die "assertion failed\n"
            );
            ( is_deeply( $result->{stdout}, "" ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "no branch, tag, or commit matches" ) )
                  or die "assertion failed\n"
            );
            (
                ok(
                    (
                        0 + !!(
                            grep { $_ } @{
                                [
                                    map {
                                        my $call = $_;
                                        ( ( $call->{"command"} eq "ls-remote" ) )
                                    } @{ $self->{transport} }
                                ]
                            }
                        )
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
        }
    }
}

sub test_hex_named_comparison_branch_is_refreshed {
    my ($self) = @_;
    my ( $call, $destination, $newer );
    git( $self, $self->{source}, [ "branch", "2026" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    $newer       = commit(
        $self, $self->{source}, 'new hexadecimal branch version
', "file.txt"
    );
    git( $self, $self->{source}, [ "branch", "--force", "2026", $newer ], 1, undef );
    assert_resolves( $self, $destination, "2026", $newer, 0 );
    (
        ok(
            (
                0 + !!(
                    grep { $_ } @{
                        [
                            map {
                                my $call = $_;
                                ( ( $call->{"command"} eq "fetch" ) )
                            } @{ $self->{transport} }
                        ]
                    }
                )
            )
          )
          or die "assertion failed\n"
    );
    assert_resolves( $self, $destination, "2026", $newer, 1 );
}

sub test_named_comparison_has_no_array_index_errors_with_bsd_seq {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    $destination = clone( $self, 0, undef, undef );
    $newer       = commit(
        $self, $self->{source}, 'updated main
', "file.txt"
    );
    $result = fish(
        $self, 'function seq
    if test "$argv" = 0
        printf \'%s\\n\' 1 0
    else
        command seq $argv
    end
end
__ghe_compare_ref "$argv[1]" "$argv[2]" main', [ $URL, $destination ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $newer ) or die "assertion failed\n" );
    ( is_deeply( $result->{stderr},         "" )     or die "assertion failed\n" );
}

sub test_cached_comparison_commit_ids_do_not_attempt_transport {
    my ($self) = @_;
    my ( $destination, $offline, $ref, $result );
    $destination = clone( $self, 0, undef, undef );
    for $ref ( @{ [ $self->{initial}, string_slice( $self->{initial}, undef, 10 ) ] } ) {
        for $offline ( @{ [ 0, 1 ] } ) {
            {
                $result = compare_ref( $self, $destination, $ref, $offline, $URL );
                assert_success( $self, $result );
                ( is_deeply( trim( $result->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
                ( is_deeply( $self->{transport},        [] )               or die "assertion failed\n" );
            }
        }
    }
}

sub test_cached_comparison_tips_fetch_a_missing_shallow_merge_base {
    my ($self) = @_;
    my (
        $base, $before, $cached,  $call,   $compare,    $destination,
        $head, $length, $offline, $online, $range_spec, $two_dot
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $head = commit(
        $self, $self->{source}, 'topic change
', "topic.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $base = commit(
        $self, $self->{source}, 'main change
', "main.txt"
    );
    for $length ( @{ [ 40, 10 ] } ) {
        {
            $destination = clone( $self, 0, 1, undef );
            git( $self, $destination,
                [ "fetch", "--quiet", "--depth=1", file_uri( $self->{source} ), "refs/heads/topic" ],
                1, undef );
            $before =
              git( $self, $destination, ["for-each-ref"], 1, undef )->{stdout};
            $compare = "__ghe_compare \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\"";
            $two_dot = fish(
                $self, $compare,
                [
                    $URL,
                    $destination,
                    ( string_slice( $base, undef, $length ) . ".." . string_slice( $head, undef, $length ) )
                ],
                1
            );
            assert_success( $self, $two_dot );
            ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
            $range_spec =
              ( string_slice( $base, undef, $length ) . "..." . string_slice( $head, undef, $length ) );
            $offline = fish( $self, $compare, [ $URL, $destination, $range_spec ], 1 );
            ( is_deeply( $offline->{returncode}, 1 ) or die "assertion failed\n" );
            (
                ok( contains_value( $offline->{stderr}, "comparison has no local merge base" ) )
                  or die "assertion failed\n"
            );
            (
                is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ], ["fetch"] )
                  or die "assertion failed\n"
            );
            $online = fish( $self, $compare, [ $URL, $destination, $range_spec ], 0 );
            assert_success( $self, $online );
            ( ok( contains_value( $online->{stdout},  "+topic change" ) ) or die "assertion failed\n" );
            ( ok( !contains_value( $online->{stdout}, "main.txt" ) )      or die "assertion failed\n" );
            (
                is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ], ["fetch"] )
                  or die "assertion failed\n"
            );
            (
                is_deeply( git( $self, $destination, ["for-each-ref"], 1, undef )->{stdout}, $before )
                  or die "assertion failed\n"
            );
            $cached = fish( $self, $compare, [ $URL, $destination, $range_spec ], 1 );
            assert_success( $self, $cached );
            ( is_deeply( $cached->{stdout},  $online->{stdout} ) or die "assertion failed\n" );
            ( is_deeply( $self->{transport}, [] )                or die "assertion failed\n" );
        }
    }
}

sub test_cached_comparison_ancestors_fetch_a_missing_shallow_merge_base {
    my ($self) = @_;
    my ( $call, $compare, $destination, $head, $parent, $range_spec, $result, $tip );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    commit(
        $self, $self->{source}, 'topic parent
', "topic.txt"
    );
    $head = commit(
        $self, $self->{source}, 'topic change
', "topic.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $parent = commit(
        $self, $self->{source}, 'main parent
', "main.txt"
    );
    $tip = commit(
        $self, $self->{source}, 'main tip
', "main.txt"
    );
    $destination = clone( $self, 0, 2, undef );
    git( $self, $destination,
        [ "fetch", "--quiet", "--depth=2", file_uri( $self->{source} ), "refs/heads/topic" ],
        1, undef );
    ( is_deeply( oid( $self, $destination, ( $tip . "~1" ) ), $parent ) or die "assertion failed\n" );
    (
        is_deeply( git( $self, $destination, [ "merge-base", $parent, $head ], 0, undef )->{returncode}, 1 )
          or die "assertion failed\n"
    );
    $compare    = "__ghe_compare \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\"";
    $range_spec = ( string_slice( $tip, undef, 10 ) . "~1..." . $head );
    $result     = fish( $self, $compare, [ $URL, $destination, $range_spec ], 0 );
    assert_success( $self, $result );
    ( ok( contains_value( $result->{stdout}, "+topic change" ) ) or die "assertion failed\n" );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ], ["fetch"] )
          or die "assertion failed\n"
    );
}

sub test_shallow_three_dot_comparison_checks_for_a_closer_merge_base {
    my ($self) = @_;
    my (
        $anchor, $base,        $branch,   $call,       $common, $compare,
        $depth,  $destination, $expected, $generation, $head,   $local_base,
        $mixed,  $offline,     $online,   $range_spec, $side,   $tips
    );
    for $generation ( @{ [ 0 .. ( 3 - 1 ) ] } ) {
        $anchor = commit(
            $self,
            $self->{source},
            (
                "ancestor "
                  . $generation . '
'
            ),
            "ancestor.txt"
        );
    }
    for $side ( @{ [ "left-side", "right-side" ] } ) {
        git( $self, $self->{source}, [ "switch", "--quiet", "--create", $side, "main" ], 1, undef );
        commit(
            $self,
            $self->{source},
            (
                $side . '
'
            ),
            ( $side . ".txt" )
        );
    }
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $common = commit(
        $self, $self->{source}, 'already shared
', "shared.txt"
    );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    $tips = [];
    for my $item_726 ( @{ [ [ "topic", "right-side" ], [ "main", "left-side" ] ] } ) {
        $branch = ($item_726)->[0];
        $side   = ($item_726)->[1];
        git( $self, $self->{source}, [ "switch", "--quiet", $branch ], 1, undef );
        commit(
            $self,
            $self->{source},
            (
                $branch
                  . ' parent
'
            ),
            ( $branch . ".txt" )
        );
        commit(
            $self,
            $self->{source},
            (
                $branch
                  . ' change
'
            ),
            ( $branch . ".txt" )
        );
        git( $self, $self->{source}, [ "merge", "--quiet", "--no-edit", "--no-ff", $side ], 1, undef );
        push( @{$tips}, oid( $self, $self->{source}, "HEAD" ) );
    }
    { my $tuple = $tips; $head = ($tuple)->[0]; $base = ($tuple)->[1]; }
    $range_spec = ( $base . "..." . $head );
    $compare    = "__ghe_compare \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\"";
    $expected   = git( $self, $self->{source}, [ "diff", $range_spec, "--" ], 1, undef )->{stdout};
    ( ok( !contains_value( $expected, "shared.txt" ) ) or die "assertion failed\n" );
    for my $item_738 ( @{ [ [ 3, $anchor ], [ 5, $common ] ] } ) {
        $depth      = ($item_738)->[0];
        $local_base = ($item_738)->[1];
        {
            $destination = clone( $self, 0, $depth, undef );
            git(
                $self,
                $destination,
                [
                    "fetch",                 "--quiet",
                    ( "--depth=" . $depth ), file_uri( $self->{source} ),
                    "refs/heads/topic"
                ],
                1, undef
            );
            (
                is_deeply(
                    trim( git( $self, $destination, [ "merge-base", $base, $head ], 1, undef )->{stdout} ),
                    $local_base )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    trim(
                        git( $self, $destination, [ "rev-parse", "--is-shallow-repository" ], 1, undef )
                          ->{stdout}
                    ),
                    "true"
                  )
                  or die "assertion failed\n"
            );
            $offline = fish( $self, $compare, [ $URL, $destination, $range_spec ], 1 );
            if ( ( ( $depth eq 5 ) ) ) {
                assert_success( $self, $offline );
                ( is_deeply( $offline->{stdout}, $expected ) or die "assertion failed\n" );
                ( is_deeply( $self->{transport}, [] )        or die "assertion failed\n" );
                next;
            }
            ( ok( !equal_values( $offline->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok(
                    contains_value(
                        $offline->{stderr}, "shallow history may hide a closer comparison merge base"
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( $offline->{stdout}, "" ) or die "assertion failed\n" );
            (
                is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ], ["fetch"] )
                  or die "assertion failed\n"
            );
            git( $self, $destination,
                [ "config", "--add", "remote.origin.fetch", "+refs/heads/topic:refs/remotes/origin/topic" ],
                1, undef );
            git( $self, $destination, [ "update-ref", "refs/remotes/origin/topic", $head ], 1, undef );
            $mixed = fish( $self, $compare, [ $URL, $destination, ( $base . "...topic" ) ], 1 );
            ( ok( !equal_values( $mixed->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok(
                    contains_value(
                        $mixed->{stderr}, "shallow history may hide a closer comparison merge base"
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( $mixed->{stdout}, "" ) or die "assertion failed\n" );
            $online = fish( $self, $compare, [ $URL, $destination, $range_spec ], 0 );
            assert_success( $self, $online );
            ( is_deeply( $online->{stdout}, $expected ) or die "assertion failed\n" );
            (
                is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ], ["fetch"] )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_cached_commit_ancestry_in_shallow_clone_fetches_missing_history {
    my ($self) = @_;
    my ( $call, $destination, $parent, $ref, $result, $tip );
    $parent = commit(
        $self, $self->{source}, 'parent
', "file.txt"
    );
    $tip = commit(
        $self, $self->{source}, 'tip
', "file.txt"
    );
    for $ref ( @{ [ ( $tip . "~1" ), ( string_slice( $tip, undef, 10 ) . "~1" ) ] } ) {
        {
            $destination = clone( $self, 0, 1, undef );
            (
                is_deeply(
                    trim(
                        git( $self, $destination, [ "rev-parse", "--is-shallow-repository" ], 1, undef )
                          ->{stdout}
                    ),
                    "true"
                  )
                  or die "assertion failed\n"
            );
            $result = compare_ref( $self, $destination, $ref, 0, $URL );
            assert_success( $self, $result );
            ( is_deeply( trim( $result->{stdout} ), $parent ) or die "assertion failed\n" );
            (
                ok(
                    (
                        0 + !!(
                            grep { $_ } @{
                                [
                                    map {
                                        my $call = $_;
                                        ( ( $call->{"command"} eq "fetch" ) )
                                    } @{ $self->{transport} }
                                ]
                            }
                        )
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $tip ) or die "assertion failed\n" );
            (
                is_deeply(
                    read_file( join_path( $destination, "file.txt" ) ), 'tip
'
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_head_file_open_follows_pulls_and_comparisons_in_observation_order {
    my ($self) = @_;
    my ( $compared, $destination, $mapping, $pulled );
    for $mapping (
        @{
            [
                "+refs/heads/*:refs/remotes/origin/*", "+refs/heads/*:refs/cache/origin/*",
                "+refs/heads/*:refs/custom/origin/*"
            ]
        }
      )
    {
        {
            $destination = clone( $self, 0, undef, undef );
            git( $self, $destination, [ "config", "--replace-all", "remote.origin.fetch", $mapping ],
                1, undef );
            git(
                $self,
                $destination,
                [
                    "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                    "fetch", "--quiet", "origin"
                ],
                1, undef
            );
            assert_resolves( $self, $destination, "HEAD", oid( $self, $self->{source}, "HEAD" ), 0 );
            $pulled = commit(
                $self, $self->{source}, 'pulled default version
', "file.txt"
            );
            git(
                $self,
                $destination,
                [
                    "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                    "pull", "--quiet", "--ff-only", "origin", "main"
                ],
                1, undef
            );
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $pulled ) or die "assertion failed\n" );
            $compared = commit(
                $self, $self->{source}, 'comparison default version
', "file.txt"
            );
            assert_resolves( $self, $destination, "HEAD", $compared, 0 );
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $compared ) or die "assertion failed\n" );
            ( is_deeply( $self->{transport},                 [] )        or die "assertion failed\n" );
        }
    }
}

sub test_head_comparison_refreshes_tracking_on_force_rewind_and_divergence {
    my ($self) = @_;
    my ( $destination, $divergent, $newer );
    $destination = clone( $self, 0, undef, undef );
    $newer       = commit(
        $self, $self->{source}, 'new remote version
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
          or die "assertion failed\n"
    );
    git( $self, $self->{source}, [ "reset", "--hard", $self->{initial} ], 1, undef );
    git(
        $self,
        $destination,
        [
            "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
            "fetch", "--quiet", "origin"
        ],
        1, undef
    );
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    $divergent = commit(
        $self, $self->{source}, 'divergent remote version
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $divergent, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $divergent )
          or die "assertion failed\n"
    );
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $divergent ) or die "assertion failed\n" );
}

sub test_head_comparison_updates_tracking_after_force_push_without_local_fetch {
    my ($self) = @_;
    my ( $call, $destination, $pushed, $remote, $rewritten, $target, $tracking );
    $destination = clone( $self, 0, undef, undef );
    $tracking    = matching_remote( $self, $destination, "aaa", "refs/cache/aaa/main" );
    $pushed      = commit(
        $self, $self->{source}, 'default before force push
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $pushed, 0 );
    git( $self, $self->{source}, [ "reset", "--hard", $self->{initial} ], 1, undef );
    $rewritten = commit(
        $self, $self->{source}, 'force-pushed default
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $rewritten, 0 );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ],
            [ "ls-remote", "fetch" ] )
          or die "assertion failed\n"
    );
    for my $item_832 ( @{ [ [ "aaa", $tracking ], [ "origin", "refs/remotes/origin/main" ] ] } ) {
        $remote = ($item_832)->[0];
        $target = ($item_832)->[1];
        ( is_deeply( oid( $self, $destination, $target ), $rewritten ) or die "assertion failed\n" );
        (
            is_deeply(
                trim(
                    git( $self, $destination, [ "symbolic-ref", ( ( "refs/remotes/" . $remote ) . "/HEAD" ) ],
                        1, undef )->{stdout}
                ),
                $target
              )
              or die "assertion failed\n"
        );
    }
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $rewritten ) or die "assertion failed\n" );
    ( is_deeply( $self->{transport},                 [] )         or die "assertion failed\n" );
}

sub test_case_distinct_branches_do_not_shadow_existing_tracking_refs {
    my ($self) = @_;
    my (
        $destination, $destinations, $earlier, $folds_case, $newer, $offline,
        $packed,      $refs,         $result,  $tracking,   $upper_refs
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "Topic" ], 1, undef );
    $earlier = commit(
        $self, $self->{source}, 'uppercase branch
', "upper.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $destinations =
      [ clone( $self, 0, undef, undef ), clone( $self, 0, undef, undef ) ];
    git( $self, $self->{source}, [ "pack-refs", "--all", "--prune" ], 1, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'lowercase branch
', "file.txt"
    );
    for my $item_847 ( @{ zip_lists( [ 1, 0 ], $destinations ) } ) {
        $packed      = ($item_847)->[0];
        $destination = ($item_847)->[1];
        {
            $tracking = "refs/remotes/origin/Topic";
            if ( 0 + ( !($packed) ) ) {
                git( $self, $destination, [ "update-ref", "-d", $tracking ], 1, undef );
                git( $self, $destination, [ "update-ref", $tracking, $earlier ], 1, undef );
            }
            $refs       = join_path( join_path( $destination, ".git" ), "refs" );
            $upper_refs = join_path( dirname($refs),                    "REFS" );
            $folds_case =
              ( ( -e $upper_refs ) && same_file( $refs, $upper_refs ) );
            $offline = compare_ref( $self, $destination, "topic", 1, $URL );
            ( ok( !equal_values( $offline->{returncode}, 0 ) ) or die "assertion failed\n" );
            assert_resolves( $self, $destination, "topic", $newer, 0 );
            ( is_deeply( oid( $self, $destination, $tracking ), $earlier ) or die "assertion failed\n" );
            $result = checkout( $self, $destination, "blob/topic/file.txt", 0 );

            if ($folds_case) {
                ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
                (
                    ok(
                        contains_value(
                            $result->{stderr}, "tracking ref conflicts with a differently spelled ref"
                        )
                      )
                      or die "assertion failed\n"
                );
                (
                    is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} )
                      or die "assertion failed\n"
                );
            }
            else {
                assert_success( $self, $result );
                ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
            }
            ( is_deeply( oid( $self, $destination, $tracking ), $earlier ) or die "assertion failed\n" );
            if ( ( $folds_case && 0 + ( !($packed) ) ) ) {
                git( $self, $destination, [ "branch", "Topic", $self->{initial} ], 1, undef );
                $result = checkout( $self, $destination, "blob/topic/file.txt", 0 );
                ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
                (
                    ok(
                        contains_value(
                            $result->{stderr}, "local branch conflicts with a differently spelled ref"
                        )
                      )
                      or die "assertion failed\n"
                );
                (
                    is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} )
                      or die "assertion failed\n"
                );
                git( $self, $destination, [ "branch", "--delete", "Topic" ],                      1, undef );
                git( $self, $destination, [ "switch", "--quiet", "--create", "topic", $earlier ], 1, undef );
                git( $self, $destination, [ "config", "branch.topic.remote", "origin" ],          1, undef );
                git( $self, $destination, [ "config", "branch.topic.merge", "refs/heads/topic" ], 1, undef );
                $result =
                  fish( $self, "__gho_url \"\$argv[1]\"", [ join_path( $destination, "upper.txt" ) ], 1 );
                assert_success( $self, $result );
                (
                    is_deeply( trim( $result->{stdout} ),
                        "https://github.com/example/project/blob/topic/upper.txt" )
                      or die "assertion failed\n"
                );
                ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
            }
        }
    }
}

sub test_compare_does_not_read_or_overwrite_a_unicode_loose_ref_alias {
    my ($self) = @_;
    my ( $destination, $newer, $older, $result, $tracking );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "münchen" ], 1, undef );
    $older = commit(
        $self, $self->{source}, 'lowercase branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    $tracking    = "refs/remotes/origin/münchen";
    git( $self, $destination,    [ "update-ref", "-d", $tracking ], 1, undef );
    git( $self, $destination,    [ "update-ref", $tracking, $older ], 1, undef );
    git( $self, $self->{source}, [ "pack-refs",  "--all", "--prune" ], 1, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "MÜNCHEN" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'uppercase branch
', "file.txt"
    );
    (
        ok( !equal_values( compare_ref( $self, $destination, "MÜNCHEN", 1, $URL )->{returncode}, 0 ) )
          or die "assertion failed\n"
    );
    assert_resolves( $self, $destination, "MÜNCHEN", $newer, 0 );
    ( is_deeply( oid( $self, $destination, $tracking ), $older ) or die "assertion failed\n" );
    git(
        $self,
        $destination,
        [
            "config",              "--replace-all",
            "remote.origin.fetch", "+refs/heads/MÜNCHEN:refs/remotes/origin/MÜNCHEN"
        ],
        1, undef
    );
    git( $self, $destination, [ "branch", "--move",               "MÜNCHEN" ],            1, undef );
    git( $self, $destination, [ "config", "branch.MÜNCHEN.merge", "refs/heads/MÜNCHEN" ], 1, undef );
    $result =
      fish( $self, "__ghe_pull \"\$argv[1]\" \"\$argv[2]\" MÜNCHEN file.txt", [ $destination, $URL ], 0 );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ),    $newer ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, $tracking ), $older ) or die "assertion failed\n" );
    git( $self, $destination, [ "update-ref", "refs/tags/café", $older ], 1, undef );
    assert_resolves( $self, $destination, "tags/café", $older, 1 );
    (
        ok( !equal_values( compare_ref( $self, $destination, "tags/café", 1, $URL )->{returncode}, 0 ) )
          or die "assertion failed\n"
    );
}

sub test_missing_full_tag_does_not_resolve_through_a_nested_tag {
    my ($self) = @_;
    my ( $destination, $result );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "tag", "--annotate", "--message", "nested tag", "refs/tags/release" ],
        1, undef );
    assert_resolves( $self, $destination, "tags/refs/tags/release", $self->{initial}, 1 );
    $result = compare_ref( $self, $destination, "tags/release", 1, $URL );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( $result->{stdout}, "" ) or die "assertion failed\n" );
}

sub test_gho_opens_paths_without_a_tracking_ref {
    my ($self) = @_;
    my ( $destination, $result, $tracking );
    $destination = clone( $self, 0, undef, undef );
    $tracking    = "refs/remotes/origin/main";
    git( $self, $destination, [ "update-ref", "-d", $tracking ], 1, undef );
    git( $self, $destination, [ "tag", $tracking, $self->{initial} ], 1, undef );
    $result = fish( $self, "__gho_url \"\$argv[1]\"", [ join_path( $destination, "file.txt" ) ], 1 );
    assert_success( $self, $result );
    (
        is_deeply( trim( $result->{stdout} ), "https://github.com/example/project/blob/main/file.txt" )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_offline_tag_comparison_does_not_reuse_a_differently_cased_tag {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    git( $self, $self->{source}, [ "tag", "Release" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "update-ref", "-d",                "refs/tags/Release" ], 1, undef );
    git( $self, $destination, [ "update-ref", "refs/tags/Release", $self->{initial} ],    1, undef );
    assert_resolves( $self, $destination, "tags/Release", $self->{initial}, 1 );
    $result = compare_ref( $self, $destination, "tags/release", 1, $URL );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    git( $self, $self->{source}, [ "pack-refs", "--all", "--prune" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'lowercase release
', "file.txt"
    );
    git( $self, $self->{source}, [ "tag", "release" ], 1, undef );
    assert_resolves( $self, $destination, "tags/release", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/tags/Release" ), $self->{initial} )
          or die "assertion failed\n"
    );
    assert_resolves( $self, $destination, "tags/release", $newer,           1 );
    assert_resolves( $self, $destination, "tags/Release", $self->{initial}, 1 );
}

sub test_topic_comparison_updates_tracking_after_force_push_without_local_fetch {
    my ($self) = @_;
    my ( $call, $destination, $rewritten );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    commit(
        $self, $self->{source}, 'topic before force push
', "topic.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "topic" ],          1, undef );
    git( $self, $self->{source}, [ "reset",  "--hard",  $self->{initial} ], 1, undef );
    $rewritten = commit(
        $self, $self->{source}, 'force-pushed topic
', "topic.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    assert_resolves( $self, $destination, "topic", $rewritten, 0 );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ],
            [ "ls-remote", "fetch" ] )
          or die "assertion failed\n"
    );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/topic" ), $rewritten )
          or die "assertion failed\n"
    );
}

sub test_head_open_follows_updates_through_each_matching_remote {
    my ($self) = @_;
    my ( $compared, $destination, $newer, $remote, $result, $target, $tracking );
    for $remote ( @{ [ "aaa", "origin" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            $tracking    = matching_remote( $self, $destination, "aaa", "refs/cache/aaa/main" );
            assert_resolves( $self, $destination, "HEAD", oid( $self, $self->{source}, "HEAD" ), 0 );
            $newer = commit(
                $self,
                $self->{source},
                (
                    ( "pulled through " . $remote ) . '
'
                ),
                "file.txt"
            );
            git(
                $self,
                $destination,
                [
                    "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                    "pull", "--quiet", "--ff-only", $remote, "main"
                ],
                1, undef
            );
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
            ( is_deeply( $self->{transport},                 [] )     or die "assertion failed\n" );
            $compared = commit(
                $self,
                $self->{source},
                (
                    ( "compared after " . $remote ) . '
'
                ),
                "file.txt"
            );
            assert_resolves( $self, $destination, "HEAD", $compared, 0 );
            for $target ( @{ [ $tracking, "refs/remotes/origin/main" ] } ) {
                ( is_deeply( oid( $self, $destination, $target ), $compared ) or die "assertion failed\n" );
            }
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $compared ) or die "assertion failed\n" );
            ( is_deeply( $self->{transport},                 [] )        or die "assertion failed\n" );
        }
    }
    {
        $destination = clone( $self, 0, undef, undef );
        assert_resolves( $self, $destination, "HEAD", oid( $self, $self->{source}, "HEAD" ), 0 );
        git( $self, $destination, [ "remote", "add", "zzz", $URL ], 1, undef );
        $newer = commit(
            $self, $self->{source}, 'pulled through a new matching remote
', "file.txt"
        );
        git(
            $self,
            $destination,
            [
                "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                "pull", "--quiet", "--ff-only", "zzz", "main"
            ],
            1, undef
        );
        $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
        ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
        ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
        assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 0 ) );
        ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
        assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
        ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
        ( is_deeply( $self->{transport},                 [] )     or die "assertion failed\n" );
    }
}

sub test_head_open_follows_nonquery_remote_rewinds_and_divergence {
    my ($self) = @_;
    my ( $destination, $expected );
    commit(
        $self, $self->{source}, 'initial synchronized tip
', "file.txt"
    );
    $destination = clone( $self, 0, undef, undef );
    matching_remote( $self, $destination, "aaa", undef );
    assert_resolves( $self, $destination, "HEAD", oid( $self, $self->{source}, "HEAD" ), 0 );
    git( $self, $self->{source}, [ "reset", "--hard", $self->{initial} ], 1, undef );
    for $expected ( @{ [ $self->{initial}, undef ] } ) {
        if ( ( !defined($expected) ) ) {
            $expected = commit(
                $self, $self->{source}, 'divergent nonquery tip
', "file.txt"
            );
        }
        git(
            $self,
            $destination,
            [
                "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                "fetch", "--quiet", "origin"
            ],
            1, undef
        );
        assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
        ( is_deeply( oid( $self, $destination, "HEAD" ), $expected ) or die "assertion failed\n" );
        ( is_deeply( $self->{transport},                 [] )        or die "assertion failed\n" );
    }
}

sub test_matching_remote_head_conflicts_require_refresh {
    my ($self) = @_;
    my ( $before, $conflict, $destination, $marker, $markers, $result );
    for $conflict ( @{ [ "multiple_updates", "missing_marker", "legacy" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            matching_remote( $self, $destination, "aaa", undef );
            if ( ( ( $conflict ne "legacy" ) ) ) {
                assert_resolves( $self, $destination, "HEAD", oid( $self, $self->{source}, "HEAD" ), 0 );
            }
            commit(
                $self,
                $self->{source},
                (
                    $conflict
                      . ' first observation
'
                ),
                "file.txt"
            );
            git(
                $self,
                $destination,
                [
                    "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                    "fetch", "--quiet", "aaa"
                ],
                1, undef
            );
            if ( ( ( $conflict eq "multiple_updates" ) ) ) {
                commit(
                    $self, $self->{source}, 'second independent observation
', "file.txt"
                );
                git(
                    $self,
                    $destination,
                    [
                        "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                        "fetch", "--quiet", "origin"
                    ],
                    1, undef
                );
            }
            else {
                if ( ( ( $conflict eq "missing_marker" ) ) ) {
                    $markers = [
                        split(
                            /\n/,
                            git( $self, $destination,
                                [ "for-each-ref", "--format=%(refname)", "refs/gh/compare/" ],
                                1, undef )->{stdout}
                        )
                    ];
                    for $marker ( @{$markers} ) {
                        if ( ( contains_value( $marker, "/tracking-synced/" ) ) ) {
                            git( $self, $destination, [ "update-ref", "-d", $marker ], 1, undef );
                        }
                    }
                }
            }
            $before = oid( $self, $destination, "HEAD" );
            $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "cannot refresh default HEAD" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 0 ) );
            (
                is_deeply( oid( $self, $destination, "HEAD" ), oid( $self, $self->{source}, "HEAD" ) )
                  or die "assertion failed\n"
            );
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
            ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
        }
    }
}

sub test_matching_remotes_can_share_a_tracking_destination {
    my ($self) = @_;
    my ( $destination, $newer );
    $destination = clone( $self, 0, undef, undef );
    matching_remote( $self, $destination, "aaa", "refs/remotes/origin/main" );
    $newer = commit(
        $self, $self->{source}, 'shared tracking target
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
          or die "assertion failed\n"
    );
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
    ( is_deeply( $self->{transport},                 [] )     or die "assertion failed\n" );
}

sub test_failed_matching_remote_sync_invalidates_all_default_aliases {
    my ($self) = @_;
    my ( $before, $destination, $lock, $newer, $ref, $remote, $result, $tracking );
    $destination = clone( $self, 0, undef, undef );
    $tracking    = matching_remote( $self, $destination, "aaa", undef );
    assert_resolves( $self, $destination, "HEAD", $self->{initial}, 0 );
    $newer = commit(
        $self, $self->{source}, 'partially synchronized default
', "file.txt"
    );
    $lock = join_path( $destination, ".git/refs/remotes/origin/main.lock" );
    write_file(
        $lock, 'held by another process
'
    );
    assert_resolves( $self, $destination, "HEAD", $newer, 0 );
    for $ref ( @{ [ $tracking, "refs/remotes/origin/main" ] } ) {
        ( is_deeply( oid( $self, $destination, $ref ), $self->{initial} ) or die "assertion failed\n" );
    }
    for $remote ( @{ [ "aaa", "origin" ] } ) {
        (
            ok(
                !equal_values(
                    git( $self, $destination,
                        [ "symbolic-ref", "--quiet", ( ( "refs/remotes/" . $remote ) . "/HEAD" ) ],
                        0, undef )->{returncode},
                    0
                )
              )
              or die "assertion failed\n"
        );
    }
    $before = oid( $self, $destination, "HEAD" );
    $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
}

sub test_matching_remote_alias_cannot_replace_another_tracking_target {
    my ($self) = @_;
    my ( $before, $destination, $newer, $result, $target );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "symbolic-ref", "--delete", "refs/remotes/origin/HEAD" ], 1, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:refs/cache/origin/main" ],
        1, undef );
    matching_remote( $self, $destination, "aaa", "refs/remotes/origin/HEAD" );
    $newer = commit(
        $self, $self->{source}, 'cross-remote alias collision
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $newer, 0 );
    for $target ( @{ [ "refs/remotes/origin/HEAD", "refs/cache/origin/main" ] } ) {
        ( is_deeply( oid( $self, $destination, $target ), $newer ) or die "assertion failed\n" );
        (
            ok(
                !equal_values(
                    git( $self, $destination, [ "symbolic-ref", "--quiet", $target ], 0, undef )
                      ->{returncode},
                    0
                )
              )
              or die "assertion failed\n"
        );
    }
    $before = oid( $self, $destination, "HEAD" );
    $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
}

sub test_delayed_default_comparison_cannot_restore_the_old_default_branch {
    my ($self) = @_;
    my ( $destination, $newer, $result, $tip );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'new default
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    for $tip ( @{ [ $self->{initial}, $newer ] } ) {
        {
            git( $self, $self->{source}, [ "branch", "--force", "topic", $tip ], 1, undef );
            $destination = clone( $self, 0, undef, undef );
            assert_resolves( $self, $destination, "HEAD", $self->{initial}, 0 );
            $result = fish(
                $self, 'set -g repository "$argv[1]"
set -g checkout "$argv[2]"
set -g source "$argv[3]"
function git
    command git $argv; or return
    if not set -q interleaved; and contains -- fetch $argv; and contains -- --stdin $argv
        set -g interleaved true
        command git -C "$source" symbolic-ref HEAD refs/heads/topic; or return
        __ghe_compare_ref "$repository" "$checkout" HEAD >/dev/null; or return
    end
end
__ghe_compare_ref "$repository" "$checkout" HEAD',
                [ $URL, $destination, $self->{source} ], 0
            );
            assert_success( $self, $result );
            ( is_deeply( trim( $result->{stdout} ), $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply(
                    trim(
                        git( $self, $destination, [ "symbolic-ref", "refs/remotes/origin/HEAD" ], 1, undef )
                          ->{stdout}
                    ),
                    "refs/remotes/origin/topic"
                  )
                  or die "assertion failed\n"
            );
            git( $self, $self->{source}, [ "symbolic-ref", "HEAD", "refs/heads/main" ], 1, undef );
            if ( ( ( $tip eq $self->{initial} ) ) ) {
                git( $self, $self->{source}, [ "branch", "--force", "topic", $newer ], 1, undef );
                git(
                    $self,
                    $destination,
                    [
                        "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                        "fetch", "--quiet", "origin", "topic"
                    ],
                    1, undef
                );
            }
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
            ( is_deeply( $self->{transport},                 [] )     or die "assertion failed\n" );
        }
    }
}

sub test_head_comparison_updates_default_alias_without_overwriting_old_branch {
    my ($self) = @_;
    my ( $destination, $newer );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "HEAD", $self->{initial}, 0 );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "new-default" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'new default branch
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $self->{initial} )
          or die "assertion failed\n"
    );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/new-default" ), $newer )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            trim(
                git( $self, $destination, [ "symbolic-ref", "refs/remotes/origin/HEAD" ], 1, undef )->{stdout}
            ),
            "refs/remotes/origin/new-default"
          )
          or die "assertion failed\n"
    );
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
}

sub test_head_comparison_succeeds_when_a_dangling_symref_blocks_its_alias {
    my ($self) = @_;
    my ( $alias, $blocker, $destination, $newer, $target );
    $destination = clone( $self, 0, undef, undef );
    $alias       = "refs/remotes/origin/HEAD";
    git( $self, $destination, [ "symbolic-ref", "--delete", $alias ], 1, undef );
    $blocker = ( $alias . "/marker" );
    $target  = "refs/heads/missing";
    git( $self, $destination, [ "symbolic-ref", $blocker, $target ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'blocked default alias
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $destination, [ "symbolic-ref", $blocker ], 1, undef )->{stdout} ),
            $target )
          or die "assertion failed\n"
    );
}

sub test_head_comparison_preserves_direct_and_overlapping_tracking_destinations {
    my ($self) = @_;
    my ( $before, $compared, $destination, $fetched, $target );
    for $target (
        @{ [ "refs/remotes/origin/HEAD", "refs/remotes/origin/HEAD/main", "refs/remotes/origin" ] } )
    {
        {
            $destination = clone( $self, 0, undef, undef );
            git( $self, $destination, [ "symbolic-ref", "--delete", "refs/remotes/origin/HEAD" ], 1, undef );
            git( $self, $destination, [ "update-ref",   "-d",       "refs/remotes/origin/main" ], 1, undef );
            git( $self, $destination,
                [ "config", "--replace-all", "remote.origin.fetch", ( "+refs/heads/main:" . $target ) ],
                1, undef );
            $compared = commit(
                $self,
                $self->{source},
                (
                    ( "comparison for " . $target ) . '
'
                ),
                "file.txt"
            );
            $before = oid( $self, $destination, "HEAD" );
            assert_resolves( $self, $destination, "HEAD", $compared, 0 );
            ( is_deeply( oid( $self, $destination, $target ), $compared ) or die "assertion failed\n" );
            (
                ok(
                    !equal_values(
                        git( $self, $destination, [ "symbolic-ref", "--quiet", $target ], 0, undef )
                          ->{returncode},
                        0
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
            $fetched = commit(
                $self,
                $self->{source},
                (
                    ( "ordinary fetch for " . $target ) . '
'
                ),
                "file.txt"
            );
            git(
                $self,
                $destination,
                [
                    "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                    "fetch", "--quiet", "origin"
                ],
                1, undef
            );
            ( is_deeply( oid( $self, $destination, $target ), $fetched ) or die "assertion failed\n" );
            (
                ok(
                    !equal_values(
                        git( $self, $destination, [ "symbolic-ref", "--quiet", $target ], 0, undef )
                          ->{returncode},
                        0
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
        }
    }
}

sub test_direct_default_tracking_destination_follows_later_fetch_offline {
    my ($self) = @_;
    my ( $compared, $destination, $fetched );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "symbolic-ref", "--delete", "refs/remotes/origin/HEAD" ], 1, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/HEAD" ],
        1, undef );
    $compared = commit(
        $self, $self->{source}, 'direct default comparison
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $compared, 0 );
    $fetched = commit(
        $self, $self->{source}, 'direct default ordinary fetch
', "file.txt"
    );
    git(
        $self,
        $destination,
        [
            "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
            "fetch", "--quiet", "origin"
        ],
        1, undef
    );
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $fetched ) or die "assertion failed\n" );
    ( is_deeply( $self->{transport},                 [] )       or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/HEAD" ), $fetched )
          or die "assertion failed\n"
    );
    (
        ok(
            !equal_values(
                git( $self, $destination, [ "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD" ],
                    0, undef )->{returncode},
                0
            )
          )
          or die "assertion failed\n"
    );
}

sub test_failed_direct_default_update_does_not_reuse_the_previous_head_snapshot {
    my ($self) = @_;
    my ( $destination, $lock, $newer, $ref, $result );
    $destination = clone( $self, 0, undef, undef );
    $ref         = "refs/remotes/origin/HEAD";
    git( $self, $destination, [ "symbolic-ref", "--delete", $ref ], 1, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", ( "+refs/heads/main:" . $ref ) ],
        1, undef );
    assert_resolves( $self, $destination, "HEAD", $self->{initial}, 0 );
    $newer = commit(
        $self, $self->{source}, 'new default during tracking lock
', "file.txt"
    );
    $lock = join_path( $destination, ".git/refs/remotes/origin/HEAD.lock" );
    write_file(
        $lock, 'held by another process
'
    );
    assert_resolves( $self, $destination, "main", $newer, 0 );
    $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                          or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "cannot refresh default HEAD" ) ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} )        or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, $ref ), $self->{initial} )          or die "assertion failed\n" );
    unlink($lock);
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 0 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_direct_default_alias_requires_an_active_round_trip_fetch_mapping {
    my ($self) = @_;
    my ( $destination, $restriction, $result, $target );
    for $restriction ( @{ [ "unmapped", "excluded", "secondary" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            git( $self, $destination, [ "symbolic-ref", "--delete", "refs/remotes/origin/HEAD" ], 1, undef );
            git( $self, $destination, [ "update-ref", "refs/remotes/origin/HEAD", $self->{initial} ],
                1, undef );
            $target = (
                ( ( $restriction eq "excluded" ) )
                ? "refs/remotes/origin/HEAD"
                : "refs/custom/main"
            );
            git( $self, $destination,
                [ "config", "--replace-all", "remote.origin.fetch", ( "+refs/heads/main:" . $target ) ],
                1, undef );
            if ( ( ( $restriction eq "excluded" ) ) ) {
                git( $self, $destination, [ "config", "--add", "remote.origin.fetch", "^refs/heads/main" ],
                    1, undef );
            }
            else {
                if ( ( ( $restriction eq "secondary" ) ) ) {
                    git(
                        $self,
                        $destination,
                        [
                            "config",              "--add",
                            "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/HEAD"
                        ],
                        1, undef
                    );
                }
            }
            $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "cannot refresh default HEAD" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply( oid( $self, $destination, "refs/remotes/origin/HEAD" ), $self->{initial} )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_direct_default_alias_requires_an_explicit_fetch_destination {
    my ($self) = @_;
    my ( $destination, $result );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "symbolic-ref", "--delete", "refs/remotes/origin/HEAD" ],       1, undef );
    git( $self, $destination, [ "update-ref",   "refs/remotes/origin/HEAD", $self->{initial} ], 1, undef );
    $result = fish( $self, "__gh_default_ref origin \"\$argv[1]\" (__gh_refspecs origin \"\$argv[1]\")",
        [$destination], 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( $result->{stdout},  "" ) or die "assertion failed\n" );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_missing_default_alias_is_not_inferred_from_a_wildcard_mapping {
    my ($self) = @_;
    my ( $destination, $result );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "symbolic-ref", "--delete", "refs/remotes/origin/HEAD" ], 1, undef );
    $result =
      fish( $self,
        "set -l specs (__gh_refspecs origin \"\$argv[1]\"); __gh_default_ref origin \"\$argv[1]\" \$specs",
        [$destination], 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( $result->{stdout},  "" ) or die "assertion failed\n" );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_head_open_refreshes_unsafe_mapping_without_modifying_its_target {
    my ($self) = @_;
    my ( $before, $destination, $mapping, $newer, $result );
    for $mapping ( @{ [ "+refs/heads/main:refs/heads/main", "+refs/heads/main:refs/tags/local-copy" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            git( $self, $destination, [ "config", "--replace-all", "remote.origin.fetch", $mapping ],
                1, undef );
            $before = oid( $self, $destination, "HEAD" );
            $newer  = commit(
                $self,
                $self->{source},
                (
                    ( "unsafe mapping comparison " . $mapping ) . '
'
                ),
                "file.txt"
            );
            assert_resolves( $self, $destination, "HEAD", $newer, 0 );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
            $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "cannot refresh default HEAD" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 0 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
        }
    }
}

sub test_head_open_does_not_trust_a_negatively_excluded_default {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "config", "--add", "remote.origin.fetch", "^refs/heads/main" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'excluded default comparison
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $self->{initial} )
          or die "assertion failed\n"
    );
    $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                          or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "cannot refresh default HEAD" ) ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} )        or die "assertion failed\n" );
}

sub test_head_comparison_handles_tracking_refs_overlapping_its_alias {
    my ($self) = @_;
    my ( $destination, $newer, $spec, $tracking );
    for my $item_1289 (
        @{
            [
                [ "+refs/heads/main:refs/remotes/origin/HEAD", "refs/remotes/origin/HEAD" ],
                [ "+refs/heads/*:refs/remotes/origin/HEAD/*",  "refs/remotes/origin/HEAD/main" ],
                [ "+refs/heads/main:refs/remotes/origin",      "refs/remotes/origin" ],
                [ "+refs/heads/main:refs/remotes/origin/head", "refs/remotes/origin/head" ],
                [ "+refs/heads/*:refs/remotes/origin/head/*",  "refs/remotes/origin/head/main" ],
                [ "+refs/heads/main:refs/remotes/Origin",      "refs/remotes/Origin" ]
            ]
        }
      )
    {
        $spec     = ($item_1289)->[0];
        $tracking = ($item_1289)->[1];
        {
            $destination = clone( $self, 0, undef, undef );
            git( $self, $destination, [ "symbolic-ref", "--delete", "refs/remotes/origin/HEAD" ], 1, undef );
            git( $self, $destination, [ "update-ref",   "-d",       "refs/remotes/origin/main" ], 1, undef );
            git( $self, $destination, [ "config", "--replace-all", "remote.origin.fetch", $spec ], 1, undef );
            $newer = commit(
                $self,
                $self->{source},
                (
                    $spec . '
'
                ),
                "file.txt"
            );
            assert_resolves( $self, $destination, "HEAD", $newer, 0 );
            ( is_deeply( oid( $self, $destination, $tracking ), $newer ) or die "assertion failed\n" );
            (
                ok(
                    !equal_values(
                        git( $self, $destination,
                            [ "symbolic-ref", "--quiet", "--no-recurse", "refs/remotes/origin/HEAD" ],
                            0, undef )->{returncode},
                        0
                    )
                  )
                  or die "assertion failed\n"
            );
            assert_success( $self,
                fish( $self, "git -C \"\$argv[1]\" fetch --quiet origin", [$destination], 0 ) );
        }
    }
}

sub test_changed_default_with_no_safe_mapping_invalidates_the_old_alias {
    my ($self) = @_;
    my ( $destination, $newer, $restriction, $result );
    for $restriction ( @{ [ "unmapped", "excluded", "local_branch", "symbolic" ] } ) {
        {
            git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
            $destination = clone( $self, 0, undef, undef );
            assert_resolves( $self, $destination, "HEAD", oid( $self, $self->{source}, "HEAD" ), 0 );
            git( $self, $self->{source}, [ "switch", "--quiet", "--create", ( "new-" . $restriction ) ],
                1, undef );
            $newer = commit(
                $self, $self->{source}, 'new unmapped default
', "file.txt"
            );
            if ( ( ( $restriction eq "unmapped" ) ) ) {
                git(
                    $self,
                    $destination,
                    [
                        "config",              "--replace-all",
                        "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/main"
                    ],
                    1, undef
                );
            }
            else {
                if ( ( ( $restriction eq "excluded" ) ) ) {
                    git( $self, $destination,
                        [ "config", "--add", "remote.origin.fetch", ( "^refs/heads/new-" . $restriction ) ],
                        1, undef );
                }
                else {
                    if ( ( ( $restriction eq "local_branch" ) ) ) {
                        git(
                            $self,
                            $destination,
                            [
                                "config",              "--add",
                                "remote.origin.fetch", "+refs/heads/new-local_branch:refs/heads/local-copy"
                            ],
                            1, undef
                        );
                        git(
                            $self,
                            $destination,
                            [
                                "config",              "--replace-all",
                                "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/main",
                                "refs/heads/\\*"
                            ],
                            1, undef
                        );
                    }
                    else {
                        git( $self, $destination,
                            [ "symbolic-ref", "refs/remotes/origin/new-symbolic", "refs/heads/main" ],
                            1, undef );
                    }
                }
            }
            assert_resolves( $self, $destination, "HEAD", $newer, 0 );
            (
                ok(
                    !equal_values(
                        git( $self, $destination, [ "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD" ],
                            0, undef )->{returncode},
                        0
                    )
                  )
                  or die "assertion failed\n"
            );
            $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "cannot refresh default HEAD" ) )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    oid( $self, $destination, "HEAD" ), oid( $self, $destination, "refs/heads/main" )
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_comparison_survives_a_stale_tracking_ref_hierarchy {
    my ($self) = @_;
    my ( $destination, $newer );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $self->{source}, [ "branch", "--delete", "topic" ], 1, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic/fix" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'new topic hierarchy
', "file.txt"
    );
    assert_resolves( $self, $destination, "heads/topic/fix", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/topic" ), $self->{initial} )
          or die "assertion failed\n"
    );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
}

sub test_failed_default_tracking_update_requires_refresh_instead_of_old_head_cache {
    my ($self) = @_;
    my ( $destination, $lock, $newer, $result );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "HEAD", $self->{initial}, 0 );
    $newer = commit(
        $self, $self->{source}, 'locked default tracking
', "file.txt"
    );
    $lock = join_path( $destination, ".git/refs/remotes/origin/main.lock" );
    write_file(
        $lock, 'held by another process
'
    );
    assert_resolves( $self, $destination, "main", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $self->{initial} )
          or die "assertion failed\n"
    );
    (
        ok(
            !equal_values(
                git( $self, $destination, [ "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD" ],
                    0, undef )->{returncode},
                0
            )
          )
          or die "assertion failed\n"
    );
    $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                          or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "cannot refresh default HEAD" ) ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} )        or die "assertion failed\n" );
}

sub test_legacy_head_snapshot_conflict_requires_one_online_synchronization {
    my ($self) = @_;
    my ( $before, $destination, $identity, $key, $newer, $result, $snapshot, $snapshot_position );
    for $snapshot_position ( @{ [ "newer", "older" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            $before      = oid( $self, $destination, "HEAD" );
            $newer       = commit(
                $self,
                $self->{source},
                (
                    ( "legacy " . $snapshot_position )
                    . ' snapshot
'
                ),
                "file.txt"
            );
            if ( ( ( $snapshot_position eq "newer" ) ) ) {
                git( $self, $destination,
                    [ "fetch", "--quiet", "--refmap=", file_uri( $self->{source} ), "main" ],
                    1, undef );
                $snapshot = $newer;
            }
            else {
                git(
                    $self,
                    $destination,
                    [
                        "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
                        "pull", "--quiet", "--ff-only", "origin", "main"
                    ],
                    1, undef
                );
                $snapshot = $before;
                $before   = $newer;
            }
            $identity = trim(
                git(
                    $self, $destination, [ "hash-object", "--stdin" ], 1,
                    'example/project
'
                )->{stdout}
            );
            $key = trim(
                git(
                    $self, $destination, [ "hash-object", "--stdin" ], 1, 'HEAD
'
                )->{stdout}
            );
            git( $self, $destination,
                [ "update-ref", ( ( ( "refs/gh/compare/" . $identity ) . "/by-ref/" ) . $key ), $snapshot ],
                1, undef );
            $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "cannot refresh default HEAD" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 0 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
            assert_success( $self, checkout( $self, $destination, "blob/HEAD/file.txt", 1 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
            ( is_deeply( $self->{transport},                 [] )     or die "assertion failed\n" );
        }
    }
}

sub test_head_file_open_refreshes_a_cached_default_missing_the_path {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    $destination = clone( $self, 0, undef, undef );
    $newer       = commit(
        $self, $self->{source}, 'added upstream
', "new.txt"
    );
    $result = checkout( $self, $destination, "blob/HEAD/new.txt", 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                   or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "path does not exist" ) )  or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/new.txt", 0 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            read_file( join_path( $destination, "new.txt" ) ), 'added upstream
'
          )
          or die "assertion failed\n"
    );
    assert_success( $self, checkout( $self, $destination, "blob/HEAD/new.txt", 1 ) );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_unmapped_head_refresh_does_not_cache_a_new_default_under_the_old_branch {
    my ($self) = @_;
    my ( $destination, $ref, $result, $topic );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $topic = commit(
        $self, $self->{source}, 'new default branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/topic:refs/remotes/origin/topic" ],
        1, undef );
    assert_resolves( $self, $destination, "main", $self->{initial}, 0 );
    $result = fish(
        $self, 'set -g source "$argv[3]"
function git
    command git $argv; or return
    if contains -- ls-remote $argv; and contains -- HEAD $argv
        command git -C "$source" symbolic-ref HEAD refs/heads/topic; or return
    end
end
__ghe_compare_ref "$argv[1]" "$argv[2]" HEAD',
        [ $URL, $destination, $self->{source} ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $topic ) or die "assertion failed\n" );
    assert_resolves( $self, $destination, "HEAD", $topic, 1 );
    for $ref ( @{ [ "main", "heads/main" ] } ) {
        assert_resolves( $self, $destination, $ref, $self->{initial}, 1 );
    }
}

sub test_head_comparison_refreshes_default_branch_snapshot_offline {
    my ($self) = @_;
    my ( $destination, $newer, $ref );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "main", $self->{initial}, 0 );
    $newer = commit(
        $self, $self->{source}, 'default moved before a HEAD comparison
', "file.txt"
    );
    assert_resolves( $self, $destination, "HEAD", $newer, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
          or die "assertion failed\n"
    );
    for $ref ( @{ [ "main", "heads/main" ] } ) {
        {
            assert_resolves( $self, $destination, $ref, $newer, 1 );
        }
    }
}

sub test_head_file_open_uses_cached_default_commit_without_transport {
    my ($self) = @_;
    my ( $destination, $result );
    $destination = clone( $self, 0, undef, undef );
    commit(
        $self, $self->{source}, 'new remote default version
', "file.txt"
    );
    $result = checkout( $self, $destination, "blob/HEAD/file.txt", 1 );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply(
            read_file( join_path( $destination, "file.txt" ) ), 'initial
'
          )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_empty_fork_does_not_resolve_an_unrelated_local_commit_prefix {
    my ($self) = @_;
    my ( $before, $destination, $empty_fork, $result );
    $destination = clone( $self, 0, undef, undef );
    $empty_fork  = new_repository( $self, "empty-fork" );
    $self->{urls}->{"https://github.com/empty/project.git"} =
      file_uri($empty_fork);
    $before = oid( $self, $destination, "HEAD" );
    $result = compare_ref( $self, $destination, ( "empty:" . string_slice( $before, undef, 10 ) ), 0, $URL );
    ( ok( !equal_values( $result->{returncode}, 0 ), $result->{stdout} ) or die "assertion failed\n" );
    ( is_deeply( $result->{stdout},                  "" )      or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            "main" )
          or die "assertion failed\n"
    );
}

sub test_nonempty_fork_does_not_resolve_an_unrelated_local_commit_prefix {
    my ($self) = @_;
    my ( $destination, $fork, $local, $result );
    $destination = clone( $self, 0, undef, undef );
    $fork        = new_repository( $self, "unrelated-fork" );
    commit(
        $self, $fork, 'unrelated fork history
', "file.txt"
    );
    $self->{urls}->{"https://github.com/alice/project.git"} = file_uri($fork);
    $local = oid( $self, $destination, "HEAD" );
    $result = compare_ref( $self, $destination, ( "alice:" . string_slice( $local, undef, 10 ) ), 0, $URL );
    ( ok( !equal_values( $result->{returncode}, 0 ), $result->{stdout} ) or die "assertion failed\n" );
    ( is_deeply( $result->{stdout},                  "" )     or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $local ) or die "assertion failed\n" );
}

sub test_fork_prefix_ignores_a_colliding_unrelated_local_commit {
    my ($self) = @_;
    my ( $destination, $fork, $result, $unrelated, $wanted );
    $destination                                            = clone( $self, 0, undef, undef );
    $fork                                                   = new_repository( $self, "colliding-fork" );
    $self->{urls}->{"https://github.com/alice/project.git"} = file_uri($fork);

    # Fixed messages give distinct SHA-1 commits sharing the prefix f546c.
    $wanted    = empty_root_commit( $self, $fork,        "fork 34609" );
    $unrelated = empty_root_commit( $self, $destination, "local 50" );
    ( ok( !equal_values( $wanted, $unrelated ) ) or die "assertion failed\n" );
    (
        is_deeply( string_slice( $wanted, undef, 5 ), string_slice( $unrelated, undef, 5 ) )
          or die "assertion failed\n"
    );
    git( $self, $fork,        [ "update-ref", "refs/heads/main",      $wanted ],    1, undef );
    git( $self, $destination, [ "update-ref", "refs/heads/unrelated", $unrelated ], 1, undef );
    $result = compare_ref( $self, $destination, ( "alice:" . string_slice( $wanted, undef, 5 ) ), 0, $URL );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ),          $wanted )          or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
}

sub test_fork_prefix_counts_a_commit_and_its_colliding_tag_once {
    my ($self) = @_;
    my ( $destination, $fork, $local_tag, $result, $tag, $tag_text, $unqualified, $wanted );
    $destination                                            = clone( $self, 0, undef, undef );
    $fork                                                   = new_repository( $self, "tag-collision-fork" );
    $self->{urls}->{"https://github.com/alice/project.git"} = file_uri($fork);
    $wanted                                                 = empty_root_commit( $self, $fork, "fork 34609" );
    empty_root_commit( $self, $destination, "fork 34609" );
    git( $self, $fork, [ "update-ref", "refs/heads/main", $wanted ], 1, undef );

    # This fixed tag hashes to f546ce43..., sharing the commit's prefix.
    $tag_text = sprintf(
        'object %s
type commit
tag local-only
tagger Dotfiles tests <dotfiles-tests@example.invalid> 0 +0000

local 573300
', $wanted
    );
    $tag = trim(
        git( $self, $destination, [ "hash-object", "-w", "-t", "tag", "--stdin" ], 1, $tag_text )->{stdout} );
    ( ok( !equal_values( $wanted, $tag ) ) or die "assertion failed\n" );
    (
        is_deeply( string_slice( $wanted, undef, 5 ), string_slice( $tag, undef, 5 ) )
          or die "assertion failed\n"
    );
    git( $self, $destination, [ "update-ref", "refs/tags/local-only", $tag ], 1, undef );
    $result = compare_ref( $self, $destination, ( "alice:" . string_slice( $wanted, undef, 5 ) ), 0, $URL );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $wanted ) or die "assertion failed\n" );
    $unqualified = compare_ref( $self, $destination, string_slice( $wanted, undef, 5 ), 0, $URL );
    (
        ok( !equal_values( $unqualified->{returncode}, 0 ), $unqualified->{stdout} )
          or die "assertion failed\n"
    );
    ( is_deeply( $unqualified->{stdout}, "" ) or die "assertion failed\n" );

    # Only the local tag matches this longer prefix, not any fork object.
    (
        ok( !equal_values( string_slice( $wanted, undef, 10 ), string_slice( $tag, undef, 10 ) ) )
          or die "assertion failed\n"
    );
    $local_tag = compare_ref( $self, $destination, ( "alice:" . string_slice( $tag, undef, 10 ) ), 0, $URL );
    ( ok( !equal_values( $local_tag->{returncode}, 0 ), $local_tag->{stdout} ) or die "assertion failed\n" );
    ( is_deeply( $local_tag->{stdout}, "" ) or die "assertion failed\n" );
}

sub test_fork_prefix_of_a_fetched_annotated_tag_resolves_to_its_commit {
    my ($self) = @_;
    my ( $destination, $fork, $result, $tag, $wanted );
    $destination                                            = clone( $self, 0, undef, undef );
    $fork                                                   = new_repository( $self, "tagged-fork" );
    $self->{urls}->{"https://github.com/alice/project.git"} = file_uri($fork);
    $wanted                                                 = commit(
        $self, $fork, 'tagged fork commit
', "file.txt"
    );
    git( $self, $fork, [ "tag", "--annotate", "--message", "Fork release", "release" ], 1, undef );
    $tag = oid( $self, $fork, "refs/tags/release" );
    (
        ok( !equal_values( string_slice( $wanted, undef, 10 ), string_slice( $tag, undef, 10 ) ) )
          or die "assertion failed\n"
    );
    $result = compare_ref( $self, $destination, ( "alice:" . string_slice( $tag, undef, 10 ) ), 0, $URL );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $wanted ) or die "assertion failed\n" );
}

sub test_fork_prefix_rejects_two_colliding_fetched_commits {
    my ($self) = @_;
    my ( $destination, $first, $fork, $result, $second );
    $destination                                            = clone( $self, 0, undef, undef );
    $fork                                                   = new_repository( $self, "ambiguous-fork" );
    $self->{urls}->{"https://github.com/alice/project.git"} = file_uri($fork);
    $first                                                  = empty_root_commit( $self, $fork, "fork 34609" );
    $second                                                 = empty_root_commit( $self, $fork, "local 50" );
    ( ok( !equal_values( $first, $second ) ) or die "assertion failed\n" );
    (
        is_deeply( string_slice( $first, undef, 5 ), string_slice( $second, undef, 5 ) )
          or die "assertion failed\n"
    );
    git( $self, $fork, [ "update-ref", "refs/heads/main",  $first ],  1, undef );
    git( $self, $fork, [ "update-ref", "refs/heads/other", $second ], 1, undef );
    $result = compare_ref( $self, $destination, ( "alice:" . string_slice( $first, undef, 5 ) ), 0, $URL );
    ( ok( !equal_values( $result->{returncode}, 0 ), $result->{stdout} ) or die "assertion failed\n" );
    ( is_deeply( $result->{stdout},                  "" )               or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
}

sub test_comparison_uses_its_own_fetch_result {
    my ($self) = @_;
    my ( $attempt, $compare, $destination, $result, $tip );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $tip = commit(
        $self, $self->{source}, 'topic change
', "file.txt"
    );
    $compare = 'function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- --stdin $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin refs/heads/main
    end
end
__ghe_compare_ref "$argv[1]" "$argv[2]" "$argv[3]"
';
    for $attempt ( @{ [ 0 .. ( 2 - 1 ) ] } ) {
        {
            $result = fish( $self, $compare, [ $URL, $destination, "topic" ], 0 );
            assert_success( $self, $result );
            ( is_deeply( trim( $result->{stdout} ), $tip ) or die "assertion failed\n" );
            (
                is_deeply( oid( $self, $destination, "FETCH_HEAD" ), $self->{initial} )
                  or die "assertion failed\n"
            );
        }
    }
    assert_resolves( $self, $destination, "topic", $tip, 1 );
}

sub test_checkout_caches_a_tag_that_moves_before_fetch {
    my ($self) = @_;
    my ( $cached, $destination, $newer, $result, $tag );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "config", "remote.origin.tagOpt", "--no-tags" ], 1, undef );
    commit(
        $self, $self->{source}, 'old release
', "file.txt"
    );
    git( $self, $self->{source}, [ "tag", "--annotate", "--message", "old release", "v2" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'new release
', "file.txt"
    );
    git( $self, $self->{source}, [ "tag", "--annotate", "--message", "new release", "new-v2" ], 1, undef );
    $tag    = oid( $self, $self->{source}, "refs/tags/new-v2" );
    $result = fish(
        $self, 'set -g test_source "$argv[3]"
set -g test_tag "$argv[4]"
function git
    if contains -- fetch $argv; and contains -- refs/tags/v2 $argv
        command git -C "$test_source" update-ref refs/tags/v2 "$test_tag"; or return
    end
    command git $argv
end
__ghe_checkout "$argv[1]" "$argv[2]" releases/tag/v2 "" "" "" ""
', [ $URL, $destination, $self->{source}, $tag ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
    assert_success( $self, checkout( $self, $destination, "releases/tag/v2", 1 ) );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
    $cached =
      git( $self, $destination, [ "for-each-ref", "--format=%(objectname)", "refs/gh/compare" ], 1, undef );
    ( is_deeply( trim( $cached->{stdout} ), $tag ) or die "assertion failed\n" );
}

sub test_delayed_pull_request_fetch_keeps_a_newer_cached_head {
    my ($self) = @_;
    my ( $cached, $destination, $newer, $older, $result );
    $destination = clone( $self, 0, undef, undef );
    $older       = commit(
        $self, $self->{source}, 'older pull request head
', "file.txt"
    );
    $newer = commit(
        $self, $self->{source}, 'newer pull request head
', "file.txt"
    );
    git( $self, $self->{source}, [ "update-ref", "refs/pull/7/head", $older ], 1, undef );
    $result = fish(
        $self, 'set -g test_remote "$argv[1]"
set -g test_source "$argv[3]"
set -g test_newer "$argv[4]"
function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- refs/pull/7/head $argv; and not set -q test_refreshed
        set -g test_refreshed 1
        command git -C "$test_source" update-ref refs/pull/7/head "$test_newer"; or return
        __ghe_pull_request "$test_remote" "$argv[2]" 7 >/dev/null; or return
    end
end
__ghe_pull_request "$argv[1]" "$argv[2]" 7
', [ $URL, $destination, $self->{source}, $newer ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ), $older ) or die "assertion failed\n" );
    $cached = fish( $self, "__ghe_pull_request \"\$argv[1]\" \"\$argv[2]\" 7", [ $URL, $destination ], 1 );
    assert_success( $self, $cached );
    ( is_deeply( trim( $cached->{stdout} ), $newer ) or die "assertion failed\n" );
}

sub test_fork_prefix_uses_its_own_fetched_histories {
    my ($self) = @_;
    my ( $destination, $fork, $result, $wanted );
    $destination                                            = clone( $self, 0, undef, undef );
    $fork                                                   = new_repository( $self, "racing-fork" );
    $self->{urls}->{"https://github.com/alice/project.git"} = file_uri($fork);
    $wanted                                                 = commit(
        $self, $fork, 'fork commit
', "file.txt"
    );
    $result = fish(
        $self, 'function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- --stdin $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin refs/heads/main
    end
end
__ghe_compare_ref "$argv[1]" "$argv[2]" "$argv[3]"
',
        [
            $URL, $destination,
            ( "alice:" . string_slice( $wanted, undef, 10 ) )
        ],
        0
    );
    assert_success( $self, $result );
    ( is_deeply( trim( $result->{stdout} ),                $wanted )          or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "FETCH_HEAD" ), $self->{initial} ) or die "assertion failed\n" );
}

sub test_symbolic_comparison_cache_cannot_redirect_to_unrelated_branch {
    my ($self) = @_;
    my ( $cache, $destination, $identity, $key, $newer );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "update-ref", "-d", "refs/remotes/origin/topic" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'unrelated main
', "file.txt"
    );
    git( $self, $destination, [ "fetch", "--quiet", file_uri( $self->{source} ), "main" ], 1, undef );
    git( $self, $destination, [ "update-ref", "refs/heads/unrelated", $newer ], 1, undef );
    $identity = trim(
        git(
            $self, $destination, [ "hash-object", "--stdin" ], 1,
            'example/project
'
        )->{stdout}
    );
    $key = trim(
        git(
            $self, $destination, [ "hash-object", "--stdin" ], 1,
            'refs/heads/topic
'
        )->{stdout}
    );
    $cache = ( ( ( "refs/gh/compare/" . $identity ) . "/by-ref/" ) . $key );
    git( $self, $destination, [ "symbolic-ref", $cache, "refs/heads/unrelated" ], 1, undef );
    assert_resolves( $self, $destination, "topic", $self->{initial}, 0 );
    ( is_deeply( oid( $self, $destination, "refs/heads/unrelated" ), $newer ) or die "assertion failed\n" );
    assert_resolves( $self, $destination, "topic", $self->{initial}, 1 );
}

sub test_comparison_can_select_branch_or_tag_with_the_same_name {
    my ($self) = @_;
    my ( $destination, $newer );
    git( $self, $self->{source}, [ "tag", "release" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'newer branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "branch", "release" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    assert_resolves( $self, $destination, "release",       $newer,           1 );
    assert_resolves( $self, $destination, "heads/release", $newer,           1 );
    assert_resolves( $self, $destination, "tags/release",  $self->{initial}, 1 );
}

sub test_remote_head_and_ancestry_ignore_unpushed_local_commits {
    my ($self) = @_;
    my ( $destination, $local, $upstream );
    $upstream = commit(
        $self, $self->{source}, 'upstream
', "file.txt"
    );
    $destination = clone( $self, 0, undef, undef );
    $local       = commit(
        $self, $destination, 'local only
', "file.txt"
    );
    ( ok( !equal_values( $local, $upstream ) ) or die "assertion failed\n" );
    assert_resolves( $self, $destination, "HEAD",   $upstream,        1 );
    assert_resolves( $self, $destination, "HEAD~1", $self->{initial}, 1 );
}

sub test_two_and_three_dot_comparisons_match_git_without_changing_checkout {
    my ($self) = @_;
    my ( $before, $comparison, $destination, $expected, $main, $result, $separator, $topic );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $topic = commit(
        $self, $self->{source}, 'topic
', "topic.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $main = commit(
        $self, $self->{source}, 'main
', "main.txt"
    );
    $destination = clone( $self, 0, undef, undef );
    $before      = git( $self, $destination, [ "status", "--porcelain" ], 1, undef )->{stdout};
    for $separator ( @{ [ "..", "..." ] } ) {
        {
            $comparison = ( ( "main" . $separator ) . "topic" );
            $expected =
              git( $self, $destination, [ "diff", ( ( $main . $separator ) . $topic ), "--" ], 1, undef )
              ->{stdout};
            $result = fish(
                $self,
                "__ghe_compare \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\"",
                [ $URL, $destination, $comparison ], 1
            );
            assert_success( $self, $result );
            ( is_deeply( $result->{stdout}, $expected )              or die "assertion failed\n" );
            ( ok( ( scalar( @{ $self->{transport} } ) ) )            or die "assertion failed\n" );
            ( ok( contains_value( $result->{stderr}, "cached" ) )    or die "assertion failed\n" );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $main ) or die "assertion failed\n" );
            (
                is_deeply( git( $self, $destination, [ "status", "--porcelain" ], 1, undef )->{stdout},
                    $before )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_gho_opens_branch_without_checking_for_same_named_tags {
    my ($self) = @_;
    my ( $destination, $result );
    git( $self, $self->{source}, [ "tag", "main" ], 1, undef );
    commit(
        $self, $self->{source}, 'branch version
', "file.txt"
    );
    $destination = clone( $self, 0, undef, undef );
    $result      = fish( $self, "gho \"\$argv[1]\"", [ join_path( $destination, "file.txt" ) ], 1 );
    assert_success( $self, $result );
    (
        is_deeply( trim( $result->{stdout} ), "https://github.com/example/project/blob/main/file.txt" )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_stale_default_head_alias_uses_current_fetch_mapping_offline {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    $destination = clone( $self, 0, undef, undef );
    $newer       = commit(
        $self, $self->{source}, 'new mapped default
', "file.txt"
    );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/*:refs/cache/origin/*" ],
        1, undef );
    git(
        $self,
        $destination,
        [
            "fetch", "--quiet", "--no-tags", "--refmap=",
            file_uri( $self->{source} ),
            "+refs/heads/main:refs/cache/origin/main"
        ],
        1, undef
    );
    $result = fish( $self, "gho \"\$argv[1]\"", [$destination], 1 );
    assert_success( $self, $result );
    (
        is_deeply( trim( $result->{stdout} ), "https://github.com/example/project" )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
    assert_resolves( $self, $destination, "HEAD", $newer, 1 );
}

sub test_gho_opens_paths_without_checking_for_longer_tags {
    my ($self) = @_;
    my ( $destination, $result );
    commit(
        $self, $self->{source}, 'nested file
', "directory/file.txt"
    );
    git( $self, $self->{source}, [ "tag", "main/directory" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    $result      = fish( $self, "gho \"\$argv[1]\"", [ join_path( $destination, "directory/file.txt" ) ], 1 );
    assert_success( $self, $result );
    (
        is_deeply( trim( $result->{stdout} ),
            "https://github.com/example/project/blob/main/directory/file.txt" )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_explicit_tag_checks_out_tag_instead_of_same_named_branch {
    my ($self) = @_;
    my ( $destination, $result );
    git( $self, $self->{source}, [ "tag", "release" ], 1, undef );
    commit(
        $self, $self->{source}, 'newer branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "branch", "release" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    $result      = checkout( $self, $destination, "releases/tag/release", 1 );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    (
        ok(
            !equal_values(
                git( $self, $destination, [ "symbolic-ref", "--quiet", "HEAD" ], 0, undef )->{returncode}, 0
            )
          )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_full_commit_id_wins_over_a_branch_with_the_same_name {
    my ($self) = @_;
    my ( $destination, $result );
    commit(
        $self, $self->{source}, 'newer branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "branch", $self->{initial} ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    $result      = checkout( $self, $destination, ( ( "blob/" . $self->{initial} ) . "/file.txt" ), 1 );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    (
        ok(
            !equal_values(
                git( $self, $destination, [ "symbolic-ref", "--quiet", "HEAD" ], 0, undef )->{returncode}, 0
            )
          )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_short_hex_branch_stays_a_tracking_branch {
    my ($self) = @_;
    my ($destination);
    git( $self, $self->{source}, [ "branch", "deadbeef" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    assert_success( $self, checkout( $self, $destination, "blob/deadbeef/file.txt", 1 ) );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            "deadbeef" )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            trim(
                git( $self, $destination, [ "rev-parse", "--symbolic-full-name", "\@{upstream}" ], 1, undef )
                  ->{stdout}
            ),
            "refs/remotes/origin/deadbeef"
          )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_uncached_slash_branch_opens_a_path_with_glob_characters {
    my ($self) = @_;
    my ( $branch, $destination, $filename, $result );
    $branch   = "feature/nested";
    $filename = "dir/[draft]*?.txt";
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", $branch ], 1, undef );
    commit(
        $self, $self->{source}, 'literal filename
', $filename
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $destination = clone( $self, 1, undef, undef );
    $result      = checkout( $self, $destination, ( "blob/" . $branch . "/" . $filename ), 0 );
    assert_success( $self, $result );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            $branch )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            read_file( join_path( $destination, $filename ) ), 'literal filename
'
          )
          or die "assertion failed\n"
    );
}

sub test_new_hex_branches_win_over_cached_abbreviated_commits {
    my ($self) = @_;
    my (
        $advertised_ref, $call,   $cases,     $destination, $ref, $result,
        $route,          $routes, $unrelated, $wanted,      $with_paths
    );
    $routes = [
        [ "2026/fix", "blob/2026/fix/file.txt" ],
        [ "2026/fix", "tree/2026/fix" ],
        [ "2026",     "blob/2026/file.txt" ],
        [ "2026",     "tree/2026" ]
    ];
    $cases = [
        map {
            my $with_paths = $_;
            map {
                my $ref   = ($_)->[0];
                my $route = ($_)->[1];
                [ $with_paths, $ref, $route, clone( $self, 0, undef, undef ) ]
            } @{$routes}
        } @{ [ 0, 1 ] }
    ];
    $wanted = commit(
        $self, $self->{source}, 'new hexadecimal branches
', "file.txt"
    );
    $advertised_ref = undef;
    for my $item_1789 ( @{$cases} ) {
        $with_paths  = ($item_1789)->[0];
        $ref         = ($item_1789)->[1];
        $route       = ($item_1789)->[2];
        $destination = ($item_1789)->[3];
        if ( ( ( $ref ne $advertised_ref ) ) ) {
            if ($advertised_ref) {
                git( $self, $self->{source}, [ "branch", "--delete", "--force", $advertised_ref ], 1, undef );
            }
            git( $self, $self->{source}, [ "branch", $ref ], 1, undef );
            $advertised_ref = $ref;
        }
        {
            $unrelated = colliding_hex_commit( $self, $destination, $with_paths );
            ( ok( ( ( index( $unrelated, "2026" ) == 0 ) ) ) or die "assertion failed\n" );
            git( $self, $destination, [ "update-ref", "refs/heads/unrelated", $unrelated ], 1, undef );
            $result = checkout( $self, $destination, $route, 0 );
            assert_success( $self, $result );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $wanted ) or die "assertion failed\n" );
            (
                is_deeply(
                    trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
                    $ref )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    read_file( join_path( $destination, "file.txt" ) ),
                    'new hexadecimal branches
'
                  )
                  or die "assertion failed\n"
            );
            (
                ok(
                    (
                        0 + !!(
                            grep { $_ } @{
                                [
                                    map {
                                        my $call = $_;
                                        ( ( $call->{"command"} eq "ls-remote" ) )
                                    } @{ $self->{transport} }
                                ]
                            }
                        )
                    )
                  )
                  or die "assertion failed\n"
            );
            assert_success( $self, checkout( $self, $destination, $route, 1 ) );
            ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
        }
    }
}

sub test_cached_short_commit_fails_closed_when_remote_refs_are_unavailable {
    my ($self) = @_;
    my ( $before, $call, $destination, $result, $route, $unrelated );
    $destination = clone( $self, 0, undef, undef );
    $unrelated   = colliding_hex_commit( $self, $destination, 1 );
    ( ok( ( ( index( $unrelated, "2026" ) == 0 ) ) ) or die "assertion failed\n" );
    git( $self, $destination, [ "update-ref", "refs/heads/unrelated", $unrelated ], 1, undef );
    $before = git( $self, $destination, [ "status", "--porcelain" ], 1, undef )->{stdout};
    for $route ( @{ [ "blob/2026/fix/file.txt", "tree/2026/fix", "commit/2026" ] } ) {
        {
            $result = checkout( $self, $destination, $route, 1 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "full 40-character commit hash" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply(
                    trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
                    "main" )
                  or die "assertion failed\n"
            );
            (
                is_deeply( git( $self, $destination, [ "status", "--porcelain" ], 1, undef )->{stdout},
                    $before )
                  or die "assertion failed\n"
            );
            (
                is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ],
                    ["ls-remote"] )
                  or die "assertion failed\n"
            );
        }
    }
    $result = checkout( $self, $destination, ( ( "blob/" . $unrelated ) . "/fix/file.txt" ), 1 );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $unrelated ) or die "assertion failed\n" );
    ( is_deeply( $self->{transport},                 [] )         or die "assertion failed\n" );
    assert_success(
        $self,
        checkout(
            $self, $destination, ( ( "archive/" . string_slice( $unrelated, undef, 10 ) ) . ".zip" ), 1
        )
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_cached_short_commit_checks_remote_refs_before_switching {
    my ($self) = @_;
    my ( $call, $destination, $result );
    $destination = clone( $self, 0, undef, undef );
    $result      = checkout( $self, $destination,
        ( ( "blob/" . string_slice( $self->{initial}, undef, 10 ) ) . "/file.txt" ), 0 );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    (
        ok(
            !equal_values(
                git( $self, $destination, [ "symbolic-ref", "--quiet", "HEAD" ], 0, undef )->{returncode}, 0
            )
          )
          or die "assertion failed\n"
    );
    (
        is_deeply( [ map { my $call = $_; $call->{"command"} } @{ $self->{transport} } ], ["ls-remote"] )
          or die "assertion failed\n"
    );
}

sub test_gho_opens_detached_commit_offline_despite_ambiguous_short_ref {
    my ($self) = @_;
    my ( $destination, $result, $unrelated );
    $destination = clone( $self, 0, undef, undef );
    $unrelated   = colliding_hex_commit( $self, $destination, 1 );
    git( $self, $destination, [ "update-ref", "refs/heads/unrelated", $unrelated ], 1, undef );
    git( $self, $destination, [ "switch", "--quiet", "--detach", $unrelated ], 1, undef );
    $result = fish( $self, "gho \"\$argv[1]\"", [ join_path( $destination, "fix/file.txt" ) ], 1 );
    assert_success( $self, $result );
    (
        is_deeply( trim( $result->{stdout} ),
            ( ( "https://github.com/example/project/blob/" . $unrelated ) . "/fix/file.txt" ) )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_missing_abbreviated_commit_is_fetched_and_detached {
    my ($self) = @_;
    my ( $call, $destination, $requested );
    $destination = clone( $self, 0, undef, undef );
    $requested   = commit(
        $self, $self->{source}, 'requested commit
', "file.txt"
    );
    commit(
        $self, $self->{source}, 'newest commit
', "file.txt"
    );
    (
        ok(
            !equal_values(
                git( $self, $destination, [ "cat-file", "-e", $requested ], 0, undef )->{returncode}, 0
            )
          )
          or die "assertion failed\n"
    );
    assert_success(
        $self,
        checkout(
            $self, $destination, ( ( "blob/" . string_slice( $requested, undef, 10 ) ) . "/file.txt" ), 0
        )
    );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $requested ) or die "assertion failed\n" );
    (
        is_deeply(
            read_file( join_path( $destination, "file.txt" ) ),
            'requested commit
'
          )
          or die "assertion failed\n"
    );
    (
        ok(
            !equal_values(
                git( $self, $destination, [ "symbolic-ref", "--quiet", "HEAD" ], 0, undef )->{returncode}, 0
            )
          )
          or die "assertion failed\n"
    );
    (
        ok(
            (
                0 + !!(
                    grep { $_ } @{
                        [
                            map {
                                my $call = $_;
                                ( ( $call->{"command"} eq "fetch" ) )
                            } @{ $self->{transport} }
                        ]
                    }
                )
            )
          )
          or die "assertion failed\n"
    );
    assert_success( $self, checkout( $self, $destination, ( ( "blob/" . $requested ) . "/file.txt" ), 1 ) );
    ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
}

sub test_missing_abbreviated_commit_in_shallow_clone_fetches_history {
    my ($self) = @_;
    my ($destination);
    commit(
        $self, $self->{source}, 'second
', "file.txt"
    );
    commit(
        $self, $self->{source}, 'third
', "file.txt"
    );
    $destination = clone( $self, 0, 1, undef );
    (
        is_deeply(
            trim(
                git( $self, $destination, [ "rev-parse", "--is-shallow-repository" ], 1, undef )->{stdout}
            ),
            "true"
          )
          or die "assertion failed\n"
    );
    assert_success(
        $self,
        checkout(
            $self,                                                                       $destination,
            ( ( "blob/" . string_slice( $self->{initial}, undef, 10 ) ) . "/file.txt" ), 0
        )
    );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply(
            trim(
                git( $self, $destination, [ "rev-parse", "--is-shallow-repository" ], 1, undef )->{stdout}
            ),
            "false"
          )
          or die "assertion failed\n"
    );
}

sub test_unknown_abbreviated_commit_has_clear_error_and_keeps_checkout {
    my ($self) = @_;
    my ( $before, $destination, $result );
    $destination = clone( $self, 0, undef, undef );
    $before      = oid( $self, $destination, "HEAD" );
    $result      = checkout( $self, $destination, "blob/ffffffffffff/file.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                        or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "commit" ) )                    or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "longer or full" ) )            or die "assertion failed\n" );
    ( ok( !contains_value( $result->{stderr}, "couldn't find remote ref" ) ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $before )               or die "assertion failed\n" );
}

sub test_overlapping_fetch_mappings_do_not_invent_a_cached_branch {
    my ($self) = @_;
    my ( $destination, $main, $result );
    git( $self, $self->{source}, [ "branch", "-m", "main", "release/main" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/release/*:refs/remotes/origin/*" ],
        1, undef );
    git( $self, $destination,
        [ "config", "--add", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*" ],
        1, undef );
    assert_success( $self, fish( $self, "git -C \"\$argv[1]\" fetch --quiet origin", [$destination], 0 ) );
    $result = checkout( $self, $destination, "blob/main/file.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "no branch, tag, or commit matches" ) )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            "release/main" )
          or die "assertion failed\n"
    );
    (
        ok(
            !equal_values(
                git(
                    $self, $destination, [ "show-ref", "--verify", "--quiet", "refs/heads/main" ], 0, undef
                )->{returncode},
                0
            )
          )
          or die "assertion failed\n"
    );
    assert_success( $self, checkout( $self, $destination, "blob/release/main/file.txt", 1 ) );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "main" ], 1, undef );
    $main = commit(
        $self, $self->{source}, 'different main contents
', "main-only.txt"
    );
    $result = checkout( $self, $destination, "blob/main/file.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "fetch destination is mapped from another branch" ) )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            "release/main" )
          or die "assertion failed\n"
    );
    (
        ok(
            !equal_values(
                git(
                    $self, $destination, [ "show-ref", "--verify", "--quiet", "refs/heads/main" ], 0, undef
                )->{returncode},
                0
            )
          )
          or die "assertion failed\n"
    );
    (
        ok( !equal_values( compare_ref( $self, $destination, "main", 1, $URL )->{returncode}, 0 ) )
          or die "assertion failed\n"
    );
    assert_resolves( $self, $destination, "main", $main, 0 );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $self->{initial} )
          or die "assertion failed\n"
    );
    assert_resolves( $self, $destination, "main", $main, 1 );
    git( $self, $destination, [ "switch", "--quiet", "--create", "main", "refs/remotes/origin/main" ],
        1, undef );
    git( $self, $destination, [ "config", "branch.main.remote", "origin" ],          1, undef );
    git( $self, $destination, [ "config", "branch.main.merge",  "refs/heads/main" ], 1, undef );
    assert_success( $self, checkout( $self, $destination, "blob/main/main-only.txt", 0 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $main ) or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $self->{initial} )
          or die "assertion failed\n"
    );
}

sub test_nonbranch_fetch_source_does_not_claim_a_tracking_destination {
    my ($self) = @_;
    my ( $destination, $other, $result, $source, $spec, $topic, $tracking );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $topic = commit(
        $self, $self->{source}, 'topic branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "other", "main" ], 1, undef );
    $other = commit(
        $self, $self->{source}, 'other branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "tag", "other-tag" ], 1, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $tracking = "refs/remotes/origin/topic";
    for $source ( @{ [ "other", "refs/tags/other-tag" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            $spec        = ( "+" . $source . ":" . $tracking );
            git( $self, $destination, [ "config", "--replace-all", "remote.origin.fetch", $spec ], 1, undef );
            git( $self, $destination, [ "fetch", "--quiet", file_uri( $self->{source} ), $spec ], 1, undef );
            ( is_deeply( oid( $self, $destination, $tracking ), $other ) or die "assertion failed\n" );
            $result = checkout( $self, $destination, "blob/topic/file.txt", 0 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "mapped from another branch" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply(
                    trim(
                        git(
                            $self, $destination, [ "config", "--get-all", "remote.origin.fetch" ], 1, undef
                        )->{stdout}
                    ),
                    $spec
                  )
                  or die "assertion failed\n"
            );
            git( $self, $destination,
                [ "config", "--add", "remote.origin.fetch", ( "+refs/heads/topic:" . $tracking ) ],
                1, undef );
            (
                ok( !equal_values( compare_ref( $self, $destination, "topic", 1, $URL )->{returncode}, 0 ) )
                  or die "assertion failed\n"
            );
            assert_resolves( $self, $destination, "topic", $topic, 0 );
            ( is_deeply( oid( $self, $destination, $tracking ), $other ) or die "assertion failed\n" );
        }
    }
}

sub test_two_sources_do_not_claim_the_same_tracking_destination {
    my ($self) = @_;
    my ( $destination, $first, $release, $result, $second, $topic, $tracking );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "release/topic" ], 1, undef );
    $release = commit(
        $self, $self->{source}, 'release branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic", "main" ], 1, undef );
    $topic = commit(
        $self, $self->{source}, 'topic branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $tracking = "refs/remotes/origin/topic";
    for my $item_1960 (
        @{
            [
                [ ( "+refs/heads/release/topic:" . $tracking ), ( "+refs/heads/topic:" . $tracking ) ],
                [ "+refs/heads/release/*:refs/remotes/origin/*", "+refs/heads/*:refs/remotes/origin/*" ]
            ]
        }
      )
    {
        $first  = ($item_1960)->[0];
        $second = ($item_1960)->[1];
        {
            $destination = clone( $self, 1, undef, undef );
            git( $self, $destination,
                [ "config", "--replace-all", "remote.origin.fetch", $first ], 1, undef );
            git( $self, $destination, [ "config", "--add", "remote.origin.fetch", $second ], 1, undef );
            assert_success( $self,
                fish( $self, "git -C \"\$argv[1]\" fetch --quiet origin topic", [$destination], 0 ) );
            ( is_deeply( oid( $self, $destination, $tracking ), $topic ) or die "assertion failed\n" );
            $result = checkout( $self, $destination, "blob/release/topic/file.txt", 1 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            (
                ok(
                    !equal_values(
                        compare_ref( $self, $destination, "release/topic", 1, $URL )->{returncode}, 0
                    )
                  )
                  or die "assertion failed\n"
            );
            assert_resolves( $self, $destination, "release/topic", $release, 0 );
            ( is_deeply( oid( $self, $destination, $tracking ), $topic ) or die "assertion failed\n" );
            git( $self, $destination, [ "config", "--add", "remote.origin.fetch", "^refs/heads/topic" ],
                1, undef );
            assert_success( $self,
                fish( $self, "git -C \"\$argv[1]\" fetch --quiet origin", [$destination], 0 ) );
            ( is_deeply( oid( $self, $destination, $tracking ), $release ) or die "assertion failed\n" );
            assert_success(
                $self,
                fish(
                    $self, "git -C \"\$argv[1]\" fetch --quiet origin refs/heads/topic", [$destination], 0
                )
            );
            ( is_deeply( oid( $self, $destination, $tracking ), $topic ) or die "assertion failed\n" );
            $result = checkout( $self, $destination, "blob/release/topic/file.txt", 1 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            git( $self, $destination,
                [ "config", "--replace-all", "remote.origin.fetch", $first ], 1, undef );
            assert_success( $self,
                fish( $self, "git -C \"\$argv[1]\" fetch --quiet origin", [$destination], 0 ) );
            assert_success( $self, checkout( $self, $destination, "blob/release/topic/file.txt", 1 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $release ) or die "assertion failed\n" );
        }
    }
}

sub test_custom_cached_fetch_destinations_set_a_working_upstream {
    my ($self) = @_;
    my ( $destination, $spec, $tracking );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    for my $item_1994 (
        @{
            [
                [ "+refs/heads/*:refs/cache/origin/*",      "refs/cache/origin/topic" ],
                [ "+refs/heads/topic:remotes/origin/topic", "refs/remotes/origin/topic" ]
            ]
        }
      )
    {
        $spec     = ($item_1994)->[0];
        $tracking = ($item_1994)->[1];
        {
            $destination = clone( $self, 0, undef, undef );
            git( $self, $destination, [ "config", "--replace-all", "remote.origin.fetch", $spec ], 1, undef );
            if ( ( ( $tracking ne "refs/remotes/origin/topic" ) ) ) {
                git( $self, $destination, [ "update-ref", $tracking, $self->{initial} ], 1, undef );
                git( $self, $destination, [ "update-ref", "-d", "refs/remotes/origin/topic" ], 1, undef );
            }
            assert_success( $self, checkout( $self, $destination, "blob/topic/file.txt", 1 ) );
            (
                is_deeply(
                    trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
                    "topic" )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    trim(
                        git( $self, $destination, [ "rev-parse", "--symbolic-full-name", "\@{upstream}" ],
                            1, undef )->{stdout}
                    ),
                    $tracking
                  )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    trim(
                        git(
                            $self, $destination, [ "config", "--get-all", "remote.origin.fetch" ], 1, undef
                        )->{stdout}
                    ),
                    $spec
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
        }
    }
}

sub test_explicit_checkout_fetches_preserve_unrelated_tags {
    my ($self) = @_;
    my ( $ignored, $destination, $destinations, $expected, $main, $routes, $tail, $topic );
    $destinations = [ map { my $unused_1 = $_; clone( $self, 1, undef, undef ) } @{ [ 0 .. ( 3 - 1 ) ] } ];
    $main         = commit(
        $self, $self->{source}, 'main branch file
', "main.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $topic = commit(
        $self, $self->{source}, 'topic branch file
', "topic.txt"
    );
    git( $self, $self->{source}, [ "tag", "unrelated" ],                                     1, undef );
    git( $self, $self->{source}, [ "tag", "--annotate", "--message", "release", "release" ], 1, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ],                            1, undef );
    $routes = [
        [ "blob/main/main.txt",   $main ],
        [ "blob/topic/topic.txt", $topic ],
        [ "releases/tag/release", $topic ]
    ];
    for my $item_2023 ( @{ zip_lists( $routes, $destinations ) } ) {
        $tail        = ( ($item_2023)->[0] )->[0];
        $expected    = ( ($item_2023)->[0] )->[1];
        $destination = ($item_2023)->[1];
        {
            git( $self, $destination, [ "config", "remote.origin.tagOpt", "--tags" ],         1, undef );
            git( $self, $destination, [ "tag",    "unrelated",            $self->{initial} ], 1, undef );
            assert_success( $self, checkout( $self, $destination, $tail, 0 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $expected ) or die "assertion failed\n" );
            (
                is_deeply(
                    git( $self, $destination, ["tag"], 1, undef )->{stdout},
                    'unrelated
'
                  )
                  or die "assertion failed\n"
            );
            (
                is_deeply( oid( $self, $destination, "refs/tags/unrelated" ), $self->{initial} )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_checkout_preserves_edits_made_during_fetch {
    my ($self) = @_;
    my ( $destination, $result, $tail );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    commit(
        $self, $self->{source}, 'topic change
', "topic.txt"
    );
    git( $self, $self->{source}, [ "tag", "--annotate", "--message", "Release", "v2" ], 1, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    for $tail ( @{ [ "tree/topic", "releases/tag/v2" ] } ) {
        {
            $destination = clone( $self, 1, undef, undef );
            $result      = fish(
                $self, 'function git
    command git $argv; or return
    if contains -- fetch $argv
        printf \'%s\\n\' \'late edit\' > "$argv[2]/file.txt"
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" "$argv[3]" "" "" "" ""
', [ $URL, $destination, $tail ], 0
            );
            assert_success( $self, $result );
            (
                ok(
                    contains_value(
                        $result->{stderr}, "keeping the current ref because the checkout has local changes"
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply(
                    trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
                    "main" )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    read_file( join_path( $destination, "file.txt" ) ),
                    'late edit
'
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_new_branch_starts_from_its_own_fetch_result {
    my ($self) = @_;
    my ( $destination, $result, $tip, $tracking );
    $destination = clone( $self, 1, undef, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $tip = commit(
        $self, $self->{source}, 'topic change
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $tracking = "refs/remotes/origin/topic";
    $result   = fish(
        $self, 'function git
    command git $argv; or return
    if contains -- +refs/heads/topic:refs/remotes/origin/topic $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin +refs/heads/main:refs/remotes/origin/topic
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" tree/topic "" "" "" ""
', [ $URL, $destination ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ),    $tip )             or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, $tracking ), $self->{initial} ) or die "assertion failed\n" );
}

sub test_checkout_preserves_clean_branch_changes_during_fetch {
    my ($self) = @_;
    my ( $change, $destination, $expected, $result, $topic );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $topic = commit(
        $self, $self->{source}, 'topic branch
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    for $change ( @{ [ "switch", "advance", "advance-before-fetch" ] } ) {
        {
            $destination = clone( $self, 1, undef, undef );
            git( $self, $destination, [ "branch", "side" ], 1, undef );
            $result = fish(
                $self, 'set -gx CHANGE "$argv[3]"
function git
    if test "$CHANGE" = advance-before-fetch; and contains -- show-ref $argv; and test "$argv[-1]" = refs/heads/topic
        command git -C "$argv[2]" commit --quiet --allow-empty --message \'concurrent commit\'; or return
    end
    command git $argv; or return
    if contains -- fetch $argv
        if test "$CHANGE" = switch
            command git -C "$argv[2]" switch --quiet side
        else if test "$CHANGE" = advance
            command git -C "$argv[2]" commit --quiet --allow-empty --message \'concurrent commit\'
        end
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" tree/topic "" "" "" ""
', [ $URL, $destination, $change ], 0
            );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "checkout changed while fetching; skipping switch" ) )
                  or die "assertion failed\n"
            );
            (
                is_deeply( oid( $self, $destination, "refs/remotes/origin/topic" ), $topic )
                  or die "assertion failed\n"
            );
            (
                ok(
                    !equal_values(
                        git( $self, $destination, [ "show-ref", "--verify", "--quiet", "refs/heads/topic" ],
                            0, undef )->{returncode},
                        0
                    )
                  )
                  or die "assertion failed\n"
            );
            $expected = ( ( ( $change eq "switch" ) ) ? "side" : "main" );
            (
                is_deeply(
                    trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
                    $expected )
                  or die "assertion failed\n"
            );
            if ( ( ( $change eq "switch" ) ) ) {
                (
                    is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} )
                      or die "assertion failed\n"
                );
            }
            else {
                (
                    is_deeply( oid( $self, $destination, "HEAD^" ), $self->{initial} )
                      or die "assertion failed\n"
                );
            }
        }
    }
}

sub test_checkout_preserves_a_branch_created_during_fetch {
    my ($self) = @_;
    my ( $destination, $result, $target, $tip );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $tip = commit(
        $self, $self->{source}, 'topic change
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    for $target ( @{ [ "refs/remotes/origin/topic", "refs/heads/topic" ] } ) {
        {
            $destination = clone( $self, 1, undef, undef );
            git( $self, $destination,
                [ "config", "--add", "remote.origin.fetch", ( "+refs/heads/topic:" . $target ) ],
                1, undef );
            $result = fish(
                $self, 'function git
    command git $argv; or return
    if contains -- fetch $argv
        command git -C "$argv[2]" update-ref refs/heads/topic refs/heads/main
        command git -C "$argv[2]" config branch.topic.remote private
        command git -C "$argv[2]" config branch.topic.merge refs/heads/local-topic
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" tree/topic "" "" "" ""
', [ $URL, $destination ], 0
            );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            (
                is_deeply( oid( $self, $destination, "refs/heads/topic" ), $self->{initial} )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
                    "main" )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    trim(
                        git( $self, $destination, [ "config", "branch.topic.remote" ], 1, undef )->{stdout}
                    ),
                    "private"
                  )
                  or die "assertion failed\n"
            );
            (
                is_deeply(
                    trim(
                        git( $self, $destination, [ "config", "branch.topic.merge" ], 1, undef )->{stdout}
                    ),
                    "refs/heads/local-topic"
                  )
                  or die "assertion failed\n"
            );
            if ( ( ( $target ne "refs/heads/topic" ) ) ) {
                ( is_deeply( oid( $self, $destination, $target ), $tip ) or die "assertion failed\n" );
            }
        }
    }
}

sub test_checkout_creates_the_requested_branch_with_a_local_fetch_destination {
    my ($self) = @_;
    my ( $destination, $tip );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $tip = commit(
        $self, $self->{source}, 'topic change
', "file.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    $destination = clone( $self, 1, undef, undef );
    git( $self, $destination,
        [ "config", "--add", "remote.origin.fetch", "+refs/heads/topic:refs/heads/topic" ],
        1, undef );
    assert_success( $self, checkout( $self, $destination, "blob/topic/file.txt", 0 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $tip ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            "topic" )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            trim( git( $self, $destination, [ "config", "branch.topic.remote" ], 1, undef )->{stdout} ),
            "origin" )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $destination, [ "config", "branch.topic.merge" ], 1, undef )->{stdout} ),
            "refs/heads/topic" )
          or die "assertion failed\n"
    );
}

sub test_single_branch_clone_adds_tracking_for_new_branch_and_future_fetches {
    my ($self) = @_;
    my ( $destination, $newer );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    $destination = clone( $self, 1, undef, undef );
    assert_success( $self, checkout( $self, $destination, "blob/topic/file.txt", 0 ) );
    (
        is_deeply(
            trim(
                git( $self, $destination, [ "rev-parse", "--symbolic-full-name", "\@{upstream}" ], 1, undef )
                  ->{stdout}
            ),
            "refs/remotes/origin/topic"
          )
          or die "assertion failed\n"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "topic" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'new topic
', "file.txt"
    );
    git(
        $self,
        $destination,
        [
            "-c", ( ( ( "url." . file_uri( $self->{source} ) ) . ".insteadOf=" ) . $URL ),
            "fetch", "--quiet", "origin"
        ],
        1, undef
    );
    ( is_deeply( oid( $self, $destination, "\@{upstream}" ), $newer ) or die "assertion failed\n" );
}

sub test_excluded_branch_is_not_fetched_or_checked_out {
    my ($self) = @_;
    my ( $before, $call, $destination, $result );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "config", "--add", "remote.origin.fetch", "^refs/heads/topic" ], 1, undef );
    $before =
      git( $self, $destination, [ "config", "--get-all", "remote.origin.fetch" ], 1, undef )->{stdout};
    $result = checkout( $self, $destination, "blob/topic/file.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) )       or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "excluded" ) ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            "main" )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            git( $self, $destination, [ "config", "--get-all", "remote.origin.fetch" ], 1, undef )->{stdout},
            $before
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
                                ( ( $call->{"command"} eq "fetch" ) )
                            } @{ $self->{transport} }
                        ]
                    }
                )
            )
          )
          or die "assertion failed\n"
    );
}

sub test_missing_file_pull_checks_the_fetched_path_in_a_tree_filtered_clone {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    git( $self, $self->{source}, [ "config", "uploadpack.allowFilter",        "true" ], 1, undef );
    git( $self, $self->{source}, [ "config", "uploadpack.allowAnySHA1InWant", "true" ], 1, undef );
    $destination = clone( $self, 0, undef, "tree:0" );
    $newer       = commit(
        $self, $self->{source}, 'partial clone file
', "new.txt"
    );

    # Git's internal promisor fetches bypass the transport wrapper.
    $result = fish(
        $self, 'set -g promisor_rewrite "url.$argv[3].insteadOf=$argv[1]"
function git
    if contains -- rev-parse $argv; or contains -- merge $argv
        command git -c "$promisor_rewrite" $argv
    else
        command git $argv
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" blob/main/new.txt "" "" "" ""
', [ $URL, $destination, file_uri( $self->{source} ) ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
    (
        is_deeply(
            read_file( join_path( $destination, "new.txt" ) ),
            'partial clone file
'
          )
          or die "assertion failed\n"
    );
}

sub test_missing_file_pull_does_not_merge_a_tip_without_the_requested_path {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    $destination = clone( $self, 0, undef, undef );
    $newer       = commit(
        $self, $self->{source}, 'new branch file
', "new.txt"
    );
    $result = checkout( $self, $destination, "blob/main/typo.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "path does not exist in this checkout" ) )
          or die "assertion failed\n"
    );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    ( ok( !( ( -e join_path( $destination, "new.txt" ) ) ) ) or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
          or die "assertion failed\n"
    );
    assert_success( $self, checkout( $self, $destination, "blob/main/new.txt", 0 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
}

sub test_missing_file_pull_uses_the_refmap_it_checked {
    my ($self) = @_;
    my ( $destination, $newer, $result, $saved );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "switch", "--quiet", "--create", "private" ], 1, undef );
    $saved = commit(
        $self, $destination, 'private file
', "saved.txt"
    );
    git( $self, $destination, [ "switch", "--quiet", "main" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'remote file
', "new.txt"
    );
    $result = fish(
        $self, 'function git
    if contains -- fetch $argv
        command git -C "$argv[2]" config --replace-all remote.origin.fetch +refs/heads/main:refs/heads/private; or return
    end
    command git $argv
end
__ghe_checkout "$argv[1]" "$argv[2]" blob/main/new.txt "" "" "" ""
', [ $URL, $destination ], 0
    );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ),               $newer ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "refs/heads/private" ), $saved ) or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
          or die "assertion failed\n"
    );
}

sub test_missing_file_pull_preserves_local_branch_and_tag_fetch_destinations {
    my ($self) = @_;
    my ( $destination, $destinations, $newer, $saved, $target );
    $destinations =
      [ clone( $self, 0, undef, undef ), clone( $self, 0, undef, undef ) ];
    $newer = commit(
        $self, $self->{source}, 'new branch file
', "new.txt"
    );
    for my $item_2242 ( @{ zip_lists( [ "refs/heads/private", "refs/tags/private" ], $destinations ) } ) {
        $target      = ($item_2242)->[0];
        $destination = ($item_2242)->[1];
        {
            git( $self, $destination, [ "switch", "--quiet", "--create", "local-work" ], 1, undef );
            $saved = commit(
                $self, $destination, 'unpublished local work
', "saved.txt"
            );
            git( $self, $destination, [ "update-ref", $target, $saved ], 1, undef );
            git( $self, $destination, [ "switch",     "--quiet", "main" ], 1, undef );
            git( $self, $destination, [ "branch", "--delete", "--force", "local-work" ], 1, undef );
            git( $self, $destination,
                [ "config", "--replace-all", "remote.origin.fetch", ( "+refs/heads/main:" . $target ) ],
                1, undef );
            assert_success( $self, checkout( $self, $destination, "blob/main/new.txt", 0 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ),  $newer ) or die "assertion failed\n" );
            ( is_deeply( oid( $self, $destination, $target ), $saved ) or die "assertion failed\n" );
            ( ok( !( ( -e join_path( $destination, "saved.txt" ) ) ) ) or die "assertion failed\n" );
        }
    }
}

sub test_new_branch_checkout_does_not_use_a_local_branch_or_tag_as_remote_cache {
    my ($self) = @_;
    my ( $ignored, $destination, $destinations, $target, $tip );
    $destinations = [ map { my $unused_2 = $_; clone( $self, 1, undef, undef ) } @{ [ 0 .. ( 2 - 1 ) ] } ];
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "release/topic" ], 1, undef );
    $tip = commit(
        $self, $self->{source}, 'new topic file
', "topic.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    for my $item_2262 ( @{ zip_lists( [ "refs/heads/private", "refs/tags/private" ], $destinations ) } ) {
        $target      = ($item_2262)->[0];
        $destination = ($item_2262)->[1];
        {
            git( $self, $destination, [ "tag", "release", $self->{initial} ], 1, undef );
            git( $self, $destination, [ "update-ref", $target, $self->{initial} ], 1, undef );
            git( $self, $destination,
                [ "config", "--add", "remote.origin.fetch", ( "+refs/heads/release/topic:" . $target ) ],
                1, undef );
            assert_success( $self, checkout( $self, $destination, "blob/release/topic/file.txt", 0 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $tip ) or die "assertion failed\n" );
            (
                is_deeply(
                    trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
                    "release/topic" )
                  or die "assertion failed\n"
            );
            (
                is_deeply( oid( $self, $destination, $target ), $self->{initial} )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_missing_file_pull_respects_sparse_rules_for_new_paths {
    my ($self) = @_;
    my ( $cases, $destination, $destinations, $excluded, $included, $newer, $result, $rules );
    $destinations =
      [ clone( $self, 0, undef, undef ), clone( $self, 0, undef, undef ) ];
    commit(
        $self, $self->{source}, 'outside sparse selection
', "outside/excluded.txt"
    );
    $newer = commit(
        $self, $self->{source}, 'inside sparse selection
', "visible/included.txt"
    );
    $cases = [
        [ [ "--cone", "visible" ], "tree/main/outside", "tree/main/visible" ],
        [
            [ "--no-cone", "/visible/included.txt" ], "blob/main/outside/excluded.txt",
            "blob/main/visible/included.txt"
        ]
    ];
    for my $item_2283 ( @{ zip_lists( $cases, $destinations ) } ) {
        $rules       = ( ($item_2283)->[0] )->[0];
        $excluded    = ( ($item_2283)->[0] )->[1];
        $included    = ( ($item_2283)->[0] )->[2];
        $destination = ($item_2283)->[1];
        {
            git(
                $self,
                ( [ $destination, "sparse-checkout", "set", @{$rules} ] )->[0],
                array_slice( [ $destination, "sparse-checkout", "set", @{$rules} ], 1, undef ),
                1, undef
            );
            $result = checkout( $self, $destination, $excluded, 0 );
            ( ok( !equal_values( $result->{returncode}, 0 ) )                   or die "assertion failed\n" );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            ( ok( !( ( -e join_path( $destination, "visible" ) ) ) )            or die "assertion failed\n" );
            (
                is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $newer )
                  or die "assertion failed\n"
            );
            assert_success( $self, checkout( $self, $destination, $included, 0 ) );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
            ( ok( !( ( -e join_path( $destination, "outside" ) ) ) )  or die "assertion failed\n" );
            (
                is_deeply(
                    read_file( join_path( $destination, "visible/included.txt" ) ),
                    'inside sparse selection
'
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_missing_sparse_path_does_not_pull_a_tracked_file {
    my ($self) = @_;
    my ( $before, $destination, $result );
    $before = commit(
        $self, $self->{source}, 'sparse file
', "excluded.txt"
    );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "sparse-checkout", "set", "--no-cone", "/file.txt" ], 1, undef );
    ( ok( !( ( -e join_path( $destination, "excluded.txt" ) ) ) ) or die "assertion failed\n" );
    (
        is_deeply( git( $self, $destination, [ "status", "--porcelain" ], 1, undef )->{stdout}, "" )
          or die "assertion failed\n"
    );
    commit(
        $self, $self->{source}, 'updated visible file
', "file.txt"
    );
    $result = checkout( $self, $destination, "blob/main/excluded.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "path does not exist in this checkout" ) )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport},                 [] )      or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $before )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            read_file( join_path( $destination, "file.txt" ) ), 'initial
'
          )
          or die "assertion failed\n"
    );
}

sub test_missing_file_pull_keeps_all_tracking_refs_when_one_update_fails {
    my ($self) = @_;
    my ( $destination, $lock, $result, $tracking );
    $destination = clone( $self, 0, undef, undef );
    $tracking    = "refs/cache/origin/main";
    git( $self, $destination,
        [ "config", "--add", "remote.origin.fetch", ( "+refs/heads/main:" . $tracking ) ],
        1, undef );
    git( $self, $destination, [ "update-ref", $tracking, $self->{initial} ], 1, undef );
    $lock =
      join_path( join_path( $destination, ".git" ), ( $tracking . ".lock" ) );
    write_file(
        $lock, 'held by another process
'
    );
    commit(
        $self, $self->{source}, 'new branch file
', "new.txt"
    );
    $result = checkout( $self, $destination, "blob/main/new.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $self->{initial} )
          or die "assertion failed\n"
    );
    ( is_deeply( oid( $self, $destination, $tracking ), $self->{initial} ) or die "assertion failed\n" );
    ( ok( !( ( -e join_path( $destination, "new.txt" ) ) ) ) or die "assertion failed\n" );
}

sub test_missing_file_does_not_pull_a_negatively_excluded_upstream {
    my ($self) = @_;
    my ( $destination, $result );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "config", "--add", "remote.origin.fetch", "^refs/heads/main" ], 1, undef );
    commit(
        $self, $self->{source}, 'new file
', "new.txt"
    );
    $result = checkout( $self, $destination, "blob/main/new.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) )                   or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "upstream is excluded" ) ) or die "assertion failed\n" );
    ( is_deeply( $self->{transport}, [] )                               or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    ( ok( !( ( -e join_path( $destination, "new.txt" ) ) ) )            or die "assertion failed\n" );
}

sub test_missing_file_does_not_pull_a_different_upstream_branch {
    my ($self) = @_;
    my ( $destination, $result, $upstream );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "other" ], 1, undef );
    commit(
        $self, $self->{source}, 'other branch only
', "new.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "main" ], 1, undef );
    for $upstream ( @{ [ "origin/other", "other" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            if ( ( ( $upstream eq "other" ) ) ) {
                git( $self, $destination, [ "branch", "other", "origin/other" ], 1, undef );
            }
            git( $self, $destination, [ "switch", "--quiet", "--create", "topic", "--track", $upstream ],
                1, undef );
            git( $self, $destination, [ "reset", "--hard", $self->{initial} ], 1, undef );
            assert_success( $self, checkout( $self, $destination, "blob/topic/file.txt", 1 ) );
            ( is_deeply( $self->{transport}, [] ) or die "assertion failed\n" );
            $result = checkout( $self, $destination, "blob/topic/new.txt", 0 );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok(
                    contains_value(
                        $result->{stderr}, "upstream branch does not match the requested branch"
                    )
                  )
                  or die "assertion failed\n"
            );
            ( is_deeply( $self->{transport},                 [] )               or die "assertion failed\n" );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            ( ok( !( ( -e join_path( $destination, "new.txt" ) ) ) ) or die "assertion failed\n" );
        }
    }
}

sub test_missing_file_does_not_fetch_a_tag_for_an_abbreviated_upstream {
    my ($self) = @_;
    my ( $call, $destination, $result );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+topic:refs/remotes/origin/topic" ],
        1, undef );
    git( $self, $destination,    [ "switch", "--quiet", "--create", "topic", "--no-track" ], 1, undef );
    git( $self, $destination,    [ "config", "branch.topic.remote", "origin" ], 1, undef );
    git( $self, $destination,    [ "config", "branch.topic.merge",  "topic" ],  1, undef );
    git( $self, $self->{source}, [ "branch", "--delete",            "topic" ],  1, undef );
    commit(
        $self, $self->{source}, 'tag only
', "new.txt"
    );
    git( $self, $self->{source}, [ "tag", "topic" ], 1, undef );
    $result = checkout( $self, $destination, "blob/topic/new.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        is_deeply( [ map { my $call = $_; $call->{"args"}->[ -(1) ] } @{ $self->{transport} } ],
            ["refs/heads/topic"] )
          or die "assertion failed\n"
    );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    ( ok( !( ( -e join_path( $destination, "new.txt" ) ) ) ) or die "assertion failed\n" );
}

sub test_missing_file_does_not_merge_a_tag_for_an_abbreviated_local_upstream {
    my ($self) = @_;
    my ( $destination, $result, $tagged );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "switch", "--quiet", "--create", "topic", "--no-track" ], 1, undef );
    $tagged = commit(
        $self, $destination, 'tag only
', "new.txt"
    );
    git( $self, $destination, [ "tag",    "topic",               $tagged ],          1, undef );
    git( $self, $destination, [ "reset",  "--hard",              $self->{initial} ], 1, undef );
    git( $self, $destination, [ "config", "branch.topic.remote", "." ],              1, undef );
    git( $self, $destination, [ "config", "branch.topic.merge",  "topic" ],          1, undef );
    $result = checkout( $self, $destination, "blob/refs/heads/topic/new.txt", 1 );
    ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
    (
        ok( contains_value( $result->{stderr}, "path does not exist in this checkout" ) )
          or die "assertion failed\n"
    );
    ( is_deeply( $self->{transport},                 [] )               or die "assertion failed\n" );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
    ( ok( !( ( -e join_path( $destination, "new.txt" ) ) ) ) or die "assertion failed\n" );
}

sub test_missing_file_does_not_pull_after_a_skipped_switch {
    my ($self) = @_;
    my ( $destination, $destinations, $dirty_file, $result, $tail );
    git( $self, $self->{source}, [ "branch", "topic" ],   1, undef );
    git( $self, $self->{source}, [ "tag",    "release" ], 1, undef );
    $destinations =
      [ clone( $self, 0, undef, undef ), clone( $self, 0, undef, undef ) ];
    commit(
        $self, $self->{source}, 'main branch only
', "new.txt"
    );
    for my $item_2412 ( @{ zip_lists( [ "blob/topic/new.txt", "blob/release/new.txt" ], $destinations ) } ) {
        $tail        = ($item_2412)->[0];
        $destination = ($item_2412)->[1];
        {
            $dirty_file = join_path( $destination, "untracked" );
            write_file( $dirty_file, "" );
            $result = fish(
                $self, 'function git
    command git $argv; or return
    if contains -- status $argv; and test -f "$argv[2]/untracked"
        rm -- "$argv[2]/untracked"
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" "$argv[3]" "" "" "" ""
', [ $URL, $destination, $tail ], 0
            );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            (
                ok( contains_value( $result->{stderr}, "keeping the current ref" ) )
                  or die "assertion failed\n"
            );
            ( is_deeply( $self->{transport}, [] )                               or die "assertion failed\n" );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $self->{initial} ) or die "assertion failed\n" );
            ( ok( !( ( -e join_path( $destination, "new.txt" ) ) ) )            or die "assertion failed\n" );
            ( ok( !( ( -e $dirty_file ) ) )                                     or die "assertion failed\n" );
        }
    }
}

sub test_symbolic_fetch_destination_is_rejected_without_overwriting_it {
    my ($self) = @_;
    my ( $destination, $result );
    git( $self, $self->{source}, [ "branch", "topic" ], 1, undef );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination, [ "symbolic-ref", "refs/remotes/origin/topic", "refs/remotes/origin/main" ],
        1, undef );
    $result = checkout( $self, $destination, "blob/topic/file.txt", 0 );
    ( ok( !equal_values( $result->{returncode}, 0 ) )       or die "assertion failed\n" );
    ( ok( contains_value( $result->{stderr}, "symbolic" ) ) or die "assertion failed\n" );
    (
        is_deeply(
            trim(
                git( $self, $destination, [ "symbolic-ref", "refs/remotes/origin/topic" ], 1, undef )
                  ->{stdout}
            ),
            "refs/remotes/origin/main"
          )
          or die "assertion failed\n"
    );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            "main" )
          or die "assertion failed\n"
    );
}

sub test_comparisons_preserve_case_folded_local_branch_and_tag_namespaces {
    my ($self) = @_;
    my ( $after_target, $before, $before_tag, $before_target, $destination, $target, $tip );
    for $target ( @{ [ "refs/Heads/main", "refs/Tags/local-tag" ] } ) {
        {
            $destination = clone( $self, 0, undef, undef );
            git( $self, $destination, [ "tag", "local-tag" ], 1, undef );
            git( $self, $destination,
                [ "config", "--replace-all", "remote.origin.fetch", ( "+refs/heads/main:" . $target ) ],
                1, undef );
            $before     = oid( $self, $destination, "HEAD" );
            $before_tag = oid( $self, $destination, "refs/tags/local-tag" );
            $before_target =
              git( $self, $destination, [ "rev-parse", "--verify", "--quiet", $target ], 0, undef );
            $tip = commit(
                $self,
                $self->{source},
                (
                    $target . '
'
                ),
                "file.txt"
            );
            assert_resolves( $self, $destination, "HEAD", $tip, 0 );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $before ) or die "assertion failed\n" );
            (
                is_deeply( oid( $self, $destination, "refs/tags/local-tag" ), $before_tag )
                  or die "assertion failed\n"
            );
            (
                is_deeply( git( $self, $destination, [ "status", "--porcelain" ], 1, undef )->{stdout}, "" )
                  or die "assertion failed\n"
            );
            $after_target =
              git( $self, $destination, [ "rev-parse", "--verify", "--quiet", $target ], 0, undef );
            (
                is_deeply(
                    [ $after_target->{returncode},  $after_target->{stdout} ],
                    [ $before_target->{returncode}, $before_target->{stdout} ]
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_pull_handles_case_folded_checked_out_branch_destinations {
    my ($self) = @_;
    my ( $destination, $filename, $index, $newer, $result, $target );
    for my $item_2466 ( @{ enumerate_list( [ "refs/Heads/main", "refs/heads/Main" ] ) } ) {
        $index  = ($item_2466)->[0];
        $target = ($item_2466)->[1];
        {
            $destination = clone( $self, 0, undef, undef );
            git( $self, $destination,
                [ "config", "--replace-all", "remote.origin.fetch", ( "+refs/heads/main:" . $target ) ],
                1, undef );
            $filename = sprintf( "new-%d.txt", $index );
            $newer    = commit(
                $self, $self->{source}, 'new file
', $filename
            );
            $result = fish(
                $self,
                "__ghe_pull \"\$argv[1]\" \"\$argv[2]\" main \"\$argv[3]\"",
                [ $destination, $URL, $filename ], 0
            );
            assert_success( $self, $result );
            ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
            ( ok( ( ( -f join_path( $destination, $filename ) ) ) )   or die "assertion failed\n" );
            (
                is_deeply(
                    read_file( join_path( $destination, $filename ) ), 'new file
'
                  )
                  or die "assertion failed\n"
            );
            (
                is_deeply( git( $self, $destination, [ "status", "--porcelain" ], 1, undef )->{stdout}, "" )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_pull_does_not_update_another_branch_through_a_symbolic_fetch_destination {
    my ($self) = @_;
    my ( $alias, $destination, $newer );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    $newer = commit(
        $self, $self->{source}, 'topic file
', "topic-only.txt"
    );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/topic:refs/remotes/origin/HEAD" ],
        1, undef );
    git( $self, $destination, [ "switch", "--quiet", "--create", "topic" ], 1, undef );
    git( $self, $destination, [ "config", "branch.topic.remote", "origin" ],           1, undef );
    git( $self, $destination, [ "config", "branch.topic.merge",  "refs/heads/topic" ], 1, undef );
    assert_success( $self, checkout( $self, $destination, "blob/topic/topic-only.txt", 0 ) );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
    (
        is_deeply( oid( $self, $destination, "refs/remotes/origin/main" ), $self->{initial} )
          or die "assertion failed\n"
    );
    $alias =
      trim( git( $self, $destination, [ "symbolic-ref", "refs/remotes/origin/HEAD" ], 1, undef )->{stdout} );
    ( is_deeply( $alias, "refs/remotes/origin/main" ) or die "assertion failed\n" );
}

sub test_pull_preserves_tracking_refs_with_ambiguous_fetch_mappings {
    my ($self) = @_;
    my ( $destination, $first, $mappings, $newer, $packed, $refs, $second, $tracking, $upstream );
    git( $self, $self->{source}, [ "branch", "-m",      "main",     "release/topic" ], 1, undef );
    git( $self, $self->{source}, [ "switch", "--quiet", "--create", "topic" ],         1, undef );
    $newer = commit(
        $self, $self->{source}, 'topic file
', "topic-only.txt"
    );
    git( $self, $self->{source}, [ "switch", "--quiet", "release/topic" ], 1, undef );
    $mappings = [
        [
            "+release/topic:refs/remotes/origin/topic", "+refs/heads/*:refs/remotes/origin/*",
            "refs/heads/topic",                         "refs/remotes/origin/topic"
        ],
        [
            "+refs/heads/release/topic:refs/remotes/origin/Topic", "+refs/heads/*:refs/remotes/origin/*",
            "refs/heads/topic",                                    "refs/remotes/origin/Topic"
        ],
        [
            "+refs/heads/release/*:refs/remotes/origin/Topic/*",
            "+refs/heads/*:refs/remotes/origin/topic/*",
            "refs/heads/topic",
            "refs/remotes/origin/Topic/topic"
        ],
        [
            "+release/topic:refs/remotes/origin/topic", "+topic:refs/remotes/origin/topic",
            "topic",                                    "refs/remotes/origin/topic"
        ],
        [
            "+release/topic:refs/remotes/origin/Topic", "+topic:refs/remotes/origin/topic",
            "topic",                                    "refs/remotes/origin/Topic"
        ]
    ];
    for my $item_2531 ( @{$mappings} ) {
        $first    = ($item_2531)->[0];
        $second   = ($item_2531)->[1];
        $upstream = ($item_2531)->[2];
        $tracking = ($item_2531)->[3];
        for $packed ( @{ [ 0, 1 ] } ) {
            {
                $destination = clone( $self, 0, undef, undef );
                git( $self, $destination, [ "update-ref", "-d", "refs/remotes/origin/topic" ], 1, undef );
                git( $self, $destination, [ "update-ref", $tracking, $self->{initial} ], 1, undef );
                if ($packed) {
                    git( $self, $destination, [ "pack-refs", "--all", "--prune" ], 1, undef );
                }
                git( $self, $destination, [ "config", "--replace-all", "remote.origin.fetch", $first ],
                    1, undef );
                git( $self, $destination, [ "config", "--add", "remote.origin.fetch", $second ], 1, undef );
                git( $self, $destination, [ "switch", "--quiet", "--create", "topic", $self->{initial} ],
                    1, undef );
                git( $self, $destination, [ "config", "branch.topic.remote", "origin" ],  1, undef );
                git( $self, $destination, [ "config", "branch.topic.merge",  $upstream ], 1, undef );
                assert_success( $self, checkout( $self, $destination, "blob/topic/topic-only.txt", 0 ) );
                ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
                (
                    is_deeply( oid( $self, $destination, $tracking ), $self->{initial} )
                      or die "assertion failed\n"
                );
                $refs = [
                    split(
                        /\n/,
                        git( $self, $destination,
                            [ "for-each-ref", "--ignore-case", "--format=%(refname)", $tracking ],
                            1, undef )->{stdout}
                    )
                ];
                ( is_deeply( $refs, [$tracking] ) or die "assertion failed\n" );
            }
        }
    }
}

sub test_pull_can_fast_forward_when_fetch_mapping_targets_current_branch {
    my ($self) = @_;
    my ( $destination, $newer, $result );
    $destination = clone( $self, 0, undef, undef );
    git( $self, $destination,
        [ "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:refs/heads/main" ],
        1, undef );
    $newer = commit(
        $self, $self->{source}, 'new upstream
', "file.txt"
    );
    $result =
      fish( $self, "__ghe_pull \"\$argv[1]\" \"\$argv[2]\" main file.txt", [ $destination, $URL ], 0 );
    assert_success( $self, $result );
    ( is_deeply( oid( $self, $destination, "HEAD" ), $newer ) or die "assertion failed\n" );
    (
        is_deeply( trim( git( $self, $destination, [ "branch", "--show-current" ], 1, undef )->{stdout} ),
            "main" )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            read_file( join_path( $destination, "file.txt" ) ), 'new upstream
'
          )
          or die "assertion failed\n"
    );
}

run_cases(
    {
        "test_commit_ref_avoids_a_redundant_revision_lookup" =>
          \&test_commit_ref_avoids_a_redundant_revision_lookup,
        "test_commit_ref_preserves_tag_peeling_and_direct_ref_checks" =>
          \&test_commit_ref_preserves_tag_peeling_and_direct_ref_checks,
        "test_remote_matching_handles_filters_multiple_urls_and_rewrites" =>
          \&test_remote_matching_handles_filters_multiple_urls_and_rewrites,
        "test_comparison_cache_handles_unicode_ref_without_filename_expansion" =>
          \&test_comparison_cache_handles_unicode_ref_without_filename_expansion,
        "test_comparison_cache_survives_ref_hierarchy_replacements" =>
          \&test_comparison_cache_survives_ref_hierarchy_replacements,
        "test_preexisting_comparison_cache_formats_work_offline" =>
          \&test_preexisting_comparison_cache_formats_work_offline,
        "test_comparison_request_cannot_alias_another_cache_key" =>
          \&test_comparison_request_cannot_alias_another_cache_key,
        "test_fork_comparison_caches_are_repository_specific" =>
          \&test_fork_comparison_caches_are_repository_specific,
        "test_fork_comparison_does_not_fetch_or_prune_unrelated_tags" =>
          \&test_fork_comparison_does_not_fetch_or_prune_unrelated_tags,
        "test_named_comparisons_refresh_and_keep_latest_snapshot_offline" =>
          \&test_named_comparisons_refresh_and_keep_latest_snapshot_offline,
        "test_named_comparison_rejects_tracking_written_through_a_custom_symref" =>
          \&test_named_comparison_rejects_tracking_written_through_a_custom_symref,
        "test_named_comparison_follows_a_synchronized_tracking_ref_offline" =>
          \&test_named_comparison_follows_a_synchronized_tracking_ref_offline,
        "test_bare_comparison_does_not_follow_a_branch_after_selecting_a_same_oid_tag" =>
          \&test_bare_comparison_does_not_follow_a_branch_after_selecting_a_same_oid_tag,
        "test_offline_comparison_rejects_local_branch_as_a_tracking_snapshot" =>
          \&test_offline_comparison_rejects_local_branch_as_a_tracking_snapshot,
        "test_named_comparison_works_when_a_snapshot_ref_is_locked" =>
          \&test_named_comparison_works_when_a_snapshot_ref_is_locked,
        "test_delayed_comparison_keeps_a_newer_tracked_snapshot" =>
          \&test_delayed_comparison_keeps_a_newer_tracked_snapshot,
        "test_delayed_comparison_does_not_replace_a_newer_tag_snapshot" =>
          \&test_delayed_comparison_does_not_replace_a_newer_tag_snapshot,
        "test_delayed_comparison_cannot_restore_a_branch_after_selecting_a_same_oid_tag" =>
          \&test_delayed_comparison_cannot_restore_a_branch_after_selecting_a_same_oid_tag,
        "test_moved_tag_and_branch_to_tag_comparison_keep_latest_snapshot" =>
          \&test_moved_tag_and_branch_to_tag_comparison_keep_latest_snapshot,
        "test_deleted_comparison_ref_does_not_fall_back_to_stale_cache" =>
          \&test_deleted_comparison_ref_does_not_fall_back_to_stale_cache,
        "test_hex_named_comparison_branch_is_refreshed" => \&test_hex_named_comparison_branch_is_refreshed,
        "test_named_comparison_has_no_array_index_errors_with_bsd_seq" =>
          \&test_named_comparison_has_no_array_index_errors_with_bsd_seq,
        "test_cached_comparison_commit_ids_do_not_attempt_transport" =>
          \&test_cached_comparison_commit_ids_do_not_attempt_transport,
        "test_cached_comparison_tips_fetch_a_missing_shallow_merge_base" =>
          \&test_cached_comparison_tips_fetch_a_missing_shallow_merge_base,
        "test_cached_comparison_ancestors_fetch_a_missing_shallow_merge_base" =>
          \&test_cached_comparison_ancestors_fetch_a_missing_shallow_merge_base,
        "test_shallow_three_dot_comparison_checks_for_a_closer_merge_base" =>
          \&test_shallow_three_dot_comparison_checks_for_a_closer_merge_base,
        "test_cached_commit_ancestry_in_shallow_clone_fetches_missing_history" =>
          \&test_cached_commit_ancestry_in_shallow_clone_fetches_missing_history,
        "test_head_file_open_follows_pulls_and_comparisons_in_observation_order" =>
          \&test_head_file_open_follows_pulls_and_comparisons_in_observation_order,
        "test_head_comparison_refreshes_tracking_on_force_rewind_and_divergence" =>
          \&test_head_comparison_refreshes_tracking_on_force_rewind_and_divergence,
        "test_head_comparison_updates_tracking_after_force_push_without_local_fetch" =>
          \&test_head_comparison_updates_tracking_after_force_push_without_local_fetch,
        "test_case_distinct_branches_do_not_shadow_existing_tracking_refs" =>
          \&test_case_distinct_branches_do_not_shadow_existing_tracking_refs,
        "test_compare_does_not_read_or_overwrite_a_unicode_loose_ref_alias" =>
          \&test_compare_does_not_read_or_overwrite_a_unicode_loose_ref_alias,
        "test_missing_full_tag_does_not_resolve_through_a_nested_tag" =>
          \&test_missing_full_tag_does_not_resolve_through_a_nested_tag,
        "test_gho_opens_paths_without_a_tracking_ref" => \&test_gho_opens_paths_without_a_tracking_ref,
        "test_offline_tag_comparison_does_not_reuse_a_differently_cased_tag" =>
          \&test_offline_tag_comparison_does_not_reuse_a_differently_cased_tag,
        "test_topic_comparison_updates_tracking_after_force_push_without_local_fetch" =>
          \&test_topic_comparison_updates_tracking_after_force_push_without_local_fetch,
        "test_head_open_follows_updates_through_each_matching_remote" =>
          \&test_head_open_follows_updates_through_each_matching_remote,
        "test_head_open_follows_nonquery_remote_rewinds_and_divergence" =>
          \&test_head_open_follows_nonquery_remote_rewinds_and_divergence,
        "test_matching_remote_head_conflicts_require_refresh" =>
          \&test_matching_remote_head_conflicts_require_refresh,
        "test_matching_remotes_can_share_a_tracking_destination" =>
          \&test_matching_remotes_can_share_a_tracking_destination,
        "test_failed_matching_remote_sync_invalidates_all_default_aliases" =>
          \&test_failed_matching_remote_sync_invalidates_all_default_aliases,
        "test_matching_remote_alias_cannot_replace_another_tracking_target" =>
          \&test_matching_remote_alias_cannot_replace_another_tracking_target,
        "test_delayed_default_comparison_cannot_restore_the_old_default_branch" =>
          \&test_delayed_default_comparison_cannot_restore_the_old_default_branch,
        "test_head_comparison_updates_default_alias_without_overwriting_old_branch" =>
          \&test_head_comparison_updates_default_alias_without_overwriting_old_branch,
        "test_head_comparison_succeeds_when_a_dangling_symref_blocks_its_alias" =>
          \&test_head_comparison_succeeds_when_a_dangling_symref_blocks_its_alias,
        "test_head_comparison_preserves_direct_and_overlapping_tracking_destinations" =>
          \&test_head_comparison_preserves_direct_and_overlapping_tracking_destinations,
        "test_direct_default_tracking_destination_follows_later_fetch_offline" =>
          \&test_direct_default_tracking_destination_follows_later_fetch_offline,
        "test_failed_direct_default_update_does_not_reuse_the_previous_head_snapshot" =>
          \&test_failed_direct_default_update_does_not_reuse_the_previous_head_snapshot,
        "test_direct_default_alias_requires_an_active_round_trip_fetch_mapping" =>
          \&test_direct_default_alias_requires_an_active_round_trip_fetch_mapping,
        "test_direct_default_alias_requires_an_explicit_fetch_destination" =>
          \&test_direct_default_alias_requires_an_explicit_fetch_destination,
        "test_missing_default_alias_is_not_inferred_from_a_wildcard_mapping" =>
          \&test_missing_default_alias_is_not_inferred_from_a_wildcard_mapping,
        "test_head_open_refreshes_unsafe_mapping_without_modifying_its_target" =>
          \&test_head_open_refreshes_unsafe_mapping_without_modifying_its_target,
        "test_head_open_does_not_trust_a_negatively_excluded_default" =>
          \&test_head_open_does_not_trust_a_negatively_excluded_default,
        "test_head_comparison_handles_tracking_refs_overlapping_its_alias" =>
          \&test_head_comparison_handles_tracking_refs_overlapping_its_alias,
        "test_changed_default_with_no_safe_mapping_invalidates_the_old_alias" =>
          \&test_changed_default_with_no_safe_mapping_invalidates_the_old_alias,
        "test_comparison_survives_a_stale_tracking_ref_hierarchy" =>
          \&test_comparison_survives_a_stale_tracking_ref_hierarchy,
        "test_failed_default_tracking_update_requires_refresh_instead_of_old_head_cache" =>
          \&test_failed_default_tracking_update_requires_refresh_instead_of_old_head_cache,
        "test_legacy_head_snapshot_conflict_requires_one_online_synchronization" =>
          \&test_legacy_head_snapshot_conflict_requires_one_online_synchronization,
        "test_head_file_open_refreshes_a_cached_default_missing_the_path" =>
          \&test_head_file_open_refreshes_a_cached_default_missing_the_path,
        "test_unmapped_head_refresh_does_not_cache_a_new_default_under_the_old_branch" =>
          \&test_unmapped_head_refresh_does_not_cache_a_new_default_under_the_old_branch,
        "test_head_comparison_refreshes_default_branch_snapshot_offline" =>
          \&test_head_comparison_refreshes_default_branch_snapshot_offline,
        "test_head_file_open_uses_cached_default_commit_without_transport" =>
          \&test_head_file_open_uses_cached_default_commit_without_transport,
        "test_empty_fork_does_not_resolve_an_unrelated_local_commit_prefix" =>
          \&test_empty_fork_does_not_resolve_an_unrelated_local_commit_prefix,
        "test_nonempty_fork_does_not_resolve_an_unrelated_local_commit_prefix" =>
          \&test_nonempty_fork_does_not_resolve_an_unrelated_local_commit_prefix,
        "test_fork_prefix_ignores_a_colliding_unrelated_local_commit" =>
          \&test_fork_prefix_ignores_a_colliding_unrelated_local_commit,
        "test_fork_prefix_counts_a_commit_and_its_colliding_tag_once" =>
          \&test_fork_prefix_counts_a_commit_and_its_colliding_tag_once,
        "test_fork_prefix_of_a_fetched_annotated_tag_resolves_to_its_commit" =>
          \&test_fork_prefix_of_a_fetched_annotated_tag_resolves_to_its_commit,
        "test_fork_prefix_rejects_two_colliding_fetched_commits" =>
          \&test_fork_prefix_rejects_two_colliding_fetched_commits,
        "test_comparison_uses_its_own_fetch_result"          => \&test_comparison_uses_its_own_fetch_result,
        "test_checkout_caches_a_tag_that_moves_before_fetch" =>
          \&test_checkout_caches_a_tag_that_moves_before_fetch,
        "test_delayed_pull_request_fetch_keeps_a_newer_cached_head" =>
          \&test_delayed_pull_request_fetch_keeps_a_newer_cached_head,
        "test_fork_prefix_uses_its_own_fetched_histories" =>
          \&test_fork_prefix_uses_its_own_fetched_histories,
        "test_symbolic_comparison_cache_cannot_redirect_to_unrelated_branch" =>
          \&test_symbolic_comparison_cache_cannot_redirect_to_unrelated_branch,
        "test_comparison_can_select_branch_or_tag_with_the_same_name" =>
          \&test_comparison_can_select_branch_or_tag_with_the_same_name,
        "test_remote_head_and_ancestry_ignore_unpushed_local_commits" =>
          \&test_remote_head_and_ancestry_ignore_unpushed_local_commits,
        "test_two_and_three_dot_comparisons_match_git_without_changing_checkout" =>
          \&test_two_and_three_dot_comparisons_match_git_without_changing_checkout,
        "test_gho_opens_branch_without_checking_for_same_named_tags" =>
          \&test_gho_opens_branch_without_checking_for_same_named_tags,
        "test_stale_default_head_alias_uses_current_fetch_mapping_offline" =>
          \&test_stale_default_head_alias_uses_current_fetch_mapping_offline,
        "test_gho_opens_paths_without_checking_for_longer_tags" =>
          \&test_gho_opens_paths_without_checking_for_longer_tags,
        "test_explicit_tag_checks_out_tag_instead_of_same_named_branch" =>
          \&test_explicit_tag_checks_out_tag_instead_of_same_named_branch,
        "test_full_commit_id_wins_over_a_branch_with_the_same_name" =>
          \&test_full_commit_id_wins_over_a_branch_with_the_same_name,
        "test_short_hex_branch_stays_a_tracking_branch" => \&test_short_hex_branch_stays_a_tracking_branch,
        "test_uncached_slash_branch_opens_a_path_with_glob_characters" =>
          \&test_uncached_slash_branch_opens_a_path_with_glob_characters,
        "test_new_hex_branches_win_over_cached_abbreviated_commits" =>
          \&test_new_hex_branches_win_over_cached_abbreviated_commits,
        "test_cached_short_commit_fails_closed_when_remote_refs_are_unavailable" =>
          \&test_cached_short_commit_fails_closed_when_remote_refs_are_unavailable,
        "test_cached_short_commit_checks_remote_refs_before_switching" =>
          \&test_cached_short_commit_checks_remote_refs_before_switching,
        "test_gho_opens_detached_commit_offline_despite_ambiguous_short_ref" =>
          \&test_gho_opens_detached_commit_offline_despite_ambiguous_short_ref,
        "test_missing_abbreviated_commit_is_fetched_and_detached" =>
          \&test_missing_abbreviated_commit_is_fetched_and_detached,
        "test_missing_abbreviated_commit_in_shallow_clone_fetches_history" =>
          \&test_missing_abbreviated_commit_in_shallow_clone_fetches_history,
        "test_unknown_abbreviated_commit_has_clear_error_and_keeps_checkout" =>
          \&test_unknown_abbreviated_commit_has_clear_error_and_keeps_checkout,
        "test_overlapping_fetch_mappings_do_not_invent_a_cached_branch" =>
          \&test_overlapping_fetch_mappings_do_not_invent_a_cached_branch,
        "test_nonbranch_fetch_source_does_not_claim_a_tracking_destination" =>
          \&test_nonbranch_fetch_source_does_not_claim_a_tracking_destination,
        "test_two_sources_do_not_claim_the_same_tracking_destination" =>
          \&test_two_sources_do_not_claim_the_same_tracking_destination,
        "test_custom_cached_fetch_destinations_set_a_working_upstream" =>
          \&test_custom_cached_fetch_destinations_set_a_working_upstream,
        "test_explicit_checkout_fetches_preserve_unrelated_tags" =>
          \&test_explicit_checkout_fetches_preserve_unrelated_tags,
        "test_checkout_preserves_edits_made_during_fetch" =>
          \&test_checkout_preserves_edits_made_during_fetch,
        "test_new_branch_starts_from_its_own_fetch_result" =>
          \&test_new_branch_starts_from_its_own_fetch_result,
        "test_checkout_preserves_clean_branch_changes_during_fetch" =>
          \&test_checkout_preserves_clean_branch_changes_during_fetch,
        "test_checkout_preserves_a_branch_created_during_fetch" =>
          \&test_checkout_preserves_a_branch_created_during_fetch,
        "test_checkout_creates_the_requested_branch_with_a_local_fetch_destination" =>
          \&test_checkout_creates_the_requested_branch_with_a_local_fetch_destination,
        "test_single_branch_clone_adds_tracking_for_new_branch_and_future_fetches" =>
          \&test_single_branch_clone_adds_tracking_for_new_branch_and_future_fetches,
        "test_excluded_branch_is_not_fetched_or_checked_out" =>
          \&test_excluded_branch_is_not_fetched_or_checked_out,
        "test_missing_file_pull_checks_the_fetched_path_in_a_tree_filtered_clone" =>
          \&test_missing_file_pull_checks_the_fetched_path_in_a_tree_filtered_clone,
        "test_missing_file_pull_does_not_merge_a_tip_without_the_requested_path" =>
          \&test_missing_file_pull_does_not_merge_a_tip_without_the_requested_path,
        "test_missing_file_pull_uses_the_refmap_it_checked" =>
          \&test_missing_file_pull_uses_the_refmap_it_checked,
        "test_missing_file_pull_preserves_local_branch_and_tag_fetch_destinations" =>
          \&test_missing_file_pull_preserves_local_branch_and_tag_fetch_destinations,
        "test_new_branch_checkout_does_not_use_a_local_branch_or_tag_as_remote_cache" =>
          \&test_new_branch_checkout_does_not_use_a_local_branch_or_tag_as_remote_cache,
        "test_missing_file_pull_respects_sparse_rules_for_new_paths" =>
          \&test_missing_file_pull_respects_sparse_rules_for_new_paths,
        "test_missing_sparse_path_does_not_pull_a_tracked_file" =>
          \&test_missing_sparse_path_does_not_pull_a_tracked_file,
        "test_missing_file_pull_keeps_all_tracking_refs_when_one_update_fails" =>
          \&test_missing_file_pull_keeps_all_tracking_refs_when_one_update_fails,
        "test_missing_file_does_not_pull_a_negatively_excluded_upstream" =>
          \&test_missing_file_does_not_pull_a_negatively_excluded_upstream,
        "test_missing_file_does_not_pull_a_different_upstream_branch" =>
          \&test_missing_file_does_not_pull_a_different_upstream_branch,
        "test_missing_file_does_not_fetch_a_tag_for_an_abbreviated_upstream" =>
          \&test_missing_file_does_not_fetch_a_tag_for_an_abbreviated_upstream,
        "test_missing_file_does_not_merge_a_tag_for_an_abbreviated_local_upstream" =>
          \&test_missing_file_does_not_merge_a_tag_for_an_abbreviated_local_upstream,
        "test_missing_file_does_not_pull_after_a_skipped_switch" =>
          \&test_missing_file_does_not_pull_after_a_skipped_switch,
        "test_symbolic_fetch_destination_is_rejected_without_overwriting_it" =>
          \&test_symbolic_fetch_destination_is_rejected_without_overwriting_it,
        "test_comparisons_preserve_case_folded_local_branch_and_tag_namespaces" =>
          \&test_comparisons_preserve_case_folded_local_branch_and_tag_namespaces,
        "test_pull_handles_case_folded_checked_out_branch_destinations" =>
          \&test_pull_handles_case_folded_checked_out_branch_destinations,
        "test_pull_does_not_update_another_branch_through_a_symbolic_fetch_destination" =>
          \&test_pull_does_not_update_another_branch_through_a_symbolic_fetch_destination,
        "test_pull_preserves_tracking_refs_with_ambiguous_fetch_mappings" =>
          \&test_pull_preserves_tracking_refs_with_ambiguous_fetch_mappings,
        "test_pull_can_fast_forward_when_fetch_mapping_targets_current_branch" =>
          \&test_pull_can_fast_forward_when_fetch_mapping_targets_current_branch,
    },
    \&setUp
);
