use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

sub timeout_removes_temporary_files {
    my @paths;
    my $tempfile = \&TestHelpers::tempfile;
    {
        no warnings 'redefine';
        local *TestHelpers::tempfile = sub {
            my @result = $tempfile->(@_);
            push @paths, $result[1];
            return @result;
        };
        eval { run_command( [ perl_executable(), '-e', 'sleep 5' ], { timeout => 0.1 } ) };
    }
    like( $@, qr/Command timed out/, 'the command times out' );
    my @remaining = grep { -e $_ } @paths;
    unlink @remaining;
    is_deeply( \@remaining, [], 'timeout removes its input, output, and error files' );
}

run_cases( { timeout_removes_temporary_files => \&timeout_removes_temporary_files } );
