use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $source = absolute_path("$FindBin::Bin/../fish/functions/tex.fish");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'tex-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    write_file( "$self->{temporary}/-main.tex", '' );
}

sub run_tex {
    my ( $self, $status ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH', '--', $source, $status ],
source "$argv[1]"
set -g watcher_status "$argv[2]"
function cdc
    cd -- "$argv[1]"; or return
    $argv[2..]
end
function latexmk
    printf '%s\n' $argv
end
function fswatch
    return "$watcher_status"
end
tex -main.tex
FISH
        { cwd => $self->{temporary} }
    );
}

sub leading_dash_is_a_filename {
    my ($self) = @_;
    my $result = run_tex( $self, 0 );
    is( $result->{returncode}, 0,  'watching succeeds' );
    is( $result->{stderr},     '', 'the filename is not parsed as an option' );
    is(
        $result->{stdout},
        "-pdf\n-silent\n-pv\n./-main.tex\n",
        'latexmk receives an explicitly relative filename'
    );
}

sub watcher_status_is_preserved {
    my ($self) = @_;
    for my $status ( 23, 130 ) {
        my $result = run_tex( $self, $status );
        is( $result->{returncode}, $status, 'watcher failures and interrupts are returned' );
    }
}

run_cases(
    {
        leading_dash_is_a_filename  => \&leading_dash_is_a_filename,
        watcher_status_is_preserved => \&watcher_status_is_preserved,
    },
    \&setup
);
