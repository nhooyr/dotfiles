use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $git  = which('git');
my $fish = absolute_path("$FindBin::Bin/../fish");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'rebase-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $dir = $self->{temporary};
    make_path("$dir/bin");
    my $aliases = join "\n", read_file("$fish/config.fish") =~ /^(abbrali \w+ git_(?:log|rebase)(?: .*)?)$/mg;
    write_file( "$dir/git-aliases.fish", "$aliases\n" );
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
        TEST_FISH_FUNCTIONS => "$fish/functions",
        TEST_GIT_CONFIG     => "$dir/git-aliases.fish",
        TEST_GIT_STATUS     => 0,
    };
    write_file( "$dir/bin/git", '#!' . perl_executable() . "\n" . <<'PERL' );
use JSON::PP;
if ($ARGV[0] eq 'rebase' || $ARGV[0] eq 'log') {
    print encode_json(\@ARGV);
    exit $ENV{TEST_GIT_STATUS};
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
    real_git( $self, 'update-ref', '-d', "refs/$_" ) for qw(
      heads/main heads/master remotes/origin/main remotes/origin/master
      remotes/upstream/main remotes/upstream/master tags/main tags/master
    );
    real_git( $self, 'update-ref', "refs/$_", $self->{commit} ) for @names;
}

sub run {
    my ( $self, $wrapper, @args ) = @_;
    my $script = 'set --prepend fish_function_path "$TEST_FISH_FUNCTIONS"; ' . "$wrapper \$argv";
    return run_command(
        [ 'fish', '--no-config', '-c', $script, '--', @args ],
        { cwd => $self->{temporary}, env => $self->{env} }
    );
}

sub preferred_default {
    my ($self) = @_;
    for my $case (
        [ [qw(heads/main heads/master remotes/origin/main)],                     'main' ],
        [ ['heads/main'],                                                        'main' ],
        [ [qw(heads/master remotes/origin/main tags/main)],                      'master' ],
        [ [qw(remotes/origin/main remotes/origin/master remotes/upstream/main)], undef ],
        [ [qw(tags/main tags/master)],                                           undef ],
        [ [],                                                                    undef ]
      )
    {
        refs( $self, @{ $case->[0] } );
        for my $flag (qw(-i --interactive)) {
            my $result = run( $self, 'git_rebase', $flag );
            is( $result->{returncode}, 0, 'rebase succeeds' );
            is_deeply(
                decode_json( $result->{stdout} ),
                [ 'rebase', $flag, defined( $case->[1] ) ? $case->[1] : () ],
                'local main is preferred over local master; remote branches and tags are ignored'
            );
        }
    }
}

sub explicit_invocations {
    my ($self) = @_;
    refs( $self, qw(heads/main heads/master) );
    for my $args ( [qw(-i HEAD~2)], [qw(-i --root)], [qw(-i --autosquash)],
        ['--continue'], ['--abort'], ['-h'], ['--help'], [] )
    {
        my $result = run( $self, 'git_rebase', @$args );
        is( $result->{returncode}, 0, 'rebase succeeds' );
        is_deeply( decode_json( $result->{stdout} ), [ 'rebase', @$args ],
            'other invocations are unchanged' );
    }
}

sub exit_statuses {
    my ($self) = @_;
    for my $status ( 0, 17, 141 ) {
        $self->{env}{TEST_GIT_STATUS} = $status;
        is( run( $self, 'git_rebase', '-i' )->{returncode}, $status, 'rebase preserves every exit status' );
        is( run( $self, 'git', 'rebase', '-i' )->{returncode},
            $status, 'plain Git preserves every exit status' );
    }
}

sub log_arguments_and_statuses {
    my ($self) = @_;
    for my $args ( [], [ '--oneline', 'HEAD', '--', 'file name' ] ) {
        for my $status ( 0, 17, 141 ) {
            $self->{env}{TEST_GIT_STATUS} = $status;
            my $result = run( $self, 'git_log', @$args );
            is( $result->{returncode}, $status == 141 ? 0 : $status, 'log ignores only SIGPIPE' );
            is_deeply( decode_json( $result->{stdout} ), [ 'log', @$args ], 'log preserves its arguments' );
        }
    }
}

sub aliases_use_specific_wrappers {
    my ($self) = @_;
    my $result = run_command(
        [ 'fish', '--no-config', '-c', <<'FISH' ],
set --prepend fish_function_path "$TEST_FISH_FUNCTIONS"
function abbrali
    printf '%s\t%s\n' "$argv[1]" "$(string join ' ' -- $argv[2..])"
end
source "$TEST_GIT_CONFIG"; or exit
functions --query git; and exit 1
exit 0
FISH
        { cwd => $self->{temporary}, env => $self->{env} }
    );
    is( $result->{returncode}, 0, 'loading Git aliases does not define a global Git wrapper' );
    my %aliases  = map { split /\t/, $_, 2 } split /\n/, $result->{stdout};
    my %expected = (
        grb  => 'git_rebase',
        grbi => 'git_rebase -i',
        grbr => 'git_rebase -i --root',
        grbc => 'git_rebase --continue',
        grbs => 'git_rebase --skip',
        grba => 'git_rebase --abort',
        gl   => 'git_log',
        glp  => 'git_log -p',
        glo  => 'git_log --oneline',
        glol => 'git_log --oneline | wc -l',
        glss => 'git_log --show-signature',
    );
    is( $aliases{$_}, $expected{$_}, "$_ calls its specific wrapper" ) for sort keys %expected;
    ok( !-e "$fish/functions/git.fish", 'plain Git has no autoload wrapper' );
}

run_cases(
    {
        preferred_default             => \&preferred_default,
        explicit_invocations          => \&explicit_invocations,
        exit_statuses                 => \&exit_statuses,
        log_arguments_and_statuses    => \&log_arguments_and_statuses,
        aliases_use_specific_wrappers => \&aliases_use_specific_wrappers,
    },
    \&setup
);
