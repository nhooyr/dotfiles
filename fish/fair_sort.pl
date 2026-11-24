#!/usr/bin/env perl
use strict;
use warnings;
use Cwd        qw(abs_path);
use File::Copy qw(copy);
use File::Temp qw(tempfile);
use List::Util qw(max);

if ( @ARGV && $ARGV[0] eq '--todo' ) {
    @ARGV == 3                 or die "Usage: fair_sort.pl --todo ORDER TODO\n";
    copy( $ARGV[1], $ARGV[2] ) or die "fair: cannot write rebase order: $!\n";
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
for my $line ( split /\n/, git_output( 'log', '--reverse', '--topo-order', '--format=%H %at %s', 'HEAD' ) ) {
    my ( $id, $date, $subject ) = split / /, $line, 3;
    $count = max( $count, $1 ) if defined($subject) && $subject =~ /\Acount: ([0-9]+)\z/;
    push @commits, { id => $id, date => $date, subject => $subject // '', order => scalar @commits };
}
my @sorted = sort { $a->{date} <=> $b->{date} || $a->{order} <=> $b->{order} } @commits;
if ( join( ' ', map { $_->{id} } @commits ) eq join( ' ', map { $_->{id} } @sorted ) ) {
    print "fair: history is already chronological\n";
}
else {
    die "fair: --sort requires a linear history\n"
      if git_output( 'rev-list', '--min-parents=2', 'HEAD' ) ne '';

    my ( $order, $order_path ) = tempfile( 'fair-order-XXXXXX', TMPDIR => 1, UNLINK => 1 );
    print {$order} "pick $_->{id} $_->{subject}\n" for @sorted;
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
local $ENV{GIT_AUTHOR_DATE}    = "\@$date +0000";
local $ENV{GIT_COMMITTER_DATE} = $ENV{GIT_AUTHOR_DATE};
git_run( 'commit', '--allow-empty', '--only', '-m', "count: $count" );
