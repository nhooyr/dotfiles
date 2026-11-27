#!/usr/bin/env perl
use strict;
use warnings;
use Cwd          qw(abs_path);
use File::Copy   qw(copy);
use File::Temp   qw(tempfile);
use Getopt::Long qw(GetOptionsFromArray);
use List::Util   qw(min max sum);
use POSIX        qw(floor);
use Time::Local  qw(timegm_modern timelocal_modern);
use Time::Piece;

sub usage {
    return <<'HELP';
Usage: fair [COUNT] [--date1 YYYY-MM-DD --date2 YYYY-MM-DD]
       fair --sort
Create and push COUNT empty commits in $fair (default: 1; maximum: 99999).
Use natural-looking dates in the recent past, or within the supplied range.
With --sort, redistribute the dates of existing commits.

  -h, --help  Show this help.
HELP
}

sub main {
    my @args = @_;
    if ( @args && $args[0] eq '--todo' ) {
        shift @args;
        @args == 2                 or die "Usage: fair.pl --todo ORDER TODO\n";
        copy( $args[0], $args[1] ) or die "fair: cannot write rebase order: $!\n";
        return 0;
    }
    if ( @args && $args[0] eq '--redate' ) {
        shift @args;
        @args == 1 && $args[0] =~ /\A\@\d+ [+-]\d{4}\z/
          or die "Usage: fair.pl --redate DATE\n";
        local $ENV{GIT_AUTHOR_DATE}    = $args[0];
        local $ENV{GIT_COMMITTER_DATE} = $args[0];
        git_run( 'commit', '--amend', '--no-edit', '--allow-empty', '--only', '--date', $args[0] );
        return 0;
    }
    my ( $help, $sort, $date1, $date2 );
    Getopt::Long::Configure(qw(no_auto_abbrev no_ignore_case permute));
    GetOptionsFromArray(
        \@args,
        'h|help'  => \$help,
        'sort'    => \$sort,
        'date1=s' => \$date1,
        'date2=s' => \$date2
    ) or return 2;
    if ( @args > 1 || $sort && ( defined($date1) || defined($date2) ) ) {
        print STDERR usage();
        return 2;
    }
    if ($help) {
        print usage();
        return 0;
    }
    if ( $sort && @args ) {
        print STDERR "fair: --sort does not accept a count\n";
        return 2;
    }
    my $count = $args[0] // 1;
    if ( !$sort && ( $count !~ /\A[0-9]{1,5}\z/ || $count < 1 ) ) {
        print STDERR "fair: 1 <= n <= 99999\n";
        return 1;
    }
    if ( defined($date1) != defined($date2) ) {
        print STDERR "fair: --date1 and --date2 must be provided together\n";
        return 1;
    }
    unless ( chdir( $ENV{fair} // '' ) ) {
        print STDERR "fair: cannot enter repository: $!\n";
        return 1;
    }
    if ($sort) {
        sort_history();
        return 0;
    }
    my @dates =
      defined($date1)
      ? generate_dates( $date1, $date2, $count )
      : generate_dates( '--recent', $count );
    my ($counter) = git_output( 'show', '-s', '--format=%s' ) =~ /\Acount: ([0-9]+)\n?\z/;
    $counter //= 0;
    for my $date (@dates) {
        local $ENV{GIT_AUTHOR_DATE}    = "\@$date +0000";
        local $ENV{GIT_COMMITTER_DATE} = $ENV{GIT_AUTHOR_DATE};
        git_run( 'commit', '--allow-empty', '--only', '-m', 'count: ' . ++$counter );
    }
    git_run('push');
    return 0;
}

sub parse_date {
    my ($value) = @_;
    my $error = "fair: --date1 and --date2 must be YYYY-MM-DD dates\n";
    die $error unless $value =~ /\A\d{4}-\d{2}-\d{2}\z/;
    my $date = eval { Time::Piece->strptime( $value, '%Y-%m-%d' ) };
    die $error unless defined($date) && $date->ymd eq $value;
    return timelocal_modern( 0, 0, 0, $date->mday, $date->mon - 1, $date->year );
}

sub generate_dates {
    my @args   = @_;
    my $recent = @args == 2 && $args[0] eq '--recent';
    my $count  = $args[-1] // '';
    die "fair: expected DATE1 DATE2 COUNT or --recent COUNT (1..99999)\n"
      unless ( $recent || @args == 3 ) && $count =~ /\A[0-9]{1,5}\z/ && $count >= 1;
    my $end   = $recent ? time                                         : parse_date( $args[1] );
    my $start = $recent ? max( 0, $end - window_days($count) * 86400 ) : parse_date( $args[0] );
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
    return schedule( $start, $end, $count, \%occupied, $recent, $recent );
}

sub git_output {
    open my $pipe, '-|', 'git', @_ or die "fair: cannot run git: $!\n";
    local $/;
    my $output = <$pipe> // '';
    close $pipe or die "fair: git @_ failed\n";
    return $output;
}

sub shell_quote {
    my ($value) = @_;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub git_run {
    system 'git', @_;
    die "fair: cannot run git: $!\n" if $? == -1;
    my $status = $? & 127 ? 128 + ( $? & 127 ) : $? >> 8;
    exit $status if $status;
}

sub sort_history {
    git_output( 'symbolic-ref', '--quiet', 'HEAD' );
    my @commits;
    my $count = 0;
    my $day   = 24 * 60 * 60;
    my %days;
    for my $line (
        split /\n/,
        git_output(
            'log', '--reverse', '--topo-order', '--format=%H %at %ad %s', '--date=format:%z', 'HEAD'
        )
      )
    {
        my ( $id, $date, $zone, $subject ) = split / /, $line, 4;
        my ( $sign, $hours, $minutes ) = $zone =~ /\A([+-])(\d{2})(\d{2})\z/;
        my $offset       = ( $hours * 60 + $minutes ) * 60 * ( $sign eq '+' ? 1 : -1 );
        my $calendar_day = floor( ( $date + $offset ) / $day );
        $count = max( $count, $1 ) if defined($subject) && $subject =~ /\Acount: ([0-9]+)\z/;
        my $commit = {
            id            => $id,
            date          => $date,
            original_date => $date,
            zone          => $zone,
            subject       => $subject // '',
            order         => scalar @commits
        };
        push @commits,                  $commit;
        push @{ $days{$calendar_day} }, $commit;
    }
    my %daily_counts = map { $_ => scalar @{ $days{$_} } } keys %days;
    my $moved        = 0;
    my @crowded      = sort { $a <=> $b } grep { $daily_counts{$_} >= 64 } keys %days;
    while (@crowded) {
        my $last    = shift @crowded;
        my @cluster = @{ $days{$last} };
        $daily_counts{$last} = 0;
        while ( @crowded && $crowded[0] == $last + 1 ) {
            $last = shift @crowded;
            push @cluster, @{ $days{$last} };
            $daily_counts{$last} = 0;
        }
        @cluster = sort { $a->{date} <=> $b->{date} || $a->{order} <=> $b->{order} } @cluster;
        my $end   = $cluster[-1]{date};
        my $start = max( 0, $cluster[0]{date} - window_days( scalar @cluster ) * $day );
        my @dates = schedule( $start, $end, scalar @cluster, \%daily_counts, 0, 1 );
        for my $i ( 0 .. $#cluster ) {
            $cluster[$i]{date} = $dates[$i];
            $cluster[$i]{zone} = '+0000';
            ++$daily_counts{ int( $dates[$i] / $day ) };
            ++$moved if $dates[$i] != $cluster[$i]{original_date};
        }
    }
    my @sorted = sort { $a->{date} <=> $b->{date} || $a->{order} <=> $b->{order} } @commits;
    if ( !$moved && join( ' ', map { $_->{id} } @commits ) eq join( ' ', map { $_->{id} } @sorted ) ) {
        print "fair: history is already chronological\n";
    }
    else {
        die "fair: --sort requires a linear history\n"
          if git_output( 'rev-list', '--min-parents=2', 'HEAD' ) ne '';

        my ( $order, $order_path ) = tempfile( 'fair-order-XXXXXX', TMPDIR => 1, UNLINK => 1 );
        for my $commit (@sorted) {
            print {$order} "pick $commit->{id} $commit->{subject}\n";
            next if $commit->{date} == $commit->{original_date};
            print {$order} 'exec ',
              join( ' ',
                map { shell_quote($_) } abs_path($0),
                '--redate', "\@$commit->{date} $commit->{zone}" ),
              "\n";
        }
        close $order or die "fair: cannot write rebase order: $!\n";
        local $ENV{GIT_SEQUENCE_EDITOR} = join ' ', map { shell_quote($_) } abs_path($0), '--todo',
          $order_path;
        git_run(
            'rebase',          '--interactive',
            '--root',          '--keep-empty',
            '--empty=keep',    '--committer-date-is-author-date',
            '--no-autosquash', '--no-update-refs'
        );
    }

    my $date = max( time, map { $_->{date} } @commits );
    while ( ( $daily_counts{ floor( $date / $day ) } // 0 ) >= 128 ) {
        $date = ( floor( $date / $day ) + 1 ) * $day;
    }
    local $ENV{GIT_AUTHOR_DATE}    = "\@$date +0000";
    local $ENV{GIT_COMMITTER_DATE} = $ENV{GIT_AUTHOR_DATE};
    git_run( 'commit', '--allow-empty', '--only', '-m', "count: $count" );
}

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

exit main(@ARGV) unless caller;
1;
