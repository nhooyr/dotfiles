#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../test";
use TestHelpers    qw(run_command read_file);
use Getopt::Long   qw(GetOptions);
use File::Basename qw(basename);
use File::Temp     qw(tempdir);
use Time::HiRes    qw(time);

my $jobs = 8;
GetOptions( 'jobs|j=i' => \$jobs )
  or die "Usage: test.pl [-j JOBS] [test_module[.test_case] ...]\n";
die "--jobs must be positive\n" if $jobs < 1;
my @selectors = @ARGV;
my @tests;
my %matched;
for my $file ( sort glob "$FindBin::Bin/../test/test_*.t" ) {
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
die "Unknown test selector: $_\n" for grep { !$matched{$_} } @selectors;
die "No tests selected\n" unless @tests;
$jobs = @tests if $jobs > @tests;
printf STDERR "Running %d tests with %d workers\n", scalar(@tests), $jobs;
my $started = time;
my $logs    = tempdir( 'dotfiles-test-results-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
my ( %active, @failures );
my ( $completed, $skipped, $next ) = ( 0, 0, 0 );
$SIG{INT} = sub {
    local $SIG{INT} = 'IGNORE';
    kill 'TERM', keys %active;
    waitpid( $_, 0 ) for keys %active;
    print STDERR "\nInterrupted\n";
    exit 130;
};
while ( $next < @tests || %active ) {
    while ( $next < @tests && keys(%active) < $jobs ) {
        my ( $file, $case ) = @{ $tests[$next] };
        my $log = "$logs/$next.log";
        ++$next;
        my $pid = fork();
        die "fork: $!\n" unless defined $pid;
        if ( !$pid ) {
            open STDOUT, '>',  $log     or die "$log: $!\n";
            open STDERR, '>&', \*STDOUT or die $!;
            exec {$^X} $^X, $file, $case;
            die "exec $file: $!\n";
        }
        $active{$pid} = $log;
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
