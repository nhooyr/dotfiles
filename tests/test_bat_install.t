use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'bat-install-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path("$self->{temporary}/bin");
    $self->{env} = {
        %ENV,
        HOME            => "$self->{temporary}/home",
        PATH            => "$self->{temporary}/bin:$ENV{PATH}",
        NO_OVERWRITE    => '',
        TEST_CALLS      => "$self->{temporary}/calls",
        TEST_BAT_STATUS => 0,
    };
    write_file( "$self->{temporary}/bin/bat", '#!' . perl_executable() . "\n" . <<'PERL' );
use Cwd qw(getcwd);
use JSON::PP;
die 'configuration must be linked before building the cache' unless -l "$ENV{HOME}/.config/bat";
open my $file, '>>', $ENV{TEST_CALLS} or die $!;
print {$file} encode_json([getcwd(), @ARGV]), "\n";
exit $ENV{TEST_BAT_STATUS};
PERL
    chmod 0755, "$self->{temporary}/bin/bat" or die $!;
}

sub install {
    my ($self) = @_;
    return run_command( ["$root/bat/install.sh"], { cwd => $self->{temporary}, env => $self->{env} } );
}

sub links_config_before_building_cache {
    my ($self) = @_;
    my $source = read_file("$root/install.sh");
    is( scalar( () = $source =~ m{^\./bat/install\.sh$}gm ), 1, 'root delegates Bat setup once' );
    unlike( $source, qr{dotln \./bat\b}, 'the root installer does not manage the Bat link' );
    my $result = install($self);
    is( $result->{returncode}, 0, "installation works from another directory: $result->{stderr}" );
    is( readlink("$self->{env}{HOME}/.config/bat"), "$root/bat", 'links the Bat configuration' );
    is_deeply(
        decode_json( read_file( $self->{env}{TEST_CALLS} ) ),
        [ "$root/bat", 'cache', '--build' ],
        'builds the cache from the Bat directory'
    );
    $self->{env}{TEST_BAT_STATUS} = 23;
    $result = install($self);
    is( $result->{returncode}, 23, 'a cache-build failure is returned during reinstallation' );
    unlike( $result->{stdout}, qr/Built theme cache/, 'failure does not report a successful build' );
}

run_cases( { links_config_before_building_cache => \&links_config_before_building_cache }, \&setup );
