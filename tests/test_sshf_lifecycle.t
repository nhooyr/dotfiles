use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use Time::HiRes qw(time sleep);

my $program = absolute_path("$FindBin::Bin/../bin/sshf");

sub setup {
    my ($self) = @_;
    plan skip_all => 'GNU timeout is required' unless which('timeout');
    $self->{directory} = tempdir( 'sshf-lifecycle-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $directory = $self->{directory};
    make_path("$directory/bin");
    my %mocks = (
        ssh => <<'SSH',
use Time::HiRes qw(time sleep);
$| = 1;
my $kind = (grep { $_ eq '-MN' } @ARGV) ? 'master' : 'setup';
open my $pid, '>', "$ENV{TEST_ROOT}/$kind" or die $!;
print {$pid} $$;
close $pid;
my $phase = $kind eq 'master' ? 'auth' : 'forward';
if ($ENV{TEST_PHASE} ne $phase) {
    exit 0 if $kind eq 'setup';
    print "ssh-authenticated\n";
} elsif ($ENV{TEST_INTERRUPT}) {
    sleep 0.05;
    kill 'INT', $ENV{TEST_OWNER};
}
while (1) {
    open my $heartbeat, '>', "$ENV{TEST_ROOT}/$kind-heartbeat" or die $!;
    print {$heartbeat} time;
    close $heartbeat;
    sleep 0.02;
}
SSH
        sudo => <<'SUDO',
exit 0 if $ARGV[0] eq '-v';
shift @ARGV if $ARGV[0] eq '-n';
exec @ARGV;
die $!;
SUDO
        scutil => <<'SCUTIL',
local $/; <STDIN>;
print "  PrimaryService : test-service\n  UserDefinedName : Test Network\n";
SCUTIL
        osascript => <<'OSA',
use Time::HiRes qw(sleep);
local $/; <STDIN>;
my $action = $ARGV[3];
if ($action eq 'save') {
    open my $snapshot, '>', $ARGV[5] or die $!;
    print {$snapshot} 'saved';
    close $snapshot;
}
open my $marker, '>', "$ENV{TEST_ROOT}/$action" or die $!;
close $marker;
if ($action eq 'enable' && $ENV{TEST_INTERRUPT}) {
    sleep 0.05;
    kill 'INT', $ENV{TEST_OWNER};
}
OSA
    );
    for my $name ( keys %mocks ) {
        write_file( "$directory/bin/$name", '#!' . perl_executable() . "\n" . $mocks{$name} );
        chmod 0755, "$directory/bin/$name";
    }
    $self->{env} = {
        %ENV,
        PATH      => "$directory/bin:$ENV{PATH}",
        TMPDIR    => $directory,
        TEST_ROOT => $directory,
    };
}

sub run_tunnel {
    my ( $self, $phase, $interrupt ) = @_;
    my $started = time;
    my $result  = run_command(
        [ 'sh', '-c', 'export TEST_OWNER=$$; exec "$@"', 'sh', $program, '-D', 'example.invalid' ],
        { env => { %{ $self->{env} }, TEST_PHASE => $phase, TEST_INTERRUPT => $interrupt }, timeout => 8 }
    );
    $result->{elapsed} = time - $started;
    for my $kind (qw(master setup)) {
        my $heartbeat = "$self->{directory}/$kind-heartbeat";
        next unless -f $heartbeat;
        my $before = read_file($heartbeat);
        sleep 0.1;
        is( read_file($heartbeat), $before, "$kind SSH process stops when the tunnel closes" );
    }
    return $result;
}

sub interrupt_authentication {
    my ($self) = @_;
    my $result = run_tunnel( $self, 'auth', 1 );
    is( $result->{returncode}, 0, 'Ctrl-C during authentication succeeds' );
    cmp_ok( $result->{elapsed}, '<', 2, 'authentication cancellation is prompt' );
}

sub interrupt_forwarding_setup {
    my ($self) = @_;
    my $result = run_tunnel( $self, 'forward', 1 );
    is( $result->{returncode}, 0, 'Ctrl-C during forwarding setup succeeds' );
    cmp_ok( $result->{elapsed}, '<', 2, 'forwarding cancellation does not wait for the setup deadline' );
}

sub forwarding_deadline_stops_children {
    my ($self) = @_;
    my $result = run_tunnel( $self, 'forward', 0 );
    is( $result->{returncode}, 124, 'forwarding timeout status is preserved' );
    like( $result->{stderr}, qr/forwarding timed out after 5s/, 'the deadline is reported' );
}

sub interrupt_restores_proxy {
    my ($self) = @_;
    my $result = run_tunnel( $self, 'proxy', 1 );
    is( $result->{returncode}, 0, 'Ctrl-C with an active proxy succeeds' );
    ok( -f "$self->{directory}/restore", 'active proxy settings are restored' );
}

run_cases(
    {
        interrupt_authentication           => \&interrupt_authentication,
        interrupt_forwarding_setup         => \&interrupt_forwarding_setup,
        forwarding_deadline_stops_children => \&forwarding_deadline_stops_children,
        interrupt_restores_proxy           => \&interrupt_restores_proxy,
    },
    \&setup
);
