use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'dirtb-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{home}      = absolute_path( $self->{temporary} ) . '/home';
    make_path( "$self->{home}/code", "$self->{temporary}/cwd" );
    $self->{env} = {
        ( map { $_ => $ENV{$_} } grep { !/^GIT_/ } keys %ENV ),
        HOME                => $self->{home},
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
        TEST_FUNCTIONS      => "$root/fish/functions",
        TEST_COMPLETIONS    => "$root/fish/completions",
    };
}

sub git {
    my ( $self, $directory, @arguments ) = @_;
    return run_command( [ 'git', '-C', $directory, @arguments ], { env => $self->{env}, check => 1 } );
}

sub repository {
    my ( $self, $name, $file, $contents ) = @_;
    my $directory = "$self->{home}/code/$name";
    make_path($directory);
    git( $self, $directory, 'init', '--quiet' );
    write_file( "$directory/$file", $contents );
    git( $self, $directory, 'add', '--', $file );
    git( $self, $directory, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
        'commit', '--quiet', '-m', 'Initial content' );
    return $directory;
}

sub fish {
    my ( $self, $script ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH' . $script ],
set -p fish_function_path "$TEST_FUNCTIONS"
set -p fish_complete_path "$TEST_COMPLETIONS"
function tabt
    command cat
end
FISH
        { cwd => "$self->{temporary}/cwd", env => $self->{env}, check => 1 }
    );
}

sub lists_indexed_binaries_and_restores_cwd {
    my ($self) = @_;
    my $solo = repository( $self, 'solo', 'committed.bin', "committed\0binary" );
    write_file( "$solo/staged.bin", "staged\0binary" );
    git( $self, $solo, 'add', '--', 'staged.bin' );
    write_file( "$solo/untracked.bin", "untracked\0binary" );
    repository( $self, 'team/repo with spaces', 'binary file', "nested\0binary" );
    my $clean = repository( $self, 'team/clean', 'text', "text\n" );
    write_file( "$clean/text", "unstaged\0binary" );
    my $ignored = repository( $self, 'team/ignored', 'ignored.bin', "ignored\0binary" );
    repository( $self, 'team/deeper/outside-scan', 'deep.bin', "deep\0binary" );
    $self->{env}{TEST_IGNORE} = $ignored;
    my $result = fish( $self, <<'FISH' );
not functions -q _dirtb; or exit 1
set -g dirt_ignore "$TEST_IGNORE"
set -l previous "$PWD"
dirtb
test "$PWD" = "$previous"; or exit 2
FISH
    is( $result->{stderr}, '', 'scanning has no diagnostics' );
    is(
        $result->{stdout},
        "solo\tcommitted.bin\nsolo\tstaged.bin\nteam/repo with spaces\tbinary file\n",
        'lists committed and staged binaries in matching repos, excluding ignored, clean, and deeper repos'
    );
}

sub empty_scan_and_completions {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
dirtb
complete -C 'dirtb '
FISH
    is( $result->{stdout}, '', 'an empty scan and no-argument completion produce no candidates' );
    is( $result->{stderr}, '', 'an empty repository set is valid' );
}

run_cases(
    {
        lists_indexed_binaries_and_restores_cwd => \&lists_indexed_binaries_and_restores_cwd,
        empty_scan_and_completions              => \&empty_scan_and_completions,
    },
    \&setup
);
