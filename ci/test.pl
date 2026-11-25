#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../tests";
use TestHelpers    qw(run_command read_file);
use Getopt::Long   qw(GetOptions);
use File::Basename qw(basename);
use File::Temp     qw(tempdir);
use File::Spec;
use Time::HiRes qw(time sleep);
use POSIX       qw(SIG_BLOCK SIG_SETMASK SIGHUP SIGINT SIGTERM sigprocmask);

my $jobs = 8;
GetOptions( 'jobs|j=i' => \$jobs )
  or die "Usage: test.pl [-j JOBS] [test_selector ...]\n";
die "--jobs must be positive\n" if $jobs < 1;
my @selectors     = @ARGV;
my $home          = tempdir( 'dotfiles-test-home-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
my $original_home = $ENV{HOME} // $home;
%ENV = (
    PATH            => $ENV{PATH},
    HOME            => $home,
    TMPDIR          => $ENV{TMPDIR} // File::Spec->tmpdir(),
    XDG_CONFIG_HOME => "$home/.config",
    XDG_DATA_HOME   => "$home/.local/share",
    XDG_CACHE_HOME  => "$home/.cache",
    XDG_STATE_HOME  => "$home/.local/state",
    LANG            => 'C',
    LC_ALL          => 'C',
    TERM            => 'dumb',

    # Keep compiler downloads and installed Rustup toolchains available.
    CARGO_HOME  => $ENV{CARGO_HOME}  // "$original_home/.cargo",
    RUSTUP_HOME => $ENV{RUSTUP_HOME} // "$original_home/.rustup",
);
my @cargo = ( 'cargo', 'test', '--manifest-path', "$FindBin::Bin/../fzfp/Cargo.toml", '--locked' );

sub run_cargo {
    my $status = system( @cargo, @_ );
    exit 127                        if $status == -1;
    exit( 128 + ( $status & 127 ) ) if $status & 127;
    exit( $status >> 8 )            if $status;
}
run_cargo() unless @selectors;
my @tests;
my %matched;

for my $file ( sort glob "$FindBin::Bin/../tests/test_*.t" ) {
    my $module = basename( $file, '.t' );
    next
      if @selectors && !grep { $_ eq $module || index( $_, "$module." ) == 0 } @selectors;
    my $result = run_command( [ $^X, $file, '--list' ], { check => 1 } );
    for my $case ( split /\n/, $result->{stdout} ) {
        next
          if @selectors && !grep { $_ eq $module || $_ eq "$module.$case" } @selectors;
        $matched{$_} = 1
          for grep { $_ eq $module || $_ eq "$module.$case" } @selectors;
        push @tests, [ $file, $case ];
    }
}
my @rust;
if ( grep { !$matched{$_} } @selectors ) {
    open my $list, '-|', @cargo, '--', '--list' or die "cargo: $!\n";
    while (<$list>) {
        next unless /^(.+): test$/;
        my $name    = $1;
        my @matches = grep { $_ eq $name || index( $name, $_ . '::' ) == 0 } @selectors;
        next unless @matches;
        $matched{$_} = 1 for @matches;
        push @rust, $name;
    }
    close $list or die "Cargo test discovery failed\n";
}
die "Unknown test selector: $_\n" for grep { !$matched{$_} } @selectors;
run_cargo( '--', '--exact', @rust ) if @rust;
exit 0 unless @tests;
$jobs = @tests if $jobs > @tests;
printf STDERR "Running %d tests with %d workers\n", scalar(@tests), $jobs;
my $started = time;
my $logs    = tempdir( 'dotfiles-test-results-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
my ( %active, @failures );
my ( $completed, $skipped, $next ) = ( 0, 0, 0 );
my %exit_codes = ( INT => 130, TERM => 143, HUP => 129 );
my $interrupts = POSIX::SigSet->new( SIGHUP, SIGINT, SIGTERM );

for my $signal ( keys %exit_codes ) {
    $SIG{$signal} = sub {
        local @SIG{ keys %exit_codes } = ('IGNORE') x keys %exit_codes;
        for my $pid ( keys %active ) {
            kill( 'TERM', -$pid ) || kill( 'TERM', $pid );
        }
        if (%active) {

            # Let test helpers forward TERM to their own child groups first.
            sleep 0.5;
            kill 'KILL', -$_ for keys %active;
            kill 'KILL', $_  for keys %active;
            waitpid( $_, 0 ) for keys %active;
        }
        print STDERR "\nInterrupted\n";
        exit $exit_codes{$signal};
    };
}
while ( $next < @tests || %active ) {
    while ( $next < @tests && keys(%active) < $jobs ) {
        my ( $file, $case ) = @{ $tests[$next] };
        my $log = "$logs/$next.log";
        ++$next;
        my $mask = POSIX::SigSet->new;
        sigprocmask( SIG_BLOCK, $interrupts, $mask ) or die "block signals: $!\n";
        my $pid = fork();
        die "fork: $!\n" unless defined $pid;
        if ( !$pid ) {
            setpgrp( 0, 0 ) or die "setpgrp: $!\n";
            $SIG{$_} = 'DEFAULT' for keys %exit_codes;
            sigprocmask( SIG_SETMASK, $mask ) or die "restore signals: $!\n";
            open STDOUT, '>',  $log     or die "$log: $!\n";
            open STDERR, '>&', \*STDOUT or die $!;
            exec {$^X} $^X, $file, $case;
            die "exec $file: $!\n";
        }
        $active{$pid} = $log;
        sigprocmask( SIG_SETMASK, $mask ) or die "restore signals: $!\n";
    }
    my $pid    = wait();
    my $status = $?;
    my $output = read_file( delete $active{$pid} );
    ++$completed;
    my $skip = $output =~ /^ok \d+ - .*# SKIP /m;
    ++$skipped if $skip;
    print STDERR $status ? 'F' : $skip ? 's' : '.';
    push @failures, $output if $status;
}
print STDERR "\n";
print STDERR $_ for @failures;
printf STDERR "Ran %d tests in %.3fs\n", $completed,                  time - $started;
printf STDERR "%s%s\n",                  @failures ? 'FAILED' : 'OK', $skipped ? " (skipped=$skipped)" : '';
exit( @failures ? 1 : 0 );
