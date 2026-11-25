#!/usr/bin/env perl
use strict;
use warnings;
use List::Util  qw(min max sum);
use POSIX       qw(strftime);
use Time::Local qw(timelocal_modern);
use Time::Piece;

sub git_output {
    open my $pipe, '-|', 'git', @_ or die "fair: cannot run git: $!\n";
    local $/;
    my $output = <$pipe> // '';
    close $pipe or die "fair: git @_ failed\n";
    return $output;
}

sub daily_counts {
    my %counts;
    ++$counts{ substr( $_, 0, 10 ) } for split /\n/, git_output( 'log', '--format=%aI', 'HEAD' );
    return \%counts;
}

sub day_key {
    return strftime( '%Y-%m-%d', gmtime( $_[0] ) );
}

if ( @ARGV && $ARGV[0] eq '--check-day' ) {
    @ARGV == 2 && $ARGV[1] =~ /\A[0-9]{1,5}\z/ && $ARGV[1] >= 1
      or die "Usage: fair_dates.pl --check-day COUNT (1..99999)\n";
    my $ident = git_output( 'var', 'GIT_AUTHOR_IDENT' );
    $ident =~ / (\d+) ([+-])(\d{2})(\d{2})\s*\z/ or die "fair: invalid author date\n";
    my ( $timestamp, $sign, $hours, $minutes ) = ( $1, $2, $3, $4 );
    my $date   = day_key( $timestamp + ( $sign eq '+' ? 1 : -1 ) * ( $hours * 3600 + $minutes * 60 ) );
    my $counts = daily_counts();
    die "fair: $date cannot exceed 128 commits per day\n"
      if ( $counts->{$date} // 0 ) + $ARGV[1] > 128;
    print "\@$timestamp $sign$hours$minutes\n";
    exit;
}

sub parse_date {
    my ($value) = @_;
    my $error = "fair: --date1 and --date2 must be YYYY-MM-DD dates\n";
    die $error unless $value =~ /\A\d{4}-\d{2}-\d{2}\z/;
    my $date = eval { Time::Piece->strptime( $value, '%Y-%m-%d' ) };

    # strptime normalizes invalid days, so reject dates it changes.
    die $error unless defined($date) && $date->ymd eq $value;
    return timelocal_modern( 0, 0, 0, $date->mday, $date->mon - 1, $date->year );
}

# Floyd sampling uses bounded memory even for a long range or a nearly full window.
sub sample_seconds {
    my ( $lo, $hi, $count ) = @_;
    my %selected;
    for my $upper ( $hi - $count + 1 .. $hi ) {
        my $candidate = $lo + int( rand( $upper - $lo + 1 ) );
        $selected{ exists( $selected{$candidate} ) ? $upper : $candidate } = 1;
    }
    return keys %selected;
}

@ARGV == 3 && $ARGV[2] =~ /\A[0-9]{1,5}\z/ && $ARGV[2] >= 1
  or die "Usage: fair_dates.pl DATE1 DATE2 COUNT (1..99999)\n";
my ( $date1, $date2, $count ) = @ARGV;
my ( $start, $end ) = ( parse_date($date1), parse_date($date2) );
die "fair: --date1 must be on or after the Unix epoch\n" if $start < 0;
die "fair: --date2 must be after --date1\n"              if $end <= $start;
die "fair: date range must allow at least one second between commits\n"
  if $end - $start < $count - 1;

# Work backward to reserve enough daily capacity for every remaining commit.
my $day    = 24 * 60 * 60;
my $counts = daily_counts();
my ( @latest, %capacity, %remaining );

sub day_capacity {
    my ($date) = @_;
    return $capacity{$date} //= max( 0, 128 - ( $counts->{ day_key( $date * $day ) } // 0 ) );
}

my $last = $end;
for ( 1 .. $count ) {
    while (1) {
        die "fair: date range cannot fit $count commits with a limit of 128 commits per day\n"
          if $last < $start;
        my $date = int( $last / $day );
        $remaining{$date} //= day_capacity($date);
        if ( $remaining{$date} ) {
            --$remaining{$date};
            push @latest, $last--;
            last;
        }
        $last = int( $last / $day ) * $day - 1;
    }
}
@latest = reverse @latest;

sub print_capped_dates {
    my (@preferred) = @_;
    my ( @dates, %added );
    my $next = $start;
    for my $i ( 0 .. $#preferred ) {
        my $date     = max( $next, min( $preferred[$i], $latest[$i] ) );
        my $date_day = int( $date / $day );
        while ( ( $added{$date_day} // 0 ) >= day_capacity($date_day) ) {
            $date = ++$date_day * $day;
        }
        ++$added{$date_day};
        push @dates, $date;
        $next = $date + 1;
    }
    print "$_\n" for @dates;
}

if ( $count == 1 ) {
    print_capped_dates( int( ( $start + $end ) / 2 ) );
    exit;
}

my $quiet = 14 * $day;
my $span  = $end - $start;

# Aim for roughly 100 commits per burst, leaving two-week gaps when possible.
my $max_bursts = 1 + int( ( $span - $count + 1 ) / ( $quiet - 1 ) );
my $bursts =
  min( $count, max( 2, int( ( $count + 99 ) / 100 ) ), max( 2, $max_bursts ) );
$quiet = 1 if $max_bursts < 2;
my @sizes      = (1) x $bursts;
my @weights    = map { 0.25 + rand(1.5) } @sizes;
my $weight_sum = sum(@weights);
for ( 1 .. $count - $bursts ) {
    my $choice = rand($weight_sum);
    my $i      = 0;
    ++$i while $i < $#weights && ( $choice -= $weights[$i] ) >= 0;
    ++$sizes[$i];
}

my $extra = int( ( $span - ( $count - $bursts ) - $quiet * ( $bursts - 1 ) ) / ( 2 * $bursts ) );
my @widths =
  map { $_ - 1 + int( rand( max( 0, min( $day - $_, $extra ) ) + 1 ) ) } @sizes;
my $slack   = $span - sum(@widths) - $quiet * ( $bursts - 1 );
my @offsets = ( 0, ( sort { $a <=> $b } map { int( rand( $slack + 1 ) ) } 1 .. $bursts - 2 ), $slack );
my $cursor  = $start;
my @preferred;
for my $i ( 0 .. $#sizes ) {
    my $size = $sizes[$i];
    my ( $lo, $hi ) =
      ( $cursor + $offsets[$i], $cursor + $offsets[$i] + $widths[$i] );
    $cursor += $widths[$i] + $quiet;

    # Keep a burst on one UTC calendar day when its window has enough room.
    my $midnight = ( int( $lo / $day ) + 1 ) * $day;
    if ( $lo < $midnight && $midnight <= $hi ) {
        my @windows = ( [ $lo, $midnight - 1 ], [ $midnight, $hi ] );
        @windows = ( $windows[0] )  if $i == 0;
        @windows = ( $windows[-1] ) if $i == $#sizes;
        @windows = grep { $_->[1] - $_->[0] + 1 >= $size } @windows;
        ( $lo, $hi ) = @{ $windows[ int( rand(@windows) ) ] } if @windows;
    }
    my @fixed;
    push @fixed, $lo if $i == 0;
    push @fixed, $hi if $i == $#sizes;
    my @dates = sample_seconds( $lo + ( $i == 0 ), $hi - ( $i == $#sizes ), $size - @fixed );
    push @preferred, sort { $a <=> $b } ( @fixed, @dates );
}
print_capped_dates(@preferred);
