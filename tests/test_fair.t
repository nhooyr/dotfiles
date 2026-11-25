# Burst scheduling and argument validation regression tests for fair.
use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $FISH     = which("fish");
my $GIT      = which("git");
my $PERL     = which("perl");
my $DOTFILES = ancestors( absolute_path(__FILE__) )->[1];
my $DATES    = join_path( join_path( $DOTFILES, "fish" ), "fair_dates.pl" );

sub setUp {
    my ($self) = @_;
    my ( $key, $value );
    $self->{temporary} = tempdir( "fair-tests-" . "XXXXXX", TMPDIR => 1, CLEANUP => 1 );
    $self->{root}      = absolute_path( $self->{temporary} );
    $self->{repo}      = join_path( $self->{root}, "repo" );
    $self->{env}       = {
        map { my $key = ($_)->[0]; my $value = ($_)->[1]; ( $key => $value ) }
        grep {
            my $key   = ($_)->[0];
            my $value = ($_)->[1];
            0 + ( !( ( index( $key, "GIT_" ) == 0 ) ) )
        } @{ [ map { [ $_, ( \%ENV )->{$_} ] } sort keys %{ ( \%ENV ) } ] }
    };
    do {
        my $updates = {
            "GIT_CONFIG_GLOBAL"   => "/dev/null",
            "GIT_CONFIG_NOSYSTEM" => "1",
            "GIT_AUTHOR_NAME"     => "Regression Test",
            "GIT_AUTHOR_EMAIL"    => "test\@example.invalid",
            "GIT_COMMITTER_NAME"  => "Regression Test",
            "GIT_COMMITTER_EMAIL" => "test\@example.invalid",
            "GIT_EDITOR"          => "true",
            "GIT_PAGER"           => "cat",
            "XDG_CONFIG_HOME"     => join_path( $self->{root}, "config" ),
            "XDG_DATA_HOME"       => join_path( $self->{root}, "data" ),
            "XDG_CACHE_HOME"      => join_path( $self->{root}, "cache" ),
            "TEST_FAIR_REPO"      => $self->{repo},
            "TEST_DOTFILES"       => $DOTFILES,
            "TZ"                  => "UTC"
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    git( $self, [ "init", "--quiet", "--initial-branch=main", $self->{repo} ], $self->{root} );
    git( $self, [ "commit", "--quiet", "--allow-empty", "-m", "count: 40" ], undef );
    $self->{initial} =
      trim( git( $self, [ "rev-parse", "HEAD" ], undef )->{stdout} );
}

sub git {
    my ( $self, $args, $cwd ) = @_;
    return run_command(
        [ $GIT, @{$args} ],
        {
            "cwd"     => ( $cwd || $self->{repo} ),
            "env"     => $self->{env},
            "check"   => 1,
            "timeout" => 10
        }
    );
}

sub fair {
    my ( $self, $args, $cwd, $after, $timeout ) = @_;
    my ($script);
    $script = (
        (
            'set -p fish_function_path "$TEST_DOTFILES/fish/functions"
function git
    if test "$argv[1]" = push
        return 0
    end
    command git $argv
end
function cdc
    set -l previous_dir "$PWD"
    cd -- "$argv[1]"; or return
    $argv[2..-1]
    set -l code "$status"
    cd -- "$previous_dir"; or return
    return "$code"
end
set -g fair "$TEST_FAIR_REPO"
set -g dotfiles "$TEST_DOTFILES"
set -l starting_dir "$PWD"
fair $argv; or exit
'
        )
        . $after
    );
    return run_command(
        [ $FISH, "--no-config", "-c", $script, "--", @{$args} ],
        {
            "cwd"     => ( $cwd || $self->{repo} ),
            "env"     => $self->{env},
            "timeout" => $timeout // 15
        }
    );
}

sub commits {
    my ($self) = @_;
    my ( $author, $committer, $line, $lines, $subject );
    $lines = [
        split(
            /\n/,
            git( $self, [ "log", "--reverse", "--format=%s%x09%at%x09%ct", ( $self->{initial} . "..HEAD" ) ],
                undef )->{stdout}
        )
    ];
    return [
        map {
            my $subject   = ($_)->[0];
            my $author    = ($_)->[1];
            my $committer = ($_)->[2];
            [ $subject, int($author), int($committer) ]
        } @{ [ map { my $line = $_; split_literal( $line, "\t" ) } @{$lines} ] }
    ];
}

sub assert_success {
    my ( $self, $result ) = @_;
    ( is_deeply( $result->{returncode}, 0, $result->{stderr} ) or die "assertion failed\n" );
}

sub test_dated_commits_stay_ordered_in_range_and_set_both_dates {
    my ($self) = @_;
    my ( $ignored, $author, $commit, $commits, $committer, $dates, $end, $left, $n, $right, $start );
    assert_success( $self,
        fair( $self, [ "6", "--date1", "2024-01-01", "--date2", "2024-01-06" ], undef, "" ) );
    $commits = commits($self);
    (
        is_deeply(
            [ map { my $commit = $_; $commit->[0] } @{$commits} ],
            [ map { my $n      = $_; ( "count: " . $n ) } @{ [ 41 .. ( 47 - 1 ) ] } ]
          )
          or die "assertion failed\n"
    );
    $start = int( iso_epoch("2024-01-01T00:00:00+00:00") );
    $end   = int( iso_epoch("2024-01-06T00:00:00+00:00") );
    $dates = [
        map {
            my $unused_1 = ($_)->[0];
            my $author   = ($_)->[1];
            my $unused_2 = ($_)->[2];
            $author
        } @{$commits}
    ];
    ( is_deeply( $dates->[0],      $start ) or die "assertion failed\n" );
    ( is_deeply( $dates->[ -(1) ], $end )   or die "assertion failed\n" );
    (
        ok(
            (
                0 + !(
                    grep { !$_ } @{
                        [
                            map {
                                my $left  = ($_)->[0];
                                my $right = ($_)->[1];
                                ( ( $left < $right ) )
                            } @{ zip_lists( $dates, array_slice( $dates, 1, undef ) ) }
                        ]
                    }
                )
            )
          )
          or die "assertion failed\n"
    );

    for my $item_95 ( @{$commits} ) {
        $ignored   = ($item_95)->[0];
        $author    = ($item_95)->[1];
        $committer = ($item_95)->[2];
        ( is_deeply( $author, $committer ) or die "assertion failed\n" );
        ( cmp_ok( $start,  "<=", $author ) or die "assertion failed\n" );
        ( cmp_ok( $author, "<=", $end )    or die "assertion failed\n" );
    }
}

sub test_date_flags_before_count {
    my ($self) = @_;
    my ( $ignored, $author, $end, $start, $value );
    $start = "2024-01-02";
    $end   = "2024-01-03";
    assert_success( $self, fair( $self, [ "--date1", $start, "--date2", $end, "2" ], undef, "" ) );
    (
        is_deeply(
            [
                map {
                    my $unused_3 = ($_)->[0];
                    my $author   = ($_)->[1];
                    my $unused_4 = ($_)->[2];
                    $author
                } @{ commits($self) }
            ],
            [ map { my $value = $_; int( iso_epoch("${value}T00:00:00Z") ) } @{ [ $start, $end ] } ]
          )
          or die "assertion failed\n"
    );
}

sub test_only_exact_counter_subjects_are_continued {
    my ($self) = @_;
    for my $subject ( 'Release: 7', 'recount: 7' ) {
        git( $self, [ 'commit', '--quiet', '--allow-empty', '-m', $subject ], undef );
        assert_success( $self, fair( $self, [], undef, '' ) );
        is( trim( git( $self, [ 'show', '-s', '--format=%s' ], undef )->{stdout} ),
            'count: 1', 'unrelated numeric subjects do not change the counter' );
    }
}

sub test_date_only_values_use_local_timezone_and_forward_arguments {
    my ($self) = @_;
    my ( $ignored, $author, $value );
    $self->{env}->{"TZ"} = "America/Vancouver";
    assert_success( $self,
        fair( $self, [ "--date1=2024-01-01", "2", "--date2=2024-01-02" ], $self->{root}, "" ) );
    (
        is_deeply(
            [
                map {
                    my $unused_5 = ($_)->[0];
                    my $author   = ($_)->[1];
                    my $unused_6 = ($_)->[2];
                    $author
                } @{ commits($self) }
            ],
            [
                map { my $value = $_; int( iso_epoch($value) ) }
                  @{ [ "2024-01-01T00:00:00-08:00", "2024-01-02T00:00:00-08:00" ] }
            ]
          )
          or die "assertion failed\n"
    );
}

sub test_single_commit_defaults_to_midpoint {
    my ($self) = @_;
    my ($midpoint);
    assert_success( $self, fair( $self, [ "--date1", "2024-01-01", "--date2", "2024-01-02" ], undef, "" ) );
    $midpoint = int( iso_epoch("2024-01-01T12:00:00+00:00") );
    ( is_deeply( commits($self), [ [ "count: 41", $midpoint, $midpoint ] ] ) or die "assertion failed\n" );
}

sub test_local_midnight_bounds_follow_daylight_saving_time {
    my ($self) = @_;
    $self->{env}{TZ} = 'America/Vancouver';
    assert_success( $self,
        fair( $self, [ "2", "--date1", "2024-03-10", "--date2", "2024-03-11" ], undef, "" ) );
    my @dates = map { $_->[1] } @{ commits($self) };
    is_deeply(
        \@dates,
        [ iso_epoch('2024-03-10T00:00:00-08:00'), iso_epoch('2024-03-11T00:00:00-07:00') ],
        'each date means midnight in the local timezone'
    );
    is( $dates[1] - $dates[0], 23 * 3600, 'the spring transition spans 23 hours' );
}

sub test_missing_invalid_or_reversed_dates_do_not_make_commits {
    my ($self) = @_;
    my ( $args, $cases, $result );
    $cases = [
        [ "--date1", "2024-01-01" ],
        [ "--date2", "2024-01-02" ],
        [ "--date1", "",           "--date2", "2024-01-02" ],
        [ "--date1", "invalid",    "--date2", "2024-01-02" ],
        [ "--date1", "2024-02-30", "--date2", "2024-03-01" ],
        [ "--date1", "1969-12-31", "--date2", "2024-01-01" ],
        [ "--date1", "2024-01-02", "--date2", "2024-01-01" ],
        [ "--date1", "2024-01-01", "--date2", "2024-01-01" ],
        ["0"],
        ["100000"],
        ["invalid"],
        [ "1", "2" ],
        ["--unknown"]
    ];
    for $args ( @{$cases} ) {
        {
            $result =
              fair( $self, array_slice( [ @{$args} ], 0, undef ), undef, "" );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            ( ok( ( $result->{stderr} ) ) or die "assertion failed\n" );
            (
                is_deeply( trim( git( $self, [ "rev-parse", "HEAD" ], undef )->{stdout} ), $self->{initial} )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_dated_commits_restore_inherited_dates_for_next_call {
    my ($self) = @_;
    my ( $commits, $result );
    do {
        my $updates = {
            "GIT_AUTHOR_DATE"    => "\@1700000000 +0000",
            "GIT_COMMITTER_DATE" => "\@1700000010 +0000"
        };
        @{ $self->{env} }{ keys %$updates } = values %$updates;
    };
    $result = fair(
        $self, [ "2", "--date1", "2024-01-01", "--date2", "2024-01-02" ],
        undef, '
test "$GIT_AUTHOR_DATE" = \'@1700000000 +0000\'; or exit 91
test "$GIT_COMMITTER_DATE" = \'@1700000010 +0000\'; or exit 92
fair
'
    );
    assert_success( $self, $result );
    $commits = commits($self);
    ( is_deeply( scalar( @{$commits} ), 3 )                                    or die "assertion failed\n" );
    ( is_deeply( $commits->[ -(1) ], [ "count: 43", 1700000000, 1700000010 ] ) or die "assertion failed\n" );
}

sub test_without_dates_keeps_default_and_explicit_counts {
    my ($self) = @_;
    my ( $ignored, $after, $author, $before, $commits, $committer, $subject );
    $before = int( time() );
    assert_success( $self, fair( $self, [],    undef, "" ) );
    assert_success( $self, fair( $self, ["2"], undef, "" ) );
    $after   = int( time() );
    $commits = commits($self);
    (
        is_deeply(
            [
                map {
                    my $subject   = ($_)->[0];
                    my $unused_9  = ($_)->[1];
                    my $unused_10 = ($_)->[2];
                    $subject
                } @{$commits}
            ],
            [ "count: 41", "count: 42", "count: 43" ]
          )
          or die "assertion failed\n"
    );

    for my $item_174 ( @{$commits} ) {
        $ignored   = ($item_174)->[0];
        $author    = ($item_174)->[1];
        $committer = ($item_174)->[2];
        ( cmp_ok( $before, "<=", $author ) or die "assertion failed\n" );
        ( cmp_ok( $author, "<=", $after )  or die "assertion failed\n" );
        ( is_deeply( $author, $committer ) or die "assertion failed\n" );
    }
}

sub test_sort_rejects_count_and_date_flags {
    my ($self) = @_;
    for my $args (
        [ '--sort',  '2' ],
        [ '2',       '--sort' ],
        [ '--sort',  '--date1',    '2024-01-01' ],
        [ '--date1', '2024-01-01', '--date2', '2024-01-02', '--sort' ],
      )
    {
        my $result = fair( $self, $args, undef, '' );
        isnt( $result->{returncode}, 0, 'sort rejects count and date arguments' );
        is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
            $self->{initial}, 'invalid sort leaves HEAD unchanged' );
    }
}

sub test_sort_stays_in_repository {
    my ($self) = @_;
    assert_success( $self,
        fair( $self, ['--sort'], $self->{root}, 'test "$PWD" -ef "$TEST_FAIR_REPO"; or exit 91' ) );
    assert_success( $self,
        fair( $self, ['1'], $self->{root}, 'test "$PWD" -ef "$starting_dir"; or exit 92' ) );
}

sub commit_at {
    my ( $self, $timestamp, $message, @args ) = @_;
    local $self->{env}{GIT_COMMITTER_DATE} = '@' . ( $timestamp + 60 ) . ' +0000';
    git( $self,
        [ 'commit', '--quiet', '--allow-empty', '--date', "\@$timestamp +0000", '-m', $message, @args ],
        undef );
}

sub seed_commits {
    my ( $self, $timestamp, $count, $offset ) = @_;
    $offset //= '+0000';
    my $parent = trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} );
    my $input  = '';
    for my $i ( 1 .. $count ) {
        my $message = "Seed commit $i\n";
        $input .=
            "commit refs/heads/main\nmark :$i\n"
          . "author Regression Test <test\@example.invalid> $timestamp $offset\n"
          . "committer Regression Test <test\@example.invalid> $timestamp $offset\n" . 'data '
          . length($message)
          . "\n$message"
          . "from $parent\n\n";
        $parent = ":$i";
    }
    run_command( [ $GIT, 'fast-import', '--quiet' ],
        { cwd => $self->{repo}, env => $self->{env}, input => $input, check => 1, timeout => 10 } );
}

sub assert_daily_limit {
    my ($timestamps) = @_;
    my $counts = count_values( [ map { int( $_ / 86400 ) } @$timestamps ] );
    cmp_ok( max( values %$counts ), '<=', 128, 'every UTC calendar day stays within 128 commits' );
}

sub test_ordinary_calls_enforce_remaining_daily_capacity {
    my ($self) = @_;
    seed_commits( $self, time, 126 );
    my $head   = trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} );
    my $result = fair( $self, ['2'], undef, '' );
    isnt( $result->{returncode}, 0, 'an ordinary batch cannot cross the daily limit' );
    like( $result->{stderr}, qr/128 commits per day/, 'the rejection explains the hard limit' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $head, 'an oversized batch creates no partial commits' );
    assert_success( $self, fair( $self, [], undef, '' ) );
    $head   = trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} );
    $result = fair( $self, [], undef, '' );
    isnt( $result->{returncode}, 0, 'a repeated default call cannot add the 129th commit' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $head, 'the full day remains unchanged' );
}

sub test_inherited_author_date_uses_its_recorded_day {
    my ($self) = @_;
    my $timestamp = iso_epoch('2024-01-02T01:00:00+14:00');
    seed_commits( $self, $timestamp, 128, '+1400' );
    $self->{env}{GIT_AUTHOR_DATE} = "\@$timestamp +1400";
    my $head   = trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} );
    my $result = fair( $self, [], undef, '' );
    isnt( $result->{returncode}, 0, 'an inherited author date cannot exceed its calendar day limit' );
    like( $result->{stderr}, qr/128 commits per day/, 'the rejection explains the hard limit' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $head, 'the inherited-date rejection creates no commit' );
}

sub test_ordinary_call_keeps_the_day_checked_before_midnight {
    my ($self)  = @_;
    my $checked = iso_epoch('2024-01-01T23:59:59Z');
    my $full    = iso_epoch('2024-01-02T00:00:00Z');
    seed_commits( $self, $full, 128 );
    my $bin = "$self->{root}/bin";
    make_path($bin);
    write_file( "$bin/git", <<'PERL' );
#!/usr/bin/env perl
use strict;
use warnings;
if (@ARGV == 2 && $ARGV[0] eq 'var' && $ARGV[1] eq 'GIT_AUTHOR_IDENT') {
    print "Regression Test <test\@example.invalid> $ENV{TEST_FAIR_CHECKED} +0000\n";
    exit;
}
$ENV{GIT_AUTHOR_DATE} = "\@$ENV{TEST_FAIR_FULL} +0000" if $ARGV[0] eq 'commit';
exec {$ENV{TEST_REAL_GIT}} $ENV{TEST_REAL_GIT}, @ARGV;
die "Cannot run git: $!\n";
PERL
    chmod 0755, "$bin/git" or die "Cannot make git wrapper executable: $!\n";
    $self->{env}{PATH}              = "$bin:$self->{env}{PATH}";
    $self->{env}{TEST_REAL_GIT}     = $GIT;
    $self->{env}{TEST_FAIR_CHECKED} = $checked;
    $self->{env}{TEST_FAIR_FULL}    = $full;
    assert_success( $self, fair( $self, [], undef, '' ) );
    is( trim( git( $self, [ 'show', '-s', '--format=%at' ], undef )->{stdout} ),
        $checked, 'the commit uses the author date checked before midnight' );
    my $counts = count_values(
        [ map { substr( $_, 0, 10 ) } split /\n/, git( $self, [ 'log', '--format=%aI' ], undef )->{stdout} ]
    );
    is( $counts->{'2024-01-02'}, 128, 'crossing midnight does not add a 129th commit to the full day' );
}

sub test_repeated_dated_batches_enforce_remaining_capacity {
    my ($self) = @_;
    my $args = [ '128', '--date1', '2024-01-01', '--date2', '2024-01-02' ];
    assert_success( $self, fair( $self, $args, undef, '' ) );
    assert_daily_limit( [ map { $_->[1] } @{ commits($self) } ] );
    my $head   = trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} );
    my $result = fair( $self, $args, undef, '' );
    isnt( $result->{returncode}, 0, 'an overlapping batch accounts for the previous call' );
    like( $result->{stderr}, qr/128 commits per day/, 'the range rejection explains the hard limit' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $head, 'an impossible dated batch creates no partial commits' );
}

sub all_commit_metadata {
    my ($self) = @_;
    return [
        map {
            my @fields = split /\0/,
              git( $self, [ 'show', '-s', '--format=%B%x00%at%x00%ct', $_ ], undef )->{stdout};
            [ $fields[0], 0 + $fields[1], 0 + $fields[2] ]
        } split /\n/,
        git( $self, [ 'rev-list', '--reverse', 'HEAD' ], undef )->{stdout}
    ];
}

sub test_sort_orders_entire_branch {
    my ($self) = @_;
    my $start = iso_epoch('2024-01-01T00:00:00Z');
    commit_at( $self, $start + 4 * 86400, 'count: 40', '--amend' );
    write_file( "$self->{repo}/late.txt", "late patch\n" );
    git( $self, [ 'add', 'late.txt' ], undef );
    commit_at( $self, $start + 3 * 86400, "Late patch\n\nKeep this message body." );
    commit_at( $self, $start,             'count: 41' );
    write_file( "$self->{repo}/early.txt", "early patch\n" );
    git( $self, [ 'add', 'early.txt' ], undef );
    commit_at( $self, $start + 86400,     'Early patch' );
    commit_at( $self, $start + 2 * 86400, 'count: 99' );
    commit_at( $self, $start + 2 * 86400, 'count: 43' );
    my $before   = all_commit_metadata($self);
    my $expected = [ map { [ $before->[$_][0], $before->[$_][1], $before->[$_][1] ] } ( 2, 3, 4, 5, 1, 0 ) ];
    my $tree     = trim( git( $self, [ 'rev-parse', 'HEAD^{tree}' ], undef )->{stdout} );
    my $started  = time;
    assert_success( $self, fair( $self, ['--sort'], $self->{root}, '' ) );
    my $sorted = all_commit_metadata($self);
    my $marker = pop @$sorted;
    is_deeply( $sorted, $expected, 'every commit is sorted stably with messages and author dates preserved' );
    is( $marker->[0], "count: 99\n", 'sort appends the highest existing counter' );
    cmp_ok( $marker->[1], '>=', $started, 'counter author date is current' );
    is( $marker->[2], $marker->[1], 'counter author and committer dates match' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD^{tree}' ], undef )->{stdout} ),
        $tree, 'independent patches preserve the final tree' );
    my $head = trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} );
    assert_success( $self, fair( $self, ['--sort'], undef, '' ) );
    isnt( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $head, 'sorting an ordered branch still appends a new commit' );
    my $again = all_commit_metadata($self);
    is( pop(@$again)->[0], "count: 99\n", 'the new marker keeps the current maximum counter' );
    is_deeply( $again, [ @$expected, $marker ], 'the ordered commits are otherwise unchanged' );
    assert_success( $self, fair( $self, [], undef, '' ) );
    is( trim( git( $self, [ 'show', '-s', '--format=%s' ], undef )->{stdout} ),
        'count: 100', 'ordinary fair continues from the maximum counter' );
}

sub test_sort_initializes_counter_and_preserves_index {
    my ($self) = @_;
    my $future = time + 3600;
    commit_at( $self, $future, 'count: 999 extra', '--amend' );
    my $before = all_commit_metadata($self);
    my $tree   = trim( git( $self, [ 'rev-parse', 'HEAD^{tree}' ], undef )->{stdout} );
    write_file( "$self->{repo}/pending.txt", "keep staged\n" );
    git( $self, [ 'add', 'pending.txt' ], undef );
    my $index = trim( git( $self, ['write-tree'], undef )->{stdout} );
    assert_success( $self, fair( $self, ['--sort'], undef, '' ) );
    my $after  = all_commit_metadata($self);
    my $marker = pop @$after;
    is_deeply( $after, $before, 'an already ordered branch keeps existing commits' );
    is( $marker->[0], "count: 0\n", 'only exact counter subjects contribute to the maximum' );
    cmp_ok( $marker->[1], '>=', $future, 'counter date does not precede a future-dated commit' );
    is( $marker->[2], $marker->[1], 'counter dates stay aligned' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD^{tree}' ], undef )->{stdout} ),
        $tree, 'counter commit is empty' );
    is( trim( git( $self, ['write-tree'], undef )->{stdout} ), $index, 'staged changes remain in the index' );
}

sub test_sort_rejects_merge_history {
    my ($self) = @_;
    my $start = iso_epoch('2024-01-01T00:00:00Z');
    commit_at( $self, $start + 3 * 86400, 'count: 40', '--amend' );
    git( $self, [ 'branch', 'side' ], undef );
    commit_at( $self, $start, 'Main commit' );
    git( $self, [ 'checkout', '--quiet', 'side' ], undef );
    commit_at( $self, $start + 86400, 'Side commit' );
    git( $self, [ 'checkout', '--quiet', 'main' ], undef );
    git( $self, [ 'merge', '--quiet', '--no-ff', 'side', '-m', 'Merge side' ], undef );
    my $head   = trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} );
    my $result = fair( $self, ['--sort'], undef, '' );
    isnt( $result->{returncode}, 0, 'sort rejects out-of-order merge history' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $head, 'merge rejection leaves HEAD unchanged' );
}

sub assert_crowded_sort_repaired {
    my ( $self, $out_of_order ) = @_;
    write_file( "$self->{repo}/preserved.txt", "keep this tree\n" );
    git( $self, [ 'add', 'preserved.txt' ], undef );
    git( $self, [ 'commit', '--quiet', '--amend', '--no-edit' ], undef );
    seed_commits( $self, iso_epoch('2035-07-04T12:00:00Z'), $out_of_order ? 300 : 384 );
    commit_at( $self, iso_epoch('2024-01-01T12:00:00Z'), 'Older commit' ) if $out_of_order;
    my @before = split /\0\n?/, git( $self, [ 'log', '--reverse', '--format=%B%x00' ], undef )->{stdout};
    my $tree   = trim( git( $self, [ 'rev-parse', 'HEAD^{tree}' ], undef )->{stdout} );

    # Rebase hundreds of commits even when other CI workers are busy.
    assert_success( $self, fair( $self, ['--sort'], undef, '', 60 ) );
    my @after = split /\0\n?/, git( $self, [ 'log', '--reverse', '--format=%B%x00' ], undef )->{stdout};
    my @dates = split /\n/,    git( $self, [ 'log', '--reverse', '--format=%at' ],    undef )->{stdout};
    is( scalar(@after), scalar(@before) + 1, 'sorting preserves every commit and appends one marker' );
    assert_daily_limit( \@dates );
    is( pop(@after), "count: 40\n", 'the redistributed history retains the highest counter' );
    my $marker_date = pop @dates;

    if ( !$out_of_order ) {
        is( $marker_date, iso_epoch('2035-07-06T00:00:00Z'), 'the marker moves beyond the full latest day' );
        my $counts = count_values( [ map { int( $_ / 86400 ) } @dates ] );
        is_deeply(
            [ map { $counts->{ int( iso_epoch("2035-07-0${_}T00:00:00Z") / 86400 ) } } 3 .. 5 ],
            [ 128, 128, 128 ],
            'the original and both neighboring days each contain 128 commits'
        );
    }
    is_deeply( [ sort @after ], [ sort @before ], 'redistribution preserves every commit message' );
    ok( !grep( { $dates[ $_ - 1 ] > $dates[$_] } 1 .. $#dates ), 'redistributed commits stay chronological' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD^{tree}' ], undef )->{stdout} ),
        $tree, 'redistribution preserves the final tree' );
}

sub test_sort_rebalances_crowded_ordered_history {
    my ($self) = @_;
    assert_crowded_sort_repaired( $self, 0 );
}

sub test_sort_rebalances_crowded_unordered_history {
    my ($self) = @_;
    assert_crowded_sort_repaired( $self, 1 );
}

sub generate {
    my ( $self, $start, $end, $count, $seed, $tz ) = @_;
    my ($env);
    $env = { %{ $self->{env} }, "TZ" => $tz };
    return run_command(
        [ $PERL, "-e", "srand(shift); do shift; die \$\@ if \$\@;", $seed, $DATES, $start, $end, $count ],
        { "cwd" => $self->{repo}, "env" => $env, "timeout" => 10 } );
}

sub dates {
    my ( $self, $start, $end, $count, $kwargs ) = @_;
    my ( $dates, $left, $line, $result, $right );
    $result = generate(
        $self, $start, $end, $count,
        ( exists( $kwargs->{"seed"} ) ? $kwargs->{"seed"} : 42 ),
        ( exists( $kwargs->{"tz"} )   ? $kwargs->{"tz"}   : "UTC" )
    );
    ( is_deeply( $result->{returncode}, 0, $result->{stderr} ) or die "assertion failed\n" );
    ( is_deeply( $result->{stderr}, "" ) or die "assertion failed\n" );
    $dates = [ map { my $line = $_; int($line) } @{ [ split( /\n/, $result->{stdout} ) ] } ];
    ( is_deeply( scalar( @{$dates} ), $count ) or die "assertion failed\n" );
    (
        ok(
            (
                0 + !(
                    grep { !$_ } @{
                        [
                            map {
                                my $left  = ($_)->[0];
                                my $right = ($_)->[1];
                                ( ( $left < $right ) )
                            } @{ zip_lists( $dates, array_slice( $dates, 1, undef ) ) }
                        ]
                    }
                )
            )
          )
          or die "assertion failed\n"
    );
    return $dates;
}

sub test_busy_days_and_two_week_gaps {
    my ($self) = @_;
    my ( $daily_counts, $dates, $end, $first, $last, $left, $right, $seed, $start, $timestamp );
    $start = "2024-01-01";
    $end   = "2024-04-01";
    $first = int( iso_epoch("${start}T00:00:00Z") );
    $last  = int( iso_epoch("${end}T00:00:00Z") );
    for $seed ( @{ [ 1, 2, 42, 1234 ] } ) {
        {
            $dates = dates( $self, $start, $end, 1000, { "seed" => $seed } );
            ( is_deeply( [ $dates->[0], $dates->[ -(1) ] ], [ $first, $last ] ) or die "assertion failed\n" );
            $daily_counts =
              count_values( [ map { my $timestamp = $_; int( ( $timestamp / 86400 ) ) } @{$dates} ] );
            cmp_ok( max( values %$daily_counts ), '<=', 128, 'bursting never exceeds 128 commits per day' );
            ( cmp_ok( max( @{ [ values %{$daily_counts} ] } ), ">=", 100 ) or die "assertion failed\n" );
            (
                cmp_ok(
                    max(
                        @{
                            [
                                map {
                                    my $left  = ($_)->[0];
                                    my $right = ($_)->[1];
                                    ( $right - $left )
                                } @{ zip_lists( $dates, array_slice( $dates, 1, undef ) ) }
                            ]
                        }
                    ),
                    ">=",
                    ( 14 * 86400 )
                  )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_schedule_changes_with_random_seed {
    my ($self) = @_;
    my ($args);
    $args = [ "2024-01-01", "2024-04-01", 400 ];
    (
        ok(
            !equal_values(
                dates(
                    $self,
                    ( [ @{$args} ] )->[0],
                    ( [ @{$args} ] )->[1],
                    ( [ @{$args} ] )->[2],
                    { "seed" => 1 }
                ),
                dates(
                    $self,
                    ( [ @{$args} ] )->[0],
                    ( [ @{$args} ] )->[1],
                    ( [ @{$args} ] )->[2],
                    { "seed" => 2 }
                )
            )
          )
          or die "assertion failed\n"
    );
}

sub test_range_capacity_rejects_without_output {
    my ($self) = @_;
    my ( $dates, $end, $first, $start );
    $start = "2024-01-01";
    $end   = "2024-01-02";
    $dates = dates( $self, $start, $end, 129, {} );
    assert_daily_limit($dates);
    $first = int( iso_epoch("${start}T00:00:00Z") );
    is_deeply(
        [ $dates->[0], $dates->[-1] ],
        [ $first,      $first + 86400 ],
        'a full day plus the midnight endpoint preserves both date boundaries'
    );

    for my $count ( 130, 9999 ) {
        my $result = generate( $self, $start, $end, $count, 42, 'UTC' );
        isnt( $result->{returncode}, 0, 'a date range cannot exceed its daily capacity' );
        like( $result->{stderr}, qr/128 commits per day/, 'the error explains the hard limit' );
        is( $result->{stdout}, '', 'an impossible range emits no partial schedule' );
    }
}

sub test_maximum_count {
    my ($self) = @_;
    for my $seed ( 42, 2037 ) {
        my $dates = dates( $self, '2024-01-01', '2027-01-01', 99999, { seed => $seed } );
        assert_daily_limit($dates);
        is_deeply(
            [ $dates->[0],                       $dates->[-1] ],
            [ iso_epoch('2024-01-01T00:00:00Z'), iso_epoch('2027-01-01T00:00:00Z') ],
            'the maximum count preserves both date boundaries'
        );
    }

    my $result = run_command(
        [ $FISH, '--no-config', '-c', <<'FISH' ],
set -p fish_function_path "$TEST_DOTFILES/fish/functions"
set -g fair "$TEST_FAIR_REPO"
set -g dotfiles "$TEST_DOTFILES"
function git
    if test "$argv[1]" = commit
        printf '%s\n' $argv
        return 73
    end
    command git $argv
end
fair 99999
FISH
        { cwd => $self->{repo}, env => $self->{env}, timeout => 10 }
    );
    isnt( $result->{returncode}, 0,  'an undated maximum count exceeds daily capacity' );
    isnt( $result->{returncode}, 73, 'the daily limit is checked before the first commit' );
    like( $result->{stderr}, qr/128 commits per day/,
        'the maximum-count rejection explains the daily limit' );
    is( $result->{stdout}, '', 'the maximum-count rejection never reaches the commit stub' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $self->{initial}, 'the maximum-count check leaves HEAD unchanged' );
    $result = generate( $self, '2024-01-01', '2024-01-03', 100000, 42, 'UTC' );
    isnt( $result->{returncode}, 0, 'the date generator rejects a count above the limit' );
}

sub test_one_day_ranges_keep_count_and_endpoints {
    my ($self) = @_;
    my $first = int( iso_epoch("2024-01-01T00:00:00+00:00") );
    for my $count ( 2, 3, 50, 128, 129 ) {
        my $dates = dates( $self, "2024-01-01", "2024-01-02", $count, {} );
        assert_daily_limit($dates);
        is_deeply(
            [ $dates->[0], $dates->[-1] ],
            [ $first,      $first + 86400 ],
            'short date ranges preserve their endpoints'
        );
    }
}

sub test_non_utc_and_dst_ranges_enforce_the_utc_daily_limit {
    my ($self) = @_;
    for my $case (
        [ '2024-01-01', '2024-01-02', 'Pacific/Kiritimati' ],
        [ '2024-03-10', '2024-03-11', 'America/Vancouver' ],
        [ '2024-11-03', '2024-11-04', 'America/Vancouver' ],
      )
    {
        for my $seed ( 1, 42 ) {
            my $dates = dates( $self, $case->[0], $case->[1], 256, { seed => $seed, tz => $case->[2] } );
            assert_daily_limit($dates);
        }
        my $result = generate( $self, @$case[ 0, 1 ], 257, 42, $case->[2] );
        isnt( $result->{returncode}, 0, 'two UTC days cannot hold a 257th commit' );
        like( $result->{stderr}, qr/128 commits per day/, 'non-UTC range rejection explains the limit' );
        is( $result->{stdout}, '', 'non-UTC overflow emits no partial schedule' );
    }
}

sub test_existing_author_dates_use_the_recorded_offset {
    my ($self) = @_;
    seed_commits( $self, iso_epoch('2024-01-01T23:00:00-08:00'), 128, '-0800' );
    my $result = generate( $self, '2024-01-01', '2024-01-02', 2, 42, 'UTC' );
    isnt( $result->{returncode}, 0, 'the recorded January 1 day is already full' );
    like( $result->{stderr}, qr/128 commits per day/, 'existing-day rejection explains the limit' );
    is( $result->{stdout}, '', 'existing-day overflow emits no partial schedule' );
    is_deeply(
        dates( $self, '2024-01-01', '2024-01-02', 1, {} ),
        [ iso_epoch('2024-01-02T00:00:00Z') ],
        'the remaining endpoint belongs to January 2 in the generated UTC dates'
    );
}

sub test_epoch_and_leap_day_are_valid {
    my ($self) = @_;
    my ($dates);
    (
        is_deeply( dates( $self, "1970-01-01", "1970-01-02", 2, {} ), [ 0, 86400 ] )
          or die "assertion failed\n"
    );
    $dates = dates( $self, "2024-02-29", "2024-03-01", 2, {} );
    ( is_deeply( ( $dates->[1] - $dates->[0] ), 86400 ) or die "assertion failed\n" );
}

sub test_invalid_calendar_dates_fail_without_output {
    my ($self) = @_;
    my ( $result, $start );
    for $start (
        @{
            [
                "2024-13-01", "2023-02-29", "2024-04-31", "2024-00-01",
                "2024-01-00", "2024-01-32", "0000-01-01"
            ]
        }
      )
    {
        {
            $result = generate( $self, $start, "2025-01-01", 2, 42, "UTC" );
            ( ok( !equal_values( $result->{returncode}, 0 ) ) or die "assertion failed\n" );
            ( ok( ( $result->{stderr} ) )                     or die "assertion failed\n" );
            ( is_deeply( $result->{stdout}, "" )              or die "assertion failed\n" );
        }
    }
}

sub test_only_yyyy_mm_dd_dates_are_accepted {
    my ($self) = @_;
    for my $value (
        '',                          '2024',
        '2024-1-01',                 '2024-01-1',
        '2024/01/01',                '20240101',
        '2024-01-01 trailing',       '2024-01-01T00:00',
        '2024-01-01 00:00:00',       '2024-01-01T00:00:00Z',
        '2024-01-01T00:00:00+02:00', '2024-01-01T00:00:00.1Z',
      )
    {
        for my $bounds ( [ $value, '2025-01-01' ], [ '2023-01-01', $value ] ) {
            my $result = generate( $self, @$bounds, 2, 42, 'UTC' );
            isnt( $result->{returncode}, 0, "reject non-date input '$value'" );
            like( $result->{stderr}, qr/YYYY-MM-DD/, 'the error describes the required format' );
            is( $result->{stdout}, '', 'invalid date input produces no dates' );
        }
    }
}

run_cases(
    {
        "test_dated_commits_stay_ordered_in_range_and_set_both_dates" =>
          \&test_dated_commits_stay_ordered_in_range_and_set_both_dates,
        "test_date_flags_before_count"                 => \&test_date_flags_before_count,
        test_only_exact_counter_subjects_are_continued => \&test_only_exact_counter_subjects_are_continued,
        "test_date_only_values_use_local_timezone_and_forward_arguments" =>
          \&test_date_only_values_use_local_timezone_and_forward_arguments,
        "test_single_commit_defaults_to_midpoint"                => \&test_single_commit_defaults_to_midpoint,
        "test_local_midnight_bounds_follow_daylight_saving_time" =>
          \&test_local_midnight_bounds_follow_daylight_saving_time,
        "test_missing_invalid_or_reversed_dates_do_not_make_commits" =>
          \&test_missing_invalid_or_reversed_dates_do_not_make_commits,
        "test_dated_commits_restore_inherited_dates_for_next_call" =>
          \&test_dated_commits_restore_inherited_dates_for_next_call,
        "test_without_dates_keeps_default_and_explicit_counts" =>
          \&test_without_dates_keeps_default_and_explicit_counts,
        test_ordinary_calls_enforce_remaining_daily_capacity =>
          \&test_ordinary_calls_enforce_remaining_daily_capacity,
        test_inherited_author_date_uses_its_recorded_day =>
          \&test_inherited_author_date_uses_its_recorded_day,
        test_ordinary_call_keeps_the_day_checked_before_midnight =>
          \&test_ordinary_call_keeps_the_day_checked_before_midnight,
        test_repeated_dated_batches_enforce_remaining_capacity =>
          \&test_repeated_dated_batches_enforce_remaining_capacity,
        'test_sort_rejects_count_and_date_flags'            => \&test_sort_rejects_count_and_date_flags,
        'test_sort_stays_in_repository'                     => \&test_sort_stays_in_repository,
        'test_sort_orders_entire_branch'                    => \&test_sort_orders_entire_branch,
        'test_sort_initializes_counter_and_preserves_index' =>
          \&test_sort_initializes_counter_and_preserves_index,
        'test_sort_rejects_merge_history'              => \&test_sort_rejects_merge_history,
        test_sort_rebalances_crowded_ordered_history   => \&test_sort_rebalances_crowded_ordered_history,
        test_sort_rebalances_crowded_unordered_history => \&test_sort_rebalances_crowded_unordered_history,
        "test_busy_days_and_two_week_gaps"             => \&test_busy_days_and_two_week_gaps,
        "test_schedule_changes_with_random_seed"       => \&test_schedule_changes_with_random_seed,
        test_range_capacity_rejects_without_output     => \&test_range_capacity_rejects_without_output,
        'test_maximum_count'                           => \&test_maximum_count,
        "test_one_day_ranges_keep_count_and_endpoints" => \&test_one_day_ranges_keep_count_and_endpoints,
        test_non_utc_and_dst_ranges_enforce_the_utc_daily_limit =>
          \&test_non_utc_and_dst_ranges_enforce_the_utc_daily_limit,
        test_existing_author_dates_use_the_recorded_offset =>
          \&test_existing_author_dates_use_the_recorded_offset,
        "test_epoch_and_leap_day_are_valid"               => \&test_epoch_and_leap_day_are_valid,
        "test_invalid_calendar_dates_fail_without_output" =>
          \&test_invalid_calendar_dates_fail_without_output,
        test_only_yyyy_mm_dd_dates_are_accepted => \&test_only_yyyy_mm_dd_dates_are_accepted,
    },
    \&setUp
);
