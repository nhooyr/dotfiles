use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'fzfp-install-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path("$self->{temporary}/bin");
    $self->{env} = {
        %ENV,
        HOME              => "$self->{temporary}/home",
        PATH              => "$self->{temporary}/bin:$ENV{PATH}",
        NO_OVERWRITE      => '',
        TEST_CALLS        => "$self->{temporary}/calls",
        TEST_CARGO_STATUS => 0,
    };
    write_file( "$self->{temporary}/bin/cargo", '#!' . perl_executable() . "\n" . <<'PERL' );
use Cwd qw(getcwd);
use JSON::PP;
open my $file, '>>', $ENV{TEST_CALLS} or die $!;
print {$file} encode_json([getcwd(), @ARGV]), "\n";
exit $ENV{TEST_CARGO_STATUS};
PERL
    chmod 0755, "$self->{temporary}/bin/cargo";
}

sub install {
    my ($self) = @_;
    return run_command( ["$root/fzfp/install.sh"], { cwd => $self->{temporary}, env => $self->{env} } );
}

sub installs_and_refreshes_ignore {
    my ($self) = @_;
    my $source = read_file("$root/install.sh");
    is( scalar( () = $source =~ m{^\./fzfp/install\.sh$}gm ),
        1, 'the root installer delegates fzfp setup once' );
    unlike( $source, qr{fzfp/ignore}, 'ignore setup belongs to the fzfp installer' );
    my $result = install($self);
    is( $result->{returncode}, 0, "installation succeeds from another directory: $result->{stderr}" );
    is_deeply(
        decode_json( read_file( $self->{env}{TEST_CALLS} ) ),
        [ "$root/fzfp", 'install', '--path', '.', '--root', "$self->{env}{HOME}/.local/share", '--quiet' ],
        'Cargo runs from fzfp with the original installation arguments'
    );
    my $link = "$self->{env}{HOME}/.config/fzfp/ignore";
    is( readlink($link), "$root/fzfp/ignore", 'installs the ignore link' );
    write_file( "$self->{temporary}/previous", '' );
    unlink $link or die $!;
    symlink "$self->{temporary}/previous", $link or die $!;
    $result = install($self);
    is( $result->{returncode}, 0,                   "reinstallation succeeds: $result->{stderr}" );
    is( readlink($link),       "$root/fzfp/ignore", 'refreshes an existing ignore link' );
}

sub cargo_failure_stops_setup {
    my ($self) = @_;
    $self->{env}{TEST_CARGO_STATUS} = 23;
    my $result = install($self);
    is( $result->{returncode}, 23, 'Cargo failure is returned' );
    ok( !-l "$self->{env}{HOME}/.config/fzfp/ignore", 'failed installation does not create the ignore link' );
}

run_cases(
    {
        installs_and_refreshes_ignore => \&installs_and_refreshes_ignore,
        cargo_failure_stops_setup     => \&cargo_failure_stops_setup,
    },
    \&setup
);
