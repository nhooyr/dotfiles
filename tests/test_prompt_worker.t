use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use POSIX       qw(WNOHANG);
use Time::HiRes qw(time sleep);

my $helper = absolute_path("$FindBin::Bin/../fish/git_prompt_supervisor.pl");
my $fish   = which('fish');

{

    package PromptWorkerJob;

    sub DESTROY {
        my ($self) = @_;
        return unless $self->{pid};

        # The direct child has not been reaped, so its process-group ID is reserved.
        kill 'KILL', -$self->{pid};
        kill 'KILL', $self->{pid};
        waitpid( $self->{pid}, 0 );
    }
}

sub setup {
    my ($self) = @_;
    $self->{temporary}  = tempdir( 'prompt-worker-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{root}       = absolute_path( $self->{temporary} );
    $self->{work}       = "$self->{root}/work";
    $self->{rendezvous} = "$self->{root}/rendezvous";
    $self->{prompt}     = "$self->{root}/prompt.fish";
    make_path( "$self->{work}/.git", $self->{rendezvous} );
    $self->{token}  = "$$-request";
    $self->{result} = "$self->{rendezvous}/vcs-prompt-$self->{token}";
    $self->{env}    = {
        %ENV,
        TEST_ROOT          => $self->{root},
        TEST_PERL          => perl_executable(),
        GIT_OPTIONAL_LOCKS => '1',
        XDG_CONFIG_HOME    => "$self->{root}/config",
        XDG_DATA_HOME      => "$self->{root}/data"
    };
    $self->{notifications} = 0;
    $SIG{USR1} = sub { ++$self->{notifications}; };
    write_file( "$self->{rendezvous}/vcs-alive", "$self->{token}\n" );
}

sub help_does_not_start_job {
    my ($self) = @_;
    for my $flag ( '-h', '--help' ) {
        my $result = run_command( [ $helper, $flag ], { env => $self->{env}, cwd => $self->{work} } );
        is( $result->{returncode}, 0, $result->{stderr} );
        like( $result->{stdout}, qr/^Usage: git_prompt_supervisor\.pl/, 'help describes the one-shot job' );
        is( $result->{stderr}, '', 'help does not report an error' );
    }
    ok( !-e $self->{result}, 'help does not create a prompt result' );
    is( $self->{notifications}, 0, 'help does not signal the parent' );
}

sub exec_helper {
    my ( $self, $parent ) = @_;
    chdir $self->{work} or die $!;
    %ENV = %{ $self->{env} };
    open STDIN,  '<', '/dev/null'                   or die $!;
    open STDOUT, '>', "$self->{root}/helper.stdout" or die $!;
    open STDERR, '>', "$self->{root}/helper.stderr" or die $!;
    exec {$helper} $helper, $self->{fish} // $fish, $self->{prompt},
      $self->{rendezvous},
      $self->{token}, $parent, $self->{work};
    die "exec helper: $!\n";
}

sub start_helper {
    my ($self) = @_;
    my $parent = $$;
    my $pid    = fork();
    die "fork: $!\n"              unless defined $pid;
    exec_helper( $self, $parent ) unless $pid;
    return bless { pid => $pid }, 'PromptWorkerJob';
}

sub wait_until {
    my ( $condition, $seconds ) = @_;
    my $deadline = time + $seconds;
    while ( !$condition->() ) {
        return 0 if time >= $deadline;
        sleep 0.01;
    }
    return 1;
}

sub wait_helper {
    my ( $job, $seconds ) = @_;
    return wait_until(
        sub {
            return 1 unless $job->{pid};
            my $result = waitpid( $job->{pid}, WNOHANG );
            if ( $result == $job->{pid} ) {
                $job->{status} = $?;
                delete $job->{pid};
                return 1;
            }
            die "waitpid: $!\n" if $result == -1;
            return 0;
        },
        $seconds
    );
}

sub finished_status {
    my ( $self, $job, $seconds ) = @_;
    ok( wait_helper( $job, $seconds ), 'helper finishes promptly' )
      or die "helper did not exit\n";
    is( $job->{status} & 127,                     9,  'private process group finishes with SIGKILL' );
    is( read_file("$self->{root}/helper.stderr"), '', 'helper has no diagnostics' );
    my ( $status, $identity ) = split /\s+/, read_file("$self->{result}.status");
    my @entry = stat( $self->{git_directory} // "$self->{work}/.git" );
    is( $identity, "$entry[0]:$entry[1]", 'status retains the original Git directory identity' )
      if $status != 75;
    return $status;
}

sub immediate_completion_and_optional_locks {
    my ($self) = @_;
    write_file( $self->{prompt}, <<'FISH' );
function aqsnow_vcs_prompt
    printf ' (fresh:%s)' "$GIT_OPTIONAL_LOCKS"
end
FISH
    my $started = time;
    my $job     = start_helper($self);
    is( finished_status( $self, $job, 1.5 ), '0', 'successful status is recorded' );
    cmp_ok( time - $started, '<', 1.5, 'completion does not wait for the two-second liveness interval' );
    is( $self->{notifications},       1,            'parent is notified immediately' );
    is( read_file( $self->{result} ), ' (fresh:0)', 'worker disables optional Git locks' );
    my @results = glob "$self->{rendezvous}/vcs-prompt-*";
    is_deeply(
        [ sort @results ],
        [ sort ( $self->{result}, "$self->{result}.status" ) ],
        'result and status both use the exact request token'
    );
}

sub failed_worker_notifies_with_failure_status {
    my ($self) = @_;
    write_file( $self->{prompt}, <<'FISH' );
function aqsnow_vcs_prompt
    printf ' (partial)'
    return 7
end
FISH
    my $job = start_helper($self);
    is( finished_status( $self, $job, 1.5 ), '7',          'worker exit failure is preserved' );
    is( $self->{notifications},              1,            'failed completion still notifies the parent' );
    is( read_file( $self->{result} ),        ' (partial)', 'partial output is separate from success status' );
}

sub failed_exec_notifies_with_failure_status {
    my ($self) = @_;
    $self->{fish} = "$self->{root}/missing-fish";
    my $job = start_helper($self);
    ok( wait_helper( $job, 1.5 ), 'failed exec finishes promptly' )
      or die "helper did not exit\n";
    is( $job->{status} & 127, 9, 'supervisor cleans its private group after failed exec' );
    cmp_ok( trim( read_file("$self->{result}.status") ), '!=', 0, 'failed exec produces a failing status' );
    is( $self->{notifications}, 1, 'failed exec still notifies the parent' );
    like( read_file("$self->{root}/helper.stderr"), qr/exec .*missing-fish/, 'exec failure is diagnosed' );
}

sub install_stubborn_worker {
    my ($self) = @_;
    write_file( "$self->{root}/stubborn.pl", <<'PERL' );
use strict;
use warnings;
use Time::HiRes qw(sleep);
$SIG{TERM} = sub {};
open my $ready, '>', "$ENV{TEST_ROOT}/ready" or die $!;
print {$ready} $$;
close $ready;
my $counter = 0;
while (1) {
    open my $heartbeat, '>', "$ENV{TEST_ROOT}/heartbeat" or die $!;
    print {$heartbeat} ++$counter;
    close $heartbeat;
    sleep 0.025;
}
PERL
    write_file( $self->{prompt}, <<'FISH' );
function aqsnow_vcs_prompt
    command "$TEST_PERL" "$TEST_ROOT/stubborn.pl"
end
FISH
}

sub ownership_loss_kills_stubborn_descendants {
    my ($self) = @_;
    install_stubborn_worker($self);
    my $job = start_helper($self);
    ok( wait_until( sub { -s "$self->{root}/ready" }, 2 ), 'stubborn descendant starts' )
      or die "worker did not start\n";
    write_file( "$self->{rendezvous}/vcs-alive", "different-request\n" );
    my $lost_at = time;
    ok( wait_helper( $job, 2.75 ), 'ownership loss stops helper within the liveness interval' )
      or die "ownership loss did not stop helper\n";
    cmp_ok( time - $lost_at, '<', 2.75, 'cancellation is bounded' );
    is( $job->{status} & 127, 9, 'cancellation kills the private group' );
    my $heartbeat = read_file("$self->{root}/heartbeat");
    sleep 0.15;
    is( read_file("$self->{root}/heartbeat"), $heartbeat, 'TERM-ignoring descendant is stopped' );
    is( $self->{notifications},               0,          'obsolete request sends no completion signal' );
    ok( !-e "$self->{result}.status", 'obsolete request publishes no status' );
}

sub parent_death_kills_stubborn_descendants {
    my ($self) = @_;
    install_stubborn_worker($self);
    my $owner = fork();
    die "fork owner: $!\n" unless defined $owner;
    if ( !$owner ) {
        $SIG{USR1} = 'IGNORE';
        my $parent = $$;
        my $worker = fork();
        die "fork helper: $!\n"       unless defined $worker;
        exec_helper( $self, $parent ) unless $worker;
        write_file( "$self->{root}/helper.pid", "$worker\n" );
        sleep 30;
        POSIX::_exit(1);
    }
    my $owner_job = bless { pid => $owner }, 'PromptWorkerJob';
    ok( wait_until( sub { -s "$self->{root}/ready" }, 2 ), 'descendant starts under a separate parent' )
      or die "worker did not start\n";
    kill 'KILL', $owner;
    ok( wait_helper( $owner_job, 1 ), 'test parent exits' );

    # The dead parent's ownership token deliberately remains in place. Reparenting
    # must be sufficient to stop the entire helper group without signalling us.
    sleep 2.25;
    my $heartbeat = read_file("$self->{root}/heartbeat");
    sleep 0.15;
    is( read_file("$self->{root}/heartbeat"), $heartbeat, 'parent death stops the TERM-ignoring descendant' );
    is( $self->{notifications},               0,          'dead parent produces no completion signal' );
    ok( !-e "$self->{result}.status", 'cancelled request publishes no status' );
}

sub status_write_failure_kills_stubborn_descendants {
    my ($self) = @_;
    install_stubborn_worker($self);
    write_file( $self->{prompt}, <<'FISH' );
function aqsnow_vcs_prompt
    command "$TEST_PERL" "$TEST_ROOT/stubborn.pl" &
    disown "$last_pid"
    for i in $(seq 1 100)
        test -s "$TEST_ROOT/ready"; and break
        command sleep 0.01
    end
    printf ' (fresh)'
end
FISH
    make_path("$self->{result}.status");
    my $ended = 0;
    local $SIG{CHLD} = sub { $ended = 1; };
    my $job = start_helper($self);
    ok( wait_until( sub { $ended }, 2 ), 'supervisor exits after status-file failure' )
      or die "helper did not exit\n";
    ok( -s "$self->{root}/ready", 'TERM-ignoring descendant started before the failure' );
    my $heartbeat = read_file("$self->{root}/heartbeat");
    sleep 0.15;
    is( read_file("$self->{root}/heartbeat"), $heartbeat, 'fatal supervisor error stops its descendants' );
    ok( wait_helper( $job, 0.5 ), 'failed supervisor is reaped' );
    is( $job->{status} & 127,   9, 'fatal error invokes process-group cleanup' );
    is( $self->{notifications}, 0, 'unpublished status does not signal a completion' );
    like(
        read_file("$self->{root}/helper.stderr"),
        qr/\.status: Is a directory/,
        'status-file error is diagnosed'
    );
}

sub replaced_git_directory_rejects_result {
    my ($self) = @_;
    write_file( $self->{prompt}, <<'FISH' );
function aqsnow_vcs_prompt
    printf started > "$TEST_ROOT/ready"
    while not test -f "$TEST_ROOT/release"
        command sleep 0.01
    end
    printf ' (old-repository)'
end
FISH
    my $job = start_helper($self);
    ok( wait_until( sub { -s "$self->{root}/ready" }, 2 ), 'worker observes the original repository' )
      or die "worker did not start\n";
    rename "$self->{work}/.git", "$self->{work}/.git-old" or die $!;
    make_path("$self->{work}/.git");
    write_file( "$self->{root}/release", 'go' );
    is( finished_status( $self, $job, 1.5 ),
        '75', 'same-path repository replacement invalidates the result' );
    is( $self->{notifications}, 1, 'parent is notified to retry the replaced repository' );
}

sub retargeted_git_file_rejects_result {
    my ($self) = @_;
    rename "$self->{work}/.git", "$self->{root}/old.git" or die $!;
    make_path("$self->{root}/new.git");
    write_file( "$self->{work}/.git", "gitdir: ../old.git\n" );
    my $inode = ( stat "$self->{work}/.git" )[1];
    write_file( $self->{prompt}, <<'FISH' );
function aqsnow_vcs_prompt
    printf started > "$TEST_ROOT/ready"
    while not test -f "$TEST_ROOT/release"
        command sleep 0.01
    end
    printf ' (old-repository)'
end
FISH
    my $job = start_helper($self);
    ok( wait_until( sub { -s "$self->{root}/ready" }, 2 ), 'worker starts with the original git-file target' )
      or die "worker did not start\n";
    write_file( "$self->{work}/.git", "gitdir: ../new.git\n" );
    is( ( stat "$self->{work}/.git" )[1], $inode, 'retargeting preserves the git file inode' );
    write_file( "$self->{root}/release", 'go' );
    is( finished_status( $self, $job, 1.5 ), '75', 'changed git-directory target invalidates the result' );
}

sub unchanged_git_file_keeps_result {
    my ($self) = @_;
    $self->{git_directory} = "$self->{root}/actual.git";
    rename "$self->{work}/.git", "$self->{root}/actual.git" or die $!;
    write_file( $self->{prompt}, <<'FISH' );
function aqsnow_vcs_prompt
    printf ' (unchanged)'
end
FISH
    for my $target ( '../actual.git', "$self->{root}/actual.git" ) {
        write_file( "$self->{work}/.git", "gitdir: $target\n" );
        my $job = start_helper($self);
        is( finished_status( $self, $job, 1.5 ), '0', 'an unchanged git-file target is accepted' );
    }
}

run_cases(
    {
        help_does_not_start_job                         => \&help_does_not_start_job,
        immediate_completion_and_optional_locks         => \&immediate_completion_and_optional_locks,
        failed_worker_notifies_with_failure_status      => \&failed_worker_notifies_with_failure_status,
        failed_exec_notifies_with_failure_status        => \&failed_exec_notifies_with_failure_status,
        ownership_loss_kills_stubborn_descendants       => \&ownership_loss_kills_stubborn_descendants,
        parent_death_kills_stubborn_descendants         => \&parent_death_kills_stubborn_descendants,
        status_write_failure_kills_stubborn_descendants => \&status_write_failure_kills_stubborn_descendants,
        replaced_git_directory_rejects_result           => \&replaced_git_directory_rejects_result,
        retargeted_git_file_rejects_result              => \&retargeted_git_file_rejects_result,
        unchanged_git_file_keeps_result                 => \&unchanged_git_file_keeps_result,
    },
    \&setup
);
