use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $helper = absolute_path("$FindBin::Bin/../fish/functions/gbins.fish");

sub setup {
    my ($self) = @_;
    $self->{directory} = tempdir( 'gbins-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my %env = %ENV;
    delete @env{ grep { /^GIT_/ } keys %env };
    $self->{env} = {
        %env,
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
    };
}

sub gbins {
    my ($self) = @_;
    return run_command( [ 'fish', '--no-config', '-c', 'source "$argv[1]"; gbins', '--', $helper ],
        { cwd => $self->{directory}, env => $self->{env} } );
}

sub lists_indexed_binary_files {
    my ($self) = @_;
    run_command( [ 'git', 'init', '--quiet', $self->{directory} ], { env => $self->{env}, check => 1 } );
    write_file( "$self->{directory}/binary file", "binary\0contents" );
    write_file( "$self->{directory}/text",        "text\n" );
    run_command( [ 'git', '-C', $self->{directory}, 'add', '--', 'binary file', 'text' ],
        { env => $self->{env}, check => 1 } );
    my $result = gbins($self);
    is( $result->{returncode}, 0,               $result->{stderr} );
    is( $result->{stdout},     "binary file\n", 'only indexed binary files are listed' );
}

sub outside_repository {
    my ($self) = @_;
    my $result = gbins($self);
    is( $result->{returncode}, 128, 'Git failure is returned outside a repository' );
    is( $result->{stdout},     '',  'failed Git invocation does not produce a binary-file list' );
    like( $result->{stderr}, qr/not a git repository/, 'Git explains the missing repository' );
    unlike( $result->{stderr}, qr/unknown option/, 'Git does not fall back to no-index option parsing' );
}

sub corrupt_index_failure_is_returned {
    my ($self) = @_;
    run_command( [ 'git', 'init', '--quiet', $self->{directory} ], { env => $self->{env}, check => 1 } );
    write_file( "$self->{directory}/.git/index", 'invalid index' );
    my $result = gbins($self);
    is( $result->{returncode}, 128, 'Git index failure is returned through the pipeline' );
    like( $result->{stderr}, qr/index/, 'Git keeps its diagnostic' );
}

run_cases(
    {
        lists_indexed_binary_files        => \&lists_indexed_binary_files,
        outside_repository                => \&outside_repository,
        corrupt_index_failure_is_returned => \&corrupt_index_failure_is_returned,
    },
    \&setup
);
