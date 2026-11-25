package FairSchedule;
use strict;
use warnings;
use Exporter 'import';
use List::Util qw(min max sum);
our @EXPORT_OK = qw(schedule window_days);

sub window_days { return max( 14, int( ( $_[0] + 7 ) / 8 ) ); }

sub schedule {
    my ( $start, $end, $count, $occupied, $single_at_end, $expand ) = @_;
    my $day     = 86400;
    my $earlier = max( 0, $start - max( window_days($count) * $day, $end - $start ) );
    my ( @days, @weights, @capacity, @amount, @dates );
    my ( $active, $quiet ) = ( 0, 0 );
    for my $date ( int( $start / $day ) .. int( $end / $day ) ) {
        if ( !$active && !$quiet ) {
            $active = 1 + int rand 5;
            $quiet  = 4 + int rand 11;
        }
        push @days, $date;
        push @weights, $active ? 0.5 + rand 2 : 0;
        $active ? --$active : --$quiet;
        my $seconds = min( $end, ( $date + 1 ) * $day - 1 ) - max( $start, $date * $day ) + 1;
        push @capacity, max( 0, min( $seconds, 128 - ( $occupied->{$date} // 0 ) ) );
        push @amount,   0;
    }
    if ( sum(@capacity) < $count ) {
        return schedule( $earlier, $end, $count, $occupied, $single_at_end, $expand )
          if $expand && $start > 0;
        die "fair: date range cannot fit $count commits with a limit of 128 commits per day\n";
    }

    # Roomy ranges use varied, lighter days instead of approaching the hard cap.
    my @lighter =
      map { min( $capacity[$_], max( 0, 16 + int( rand 33 ) - ( $occupied->{ $days[$_] } // 0 ) ) ) }
      0 .. $#days;
    if ( sum(@lighter) < $count && $expand && $start > 0 ) {
        return schedule( $earlier, $end, $count, $occupied, $single_at_end, $expand );
    }
    @capacity = @lighter if sum(@lighter) >= $count;

    my %reserved;
    my @anchors   = $count == 1 && $single_at_end ? ($end) : ();
    my $remaining = $count;
    for my $date (@anchors) {
        my $i = int( $date / $day ) - $days[0];
        next unless $capacity[$i];
        push @dates, $date;
        $reserved{$date} = 1;
        --$capacity[$i];
        --$remaining;
        $weights[$i] ||= 0.5 + rand 2;
    }

    # Keep quiet stretches unless the requested density needs those days too.
    my @quiet = map { $_->[1] }
      sort { $a->[0] <=> $b->[0] }
      map { [ rand, $_ ] } grep { !$weights[$_] } 0 .. $#days;
    while ( sum( map { $weights[$_] ? $capacity[$_] : 0 } 0 .. $#days ) < $remaining ) {
        $weights[ shift @quiet ] = 0.5 + rand 2;
    }
    while ($remaining) {
        my @available = grep { $capacity[$_] && $weights[$_] } 0 .. $#days;
        my $weight    = sum( @weights[@available] );
        my $before    = $remaining;
        for my $i (@available) {
            my $take = min( $capacity[$i], int( $before * $weights[$i] / $weight ) );
            $amount[$i]   += $take;
            $capacity[$i] -= $take;
            $remaining    -= $take;
        }
        next if $remaining < $before;

        # Random weighted rounding avoids giving every short batch the same days.
        for my $choice (
            sort { $a->[0] <=> $b->[0] }
            map  { [ -log( 1 - rand ) / $weights[$_], $_ ] } @available
          )
        {
            my $i = $choice->[1];
            ++$amount[$i];
            --$capacity[$i];
            last unless --$remaining;
        }
    }
    for my $i ( 0 .. $#days ) {
        my $lo = max( $start, $days[$i] * $day );
        my $hi = min( $end, ( $days[$i] + 1 ) * $day - 1 );
        while ( $amount[$i] ) {
            my $date = $lo + int rand( $hi - $lo + 1 );
            next if $reserved{$date}++;
            push @dates, $date;
            --$amount[$i];
        }
    }
    return sort { $a <=> $b } @dates;
}

1;
