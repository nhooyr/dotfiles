#!/usr/bin/env perl
use strict;
use warnings;
use Cwd            qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(__FILE__);
use FairSchedule qw(schedule window_days);
use File::Copy   qw(copy);
use File::Temp   qw(tempfile);
use List::Util   qw(max);
use POSIX        qw(floor);

if ( @ARGV && $ARGV[0] eq '--todo' ) {
    @ARGV == 3                 or die "Usage: fair_sort.pl --todo ORDER TODO\n";
    copy( $ARGV[1], $ARGV[2] ) or die "fair: cannot write rebase order: $!\n";
    exit;
}
if ( @ARGV && $ARGV[0] eq '--redate' ) {
    @ARGV == 2 && $ARGV[1] =~ /\A\@\d+ [+-]\d{4}\z/
      or die "Usage: fair_sort.pl --redate DATE\n";
    local $ENV{GIT_AUTHOR_DATE}    = $ARGV[1];
    local $ENV{GIT_COMMITTER_DATE} = $ARGV[1];
    git_run( 'commit', '--amend', '--no-edit', '--allow-empty', '--only', '--date', $ARGV[1] );
    exit;
}
@ARGV == 0 or die "Usage: fair_sort.pl\n";

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

git_output( 'symbolic-ref', '--quiet', 'HEAD' );
my @commits;
my $count = 0;
my $day   = 24 * 60 * 60;
my %days;
for my $line ( split /\n/,
    git_output( 'log', '--reverse', '--topo-order', '--format=%H %at %ad %s', '--date=format:%z', 'HEAD' ) )
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
            map { shell_quote($_) } $^X,
            abs_path($0), '--redate', "\@$commit->{date} $commit->{zone}" ),
          "\n";
    }
    close $order or die "fair: cannot write rebase order: $!\n";
    local $ENV{GIT_SEQUENCE_EDITOR} = join ' ', map { shell_quote($_) } $^X, abs_path($0), '--todo',
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
