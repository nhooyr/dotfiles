use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $fish      = which('fish');
my $functions = absolute_path("$FindBin::Bin/../fish/functions");

sub setup {
    my ($self) = @_;
    plan skip_all => 'Fish is required' unless $fish;
    $self->{directory} = tempdir( 'gbigdirs-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$self->{directory}/bin", "$self->{directory}/repo/dir" );
    $self->{env} = {
        %ENV,
        PATH           => "$self->{directory}/bin:$ENV{PATH}",
        GBIGDIRS_INPUT => "$self->{directory}/input",
    };
    write_file( "$self->{directory}/bin/gdu", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
local $/ = "\0";
open my $input, '>', $ENV{GBIGDIRS_INPUT} or die $!;
while (<STDIN>) {
    print {$input} $_;
    chomp;
    my $size = $ENV{TEST_FILE_SIZES} ? -s $_ : 10;
    print "$size\t$_\n";
}
PERL
    write_file( "$self->{directory}/bin/gnumfmt", "#!/bin/sh\ncat\n" );
    chmod 0755, "$self->{directory}/bin/gdu", "$self->{directory}/bin/gnumfmt";
    run_command( [ 'git', 'init', '-q', "$self->{directory}/repo" ], { check => 1 } );
}

sub files {
    my ( $self, $name, $directory ) = @_;
    return run_command(
        [
            $fish, '--no-config', '-c', 'set -p fish_function_path "$argv[1]"; $argv[2]',
            '--',  $functions,    $name
        ],
        { cwd => $directory, env => $self->{env} }
    );
}

sub tracked_files_only {
    my ($self) = @_;
    my $repo = "$self->{directory}/repo";
    write_file( "$repo/top",       'top' );
    write_file( "$repo/dir/file",  'nested' );
    write_file( "$repo/deleted",   'deleted' );
    write_file( "$repo/untracked", 'untracked' );
    symlink 'top',     "$repo/link"   or die $!;
    symlink 'missing', "$repo/broken" or die $!;
    run_command( [ 'git', '-C', $repo, 'add', '--', 'top', 'dir/file', 'deleted', 'link', 'broken' ],
        { check => 1 } );
    unlink "$repo/deleted" or die $!;
    my $result = files( $self, 'gbigdirs', $repo );
    is( $result->{returncode}, 0,  $result->{stderr} );
    is( $result->{stderr},     '', 'no diagnostics for deleted or broken paths' );
    is(
        read_file( $self->{env}{GBIGDIRS_INPUT} ),
        "./broken\0./dir/file\0./link\0./top\0",
        'only existing tracked files and symlinks reach du'
    );
    is( $result->{stdout}, "40\t.\n10\t./dir\n", 'directory totals and order are preserved' );
    my $files = files( $self, 'gbigfiles', $repo );
    is( $files->{returncode}, 0, $files->{stderr} );
    is(
        $files->{stdout},
        "10\t./broken\n10\t./dir/file\n10\t./link\n10\t./top\n",
        'gbigfiles lists existing tracked files and links individually'
    );
}

sub bigfiles_ranks_and_limits_output {
    my ($self) = @_;
    my $directory = "$self->{directory}/files";
    make_path("$directory/dir");
    write_file( "$directory/dir/file-$_", 'x' x $_ ) for 1 .. 18;
    $self->{env}{TEST_FILE_SIZES} = 1;
    my $result = files( $self, 'bigfiles', $directory );
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        $result->{stdout},
        join( '', map { "$_\t./dir/file-$_\n" } reverse 3 .. 18 ),
        'bigfiles lists the 16 largest files recursively'
    );
}

sub outside_repository {
    my ($self) = @_;
    for my $name (qw(gbigdirs gbigfiles)) {
        my $result = files( $self, $name, $self->{directory} );
        isnt( $result->{returncode}, 0, "$name reports Git failure" );
        ok( !-e $self->{env}{GBIGDIRS_INPUT}, "$name skips du outside a repository" );
    }
}

sub git_listing_errors_are_returned {
    my ($self) = @_;
    write_file( "$self->{directory}/repo/.git/index", 'invalid index' );
    for my $name (qw(gbigdirs gbigfiles)) {
        my $result = files( $self, $name, "$self->{directory}/repo" );
        is( $result->{returncode}, 128, "$name returns the Git listing failure" );
        like( $result->{stderr}, qr/index/, "$name preserves the Git diagnostic" );
    }
}

sub size_errors_are_returned {
    my ($self) = @_;
    write_file( "$self->{directory}/bin/gdu", "#!/bin/sh\nprintf 'du failed\\n' >&2\nexit 23\n" );
    for my $name (qw(gbigdirs gbigfiles bigfiles)) {
        my $result = files( $self, $name, "$self->{directory}/repo" );
        is( $result->{returncode}, 23, "$name returns the size calculation failure" );
        like( $result->{stderr}, qr/du failed/, "$name preserves the size diagnostic" );
    }
}

run_cases(
    {
        tracked_files_only               => \&tracked_files_only,
        bigfiles_ranks_and_limits_output => \&bigfiles_ranks_and_limits_output,
        outside_repository               => \&outside_repository,
        git_listing_errors_are_returned  => \&git_listing_errors_are_returned,
        size_errors_are_returned         => \&size_errors_are_returned,
    },
    \&setup
);
