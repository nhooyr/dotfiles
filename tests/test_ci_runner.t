use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use POSIX       qw(WNOHANG);
use Time::HiRes qw(time sleep);

my $root = absolute_path("$FindBin::Bin/..");

sub stops_active_tests {
    my ( $signal, $code, $nested, $stubborn, $fork_gap ) = @_;
    my $temporary = tempdir( 'ci-signal-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$temporary/ci", "$temporary/tests" );
    copy_preserve( "$root/ci/test.pl",           "$temporary/ci/test.pl" );
    copy_preserve( "$root/tests/TestHelpers.pm", "$temporary/tests/TestHelpers.pm" );
    if ($fork_gap) {
        my $runner = read_file("$temporary/ci/test.pl");
        $runner =~ s/(        \$active\{\$pid\} = \$log;)/
        sleep .01 until -e \$ENV{CI_TEST_RELEASE};
$1/ or die 'could not hold the fork-registration boundary';
        write_file( "$temporary/ci/test.pl", $runner );
    }
    write_file( "$temporary/tests/test_slow.t", <<'PERL' );
use strict; use warnings; use FindBin; use lib $FindBin::Bin; use TestHelpers;
if (($ARGV[0] // '') eq '--list') { print "slow\n"; exit; }
write_file("$FindBin::Bin/worker.pid", $$);
if ($ENV{CI_TEST_STUBBORN}) {
    $SIG{TERM} = 'IGNORE';
    my $count = 0;
    while (1) {
        write_file("$FindBin::Bin/beat.next", ++$count);
        rename "$FindBin::Bin/beat.next", "$FindBin::Bin/beat" or die $!;
        select undef, undef, undef, .01;
    }
}
if ($ENV{CI_TEST_NESTED}) {
    my $child = fork(); die $! unless defined $child;
    if ($child) { waitpid($child, 0); exit; }
    write_file("$FindBin::Bin/nested.pid", $$);
}
run_command([$^X, "$FindBin::Bin/beat.pl"], { timeout => 30 });
print "1..1\nok 1\n";
PERL
    write_file( "$temporary/tests/beat.pl", <<'PERL' );
use strict; use warnings; use FindBin; use Time::HiRes qw(sleep);
open my $pid, '>', "$FindBin::Bin/child.pid" or die $!; print {$pid} $$; close $pid;
my $count = 0;
while (1) {
    open my $beat, '>', "$FindBin::Bin/beat.next" or die $!;
    print {$beat} ++$count; close $beat;
    rename "$FindBin::Bin/beat.next", "$FindBin::Bin/beat" or die $!;
    sleep .01;
}
PERL
    my $runner = fork();
    die "fork: $!" unless defined $runner;

    if ( !$runner ) {
        open STDOUT, '>',  "$temporary/log" or die $!;
        open STDERR, '>&', \*STDOUT         or die $!;
        $ENV{CI_TEST_NESTED}   = $nested   // 0;
        $ENV{CI_TEST_STUBBORN} = $stubborn // 0;
        $ENV{CI_TEST_RELEASE}  = "$temporary/release";
        exec perl_executable(), "$temporary/ci/test.pl";
        die $!;
    }
    my $deadline = time + 3;
    sleep .01 until -s "$temporary/tests/beat" || time >= $deadline;
    ok( -s "$temporary/tests/beat", 'the test command starts' );
    kill $signal, $runner;
    write_file( "$temporary/release", '' ) if $fork_gap;
    my $finished;
    $deadline = time + 3;
    sleep .01 until ( $finished = waitpid( $runner, WNOHANG ) ) != 0 || time >= $deadline;
    my $status = $?;
    my $before = -f "$temporary/tests/beat" ? read_file("$temporary/tests/beat") : '';
    sleep .1;
    my $after  = -f "$temporary/tests/beat"       ? read_file("$temporary/tests/beat")       : '';
    my $worker = -f "$temporary/tests/worker.pid" ? read_file("$temporary/tests/worker.pid") : 0;
    my $child  = -f "$temporary/tests/child.pid"  ? read_file("$temporary/tests/child.pid")  : 0;
    my $helper = -f "$temporary/tests/nested.pid" ? read_file("$temporary/tests/nested.pid") : 0;
    kill 'TERM', $worker if $worker;
    kill 'TERM', $helper if $helper;
    kill 'KILL', -$child if $child;

    if ( !$finished ) {
        kill 'KILL', -$worker if $worker;
        kill 'KILL', $runner;
        waitpid( $runner, 0 );
    }
    is( $finished,    $runner, "$signal finishes the runner" );
    is( $status >> 8, $code,   "$signal retains its conventional exit status" );
    is( $after,       $before, "$signal stops descendant test commands" );
}

run_cases(
    {
        interrupt_stops_active_tests        => sub { stops_active_tests( 'INT',  130 ) },
        terminate_stops_active_tests        => sub { stops_active_tests( 'TERM', 143 ) },
        hangup_stops_active_tests           => sub { stops_active_tests( 'HUP',  129 ) },
        terminate_stops_nested_helpers      => sub { stops_active_tests( 'TERM', 143, 1 ) },
        interrupt_stops_term_ignoring_tests => sub { stops_active_tests( 'INT',  130, 0, 1 ) },
        interrupt_during_fork_registration  => sub { stops_active_tests( 'INT',  130, 0, 0, 1 ) },
    }
);
