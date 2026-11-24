use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $vgrep = absolute_path("$FindBin::Bin/../bin/vgrep");

sub setup {
    my ($self) = @_;
    plan skip_all => 'ripgrep is needed to test vgrep' unless which('rg');
    $self->{temporary} = tempdir( 'vgrep-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{root}      = absolute_path("$self->{temporary}") . '/repo with spaces';
    make_path("$self->{root}/.git/lfs/objects");
    write_file( "$self->{root}/file with spaces.txt",     "needle\n" );
    write_file( "$self->{root}/.git/COMMIT_EDITMSG",      "needle\n" );
    write_file( "$self->{root}/.git/lfs/objects/example", "needle\n" );
}

sub searches_from_the_worktree {
    my ($self) = @_;
    my $root   = $self->{root};
    my $result = run_command( [ $vgrep, 'needle', '.' ], { cwd => $root } );
    is( $result->{stdout}, "./file with spaces.txt:1:1:needle\n", 'ordinary searches keep relative output' );
    $result = run_command( [ $vgrep, 'needle', '.' ], { cwd => "$root/.git" } );
    is(
        $result->{stdout},
        "$root/./file with spaces.txt:1:1:needle\n",
        'commit-directory searches use the worktree and report absolute paths without Git metadata'
    );
    is( $result->{returncode}, 0, 'matching search succeeds' );
}

sub preserves_arguments_and_exit_status {
    my ($self) = @_;
    my $root = $self->{root};
    my $result =
      run_command( [ $vgrep, '-F', 'needle', "$root/file with spaces.txt" ], { cwd => "$root/.git" } );
    is(
        $result->{stdout},
        "$root/file with spaces.txt:1:1:needle\n",
        'absolute arguments and output remain intact'
    );
    $result = run_command( [ $vgrep, 'missing', '.' ], { cwd => "$root/.git" } );
    is( $result->{returncode}, 1,  'no matches preserves ripgrep exit status' );
    is( $result->{stdout},     '', 'no matches emits no output' );
    $result = run_command( [ $vgrep, '[', '.' ], { cwd => "$root/.git" } );
    is( $result->{returncode}, 2, 'pattern errors preserve ripgrep exit status' );
    like( $result->{stderr}, qr/regex parse error/, 'pattern errors remain visible' );
}

run_cases(
    {
        searches_from_the_worktree          => \&searches_from_the_worktree,
        preserves_arguments_and_exit_status => \&preserves_arguments_and_exit_status,
    },
    \&setup
);
