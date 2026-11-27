use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub git {
    my ( $self, @args ) = @_;
    return run_command( [ 'git', '-C', $self->{repo}, '-c', 'commit.gpgsign=false', @args ],
        { env => $self->{env}, check => 1 } )->{stdout};
}

sub setup {
    my ($self) = @_;
    $self->{temporary} = absolute_path( tempdir( 'gho-pr-XXXXXX', TMPDIR => 1, CLEANUP => 1 ) );
    $self->{repo}      = "$self->{temporary}/repo";
    make_path("$self->{repo}/sub");
    my %env = %ENV;
    delete @env{ grep { /^GIT_/ } keys %env };
    $self->{env} = {
        %env,
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
        GIT_ALLOW_PROTOCOL  => 'file',
        GIT_TERMINAL_PROMPT => 0,
        GIT_AUTHOR_NAME     => 'Test',
        GIT_AUTHOR_EMAIL    => 'test@example.invalid',
        GIT_COMMITTER_NAME  => 'Test',
        GIT_COMMITTER_EMAIL => 'test@example.invalid',
        GH_HOST             => '',
        TEST_PR_STATUS      => 0,
        TEST_GHO            => "$root/fish/functions/gho.fish",
        TEST_LOG            => "$self->{temporary}/calls",
    };
    git( $self, 'init',       '--quiet', '--initial-branch=main', '--template=' );
    git( $self, 'commit',     '--quiet', '--allow-empty',         '-m', 'Initial' );
    git( $self, 'checkout',   '--quiet', '-b',                    'topic' );
    git( $self, 'commit',     '--quiet', '--allow-empty',         '-m', 'Topic' );
    git( $self, 'remote',     'add',     'origin',                'https://github.com/example/fork.git' );
    git( $self, 'remote',     'add',     'upstream',              'https://github.com/example/project.git' );
    git( $self, 'update-ref', 'refs/remotes/origin/topic', 'HEAD' );
    git( $self, 'config',     'branch.topic.remote',       'origin' );
    git( $self, 'config',     'branch.topic.merge',        'refs/heads/topic' );
}

sub gho {
    my ( $self, $cwd, @args ) = @_;
    unlink $self->{env}{TEST_LOG};
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH', '--', @args ],
source "$TEST_GHO"
function ghop
    printf 'pr\t%s\n' "$PWD" >> "$TEST_LOG"
    return "$TEST_PR_STATUS"
end
function gh
    printf 'unexpected network command\n' >&2
    return 99
end
function open
    printf 'open\t%s\n' "$argv[1]" >> "$TEST_LOG"
end
function pbc
    read --local url
    printf 'copy\t%s\n' "$url" >> "$TEST_LOG"
    printf '%s\n' "$url"
end
gho $argv
FISH
        { cwd => $cwd, env => $self->{env} }
    );
}

sub falls_back {
    my ( $self, @args ) = @_;
    my $result = gho( $self, $self->{repo}, @args );
    is( $result->{returncode}, 0, $result->{stderr} );
    my $calls = read_file( $self->{env}{TEST_LOG} );
    like(
        $calls,
        qr/^open\thttps:\/\/github\.com\/example\/fork(?:\/|\n)/,
        'opens the ordinary repository URL'
    );
    unlike( $calls, qr/^pr\t/m, 'does not hand off to ghop' );
}

sub published_topic_uses_ghop {
    my ($self) = @_;
    for my $directory ( $self->{repo}, "$self->{repo}/sub" ) {
        my $result = gho( $self, $directory );
        is( $result->{returncode}, 0, $result->{stderr} );
        is( read_file( $self->{env}{TEST_LOG} ),
            "pr\t$directory\n", 'published topic opens its pull request from any subdirectory' );
    }
    git( $self, 'commit',     '--quiet',                   '--allow-empty', '-m', 'Remote ahead' );
    git( $self, 'update-ref', 'refs/remotes/origin/topic', 'HEAD' );
    git( $self, 'reset',      '--quiet',                   '--hard', 'HEAD~1' );
    is( gho( $self, $self->{repo} )->{returncode}, 0, 'a branch behind origin is still pushed' );
    is( read_file( $self->{env}{TEST_LOG} ), "pr\t$self->{repo}\n", 'origin may contain newer commits' );
    git( $self, 'commit', '--quiet', '--allow-empty', '-m', 'Local change' );
    is( gho( $self, $self->{repo} )->{returncode}, 0,               'a branch may diverge from origin' );
    is( read_file( $self->{env}{TEST_LOG} ), "pr\t$self->{repo}\n", 'diverged branches still use ghop' );
    git( $self, 'update-ref', 'refs/remotes/origin/topic', 'HEAD~1' );
    is( gho( $self, $self->{repo} )->{returncode}, 0, 'a branch may have unpushed commits' );
    is( read_file( $self->{env}{TEST_LOG} ),       "pr\t$self->{repo}\n", 'ahead branches still use ghop' );
    $self->{env}{TEST_PR_STATUS} = 47;
    is( gho( $self, $self->{repo} )->{returncode}, 47, 'ghop failure status is preserved' );
    is( read_file( $self->{env}{TEST_LOG} ),
        "pr\t$self->{repo}\n", 'ghop failure does not open a fallback URL' );
}

sub required_remotes_must_exist {
    my ($self) = @_;
    git( $self, 'remote', 'remove', 'upstream' );
    falls_back($self);
    git( $self, 'remote', 'add', 'other', 'https://github.com/example/other.git' );
    falls_back($self);
    git( $self, 'remote', 'rename', 'other', 'upstream' );
    git( $self, 'remote', 'add',    'third', 'https://github.com/example/third.git' );
    is( gho( $self, $self->{repo} )->{returncode}, 0,                     'additional remotes are allowed' );
    is( read_file( $self->{env}{TEST_LOG} ),       "pr\t$self->{repo}\n", 'a third remote still uses ghop' );
    git( $self, 'remote', 'rename', 'origin', 'fork' );
    falls_back($self);
}

sub main_and_master_open_urls {
    my ($self) = @_;
    for my $branch (qw(main master)) {
        git( $self, 'checkout', '--quiet', '-B', $branch );
        git( $self, 'update-ref', "refs/remotes/origin/$branch", 'HEAD' );
        for my $directory ( $self->{repo}, "$self->{repo}/sub" ) {
            my $result = gho( $self, $directory );
            is( $result->{returncode}, 0, $result->{stderr} );
            my $url = 'https://github.com/example/fork';
            $url .= "/tree/$branch/sub" if $directory ne $self->{repo};
            is( read_file( $self->{env}{TEST_LOG} ),
                "open\t$url\n", "$branch opens its ordinary URL from the root or a subdirectory" );
        }
    }
}

sub unpublished_detached_and_unborn_use_urls {
    my ($self) = @_;
    git( $self, 'update-ref', '-d', 'refs/remotes/origin/topic' );
    falls_back($self);
    git( $self, 'update-ref', 'refs/remotes/origin/topic', 'HEAD' );
    git( $self, 'checkout',   '--quiet',                   '--detach' );
    falls_back($self);
    git( $self, 'symbolic-ref', 'HEAD', 'refs/heads/unborn' );
    falls_back($self);
}

sub explicit_targets_and_copy_never_use_ghop {
    my ($self) = @_;
    falls_back( $self, '.' );
    my $result = gho( $self, $self->{repo}, '--copy' );
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        read_file( $self->{env}{TEST_LOG} ),
        "copy\thttps://github.com/example/fork/tree/topic\n",
        'copy mode copies the normal URL without ghop or a browser'
    );
}

run_cases(
    {
        published_topic_uses_ghop                => \&published_topic_uses_ghop,
        required_remotes_must_exist              => \&required_remotes_must_exist,
        main_and_master_open_urls                => \&main_and_master_open_urls,
        unpublished_detached_and_unborn_use_urls => \&unpublished_detached_and_unborn_use_urls,
        explicit_targets_and_copy_never_use_ghop => \&explicit_targets_and_copy_never_use_ghop,
    },
    \&setup
);
