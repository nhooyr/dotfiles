use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub preserves_arguments_and_status {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'pager-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $bin = "$self->{temporary}/bin";
    make_path($bin);
    write_file( "$bin/less", '#!' . perl_executable() . "\n" . <<'PERL' );
use JSON::PP;
print encode_json(\@ARGV);
exit 23;
PERL
    chmod 0755, "$bin/less" or die $!;
    for my $n ( undef, '', '0', '7' ) {
        my %env = ( %ENV, PATH => "$bin:$ENV{PATH}" );
        defined $n ? $env{N} = $n : delete $env{N};
        my @defaults = defined($n) && $n eq '0' ? () : ( '-N', '--line-num-width=' . ( $n || 3 ) );
        for my $args ( [], [ '--line-num-width=9', '--', 'file name.txt' ] ) {
            my $result = run_command( [ "$root/bin/pager", @$args ], { env => \%env } );
            is_deeply(
                decode_json( $result->{stdout} ),
                [ @defaults, @$args ],
                'line-number defaults precede intact arguments'
            );
            is( $result->{returncode}, 23, 'less exit status is preserved' );
        }
    }
}

run_cases( { preserves_arguments_and_status => \&preserves_arguments_and_status } );
