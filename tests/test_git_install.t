use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'git-install-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{env}       = { %ENV, HOME => "$self->{temporary}/home", NO_OVERWRITE => '' };
}

sub installs_and_refreshes_links {
    my ($self) = @_;
    my $source = read_file("$root/install.sh");
    is( scalar( () = $source =~ m{^\./git/install\.sh$}gm ),
        1, 'the root installer delegates Git setup once' );
    my %links = (
        '.gitconfig'         => 'gitconfig',
        '.config/git/ignore' => 'gitignore',
    );
    for my $refresh ( 0, 1 ) {
        if ($refresh) {
            write_file( "$self->{temporary}/previous", '' );
            for my $destination ( keys %links ) {
                unlink "$self->{env}{HOME}/$destination" or die $!;
                symlink "$self->{temporary}/previous", "$self->{env}{HOME}/$destination" or die $!;
            }
        }
        my $result =
          run_command( ["$root/git/install.sh"], { cwd => $self->{temporary}, env => $self->{env} } );
        is( $result->{returncode}, 0, "installation from another directory succeeds: $result->{stderr}" );
        for my $destination ( sort keys %links ) {
            is(
                readlink("$self->{env}{HOME}/$destination"),
                "$root/git/$links{$destination}",
                "$destination points to the current checkout"
            );
        }
    }
}

run_cases( { installs_and_refreshes_links => \&installs_and_refreshes_links }, \&setup );
