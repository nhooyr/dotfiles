use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub ignored_files_are_not_formatted_or_linted {
    my $temporary = tempdir( 'ci-files-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$temporary/ci", "$temporary/bin", "$temporary/fish", "$temporary/shell",
        "$temporary/.cache" );
    copy_preserve( "$root/ci/$_", "$temporary/ci/$_" ) for qw(fmt.sh lint.sh);
    write_file( "$temporary/bin/cargo", "#!/bin/sh\nexit 0\n" );
    chmod 0755, "$temporary/bin/cargo";
    write_file( "$temporary/.gitignore",        ".cache/\n" );
    write_file( "$temporary/fish/good.fish",    "function good\nprintf x\nend\n" );
    write_file( "$temporary/fish/deleted.fish", "echo deleted\n" );
    my $ignored = "function broken\n";
    write_file( "$temporary/.cache/ignored.fish", $ignored );
    my $cached = "function cached\nprintf y\nend\n";
    write_file( "$temporary/.cache/cached.fish", $cached );
    symlink '../.cache/cached.fish', "$temporary/fish/linked.fish" or die $!;
    write_file( "$temporary/shell/good.sh",    "if true;then\nprintf x\nfi\n" );
    write_file( "$temporary/shell/deleted.sh", "echo deleted\n" );
    my $invalid_shell = "if then\n";
    write_file( "$temporary/.cache/ignored.sh", $invalid_shell );
    write_file( "$temporary/.cache/linked.sh",  $invalid_shell );
    symlink '../.cache/linked.sh', "$temporary/shell/linked.sh" or die $!;
    my $invalid_perl = "not valid perl at all {\n";
    write_file( "$temporary/.cache/linked.pm", $invalid_perl );
    symlink '../.cache/linked.pm', "$temporary/shell/linked.pm" or die $!;
    run_command( [ 'git', '-C', $temporary, 'init', '-q' ], { check => 1 } );
    run_command( [ 'git', '-C', $temporary, 'add',  '.' ],  { check => 1 } );
    unlink "$temporary/fish/deleted.fish" or die $!;
    unlink "$temporary/shell/deleted.sh"  or die $!;
    my %env  = ( %ENV, PATH => "$temporary/bin:$ENV{PATH}", GITHUB_ACTIONS => '', CI => '' );
    my $lint = run_command( ["$temporary/ci/lint.sh"], { env => \%env } );
    is( $lint->{returncode}, 0, "lint ignores cached and deleted files: $lint->{stderr}" );
    my $fmt = run_command( ["$temporary/ci/fmt.sh"], { env => \%env } );
    is( $fmt->{returncode}, 0, "formatting succeeds: $fmt->{stderr}" );
    is( read_file("$temporary/.cache/ignored.fish"),
        $ignored, 'formatting leaves ignored Fish files untouched' );
    is( read_file("$temporary/.cache/cached.fish"), $cached, 'ignored files are not reformatted either' );
    is(
        read_file("$temporary/fish/good.fish"),
        "function good\n    printf x\nend\n",
        'tracked Fish files are formatted'
    );
    is(
        read_file("$temporary/shell/good.sh"),
        "if true; then\n\tprintf x\nfi\n",
        'tracked shell files are formatted by shfmt'
    );
    is( read_file("$temporary/.cache/ignored.sh"),
        $invalid_shell, 'ignored invalid shell files are neither parsed nor formatted' );
    is( read_file("$temporary/.cache/linked.sh"),
        $invalid_shell, 'symlinked invalid shell files are neither parsed nor formatted' );
    is( read_file("$temporary/.cache/linked.pm"),
        $invalid_perl, 'symlinked Perl files are neither compiled nor formatted' );
}

sub test_script_fixture {
    my $temporary = absolute_path( tempdir( 'ci-environment-XXXXXX', TMPDIR => 1, CLEANUP => 1 ) );
    make_path( "$temporary/ci", "$temporary/tests", "$temporary/bin", "$temporary/caller-home" );
    copy_preserve( "$root/ci/$_",                "$temporary/ci/$_" ) for qw(test.sh test.pl);
    copy_preserve( "$root/tests/TestHelpers.pm", "$temporary/tests/TestHelpers.pm" );
    write_file( "$temporary/bin/nvim",  "#!/bin/sh\nexit 0\n" );
    write_file( "$temporary/bin/cargo", '#!' . perl_executable() . "\n" . <<'PERL_CARGO' );
use strict; use warnings; use FindBin; use JSON::PP;
my @keys = qw(PATH HOME XDG_CONFIG_HOME LC_ALL CARGO_HOME RUSTUP_HOME AQSNOW_DIRALIS GIT_DIR EDITOR);
my $listing = grep { $_ eq '--list' } @ARGV;
my $phase = $listing ? 'cargo-list' : 'cargo';
die "duplicate Cargo invocation\n" if -e "$FindBin::Bin/../$phase.json";
open my $out, '>', "$FindBin::Bin/../$phase.json" or die $!;
print {$out} encode_json({ args => \@ARGV, env => { map { $_ => $ENV{$_} } grep { exists $ENV{$_} } @keys } });
close $out or die $!;
if ($listing) {
    print "tests::one: test\ntests::two: test\nother::three: test\n\n3 tests, 0 benchmarks\n";
    exit;
}
if (-e "$FindBin::Bin/../signal-cargo") {
    $SIG{INT} = 'DEFAULT';
    kill 'INT', $$;
    die "signal was not delivered\n";
}
exit 7 if -e "$FindBin::Bin/../fail-cargo";
PERL_CARGO
    write_file( "$temporary/tests/test_environment.t", <<'PERL_TEST' );
use strict; use warnings; use FindBin; use lib $FindBin::Bin; use TestHelpers;
my @keys = qw(PATH HOME XDG_CONFIG_HOME LC_ALL CARGO_HOME RUSTUP_HOME AQSNOW_DIRALIS GIT_DIR EDITOR);
my $phase = ($ARGV[0] // '') eq '--list' ? 'discovery' : 'worker-' . $ARGV[0];
write_file("$FindBin::Bin/../$phase.json", encode_json({ args => \@ARGV,
    env => { map { $_ => $ENV{$_} } grep { exists $ENV{$_} } @keys } }));
if ($phase eq 'discovery') { print "selected\nunselected\n"; exit; }
die "wrong test selected\n" unless @ARGV == 1 && ($ARGV[0] eq 'selected' || $ARGV[0] eq 'unselected');
print "1..1\nok 1 - clean environment\n";
PERL_TEST
    chmod 0755, "$temporary/bin/nvim", "$temporary/bin/cargo";
    my %env = (
        %ENV,
        PATH            => "$temporary/bin:$ENV{PATH}",
        HOME            => "$temporary/caller-home",
        GITHUB_ACTIONS  => '',
        AQSNOW_DIRALIS  => 'LEAKED',
        GIT_DIR         => '/leaked/git',
        EDITOR          => 'leaked-editor',
        XDG_CONFIG_HOME => '/leaked/config',
    );
    delete @env{qw(CARGO_HOME RUSTUP_HOME)};
    return ( $temporary, \%env );
}

sub test_script_cleans_rust_and_perl_environments {
    for my $direct ( 0, 1 ) {
        my ( $temporary, $env ) = test_script_fixture();
        if ($direct) {
            $env->{CARGO_HOME}  = "$temporary/custom-cargo";
            $env->{RUSTUP_HOME} = "$temporary/custom-rustup";
        }
        my @command = $direct ? ( perl_executable(), "$temporary/ci/test.pl" ) : ("$temporary/ci/test.sh");
        my $result  = run_command( \@command, { env => $env } );
        is( $result->{returncode}, 0, $result->{stderr} );
        my %phases =
          map { $_ => decode_json( read_file("$temporary/$_.json") ) } qw(cargo discovery worker-selected);
        is_deeply(
            $phases{cargo}{args},
            [ 'test', '--manifest-path', "$temporary/ci/../fzfp/Cargo.toml", '--locked' ],
            'runs Cargo tests'
        );
        is_deeply( $phases{discovery}{args},         ['--list'],   'discovers the selected test module' );
        is_deeply( $phases{'worker-selected'}{args}, ['selected'], 'runs the discovered Perl test' );
        ok( -f "$temporary/worker-unselected.json", 'no arguments runs every Perl test' );

        for my $phase (qw(cargo discovery worker-selected)) {
            my $child = $phases{$phase}{env};
            ok( !exists $child->{$_}, "$phase does not inherit $_" ) for qw(AQSNOW_DIRALIS GIT_DIR EDITOR);
            isnt( $child->{HOME}, $env->{HOME}, "$phase gets an isolated home" );
            is( $child->{HOME},            $phases{cargo}{env}{HOME}, "$phase shares the clean test home" );
            is( $child->{XDG_CONFIG_HOME}, "$child->{HOME}/.config",  "$phase uses isolated config" );
            is( $child->{LC_ALL},          'C',                       "$phase uses a deterministic locale" );
            is( $child->{PATH},            $env->{PATH}, "$phase keeps the installed tools available" );
            is(
                $child->{CARGO_HOME},
                $env->{CARGO_HOME} // "$env->{HOME}/.cargo",
                "$phase retains Cargo's home"
            );
            is(
                $child->{RUSTUP_HOME},
                $env->{RUSTUP_HOME} // "$env->{HOME}/.rustup",
                "$phase retains Rustup's home"
            );
            ok( !-d $child->{HOME}, 'the temporary home is removed after the test run' );
        }
    }
}

sub cargo_failure_stops_before_perl_tests {
    for my $case ( [ 'fail-cargo', 7 ], [ 'signal-cargo', 130 ] ) {
        my ( $temporary, $env ) = test_script_fixture();
        write_file( "$temporary/$case->[0]", '' );
        my $result = run_command( ["$temporary/ci/test.sh"], { env => $env } );
        is( $result->{returncode}, $case->[1], 'Cargo failure status is preserved' );
        ok( !-e "$temporary/discovery.json",       'Perl test discovery does not run after Cargo fails' );
        ok( !-e "$temporary/worker-selected.json", 'Perl test cases do not run after Cargo fails' );
        my $cargo = decode_json( read_file("$temporary/cargo.json") );
        ok( !-d $cargo->{env}{HOME}, 'Cargo failure still removes the temporary home' );
    }
}

sub explicit_selectors_skip_cargo {
    for my $direct ( 0, 1 ) {
        my ( $temporary, $env ) = test_script_fixture();
        write_file( "$temporary/fail-cargo", '' );
        my @command = $direct ? ( perl_executable(), "$temporary/ci/test.pl" ) : ("$temporary/ci/test.sh");
        my $result  = run_command( [ @command, 'test_environment.selected' ], { env => $env } );
        is( $result->{returncode}, 0, $result->{stderr} );
        ok( !-e "$temporary/cargo.json",             'a targeted Perl test does not run Cargo' );
        ok( !-e "$temporary/worker-unselected.json", 'unselected Perl tests do not run' );
        my $selected = decode_json( read_file("$temporary/worker-selected.json") );
        is_deeply( $selected->{args}, ['selected'], 'the requested test selector is forwarded' );
    }
}

sub rust_selectors_run_only_matching_tests {
    for my $case (
        [ ['tests::one'],                                ['tests::one'] ],
        [ [ 'tests', 'tests::one', 'other::three' ],     [ 'tests::one', 'tests::two', 'other::three' ] ],
        [ [ 'tests::two', 'test_environment.selected' ], ['tests::two'] ],
      )
    {
        my ( $temporary, $env ) = test_script_fixture();
        my $result =
          run_command( [ perl_executable(), "$temporary/ci/test.pl", @{ $case->[0] } ], { env => $env } );
        is( $result->{returncode}, 0, $result->{stderr} );
        my $listing = decode_json( read_file("$temporary/cargo-list.json") );
        is_deeply(
            $listing->{args},
            [ 'test', '--manifest-path', "$temporary/ci/../fzfp/Cargo.toml", '--locked', '--', '--list' ],
            'discovers native Rust test names'
        );
        my $cargo = decode_json( read_file("$temporary/cargo.json") );
        is_deeply(
            $cargo->{args},
            [
                'test',     '--manifest-path', "$temporary/ci/../fzfp/Cargo.toml",
                '--locked', '--', '--exact', @{ $case->[1] }
            ],
            'runs only matching Rust tests, without duplicate names'
        );
        my $perl_selected = grep { $_ eq 'test_environment.selected' } @{ $case->[0] };
        is(
            -e "$temporary/worker-selected.json" ? 1 : 0,
            $perl_selected                       ? 1 : 0,
            'runs Perl only when selected'
        );
        ok( !-e "$temporary/worker-unselected.json", 'unselected Perl tests do not run' );
    }
}

sub unknown_selector_does_not_run_tests {
    my ( $temporary, $env ) = test_script_fixture();
    my $result =
      run_command( [ perl_executable(), "$temporary/ci/test.pl", 'missing_test' ], { env => $env } );
    isnt( $result->{returncode}, 0, 'an unknown selector fails' );
    like( $result->{stderr}, qr/Unknown test selector: missing_test/, 'reports the unknown selector' );
    ok( -e "$temporary/cargo-list.json",       'checks Rust names before rejecting the selector' );
    ok( !-e "$temporary/cargo.json",           'does not execute Rust tests' );
    ok( !-e "$temporary/worker-selected.json", 'does not execute Perl tests' );
}

run_cases(
    {
        ignored_files_are_not_formatted_or_linted     => \&ignored_files_are_not_formatted_or_linted,
        test_script_cleans_rust_and_perl_environments => \&test_script_cleans_rust_and_perl_environments,
        cargo_failure_stops_before_perl_tests         => \&cargo_failure_stops_before_perl_tests,
        explicit_selectors_skip_cargo                 => \&explicit_selectors_skip_cargo,
        rust_selectors_run_only_matching_tests        => \&rust_selectors_run_only_matching_tests,
        unknown_selector_does_not_run_tests           => \&unknown_selector_does_not_run_tests,
    }
);
