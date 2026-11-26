use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'ghop-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $dir = $self->{temporary};
    make_path("$dir/bin");
    $self->{env} = {
        %ENV,
        PATH               => "$dir/bin:$ENV{PATH}",
        TEST_ROOT          => $dir,
        TEST_CONFIG        => "$root/fish/git.fish",
        TEST_FUNCTIONS     => "$root/fish/functions",
        TEST_COMPLETIONS   => "$root/fish/completions",
        TEST_VIEW_STATUS   => 0,
        TEST_VIEW_ERROR    => '',
        TEST_CREATE_STATUS => 0,
    };
    write_file( "$dir/bin/gh", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict; use warnings; use JSON::PP;
open my $log, '>>', "$ENV{TEST_ROOT}/calls" or die $!;
print {$log} encode_json(\@ARGV), "\n";
close $log;
if ($ARGV[1] eq 'create') { exit $ENV{TEST_CREATE_STATUS}; }
if (grep { $_ eq '-h' || $_ eq '--help' } @ARGV) {
    print "Usage: gh pr view [<number> | <url> | <branch>] [flags]\n";
    exit 0;
}
print STDERR $ENV{TEST_VIEW_ERROR};
exit $ENV{TEST_VIEW_STATUS};
PERL
    chmod 0755, "$dir/bin/gh" or die $!;
}

sub run {
    my ( $self, @args ) = @_;
    unlink "$self->{temporary}/calls";
    return run_command( [ 'fish', '--no-config', '-c', <<'FISH', '--', @args ], { env => $self->{env} } );
function abbrali --argument-names name
    abbr -a "$name" $argv[2..]
    alias "$name" "$argv[2..]"
end
source "$TEST_CONFIG"
set -p fish_function_path "$TEST_FUNCTIONS"
set -g fish_complete_path "$TEST_COMPLETIONS"
ghop $argv
FISH
}

sub calls {
    my ($self) = @_;
    return [ map { decode_json($_) } split /\n/, read_file("$self->{temporary}/calls") ];
}

sub existing_pr {
    my ($self) = @_;
    for my $args ( [], ['123'], [ '--repo', 'owner/repo' ] ) {
        my $result = run( $self, @$args );
        is( $result->{returncode}, 0, 'existing PR opens successfully' );
        is_deeply( calls($self), [ [ 'pr', 'view', '--web', @$args ] ],
            'existing PR uses one gh invocation' );
    }
}

sub missing_pr {
    my ($self) = @_;
    $self->{env}{TEST_VIEW_STATUS} = 1;
    $self->{env}{TEST_VIEW_ERROR}  = "no pull requests found for branch \"topic\"\n";
    for my $args ( [], [ '--repo', 'owner/repo' ] ) {
        my $result = run( $self, @$args );
        is( $result->{returncode}, 0,  'missing PR starts the create flow' );
        is( $result->{stderr},     '', 'missing-PR diagnostic is hidden when falling back' );
        is_deeply(
            calls($self),
            [ [ 'pr', 'view', '--web', @$args ], [ 'pr', 'create', '--web', '--fill-verbose', @$args ] ],
            'fallback uses the existing ghep command'
        );
    }
    $self->{env}{TEST_CREATE_STATUS} = 7;
    is( run($self)->{returncode}, 7, 'fallback status is preserved' );
}

sub errors_do_not_create {
    my ($self) = @_;
    $self->{env}{TEST_VIEW_STATUS} = 1;
    for my $message ( "authentication failed\n", "network failed\n", "browser failed\n" ) {
        $self->{env}{TEST_VIEW_ERROR} = $message;
        my $result = run($self);
        is( $result->{returncode},    1,        'view failure is preserved' );
        is( $result->{stderr},        $message, 'view diagnostic is preserved' );
        is( scalar @{ calls($self) }, 1,        'view failure does not start PR creation' );
    }
    $self->{env}{TEST_VIEW_ERROR} = "no pull requests found for branch \"specific-branch\"\n";
    is( run( $self, 'specific-branch' )->{returncode}, 1, 'an explicit missing selector remains an error' );
    is( scalar @{ calls($self) },                      1, 'an explicit selector does not start another PR' );
}

sub underlying_help {
    my ($self) = @_;
    for my $flag ( '-h', '--help' ) {
        my $result = run( $self, $flag );
        is( $result->{returncode}, 0, 'help succeeds' );
        like( $result->{stdout}, qr/^Usage: gh pr view/, 'help comes from gh' );
        is_deeply(
            calls($self),
            [ [ qw(pr view --web), $flag ] ],
            'help only invokes the underlying view command'
        );
    }
}

sub lazy_completion {
    my ($self) = @_;
    my $result = run_command( [ 'fish', '--no-config', '-c', <<'FISH' ], { env => $self->{env} } );
set -p fish_function_path "$TEST_FUNCTIONS"
set -g fish_complete_path "$TEST_COMPLETIONS"
complete -c gh -l help -d 'Show help'
test -z "$(complete -c ghop)"; or exit 1
complete -C 'ghop --he'
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/^--help\tShow help$/m, 'native PR-view completions load on request' );
    ok( !grep( { $_->[0] eq 'pr' } @{ calls($self) } ), 'completion does not view or create a PR' );
}

run_cases(
    {
        existing_pr          => \&existing_pr,
        missing_pr           => \&missing_pr,
        errors_do_not_create => \&errors_do_not_create,
        underlying_help      => \&underlying_help,
        lazy_completion      => \&lazy_completion
    },
    \&setup
);
