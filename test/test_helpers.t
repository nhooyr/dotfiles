use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use POSIX       qw(WNOHANG);
use Time::HiRes qw(time sleep);

sub timeout_stops_descendants {
    my $temporary = tempdir( 'test-timeout-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    write_file( "$temporary/child.pl", <<'PERL' );
use strict;
use warnings;
use Time::HiRes qw(sleep);
$SIG{TERM} = 'IGNORE';
my $child = fork();
die $! unless defined $child;
if (!$child) {
    my $count = 0;
    while (1) {
        open my $beat, '>', "$ARGV[0]/heartbeat" or die $!;
        print {$beat} ++$count;
        close $beat;
        sleep 0.01;
    }
}
open my $pid, '>', "$ARGV[0]/pid" or die $!;
print {$pid} $child;
close $pid;
sleep 30;
PERL
    eval { run_command( [ perl_executable(), "$temporary/child.pl", $temporary ], { timeout => 1 } ) };
    my $error  = $@;
    my $pid    = read_file("$temporary/pid");
    my $before = read_file("$temporary/heartbeat");
    sleep 0.1;
    my $after = read_file("$temporary/heartbeat");
    kill 'KILL', $pid;
    like( $error, qr/Command timed out/, 'the timeout is reported' );
    is( $after, $before, 'a TERM-ignoring grandchild stops with its parent' );
}

sub interrupts_stop_commands {
    my $temporary = tempdir( 'test-signals-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    write_file( "$temporary/child.pl", <<'PERL' );
use strict; use warnings; use Time::HiRes qw(sleep);
my ($directory, $signal, $mode) = @ARGV;
$SIG{$signal} = $mode eq 'ignore' ? 'DEFAULT' : 'IGNORE';
open my $pid, '>', "$directory/pid" or die $!;
print {$pid} $$; close $pid;
my $count = 0;
while (1) {
    open my $beat, '>', "$directory/heartbeat" or die $!;
    print {$beat} ++$count; close $beat;
    sleep 0.01;
}
PERL
    write_file( "$temporary/runner.pl", <<'PERL' );
use strict; use warnings;
my ($module, $directory, $signal, $mode, $child) = @ARGV;
require "$module/TestHelpers.pm";
$SIG{$signal} = $mode eq 'callback' ? sub { exit 42 } : uc($mode);
my $result = TestHelpers::run_command([$^X, $child, $directory, $signal, $mode]);
open my $out, '>', "$directory/result" or die $!;
print {$out} $result->{returncode}; close $out;
PERL
    for my $case (
        [ INT  => 'default',  2 ],
        [ TERM => 'default',  15 ],
        [ HUP  => 'default',  1 ],
        [ TERM => 'callback', 42 << 8 ],
        [ INT  => 'ignore',   0 ]
      )
    {
        my ( $signal, $mode, $expected ) = @$case;
        my $directory = "$temporary/$signal-$mode";
        make_path($directory);
        my $pid = fork();
        die "fork: $!\n" unless defined $pid;
        if ( !$pid ) {
            open STDOUT, '>',  "$directory/log" or die $!;
            open STDERR, '>&', \*STDOUT         or die $!;
            exec perl_executable(), "$temporary/runner.pl", $FindBin::Bin, $directory,
              $signal, $mode, "$temporary/child.pl";
            die "exec: $!\n";
        }
        my $deadline = time + 3;
        sleep 0.01 until -s "$directory/heartbeat" || time > $deadline;
        ok( -s "$directory/heartbeat", "$signal command starts" );
        kill $signal, $pid;
        my $waited;
        sleep 0.01 until ( $waited = waitpid( $pid, WNOHANG ) ) != 0 || time > $deadline;
        my $status = $?;
        my $child  = -f "$directory/pid"       ? read_file("$directory/pid")       : 0;
        my $before = -f "$directory/heartbeat" ? read_file("$directory/heartbeat") : '';
        sleep 0.05;
        my $after = -f "$directory/heartbeat" ? read_file("$directory/heartbeat") : '';
        kill 'KILL', $child if $child;
        if ( !$waited ) { kill 'KILL', $pid; waitpid( $pid, 0 ); }
        is( $waited,          $pid,      "$signal with $mode handling finishes" );
        is( $status & 0xffff, $expected, "$signal preserves $mode exit handling" );
        is( $after,           $before,   "$signal leaves no running command" );
        is( -f "$directory/result" ? read_file("$directory/result") : 'missing',
            '-2', 'ignored parent signal still reaches the command' )
          if $mode eq 'ignore';
    }
}

run_cases(
    {
        timeout_stops_descendants => \&timeout_stops_descendants,
        interrupts_stop_commands  => \&interrupts_stop_commands,
    }
);
