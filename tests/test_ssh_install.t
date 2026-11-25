use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'ssh-install-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $source = absolute_path( $self->{temporary} ) . '/source';
    make_path( "$source/ssh", "$source/bin" );
    copy_preserve( "$root/ssh/install.sh", "$source/ssh/install.sh" );
    copy_preserve( "$root/bin/$_", "$source/bin/$_" ) for qw(dotln hpath);
    write_file( "$source/ssh/$_", "fixture\n" ) for qw(config allowed_signers);
    $self->{source} = $source;
    $self->{env}    = { %ENV, HOME => "$self->{temporary}/home", NO_OVERWRITE => '' };
}

sub installs_links_and_permissions {
    my ($self) = @_;
    my $source = read_file("$root/install.sh");
    is( scalar( () = $source =~ m{^\./ssh/install\.sh$}gm ),
        1, 'the root installer delegates SSH setup once' );
    unlike( $source, qr{ssh/(?:config|allowed_signers|sockets)}, 'SSH details stay in its installer' );
    my $ssh = "$self->{env}{HOME}/.ssh";
    for my $refresh ( 0, 1 ) {
        if ($refresh) {
            write_file( "$self->{temporary}/previous", '' );
            for my $name (qw(config allowed_signers)) {
                unlink "$ssh/$name" or die $!;
                symlink "$self->{temporary}/previous", "$ssh/$name" or die $!;
            }
            chmod 0755, $ssh or die $!;
        }
        chmod 0644, "$self->{source}/ssh/config" or die $!;
        my $result = run_command( ["$self->{source}/ssh/install.sh"],
            { cwd => $self->{temporary}, env => $self->{env} } );
        is( $result->{returncode}, 0, "installation from another directory succeeds: $result->{stderr}" );
        is( readlink("$ssh/$_"),   "$self->{source}/ssh/$_", "links $_ to the current checkout" )
          for qw(config allowed_signers);
        ok( -d "$ssh/sockets", 'creates the socket directory' );
        is( ( stat $ssh )[2] & 0777,                         0700, 'keeps the SSH directory private' );
        is( ( stat "$self->{source}/ssh/config" )[2] & 0777, 0600, 'keeps the SSH config private' );
    }
}

run_cases( { installs_links_and_permissions => \&installs_links_and_permissions }, \&setup );
