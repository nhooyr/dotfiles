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
        $runner =~ s{(        \$active\{\$pid\} = \$log;)}{
        sleep .01 until -e "\$FindBin::Bin/../release";
$1} or die 'could not hold the fork-registration boundary';
        write_file( "$temporary/ci/test.pl", $runner );
    }
    write_file( "$temporary/tests/test_slow.t", <<'PERL' );
use strict; use warnings; use FindBin; use lib $FindBin::Bin; use TestHelpers;
if (($ARGV[0] // '') eq '--list') { print "slow\n"; exit; }
write_file("$FindBin::Bin/worker.pid", $$);
if (-e "$FindBin::Bin/stubborn") {
    $SIG{TERM} = 'IGNORE';
    my $count = 0;
    while (1) {
        write_file("$FindBin::Bin/beat.next", ++$count);
        rename "$FindBin::Bin/beat.next", "$FindBin::Bin/beat" or die $!;
        select undef, undef, undef, .01;
    }
}
if (-e "$FindBin::Bin/nested") {
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
    write_file( "$temporary/tests/nested",   '' ) if $nested;
    write_file( "$temporary/tests/stubborn", '' ) if $stubborn;
    my $runner = fork();
    die "fork: $!" unless defined $runner;

    if ( !$runner ) {
        open STDOUT, '>',  "$temporary/log" or die $!;
        open STDERR, '>&', \*STDOUT         or die $!;
        exec "$temporary/ci/test.pl", 'test_slow';
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

sub cleans_discovery_and_worker_environments {
    my $temporary = tempdir( 'ci-environment-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$temporary/ci", "$temporary/tests", "$temporary/bin", "$temporary/ambient-home" );
    copy_preserve( "$root/ci/test.pl",           "$temporary/ci/test.pl" );
    copy_preserve( "$root/tests/TestHelpers.pm", "$temporary/tests/TestHelpers.pm" );
    write_file( "$temporary/bin/clean-env-tool", "#!/bin/sh\nexit 0\n" );
    chmod 0755, "$temporary/bin/clean-env-tool";
    my $path = "$temporary/bin:$ENV{PATH}";
    write_file( "$temporary/tests/expected-path",      $path );
    write_file( "$temporary/tests/test_environment.t", <<'PERL' );
use strict; use warnings; use FindBin; use lib $FindBin::Bin; use TestHelpers;
for my $name (qw(AQSNOW_DIRALIS GIT_DIR EDITOR SSH_AUTH_SOCK HOMEBREW_PREFIX DOTFILES_TEST_POISON)) {
    die "$name leaked into the test environment\n" if exists $ENV{$name};
}
die "HOME was inherited\n" if $ENV{HOME} eq "$FindBin::Bin/../ambient-home";
die "HOME is not isolated\n" unless -d $ENV{HOME};
for my $name (qw(XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME)) {
    die "$name is not isolated\n" unless defined $ENV{$name} && index($ENV{$name}, "$ENV{HOME}/") == 0;
}
die "PATH changed\n" unless $ENV{PATH} eq read_file("$FindBin::Bin/expected-path");
die "locale is not deterministic\n" unless $ENV{LANG} eq 'C' && $ENV{LC_ALL} eq 'C';
die "terminal was inherited\n" unless $ENV{TERM} eq 'dumb';
run_command(['clean-env-tool'], { check => 1 });
my $phase = ($ARGV[0] // '') eq '--list' ? 'discovery' : 'worker';
write_file("$FindBin::Bin/$phase", $ENV{HOME});
if ($phase eq 'discovery') { print "clean\n"; exit; }
print "1..1\nok 1 - clean environment\n";
PERL
    my %env = (
        %ENV,
        PATH                 => $path,
        HOME                 => "$temporary/ambient-home",
        XDG_CONFIG_HOME      => "$temporary/ambient-config",
        XDG_CACHE_HOME       => "$temporary/ambient-cache",
        XDG_DATA_HOME        => "$temporary/ambient-data",
        XDG_STATE_HOME       => "$temporary/ambient-state",
        AQSNOW_DIRALIS       => 'LEAKED',
        GIT_DIR              => "$temporary/wrong-repository",
        EDITOR               => 'false',
        SSH_AUTH_SOCK        => "$temporary/agent",
        HOMEBREW_PREFIX      => "$temporary/homebrew",
        DOTFILES_TEST_POISON => 'present',
        LANG                 => 'POSIX',
        LC_ALL               => 'POSIX',
        TERM                 => 'unexpected-terminal',
    );
    my $result =
      run_command( [ "$temporary/ci/test.pl", 'test_environment' ], { env => \%env } );
    is( $result->{returncode}, 0, "the runner supplies a clean environment: $result->{stderr}" );
    ok( -s "$temporary/tests/discovery", 'test discovery uses the clean environment' );
    ok( -s "$temporary/tests/worker",    'test execution uses the clean environment' );
}

run_cases(
    {
        cleans_discovery_and_worker_environments => \&cleans_discovery_and_worker_environments,
        interrupt_stops_active_tests             => sub { stops_active_tests( 'INT',  130 ) },
        terminate_stops_active_tests             => sub { stops_active_tests( 'TERM', 143 ) },
        hangup_stops_active_tests                => sub { stops_active_tests( 'HUP',  129 ) },
        terminate_stops_nested_helpers           => sub { stops_active_tests( 'TERM', 143, 1 ) },
        interrupt_stops_term_ignoring_tests      => sub { stops_active_tests( 'INT',  130, 0, 1 ) },
        interrupt_during_fork_registration       => sub { stops_active_tests( 'INT',  130, 0, 0, 1 ) },
    }
);
