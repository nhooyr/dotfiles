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

sub test_script_cleans_rust_and_perl_environments {
    my $temporary = tempdir( 'ci-environment-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$temporary/ci", "$temporary/tests", "$temporary/bin", "$temporary/caller-home" );
    copy_preserve( "$root/ci/test.sh",           "$temporary/ci/test.sh" );
    copy_preserve( "$root/tests/TestHelpers.pm", "$temporary/tests/TestHelpers.pm" );
    write_file( "$temporary/bin/nvim", "#!/bin/sh\nexit 0\n" );
    my $mock = '#!' . perl_executable() . "\n" . <<'PERL';
use strict;
use warnings;
use FindBin;
use JSON::PP;
my $name = $0 =~ /cargo$/ ? 'cargo' : 'perl';
if ($name eq 'perl' && $ARGV[0] ne 'ci/test.pl') {
    exec {$^X} $^X, @ARGV;
    die $!;
}
open my $out, '>', "$FindBin::Bin/../$name.json" or die $!;
print {$out} encode_json(\%ENV);
PERL
    write_file( "$temporary/bin/$_", $mock ) for qw(cargo perl);
    chmod 0755, map { "$temporary/bin/$_" } qw(nvim cargo perl);
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
    my $result = run_command( ["$temporary/ci/test.sh"], { env => \%env } );
    is( $result->{returncode}, 0, $result->{stderr} );

    for my $command (qw(cargo perl)) {
        my $child = decode_json( read_file("$temporary/$command.json") );
        ok( !exists $child->{$_}, "$command does not inherit $_" ) for qw(AQSNOW_DIRALIS GIT_DIR EDITOR);
        isnt( $child->{HOME}, $env{HOME}, "$command gets an isolated home" );
        is( $child->{XDG_CONFIG_HOME}, "$child->{HOME}/.config", "$command uses isolated config" );
        is( $child->{LC_ALL},          'C',                      "$command uses a deterministic locale" );
        is( $child->{PATH},            $env{PATH}, "$command keeps the installed tools available" );
        ok( !-d $child->{HOME}, 'the temporary home is removed after the test run' );
    }
}

run_cases(
    {
        ignored_files_are_not_formatted_or_linted     => \&ignored_files_are_not_formatted_or_linted,
        test_script_cleans_rust_and_perl_environments => \&test_script_cleans_rust_and_perl_environments,
    }
);
