use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $fish   = which('fish');
my $helper = absolute_path("$FindBin::Bin/../fish/functions/gbigdirs.fish");

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
    print "10\t$_\n";
}
PERL
    write_file( "$self->{directory}/bin/gnumfmt", "#!/bin/sh\ncat\n" );
    chmod 0755, "$self->{directory}/bin/gdu", "$self->{directory}/bin/gnumfmt";
    run_command( [ 'git', 'init', '-q', "$self->{directory}/repo" ], { check => 1 } );
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
    my $result = run_command( [ $fish, '--no-config', '-c', 'source "$argv[1]"; gbigdirs', '--', $helper ],
        { cwd => $repo, env => $self->{env} } );
    is( $result->{returncode}, 0,  $result->{stderr} );
    is( $result->{stderr},     '', 'no diagnostics for deleted or broken paths' );
    is(
        read_file( $self->{env}{GBIGDIRS_INPUT} ),
        "./broken\0./dir/file\0./link\0./top\0",
        'only existing tracked files and symlinks reach du'
    );
    is( $result->{stdout}, "40\t.\n10\t./dir\n", 'directory totals and order are preserved' );
}

sub outside_repository {
    my ($self) = @_;
    my $result = run_command( [ $fish, '--no-config', '-c', 'source "$argv[1]"; gbigdirs', '--', $helper ],
        { cwd => $self->{directory}, env => $self->{env} } );
    isnt( $result->{returncode}, 0, 'reports Git failure' );
    ok( !-e $self->{env}{GBIGDIRS_INPUT}, 'does not run du outside a repository' );
}

sub git_listing_errors_are_returned {
    my ($self) = @_;
    write_file( "$self->{directory}/repo/.git/index", 'invalid index' );
    my $result = run_command( [ $fish, '--no-config', '-c', 'source "$argv[1]"; gbigdirs', '--', $helper ],
        { cwd => "$self->{directory}/repo", env => $self->{env} } );
    is( $result->{returncode}, 128, 'Git listing failure is returned through the pipeline' );
    like( $result->{stderr}, qr/index/, 'Git keeps its diagnostic' );
}

sub size_errors_are_returned {
    my ($self) = @_;
    write_file( "$self->{directory}/bin/gdu", "#!/bin/sh\nprintf 'du failed\\n' >&2\nexit 23\n" );
    my $result = run_command( [ $fish, '--no-config', '-c', 'source "$argv[1]"; gbigdirs', '--', $helper ],
        { cwd => "$self->{directory}/repo", env => $self->{env} } );
    is( $result->{returncode}, 23, 'size calculation failure is returned through the pipeline' );
    like( $result->{stderr}, qr/du failed/, 'the size diagnostic is preserved' );
}

run_cases(
    {
        tracked_files_only              => \&tracked_files_only,
        outside_repository              => \&outside_repository,
        git_listing_errors_are_returned => \&git_listing_errors_are_returned,
        size_errors_are_returned        => \&size_errors_are_returned,
    },
    \&setup
);
