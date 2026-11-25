#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename qw(dirname);
use lib dirname(__FILE__);
use FairSchedule qw(schedule window_days);
use List::Util   qw(max);
use Time::Local  qw(timegm_modern timelocal_modern);
use Time::Piece;

sub parse_date {
    my ($value) = @_;
    my $error = "fair: --date1 and --date2 must be YYYY-MM-DD dates\n";
    die $error unless $value =~ /\A\d{4}-\d{2}-\d{2}\z/;
    my $date = eval { Time::Piece->strptime( $value, '%Y-%m-%d' ) };
    die $error unless defined($date) && $date->ymd eq $value;
    return timelocal_modern( 0, 0, 0, $date->mday, $date->mon - 1, $date->year );
}

my $recent = @ARGV == 2 && $ARGV[0] eq '--recent';
my $count  = $ARGV[-1] // '';
die "Usage: fair_dates.pl DATE1 DATE2 COUNT | --recent COUNT (1..99999)\n"
  unless ( $recent || @ARGV == 3 ) && $count =~ /\A[0-9]{1,5}\z/ && $count >= 1;
my $end   = $recent ? time                                         : parse_date( $ARGV[1] );
my $start = $recent ? max( 0, $end - window_days($count) * 86400 ) : parse_date( $ARGV[0] );
die "fair: --date1 must be on or after the Unix epoch\n"                if $start < 0;
die "fair: --date2 must be after --date1\n"                             if $end <= $start;
die "fair: date range must allow at least one second between commits\n" if $end - $start < $count - 1;

open my $log, '-|', 'git', 'log', '--format=%aI', 'HEAD' or die "fair: cannot run git: $!\n";
my %occupied;
while (<$log>) {
    my ( $year, $month, $day ) = /^(\d{4})-(\d\d)-(\d\d)/;
    ++$occupied{ int( timegm_modern( 0, 0, 0, $day, $month - 1, $year ) / 86400 ) };
}
close $log or die "fair: git log failed\n";
print "$_\n" for schedule( $start, $end, $count, \%occupied, $recent, $recent );
