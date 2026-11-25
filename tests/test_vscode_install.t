use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{directory} = tempdir( 'vscode-install-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $directory = $self->{directory};
    make_path( "$directory/theme", "$directory/bin" );
    copy_preserve( "$root/vscode/theme/install.sh",   "$directory/theme/install.sh" );
    copy_preserve( "$root/vscode/theme/package.json", "$directory/theme/package.json" );
    write_file( "$directory/theme/icon.jpg", 'downloaded image' );
    my $package = decode_json( read_file("$directory/theme/package.json") );
    $self->{extension} = "$package->{publisher}.$package->{name}\@$package->{version}";
    $self->{vsix}      = "./$package->{name}-$package->{version}.vsix";
    $self->{env}       = {
        %ENV,
        PATH             => "$directory/bin:$ENV{PATH}",
        TEST_CALLS       => "$directory/calls",
        TEST_LIST_OUTPUT => '',
        TEST_LIST_STATUS => 0,
    };

    for my $tool (qw(code vsce)) {
        write_file( "$directory/bin/$tool", '#!' . perl_executable() . "\n" . <<'PERL' );
use File::Basename qw(basename);
use JSON::PP;
my $tool = basename($0);
open my $calls, '>>', $ENV{TEST_CALLS} or die $!;
print {$calls} encode_json([$tool, @ARGV]), "\n";
close $calls;
if ($tool eq 'code' && grep { $_ eq '--list-extensions' } @ARGV) {
    print $ENV{TEST_LIST_OUTPUT};
    warn "extension listing failed\n" if $ENV{TEST_LIST_STATUS};
    exit $ENV{TEST_LIST_STATUS};
}
PERL
        chmod 0755, "$directory/bin/$tool";
    }
}

sub install {
    my ( $self, @args ) = @_;
    unlink $self->{env}{TEST_CALLS};
    return run_command( [ 'sh', "$self->{directory}/theme/install.sh", @args ], { env => $self->{env} } );
}

sub calls {
    my ($self) = @_;
    return [ map { decode_json($_) } split /\n/, read_file( $self->{env}{TEST_CALLS} ) ];
}

sub listing_failure_stops_installation {
    my ($self) = @_;
    for my $output ( '', "$self->{extension}\n" ) {
        $self->{env}{TEST_LIST_OUTPUT} = $output;
        $self->{env}{TEST_LIST_STATUS} = 23;
        my $result = install($self);
        is( $result->{returncode}, 23, 'extension-listing failure is returned' );
        like( $result->{stderr}, qr/extension listing failed/, 'the original diagnostic is retained' );
        unlike(
            $result->{stderr},
            qr/Already installed/,
            'failed output cannot claim an installed extension'
        );
        is_deeply(
            calls($self),
            [ [ 'code', '--list-extensions', '--show-versions' ] ],
            'failed inspection does not package or install the extension'
        );
    }
}

sub already_installed_is_unchanged {
    my ($self) = @_;
    $self->{env}{TEST_LIST_OUTPUT} = "$self->{extension}\n";
    my $result = install($self);
    is( $result->{returncode}, 0, 'an installed extension succeeds' );
    like(
        $result->{stderr},
        qr/Already installed \Q$self->{extension}\E/,
        'the existing status is preserved'
    );
    is_deeply(
        calls($self),
        [ [ 'code', '--list-extensions', '--show-versions' ] ],
        'an installed extension is not packaged again'
    );
}

sub forced_install_skips_listing {
    my ($self) = @_;
    $self->{env}{TEST_LIST_STATUS} = 23;
    my $result = install( $self, '--force' );
    is( $result->{returncode}, 0, $result->{stderr} );
    is_deeply(
        calls($self),
        [ [ 'vsce', 'package' ], [ 'code', '--force', '--install-extension', $self->{vsix} ] ],
        'forced installation bypasses extension inspection'
    );
}

run_cases(
    {
        listing_failure_stops_installation => \&listing_failure_stops_installation,
        already_installed_is_unchanged     => \&already_installed_is_unchanged,
        forced_install_skips_listing       => \&forced_install_skips_listing,
    },
    \&setup
);
