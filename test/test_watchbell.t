use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $source = absolute_path("$FindBin::Bin/../fish/functions/watchbell.fish");

sub watcher_status {
    my ( $self, $status, $message ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH', '--', $source, $status, $message ],
source "$argv[1]"
set -g test_status "$argv[2]"
set -g test_message "$argv[3]"
function fswatch
    test -z "$test_message"; or printf '%s\n' "$test_message" >&2
    return "$test_status"
end
watchbell '['
FISH
    );
}

sub watcher_errors_are_returned {
    my ($self) = @_;
    my $result = watcher_status( $self, 2, 'Invalid regular expression' );
    is( $result->{returncode}, 2,                              'watchbell returns the watcher failure' );
    is( $result->{stderr},     "Invalid regular expression\n", 'the watcher diagnostic is preserved once' );
}

sub success_and_interrupt_have_no_extra_diagnostics {
    my ($self) = @_;
    for my $status ( 0, 130 ) {
        my $result = watcher_status( $self, $status, '' );
        is( $result->{returncode}, $status, 'normal and interrupted watcher statuses are preserved' );
        is( $result->{stderr},     '',      'success and interruption add no diagnostics' );
    }
}

run_cases(
    {
        watcher_errors_are_returned                     => \&watcher_errors_are_returned,
        success_and_interrupt_have_no_extra_diagnostics => \&success_and_interrupt_have_no_extra_diagnostics
    }
);
