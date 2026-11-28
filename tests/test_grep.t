# Smart-case flag parsing and Git grep regression tests.
use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $FISH    = which("fish");
my $GIT     = which("git");
my $ROOT    = join_path( ancestors( absolute_path(__FILE__) )->[1], "fish" );
my $HELPERS = 'set --prepend fish_function_path "$TEST_FISH_FUNCTIONS"' . "\n";

sub setUp {
    my ($self) = @_;
    my ( $key, $value );
    $self->{temporary} = tempdir( "grep-tests-" . "XXXXXX", TMPDIR => 1, CLEANUP => 1 );
    $self->{directory} = $self->{temporary};
    $self->{env}       = {
        map { my $key = ($_)->[0]; my $value = ($_)->[1]; ( $key => $value ) }
        grep {
            my $key   = ($_)->[0];
            my $value = ($_)->[1];
            0 + ( !( ( index( $key, "GIT_" ) == 0 ) ) )
        } @{ [ map { [ $_, ( \%ENV )->{$_} ] } sort keys %{ ( \%ENV ) } ] }
    };
    do {
        my $updates = {
            "GIT_CONFIG_GLOBAL"   => "/dev/null",
            "GIT_CONFIG_NOSYSTEM" => "1",
            "TEST_FISH_FUNCTIONS" => join_path( $ROOT,              "functions" ),
            "XDG_CONFIG_HOME"     => join_path( $self->{directory}, "config" ),
            "XDG_DATA_HOME"       => join_path( $self->{directory}, "data" ),
            "XDG_CACHE_HOME"      => join_path( $self->{directory}, "cache" )
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    write_file(
        join_path( $self->{directory}, "case.txt" ), 'ERROR
error
'
    );
    write_file(
        join_path( $self->{directory}, "123" ), 'ERROR
'
    );
    write_file(
        join_path( $self->{directory}, "lower-patterns" ), 'error
'
    );
    write_file(
        join_path( $self->{directory}, "excludes" ), 'unused
'
    );
}

sub run_fish {
    my ( $self, $command, $args, $input, $backend ) = @_;
    my $env    = { %{ $self->{env} } };
    my $script = $HELPERS . "\n";
    if ( defined $backend ) {
        $env->{"GREP_BACKEND"} = $backend;
        $script .= <<'FISH';
function ggrep
    command "$GREP_BACKEND" $argv
end
FISH
        $command = 'grep';
    }
    elsif ( $command eq 'case_flags' ) {
        $script .= <<'FISH';
function ggrep
    contains -- -i $argv; and printf '%s\n' -i
    return 0
end
FISH
        $command = 'grep';
    }
    $script .= "$command \$argv";
    return run_command(
        [ $FISH, "--no-config", "-c", $script, "--", @{$args} ],
        {
            "cwd"     => $self->{directory},
            "env"     => $env,
            "input"   => $input,
            "timeout" => 10
        }
    );
}

sub fish {
    my ( $self, $command, $args, $input ) = @_;
    my ($result);
    $result = run_fish( $self, $command, $args, $input, undef );
    ( is_deeply( $result->{returncode}, 0, $result->{stderr} ) or die "assertion failed\n" );
    ( is_deeply( $result->{stderr}, "" ) or die "assertion failed\n" );
    return $result->{stdout};
}

sub test_autoload_wrappers_preserve_arguments {
    my ($self) = @_;
    for my $wrapper ( [ 'grep', 'ggrep', '--color', '-nI' ],
        [ 'gg', 'git', 'grep', '-IE', '--untracked', '--no-recurse-submodules' ] )
    {
        my ( $name, $backend, @prefix ) = @$wrapper;
        my $command = "function $backend; printf '%s\\0' \$argv; end\n$name";
        for my $case (
            [ [ 'error', 'CAPITAL_FILE' ], '-i' ],
            [ [ '--',        '-me',   'CAPITAL_FILE' ], '-i' ],
            [ [ '-e',        'error', 'CAPITAL_FILE' ], '-i' ],
            [ [ '--regexp',  'error', '--regexp=UPPER', 'file' ] ],
            [ [ '-ER',       'error', 'CAPITAL_FILE' ], '-i' ],
            [ [ '-ne',       'error', 'file' ] ],
            [ [ '--unknown', 'error', 'file' ] ],
            [ [ 'érrör',     'CAPITAL_FILE' ], '-i' ],
            [ [ 'Érror',     'file' ] ],
            [ [] ],
          )
        {
            my ( $args, @flags ) = @$case;
            is(
                fish( $self, $command, $args, undef ),
                join( "\0", @prefix, @flags, @$args ) . "\0",
                "$name adds only the expected case flag and preserves every argument"
            );
        }
    }
}

sub test_unrecognized_options_leave_case_flags_explicit {
    my ($self) = @_;
    my ( $args, $option, $options, $pattern, $value );
    $options = [
        [ "-A",                "0" ],
        [ "-B",                "0" ],
        [ "-C",                "0" ],
        [ "-m",                "1" ],
        [ "--after-context",   "0" ],
        [ "--before-context",  "0" ],
        [ "--context",         "0" ],
        [ "--max-count",       "1" ],
        [ "-d",                "read" ],
        [ "-D",                "read" ],
        [ "--include",         "*.txt" ],
        [ "--exclude",         "unused" ],
        [ "--exclude-dir",     "unused" ],
        [ "--exclude-from",    "excludes" ],
        [ "--label",           "UPPER" ],
        [ "--group-separator", "UPPER" ],
        [ "--binary-files",    "without-match" ],
        [ "--threads",         "4" ],
        [ "--max-depth",       "0" ]
    ];
    for my $item_72 ( @{$options} ) {
        $option = ($item_72)->[0];
        $value  = ($item_72)->[1];
        for $pattern ( @{ [ "ERROR", "error" ] } ) {
            for $args (
                @{ [ [ $option, $value, $pattern, "case.txt" ], [ $pattern, $option, $value, "case.txt" ] ] }
              )
            {
                {
                    (
                        is_deeply( fish( $self, "case_flags", $args, undef ), "" )
                          or die "assertion failed\n"
                    );
                }
            }
        }
    }
}

sub test_simple_searches_use_smart_case {
    my ($self) = @_;
    my ( $args, $expected );
    for my $item_79 (
        @{
            [
                [
                    [ "error", "case.txt" ], '-i
'
                ],
                [ [ "ERROR", "case.txt" ], "" ],
                [
                    [ "-E", "error", "case.txt" ], '-i
'
                ],
                [
                    [ "-F", "error", "case.txt" ], '-i
'
                ],
                [
                    [ "-G", "error", "case.txt" ], '-i
'
                ],
                [
                    [ "-R", "error", "case.txt" ], '-i
'
                ],
                [ [ "-R", "ERROR", "case.txt" ], "" ],
                [
                    [ "-ER", "error", "case.txt" ], '-i
'
                ],
                [ [ "-ER", "ERROR", "case.txt" ], "" ],
                [
                    [ "-FR", "error", "case.txt" ], '-i
'
                ],
                [ [ "-FR", "ERROR", "case.txt" ], "" ],
                [
                    [ "-e", "error", "case.txt" ], '-i
'
                ],
                [
                    [ "--regexp=error", "case.txt" ], '-i
'
                ],
                [
                    [ "error", "-" ], '-i
'
                ],
                [ [ "-A0", "ERROR", "case.txt" ],               "" ],
                [ [ "-B0", "ERROR", "case.txt" ],               "" ],
                [ [ "-C0", "ERROR", "case.txt" ],               "" ],
                [ [ "-m1", "ERROR", "case.txt" ],               "" ],
                [ [ "--context=0", "ERROR", "case.txt" ],       "" ],
                [ [ "-e", "error", "-e", "ERROR", "case.txt" ], "" ],
                [ [ "-A", "0", "-e", "error", "case.txt" ],     "" ],
                [ [ "-e", "error", "-A0", "case.txt" ],         "" ],
                [ [ "-e", "error", "-nf", "123", "case.txt" ],  "" ],
                [ [ "-e", "error", "--fi=123", "case.txt" ],    "" ],
                [ ["-e"],                                       "" ],
                [ [],                                           "" ],
                [ [ "--", "ERROR", "case.txt" ],                "" ]
            ]
        }
      )
    {
        $args     = ($item_79)->[0];
        $expected = ($item_79)->[1];
        {
            ( is_deeply( fish( $self, "case_flags", $args, undef ), $expected ) or die "assertion failed\n" );
        }
    }
}

sub test_pattern_files_do_not_enable_implicit_ignore_case {
    my ($self) = @_;
    my ($args);
    for $args (
        @{
            [
                [ "-f",     "123",            "case.txt" ],
                [ "--file", "lower-patterns", "case.txt" ],
                [ "-e",     "error",          "-f", "123", "case.txt" ],
                [ "-f",     "-",              "case.txt" ]
            ]
        }
      )
    {
        {
            (
                is_deeply(
                    fish(
                        $self, "case_flags", $args, 'ERROR
'
                    ),
                    ""
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_git_grep_uses_the_pattern_case {
    my ($self) = @_;
    my ( $actual, $args, $expected, $option, $value );
    run_command( [ $GIT, "init", "--quiet", "--initial-branch=main", $self->{directory} ],
        { "env" => $self->{env}, "check" => 1 } );
    run_command( [ $GIT, "-C", $self->{directory}, "add", "case.txt" ],
        { "env" => $self->{env}, "check" => 1 } );
    run_command( [ $GIT, '-C', $self->{directory}, 'config', 'submodule.recurse', 'true' ],
        { env => $self->{env}, check => 1 } );
    is( fish( $self, 'gg', [ 'error', '--', 'lower-patterns' ], undef ),
        "lower-patterns:error\n", 'gg searches untracked files when recursive submodules are configured' );
    for my $item_120 (
        @{
            [
                [ "-A",          "0" ],
                [ "-B",          "0" ],
                [ "-C",          "0" ],
                [ "-m",          "1" ],
                [ "--threads",   "1" ],
                [ "--max-depth", "0" ]
            ]
        }
      )
    {
        $option = ($item_120)->[0];
        $value  = ($item_120)->[1];
        {
            (
                is_deeply(
                    fish( $self, "gg", [ $option, $value, "ERROR", "--", "case.txt" ], undef ),
                    'case.txt:ERROR
'
                  )
                  or die "assertion failed\n"
            );
        }
    }
    (
        is_deeply(
            fish( $self, "gg", [ "-f", "123", "--", "case.txt" ], undef ),
            'case.txt:ERROR
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            fish( $self, "gg", [ "-i", "-f", "123", "--", "case.txt" ], undef ),
            'case.txt:ERROR
case.txt:error
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            fish(
                $self, "gg", [ "-f", "-", "--", "case.txt" ], 'ERROR
'
            ),
            'case.txt:ERROR
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            fish( $self, "gg", [ "error", "--", "case.txt" ], undef ),
            'case.txt:ERROR
case.txt:error
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            fish( $self, "gg", [ "-e", "error", "--", "case.txt" ], undef ),
            'case.txt:ERROR
case.txt:error
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            fish( $self, "gg", [ "-A", "0", "-e", "error", "--", "case.txt" ], undef ),
            'case.txt:error
'
          )
          or die "assertion failed\n"
    );
    (
        is_deeply(
            fish( $self, "gg", [ "-i", "-A", "0", "-e", "error", "--", "case.txt" ], undef ),
            'case.txt:ERROR
case.txt:error
'
          )
          or die "assertion failed\n"
    );
    $args     = [ "--audit-unsupported-option", "ERROR", "--", "case.txt" ];
    $actual   = run_fish( $self, "gg", $args, undef, undef );
    $expected = run_command(
        [ $GIT, "grep", "-IE", "--untracked", "--no-recurse-submodules", @{$args} ],
        { "cwd" => $self->{directory}, "env" => $self->{env}, "timeout" => 10 }
    );
    (
        is_deeply(
            [ $actual->{returncode},   $actual->{stdout},   $actual->{stderr} ],
            [ $expected->{returncode}, $expected->{stdout}, $expected->{stderr} ]
          )
          or die "assertion failed\n"
    );
}

sub test_ggr_uses_the_pattern_case {
    my ($self) = @_;
    my $directory = $self->{directory};
    write_file( "$directory/uppercase only.txt", "ERROR\n" );
    write_file( "$directory/outside.txt",        "error\n" );
    write_file( "$directory/untracked.txt",      "error\n" );
    my $options = { cwd => $directory, env => $self->{env}, check => 1 };
    run_command( [ $GIT, 'init', '-q' ], $options );
    run_command( [ $GIT, 'add', '--', 'case.txt', 'uppercase only.txt', 'outside.txt' ], $options );

    fish( $self, 'ggr', [ 'ERROR', 'fixed', 'case.txt' ], undef );
    is( read_file("$directory/case.txt"),           "fixed\nerror\n", 'uppercase patterns match exactly' );
    is( read_file("$directory/uppercase only.txt"), "ERROR\n",        'pathspecs limit the replacement' );

    write_file( "$directory/case.txt", "ERROR\nerror\n" );
    fish( $self, 'ggr', [ 'error', 'FIXED', 'case.txt', 'uppercase only.txt', 'untracked.txt' ], undef );
    is( read_file("$directory/case.txt"),           "FIXED\nFIXED\n", 'lowercase patterns match both cases' );
    is( read_file("$directory/uppercase only.txt"), "FIXED\n",        'Git selects uppercase-only matches' );
    is( read_file("$directory/uppercase only.txt.bak"), "ERROR\n",    'sed keeps the original as a backup' );
    is( read_file("$directory/outside.txt"),            "error\n",    'other paths are untouched' );
    is( read_file("$directory/untracked.txt"),          "error\n",    'ggr only replaces tracked files' );
}

sub test_macos_fallback_preserves_regex_modes {
    my ($self) = @_;
    plan skip_all => 'The fallback uses macOS grep' unless $^O eq 'darwin';
    write_file( "$self->{directory}/patterns", "a+\naa\n" );
    make_path("$self->{directory}/tree/original");
    write_file( "$self->{directory}/tree/original/input", "a+\naa\n" );
    symlink 'original', "$self->{directory}/tree/link" or die $!;
    my $script = $HELPERS . <<'FISH';
function type
    test "$argv" = '-q ggrep'; and return 1
    builtin type $argv
end
grep --color=never $argv
FISH
    for my $case (
        [ [],     "1:a+\n" ],
        [ ['-E'], "1:a+\n2:aa\n" ],
        [ ['-F'], "1:a+\n" ],
        [ ['-R'], "tree/link/input:1:a+\ntree/original/input:1:a+\n" ],
        [
            ['-ER'],
            "tree/link/input:1:a+\ntree/link/input:2:aa\ntree/original/input:1:a+\ntree/original/input:2:aa\n"
        ],
        [ ['-FR'], "tree/link/input:1:a+\ntree/original/input:1:a+\n" ],
      )
    {
        my ( $flags, $expected ) = @$case;
        my $path   = @$flags && $flags->[0] =~ /R/ ? 'tree' : 'patterns';
        my $result = run_command(
            [ $FISH, '--no-config', '-c', $script, '--', @$flags, 'a+', $path ],
            { cwd => $self->{directory}, env => $self->{env}, timeout => 10 }
        );
        is( $result->{returncode}, 0,  $result->{stderr} );
        is( $result->{stderr},     '', 'the native fallback has no diagnostics' );
        is( join( '', map { "$_\n" } sort split /\n/, $result->{stdout} ),
            $expected, 'the fallback preserves regex modes and recursive symlink following' );
    }
}

sub test_native_grep_backends_preserve_complex_calls_and_errors {
    my ($self) = @_;
    my ( $actual, $args, $backend, $backends, $cases, $expected, $input, $path, $result );
    $backends = ["/usr/bin/grep"];
    if ( ( $path = which("ggrep") ) ) {
        push( @{$backends}, $path );
    }
    $cases = [
        [
            [ "error", "case.txt" ], '1:ERROR
2:error
', undef
        ],
        [
            [ "-F", "error", "case.txt" ], '1:ERROR
2:error
', undef
        ],
        [
            [ "-A0", "ERROR", "case.txt" ], '1:ERROR
', undef
        ],
        [
            [ "-A", "0", "ERROR", "case.txt" ], '1:ERROR
', undef
        ],
        [
            [ "-A", "0", "-e", "error", "case.txt" ], '2:error
', undef
        ],
        [
            [ "-i", "-A", "0", "-e", "error", "case.txt" ], '1:ERROR
2:error
', undef
        ],
        [
            [ "-f", "123", "case.txt" ], '1:ERROR
', undef
        ],
        [
            [ "-f", "lower-patterns", "case.txt" ], '2:error
', undef
        ],
        [
            [ "-f", "-", "case.txt" ], '1:ERROR
', 'ERROR
'
        ]
    ];
    for $backend ( @{$backends} ) {
        for my $item_156 ( @{$cases} ) {
            $args     = ($item_156)->[0];
            $expected = ($item_156)->[1];
            $input    = ($item_156)->[2];
            {
                $result = run_fish( $self, "", $args, $input, $backend );
                ( is_deeply( $result->{returncode}, 0, $result->{stderr} ) or die "assertion failed\n" );
                ( is_deeply( $result->{stdout}, $expected ) or die "assertion failed\n" );
                ( is_deeply( $result->{stderr}, "" )        or die "assertion failed\n" );
            }
        }
        for $args ( @{ [ [ "--audit-unsupported-option", "ERROR", "case.txt" ], ["-e"], ["-A"] ] } ) {
            {
                $actual   = run_fish( $self, "", $args, undef, $backend );
                $expected = run_command(
                    [ $backend, "--color", "-nI", @{$args} ],
                    {
                        "cwd"     => $self->{directory},
                        "env"     => $self->{env},
                        "timeout" => 10
                    }
                );
                (
                    is_deeply(
                        [ $actual->{returncode},   $actual->{stdout},   $actual->{stderr} ],
                        [ $expected->{returncode}, $expected->{stdout}, $expected->{stderr} ]
                      )
                      or die "assertion failed\n"
                );
            }
        }
    }
}

sub test_recursive_smart_case_with_native_grep_backends {
    my ($self) = @_;
    my ( $actual, $args, $backend, $backends, $case_flags, $expected, $option, $path, $pattern, $tree );
    $tree = join_path( $self->{directory}, "tree" );
    make_path( join_path( $tree, "nested" ) );
    write_file(
        join_path( $tree, "nested/case.txt" ), 'ERROR
error
'
    );
    $backends = ["/usr/bin/grep"];
    if ( ( $path = which("ggrep") ) ) {
        push( @{$backends}, $path );
    }
    for $backend ( @{$backends} ) {
        for $option ( @{ [ "-R", "-ER", "-FR" ] } ) {
            for $pattern ( @{ [ "error", "ERROR" ] } ) {
                {
                    $args       = [ $option, $pattern, "tree" ];
                    $actual     = run_fish( $self, "", $args, undef, $backend );
                    $case_flags = ( ( ( $pattern eq "error" ) ) ? ["-i"] : [] );
                    $expected   = run_command(
                        [ $backend, "--color", "-nI", @{$case_flags}, @{$args} ],
                        {
                            "cwd"     => $self->{directory},
                            "env"     => $self->{env},
                            "timeout" => 10
                        }
                    );
                    (
                        is_deeply( $expected->{returncode}, 0, $expected->{stderr} )
                          or die "assertion failed\n"
                    );
                    (
                        is_deeply( scalar( @{ [ split( /\n/, $expected->{stdout} ) ] } ),
                            ( scalar( @{$case_flags} ) ? 2 : 1 ) )
                          or die "assertion failed\n"
                    );
                    (
                        is_deeply(
                            [ $actual->{returncode},   $actual->{stdout},   $actual->{stderr} ],
                            [ $expected->{returncode}, $expected->{stdout}, $expected->{stderr} ]
                          )
                          or die "assertion failed\n"
                    );
                }
            }
        }
    }
}

run_cases(
    {
        "test_autoload_wrappers_preserve_arguments"           => \&test_autoload_wrappers_preserve_arguments,
        "test_unrecognized_options_leave_case_flags_explicit" =>
          \&test_unrecognized_options_leave_case_flags_explicit,
        "test_simple_searches_use_smart_case"                   => \&test_simple_searches_use_smart_case,
        "test_pattern_files_do_not_enable_implicit_ignore_case" =>
          \&test_pattern_files_do_not_enable_implicit_ignore_case,
        "test_git_grep_uses_the_pattern_case"       => \&test_git_grep_uses_the_pattern_case,
        "test_ggr_uses_the_pattern_case"            => \&test_ggr_uses_the_pattern_case,
        "test_macos_fallback_preserves_regex_modes" => \&test_macos_fallback_preserves_regex_modes,
        "test_native_grep_backends_preserve_complex_calls_and_errors" =>
          \&test_native_grep_backends_preserve_complex_calls_and_errors,
        "test_recursive_smart_case_with_native_grep_backends" =>
          \&test_recursive_smart_case_with_native_grep_backends,
    },
    \&setUp
);
