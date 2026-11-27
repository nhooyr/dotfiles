use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use POSIX       qw(WNOHANG);
use Time::HiRes qw(time sleep);

my $super = absolute_path("$FindBin::Bin/../bin/super");
my $perl  = perl_executable();

sub setup {
    my ($self) = @_;
    $self->{root} = tempdir( 'super-test-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
}

sub help_and_errors {
    my ($self) = @_;
    for my $flag ( '-h', '--help' ) {
        my $result = run_command( [ $super, $flag ] );
        is( $result->{returncode}, 0, "$flag succeeds" );
        like( $result->{stdout}, qr/^Usage: super /, 'usage is printed' );
        is( $result->{stderr}, '', 'help has no diagnostics' );
    }
    my $missing = run_command( [ $super, "$self->{root}/missing" ] );
    is( $missing->{returncode}, 127, 'missing command returns 127' );
    like( $missing->{stderr}, qr/super: exec .*missing/, 'missing command is diagnosed' );
}

sub arguments_streams_and_status {
    my $result = run_command(
        [
            $super, '--', $perl, '-e',
            'print join(q{|}, @ARGV), qq{\n}, scalar(<STDIN>); print STDERR qq{error\n}; exit 7',
            'two words', '$(exit 9)', ''
        ],
        { input => "input\n" }
    );
    is(
        $result->{stdout},
        "two words|\$(exit 9)|\ninput\n",
        'arguments and input pass through without a shell'
    );
    is( $result->{stderr},     "error\n", 'stderr passes through' );
    is( $result->{returncode}, 7,         'command exit status is preserved' );
    my $signal = run_command( [ $super, $perl, '-e', 'kill q{TERM}, $$; sleep 10' ] );
    is( $signal->{returncode}, 143, 'command signal status is preserved' );
}

sub immediate_commands_keep_their_exit_status {
    my %active;
    my %statuses;
    my $reap = sub {
        my $pid = wait();
        die "wait: $!" if $pid == -1;
        ++$statuses{$?};
        delete $active{$pid};
    };
    for ( 1 .. 2000 ) {
        my $pid = fork();
        die "fork: $!" unless defined $pid;
        if ( !$pid ) {
            exec {$super} $super, '/bin/sh', '-c', 'exit 7' or POSIX::_exit(127);
        }
        $active{$pid} = 1;
        $reap->() if keys(%active) == 8;
    }
    $reap->() while %active;
    is_deeply(
        \%statuses,
        { 7 << 8 => 2000 },
        'fast commands retain their status while process groups are established'
    );
}

sub wait_until {
    my ( $condition, $seconds ) = @_;
    my $deadline = time + $seconds;
    until ( $condition->() ) {
        return 0 if time >= $deadline;
        sleep 0.01;
    }
    return 1;
}

{

    package SuperTestJob;

    sub DESTROY {
        my ($self) = @_;
        if ( $self->{pid} ) {
            kill 'TERM', $self->{pid};
            waitpid( $self->{pid}, 0 );
        }
        if ( -f "$self->{root}/group" ) {
            my $group = TestHelpers::read_file("$self->{root}/group");
            kill 'KILL', -$group;
        }
    }
}

sub start_job {
    my ( $self, $finish, $orphan ) = @_;
    my $script = <<'CHILD';
use strict;
use warnings;
use Time::HiRes qw(sleep);
my ($root, $finish) = @ARGV;
open my $group, '>', "$root/group" or die $!;
print {$group} $$;
close $group;
my $child = fork();
defined $child or die $!;
if (!$child) {
    $SIG{TERM} = sub {};
    my $count = 0;
    while (1) {
        open my $beat, '>', "$root/beat" or die $!;
        print {$beat} ++$count;
        close $beat;
        sleep 0.02;
    }
}
until (-s "$root/beat") { sleep 0.01 }
exit 7 if $finish;
waitpid($child, 0);
CHILD
    my $pid = fork();
    die $! unless defined $pid;
    if ( !$pid ) {
        if ($orphan) {
            my $supervisor = fork();
            die $! unless defined $supervisor;
            if ($supervisor) {
                open my $file, '>', "$self->{root}/supervisor" or die $!;
                print {$file} $supervisor;
                close $file;
                sleep 60;
                POSIX::_exit(0);
            }
        }
        open STDIN,  '<', '/dev/null'            or die $!;
        open STDOUT, '>', "$self->{root}/stdout" or die $!;
        open STDERR, '>', "$self->{root}/stderr" or die $!;
        exec {$super} $super, $perl, '-e', $script, $self->{root}, $finish or POSIX::_exit(127);
    }
    my $job = bless { pid => $pid, root => $self->{root} }, 'SuperTestJob';
    ok( wait_until( sub { -s "$self->{root}/beat" }, 2 ), 'command and stubborn descendant start' )
      or die 'command did not start';
    return $job;
}

sub wait_job {
    my ( $job, $seconds ) = @_;
    my $status;
    ok(
        wait_until(
            sub {
                my $result = waitpid( $job->{pid}, WNOHANG );
                return 0 if !$result;
                die $!   if $result == -1;
                $status = $?;
                delete $job->{pid};
                return 1;
            },
            $seconds
        ),
        'supervisor exits promptly'
    ) or die 'supervisor did not exit';
    return $status >> 8;
}

sub heartbeat_stops {
    my ($self) = @_;
    my $path = "$self->{root}/beat";
    sleep 0.1;
    my $before = read_file($path);
    sleep 0.15;
    is( read_file($path), $before, 'stubborn descendant stops writing' );
}

sub completion_cleans_descendants {
    my ($self) = @_;
    my $job = start_job( $self, 1, 0 );
    is( wait_job( $job, 1 ), 7, 'completion retains command status' );
    heartbeat_stops($self);
}

sub signals_clean_descendants {
    my ($self) = @_;
    my $job = start_job( $self, 0, 0 );
    kill 'TERM', $job->{pid};
    is( wait_job( $job, 1 ), 143, 'termination returns signal status' );
    heartbeat_stops($self);
}

sub parent_exit_cleans_descendants {
    my ($self) = @_;
    my $job = start_job( $self, 0, 1 );
    kill 'KILL', $job->{pid};
    waitpid( $job->{pid}, 0 );
    delete $job->{pid};
    my $before = read_file("$self->{root}/beat");
    ok(
        wait_until(
            sub {
                sleep 0.15;
                my $after   = read_file("$self->{root}/beat");
                my $stopped = $after eq $before;
                $before = $after;
                return $stopped;
            },
            3
        ),
        'parent death stops the command and descendant'
    );
    heartbeat_stops($self);
}

run_cases(
    {
        help_and_errors                           => \&help_and_errors,
        arguments_streams_and_status              => \&arguments_streams_and_status,
        immediate_commands_keep_their_exit_status => \&immediate_commands_keep_their_exit_status,
        completion_cleans_descendants             => \&completion_cleans_descendants,
        signals_clean_descendants                 => \&signals_clean_descendants,
        parent_exit_cleans_descendants            => \&parent_exit_cleans_descendants,
    },
    \&setup
);
