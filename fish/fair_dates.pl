#!/usr/bin/env perl
use strict;
use warnings;
use List::Util qw(min max sum);
use Time::Local qw(timegm_modern timelocal_modern);

sub parse_date {
    my ($value) = @_;
    my ($year, $month, $day, $hour, $minute, $second, $zone, $sign, $zone_hour, $zone_minute) =
        $value =~ /\A(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|([+-])(\d{2}):?(\d{2}))?)?\z/;
    my $error = "fair: --date1 and --date2 must be ISO 8601 dates or timestamps\n";
    die $error unless defined($year) && $year >= 1;
    die $error if defined($sign) && ($zone_hour > 23 || $zone_minute > 59);
    my @parts = ($second // 0, $minute // 0, $hour // 0, $day, $month - 1, $year);
    my $timestamp = eval { defined($zone) ? timegm_modern(@parts) : timelocal_modern(@parts) };
    die $error if $@;
    if (defined $sign) {
        $timestamp -= ($sign eq "+" ? 1 : -1) * ($zone_hour * 3600 + $zone_minute * 60);
    }
    return $timestamp;
}

# Floyd sampling uses bounded memory even for a long range or a nearly full window.
sub sample_seconds {
    my ($lo, $hi, $count) = @_;
    my %selected;
    for my $upper ($hi - $count + 1 .. $hi) {
        my $candidate = $lo + int(rand($upper - $lo + 1));
        $selected{exists($selected{$candidate}) ? $upper : $candidate} = 1;
    }
    return keys %selected;
}

@ARGV == 3 && $ARGV[2] =~ /\A[0-9]{1,4}\z/ && $ARGV[2] >= 1
    or die "Usage: fair_dates.pl DATE1 DATE2 COUNT (1..9999)\n";
my ($date1, $date2, $count) = @ARGV;
my ($start, $end) = (parse_date($date1), parse_date($date2));
die "fair: --date1 must be on or after the Unix epoch\n" if $start < 0;
die "fair: --date2 must be after --date1\n" if $end <= $start;
die "fair: date range must allow at least one second between commits\n" if $end - $start < $count - 1;
if ($count == 1) {
    print int(($start + $end) / 2), "\n";
    exit;
}

my $day = 24 * 60 * 60;
my $quiet = 14 * $day;
my $span = $end - $start;
# Aim for roughly 100 commits per burst, leaving two-week gaps when possible.
my $max_bursts = 1 + int(($span - $count + 1) / ($quiet - 1));
my $bursts = min($count, max(2, int(($count + 99) / 100)), max(2, $max_bursts));
$quiet = 1 if $max_bursts < 2;
my @sizes = (1) x $bursts;
my @weights = map { 0.25 + rand(1.5) } @sizes;
my $weight_sum = sum(@weights);
for (1 .. $count - $bursts) {
    my $choice = rand($weight_sum);
    my $i = 0;
    ++$i while $i < $#weights && ($choice -= $weights[$i]) >= 0;
    ++$sizes[$i];
}

my $extra = int(($span - ($count - $bursts) - $quiet * ($bursts - 1)) / (2 * $bursts));
my @widths = map { $_ - 1 + int(rand(min($day - $_, $extra) + 1)) } @sizes;
my $slack = $span - sum(@widths) - $quiet * ($bursts - 1);
my @offsets = (0, (sort { $a <=> $b } map { int(rand($slack + 1)) } 1 .. $bursts - 2), $slack);
my $cursor = $start;
for my $i (0 .. $#sizes) {
    my $size = $sizes[$i];
    my ($lo, $hi) = ($cursor + $offsets[$i], $cursor + $offsets[$i] + $widths[$i]);
    $cursor += $widths[$i] + $quiet;
    # Keep a burst on one UTC calendar day when its window has enough room.
    my $midnight = (int($lo / $day) + 1) * $day;
    if ($lo < $midnight && $midnight <= $hi) {
        my @windows = ([$lo, $midnight - 1], [$midnight, $hi]);
        @windows = ($windows[0]) if $i == 0;
        @windows = ($windows[-1]) if $i == $#sizes;
        @windows = grep { $_->[1] - $_->[0] + 1 >= $size } @windows;
        ($lo, $hi) = @{$windows[int(rand(@windows))]} if @windows;
    }
    my @fixed;
    push @fixed, $lo if $i == 0;
    push @fixed, $hi if $i == $#sizes;
    my @dates = sample_seconds($lo + ($i == 0), $hi - ($i == $#sizes), $size - @fixed);
    print "$_\n" for sort { $a <=> $b } (@fixed, @dates);
}
