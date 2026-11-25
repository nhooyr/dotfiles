use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $functions = absolute_path("$FindBin::Bin/../fish/functions");
my $url       = "https://gist.github.com/example/123\n";

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'ghg-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $dir = $self->{temporary};
    make_path("$dir/bin");
    $self->{env} = {
        %ENV,
        PATH             => "$dir/bin:$ENV{PATH}",
        TEST_ROOT        => $dir,
        TEST_FUNCTIONS   => $functions,
        TEST_CLIPBOARD   => "clipboard text\nsecond line\n",
        TEST_GIST_URL    => $url,
        TEST_GIST_STATUS => 0,
    };
    for my $name (qw(gh pbpaste pbc)) {
        write_file( "$dir/bin/$name", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
use File::Basename qw(basename);
use JSON::PP;
my $kind = basename($0);
my $input = '';
if ($kind ne 'pbpaste') { local $/; $input = <STDIN> // ''; }
open my $log, '>>', "$ENV{TEST_ROOT}/calls" or die $!;
print {$log} encode_json({ kind => $kind, args => \@ARGV, input => $input }), "\n";
close $log;
if ($kind eq 'pbpaste') { print $ENV{TEST_CLIPBOARD}; exit; }
if ($kind eq 'gh') {
    if ($ENV{TEST_GIST_STATUS}) { print STDERR "gist upload failed\n"; exit $ENV{TEST_GIST_STATUS}; }
    print $ENV{TEST_GIST_URL}; exit;
}
open my $copy, '>', "$ENV{TEST_ROOT}/copied" or die $!;
print {$copy} $input;
print $input;
PERL
        chmod 0755, "$dir/bin/$name";
    }
}

sub run {
    my ( $self, $args, $input ) = @_;
    unlink "$self->{temporary}/calls", "$self->{temporary}/copied";
    return run_command(
        [
            'fish', '--no-config', '-c', 'set -p fish_function_path "$TEST_FUNCTIONS"; ghg $argv',
            '--',   @$args
        ],
        { env => $self->{env}, input => $input // '', timeout => 10 }
    );
}

sub calls {
    my ( $self, $kind ) = @_;
    my $path = "$self->{temporary}/calls";
    return [] unless -f $path;
    return [ grep { $_->{kind} eq $kind } map { decode_json($_) } split /\n/, read_file($path) ];
}

sub clipboard_uploads {
    my ($self) = @_;
    for my $flags ( [], ['-p'], ['--public'] ) {
        my $result = run( $self, $flags );
        is( $result->{returncode},                  0,    'clipboard upload succeeds' );
        is( $result->{stdout},                      $url, 'the gist URL is printed' );
        is( read_file("$self->{temporary}/copied"), $url, 'the URL is copied' );
        is( scalar @{ calls( $self, 'pbpaste' ) },  1,    'clipboard is read once' );
        my $gh = calls( $self, 'gh' )->[0];
        is_deeply(
            $gh->{args},
            [ 'gist', 'create', ( @$flags ? '--public' : () ), '--', '-' ],
            'public option is parsed before deciding to read the clipboard'
        );
        is( $gh->{input}, $self->{env}{TEST_CLIPBOARD}, 'clipboard contents are preserved' );
    }
}

sub explicit_stdin {
    my ($self) = @_;
    my $result = run( $self, [ '-p', '-' ], "piped text\n" );
    is( $result->{returncode}, 0, 'stdin upload succeeds' );
    is_deeply( calls( $self, 'pbpaste' ), [], 'explicit stdin does not read the clipboard' );
    is( calls( $self, 'gh' )->[0]{input}, "piped text\n", 'stdin reaches gh unchanged' );
}

sub file_arguments {
    my ($self) = @_;
    for my $flag (qw(-p --public)) {
        my $result = run( $self, [ $flag, '--', '-file.txt', 'path with spaces.txt' ] );
        is( $result->{returncode}, 0, 'file upload succeeds' );
        is_deeply(
            calls( $self, 'gh' )->[0]{args},
            [ 'gist', 'create', '--public', '--', '-file.txt', 'path with spaces.txt' ],
            'file arguments stay separate'
        );
        is_deeply( calls( $self, 'pbpaste' ), [], 'file uploads do not read the clipboard' );
    }
}

sub help_and_invalid_options {
    my ($self) = @_;
    for my $option (qw(-h --help --unknown)) {
        my $result = run( $self, [$option] );
        is( $result->{returncode} == 0, $option ne '--unknown', 'option has the expected exit status' );
        like( $result->{stdout}, qr/Usage: ghg/, 'help explains the usage' ) unless $option eq '--unknown';
        ok( !-e "$self->{temporary}/calls", 'no upload or clipboard operation occurs' );
    }
}

sub upload_failure {
    my ($self) = @_;
    $self->{env}{TEST_GIST_STATUS} = 17;
    my $result = run( $self, ['file.txt'] );
    is( $result->{returncode}, 17,                     'upload failure is preserved' );
    is( $result->{stderr},     "gist upload failed\n", 'the original diagnostic is shown' );
    is( $result->{stdout},     '',                     'failure prints no URL' );
    is_deeply( calls( $self, 'pbc' ), [], 'failed uploads do not change the clipboard' );
}

run_cases(
    {
        clipboard_uploads        => \&clipboard_uploads,
        explicit_stdin           => \&explicit_stdin,
        file_arguments           => \&file_arguments,
        help_and_invalid_options => \&help_and_invalid_options,
        upload_failure           => \&upload_failure,
    },
    \&setup
);
