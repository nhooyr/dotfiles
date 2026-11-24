use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $source = absolute_path("$FindBin::Bin/../fish/functions");

sub git {
    my ( $self, @args ) = @_;
    return run_command( [ 'git', '-c', 'commit.gpgsign=false', @args ], { env => $self->{env}, check => 1 } )
      ->{stdout};
}

sub setup {
    my ($self) = @_;
    $self->{root} = tempdir( 'github-index-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{a}    = "$self->{root}/a";
    $self->{b}    = "$self->{root}/home/code/test-owner/b";
    $self->{env}  = {
        ( map { $_ => $ENV{$_} } grep { !/^GIT_/ } keys %ENV ),
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
        GIT_AUTHOR_NAME     => 'Test',
        GIT_AUTHOR_EMAIL    => 'test@example.invalid',
        GIT_COMMITTER_NAME  => 'Test',
        GIT_COMMITTER_EMAIL => 'test@example.invalid',
        HOME                => "$self->{root}/home",
        GH_HOST             => '',
        XDG_CONFIG_HOME     => "$self->{root}/config",
        XDG_DATA_HOME       => "$self->{root}/data",
    };
    for my $repo ( $self->{a}, $self->{b} ) {
        git( $self, 'init', '-q', '-b', 'main', $repo );
        write_file( "$repo/file.txt", "main\n" );
        git( $self, '-C', $repo, 'add',    'file.txt' );
        git( $self, '-C', $repo, 'commit', '-qm', 'main' );
        git( $self, '-C', $repo, 'switch', '-qc', 'topic' );
        write_file( "$repo/file.txt", "topic\n" );
        git( $self, '-C', $repo, 'commit', '-qam', 'topic' );
        git( $self, '-C', $repo, 'switch', '-q',   'main' );
    }
    git( $self, '-C', $self->{b}, 'remote', 'add', 'origin', 'https://github.com/test-owner/b.git' );
}

sub commit_editor_checkout {
    my ($self) = @_;
    my $a      = $self->{a};
    my $editor = "$self->{root}/editor";
    write_file( $editor, "#!/bin/sh\n" . <<'SH' );
set -eu
before=$(git write-tree)
fish --no-config -c 'source "$TEST_SOURCE/ghe.fish"; set -l inherited "$GIT_INDEX_FILE"; ghe https://github.com/test-owner/b/tree/topic; or exit; test "$GIT_INDEX_FILE" = "$inherited"'
test "$(git write-tree)" = "$before"
printf 'Editor test\n' >"$1"
SH
    chmod 0755, $editor or die $!;
    $self->{env}{GIT_EDITOR}  = $editor;
    $self->{env}{TEST_SOURCE} = $source;
    write_file( "$a/file.txt", "edited\n" );
    git( $self, '-C', $a, 'commit', '--only', 'file.txt' );
    is( git( $self, '-C', $a, 'show', 'HEAD:file.txt' ),
        "edited\n", 'the initiating commit keeps its intended contents' );
    is( git( $self, '-C', $self->{b}, 'branch', '--show-current' ),
        "topic\n", 'ghe switches the requested checkout' );
    is( git( $self, '-C', $self->{b}, 'status', '--porcelain' ),
        '', 'the target index matches its new HEAD and files' );
}

sub checkout_from_commit_editor {
    commit_editor_checkout(@_);
}

sub linked_checkout_from_commit_editor {
    my ($self) = @_;
    git( $self, '-C', $self->{b}, 'switch', '-qc', 'parking' );
    my $shared = "$self->{root}/shared";
    rename $self->{b}, $shared or die $!;
    git( $self, '-C', $shared, 'worktree', 'add', '-q', $self->{b}, 'main' );
    commit_editor_checkout($self);
}

sub deleted_file_uses_its_own_index {
    my ($self) = @_;
    write_file( "$self->{b}/only-b.txt", 'tracked' );
    git( $self, '-C', $self->{b}, 'add', 'only-b.txt' );
    git( $self, '-C', $self->{b}, 'commit', '-qm', 'Add target file' );
    unlink "$self->{b}/only-b.txt" or die $!;
    my $result = run_command(
        [
            'fish', '--no-config', '-c',
            'source "$argv[1]/gho.fish"; function pbc; cat; end; gho --copy "$argv[2]"',
            '--', $source, "$self->{b}/only-b.txt"
        ],
        {
            env => { %{ $self->{env} }, GIT_INDEX_FILE => "$self->{a}/.git/index" }
        }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        $result->{stdout},
        "https://github.com/test-owner/b/blob/main/only-b.txt\n",
        'gho recognizes a deleted file in the target repository despite an inherited index'
    );
}

run_cases(
    {
        checkout_from_commit_editor        => \&checkout_from_commit_editor,
        linked_checkout_from_commit_editor => \&linked_checkout_from_commit_editor,
        deleted_file_uses_its_own_index    => \&deleted_file_uses_its_own_index
    },
    \&setup
);
