use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $git = which('git');
my ($wrapper) = read_file("$FindBin::Bin/../fish/git.fish") =~ /\A(function git\n.*?^end\n)/ms;
die "Git wrapper not found\n" unless defined $wrapper;

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'rebase-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $dir = $self->{temporary};
    make_path("$dir/bin");
    my %env = %ENV;
    delete @env{ grep { /^GIT_/ } keys %env };
    $self->{env} = {
        %env,
        PATH                => "$dir/bin:$ENV{PATH}",
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
        GIT_AUTHOR_NAME     => 'Test',
        GIT_AUTHOR_EMAIL    => 'test@example.invalid',
        GIT_COMMITTER_NAME  => 'Test',
        GIT_COMMITTER_EMAIL => 'test@example.invalid',
        TEST_REAL_GIT       => $git,
        TEST_WRAPPER        => "$dir/git.fish",
        TEST_REBASE_STATUS  => 0,
    };
    write_file( "$dir/git.fish", $wrapper );
    write_file( "$dir/bin/git",  '#!' . perl_executable() . "\n" . <<'PERL' );
use JSON::PP;
if (grep { $_ eq 'rebase' } @ARGV) {
    print encode_json(\@ARGV);
    exit $ENV{TEST_REBASE_STATUS};
}
exec $ENV{TEST_REAL_GIT}, @ARGV;
PERL
    chmod 0755, "$dir/bin/git";
    real_git( $self, 'init', '-q' );
    my $tree = trim( real_git( $self, 'mktree' ) );
    $self->{commit} = trim( real_git( $self, 'commit-tree', $tree, '-m', 'fixture' ) );
}

sub real_git {
    my ( $self, @args ) = @_;
    return run_command( [ $git, @args ], { cwd => $self->{temporary}, env => $self->{env}, check => 1 } )
      ->{stdout};
}

sub refs {
    my ( $self, @names ) = @_;
    real_git( $self, 'update-ref', '-d', "refs/remotes/$_" )
      for qw(origin/main origin/master upstream/main upstream/master);
    real_git( $self, 'update-ref', "refs/remotes/$_", $self->{commit} ) for @names;
}

sub run {
    my ( $self, @args ) = @_;
    return run_command( [ 'fish', '--no-config', '-c', 'source "$TEST_WRAPPER"; git $argv', '--', @args ],
        { cwd => $self->{temporary}, env => $self->{env} } );
}

sub preferred_default {
    my ($self) = @_;
    for my $case (
        [ [qw(origin/main origin/master upstream/main upstream/master)], 'origin/main' ],
        [ ['origin/main'],                                               'origin/main' ],
        [ [qw(origin/master upstream/main upstream/master)],             'origin/master' ],
        [ [qw(upstream/main upstream/master)],                           undef ],
        [ [],                                                            undef ]
      )
    {
        refs( $self, @{ $case->[0] } );
        for my $flag (qw(-i --interactive)) {
            my $result = run( $self, 'rebase', $flag );
            is( $result->{returncode}, 0, 'rebase succeeds' );
            is_deeply(
                decode_json( $result->{stdout} ),
                [ 'rebase', $flag, defined( $case->[1] ) ? $case->[1] : () ],
                'origin/main is preferred over origin/master, otherwise Git chooses its default'
            );
        }
    }
}

sub explicit_invocations {
    my ($self) = @_;
    refs( $self, qw(origin/main origin/master) );
    for my $args ( [qw(rebase -i HEAD~2)], [qw(rebase -i --root)], [qw(rebase -i --autosquash)],
        [qw(rebase --continue)], [qw(-C . rebase -i)], ['rebase'] )
    {
        my $result = run( $self, @$args );
        is( $result->{returncode}, 0, 'rebase succeeds' );
        is_deeply( decode_json( $result->{stdout} ), $args, 'other invocations are unchanged' );
    }
}

sub exit_statuses {
    my ($self) = @_;
    for my $status ( 17, 141 ) {
        $self->{env}{TEST_REBASE_STATUS} = $status;
        is(
            run( $self, 'rebase', '-i' )->{returncode},
            $status == 141 ? 0 : $status,
            'the wrapper preserves failures and continues to ignore SIGPIPE'
        );
    }
}

run_cases(
    {
        preferred_default    => \&preferred_default,
        explicit_invocations => \&explicit_invocations,
        exit_statuses        => \&exit_statuses
    },
    \&setup
);
