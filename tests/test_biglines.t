use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $helper = absolute_path("$FindBin::Bin/../fish/functions/biglines.fish");

sub setup {
    my ($self) = @_;
    $self->{directory} = tempdir( 'biglines-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    write_file( "$self->{directory}/lines", "a\nlong\n" );
}

sub biglines {
    my ( $self, $filename, $stage, $status ) = @_;
    my $script = <<'FISH';
source "$argv[1]"
function set_color
end
function less
    command cat
end
FISH
    if ( defined $stage ) {
        $script .= "function $stage; command cat >/dev/null; return $status; end\n";
    }
    $script .= 'biglines "$argv[2]"';
    return run_command( [ 'fish', '--no-config', '-c', $script, '--', $helper, $filename ],
        { cwd => $self->{directory} } );
}

sub sorts_lines_with_lengths {
    my ($self) = @_;
    my $result = biglines( $self, 'lines' );
    is( $result->{returncode}, 0,               $result->{stderr} );
    is( $result->{stdout},     "4 long\n1 a\n", 'the formatted output stays sorted by line length' );
}

sub filenames_are_not_awk_options_or_assignments {
    my ($self) = @_;
    for my $name ( 'x=y', '-v' ) {
        write_file( "$self->{directory}/$name", "a\nlong\n" );
        my $result = biglines( $self, $name );
        is( $result->{returncode}, 0,               $result->{stderr} );
        is( $result->{stdout},     "4 long\n1 a\n", "$name is read as a filename" );
    }
}

sub missing_file_is_a_failure {
    my ($self) = @_;
    my $result = biglines( $self, 'missing' );
    isnt( $result->{returncode}, 0, 'missing input is reported as a failure' );
    like( $result->{stderr}, qr/missing/, 'the input diagnostic is retained' );
}

sub pipeline_failures_are_returned {
    my ($self) = @_;
    for my $stage (qw(sort sed less)) {
        my $result = biglines( $self, 'lines', $stage, 23 );
        is( $result->{returncode}, 23, "$stage failure is returned" );
    }
}

sub pager_sigpipe_is_successful {
    my ($self) = @_;
    for my $stage (qw(sort sed)) {
        my $result = biglines( $self, 'lines', $stage, 141 );
        is( $result->{returncode}, 0, "$stage SIGPIPE is ignored when the pager closes" );
    }
}

run_cases(
    {
        sorts_lines_with_lengths                     => \&sorts_lines_with_lengths,
        filenames_are_not_awk_options_or_assignments => \&filenames_are_not_awk_options_or_assignments,
        missing_file_is_a_failure                    => \&missing_file_is_a_failure,
        pipeline_failures_are_returned               => \&pipeline_failures_are_returned,
        pager_sigpipe_is_successful                  => \&pager_sigpipe_is_successful,
    },
    \&setup
);
