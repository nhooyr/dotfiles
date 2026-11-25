use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my $url  = 'https://github.com/fish-shell/fish-shell/releases/download/4.9.3/fish-4.9.3-linux-x86_64.tar.xz';

sub setup {
    my ($self) = @_;
    my $temporary = tempdir( 'ci-fish-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$temporary/bin", "$temporary/archive", "$temporary/installed", "$temporary/tmp" );
    write_file( "$temporary/archive/fish", "standalone Fish binary\n" );
    run_command( [ 'tar', '-cJf', "$temporary/fish.tar.xz", '-C', "$temporary/archive", 'fish' ],
        { check => 1 } );
    write_file( "$temporary/bin/mock", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict; use warnings; use File::Basename qw(basename); use File::Copy qw(copy); use JSON::PP;
my $name = basename($0);
open my $log, '>>', $ENV{TEST_LOG} or die $!;
print {$log} encode_json([$name, @ARGV]), "\n"; close $log;
if ($name eq 'curl') {
    exit 22 if ($ENV{TEST_FAIL} // '') eq 'download';
    die 'wrong asset' unless $ARGV[-1] eq $ENV{TEST_URL};
    my ($index) = grep { $ARGV[$_] eq '--output' } 0 .. $#ARGV;
    die 'missing output' unless defined $index;
    if (($ENV{TEST_FAIL} // '') eq 'archive') {
        open my $out, '>', $ARGV[$index + 1] or die $!; print {$out} 'invalid archive'; close $out;
    } else { copy($ENV{TEST_ARCHIVE}, $ARGV[$index + 1]) or die $!; }
} elsif ($name eq 'sudo') {
    exit 23 if ($ENV{TEST_FAIL} // '') eq 'install';
    die 'unexpected sudo command' unless @ARGV == 3 && $ARGV[0] eq 'install';
    die 'unexpected destination' unless $ARGV[2] =~ m{^/usr/local/bin/(fish|fish_indent)$};
    my $destination = "$ENV{TEST_INSTALLED}/$1";
    copy($ARGV[1], $destination) or die $!; chmod 0755, $destination or die $!;
} else { die 'unexpected command'; }
PERL
    chmod 0755, "$temporary/bin/mock" or die $!;
    symlink 'mock', "$temporary/bin/$_" or die $! for qw(curl sudo);
    $self->{temporary} = $temporary;
    $self->{env}       = {
        %ENV,
        PATH           => "$temporary/bin:$ENV{PATH}",
        TMPDIR         => "$temporary/tmp",
        TEST_LOG       => "$temporary/calls",
        TEST_URL       => $url,
        TEST_ARCHIVE   => "$temporary/fish.tar.xz",
        TEST_INSTALLED => "$temporary/installed",
    };
}

sub install_fish {
    my ( $self, @args ) = @_;
    return run_command( [ "$root/ci/install-fish.sh", @args ], { env => $self->{env} } );
}

sub installs_pinned_standalone_tools {
    my ($self) = @_;
    my $result = install_fish($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    my @calls = map { decode_json($_) } split /\n/, read_file( $self->{env}{TEST_LOG} );
    is( $calls[0][-1], $url, 'downloads the pinned official Linux x86_64 release' );
    is_deeply(
        [ map { $_->[2] } @calls[ 1, 2 ] ],
        [ ( $calls[1][2] ) x 2 ],
        'both commands use the one standalone binary'
    );
    is_deeply(
        [ map { $_->[3] } @calls[ 1, 2 ] ],
        [ '/usr/local/bin/fish', '/usr/local/bin/fish_indent' ],
        'installs both command names'
    );
    for my $name (qw(fish fish_indent)) {
        my $path = "$self->{env}{TEST_INSTALLED}/$name";
        is( read_file($path), "standalone Fish binary\n", "$name receives the extracted binary" );
        ok( -x $path, "$name is executable" );
    }
    is_deeply( directory_entries( $self->{env}{TMPDIR} ), [], 'temporary download files are removed' );
}

sub help_and_invalid_arguments_do_not_install {
    my ($self) = @_;
    for my $option (qw(-h --help)) {
        my $result = install_fish( $self, $option );
        is( $result->{returncode}, 0, "$option succeeds" );
        like( $result->{stdout}, qr/^Usage: install-fish\.sh\n/, 'prints usage' );
    }
    is( install_fish( $self, '--invalid' )->{returncode}, 2, 'unknown arguments are rejected' );
    ok( !-e $self->{env}{TEST_LOG}, 'argument handling performs no download or installation' );
}

sub failures_stop_and_clean_up {
    my ($self) = @_;
    for my $case ( [ 'download', 22 ], [ 'archive', undef ], [ 'install', 23 ] ) {
        $self->{env}{TEST_FAIL} = $case->[0];
        my $result = install_fish($self);
        if ( defined $case->[1] ) {
            is( $result->{returncode}, $case->[1], "$case->[0] failure status is preserved" );
        }
        else {
            isnt( $result->{returncode}, 0, 'invalid archives fail' );
        }
        is_deeply( directory_entries( $self->{env}{TEST_INSTALLED} ),
            [], 'failed installation leaves no commands' );
        is_deeply( directory_entries( $self->{env}{TMPDIR} ), [], 'failure removes temporary files' );
    }
}

sub all_ci_entrypoints_use_the_shared_installer {
    my %dependencies = (
        'fmt.sh'  => 'shfmt cargo rustfmt cpanminus',
        'lint.sh' => 'shfmt cargo rust-clippy',
        'test.sh' => 'cargo zsh fd-find ripgrep shfmt perltidy',
    );
    for my $name ( sort keys %dependencies ) {
        my $text = read_file("$root/ci/$name");
        like(
            $text,
            qr/if \[ "\$\{GITHUB_ACTIONS-\}" \]; then\n\t\.\/ci\/install-fish\.sh\n\tsudo apt-get update\n/,
            "$name installs Fish only in GitHub Actions"
        );
        like(
            $text,
            qr/sudo apt-get install --yes \Q$dependencies{$name}\E\n/,
            "$name preserves its other dependencies"
        );
        unlike(
            $text,
            qr/add-apt-repository|apt-get[^\n]*\bfish\b/,
            "$name does not install an older Fish package"
        );
    }
}

run_cases(
    {
        installs_pinned_standalone_tools            => \&installs_pinned_standalone_tools,
        help_and_invalid_arguments_do_not_install   => \&help_and_invalid_arguments_do_not_install,
        failures_stop_and_clean_up                  => \&failures_stop_and_clean_up,
        all_ci_entrypoints_use_the_shared_installer => \&all_ci_entrypoints_use_the_shared_installer,
    },
    \&setup
);
