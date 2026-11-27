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
my $FAIR     = join_path( $DOTFILES, 'fish/functions/fair.pl' );

sub setUp {
    my ($self) = @_;
    my ( $key, $value );
    $self->{temporary} = tempdir( "fair-tests-" . "XXXXXX", TMPDIR => 1, CLEANUP => 1 );
    $self->{root}      = absolute_path( $self->{temporary} );
    $self->{repo}      = join_path( $self->{root}, "repo" );
    make_path("$self->{root}/bin");
    write_file( "$self->{root}/bin/git", <<'SH' );
#!/bin/sh
if [ "$1" = push ]; then
    exit 0
fi
if [ "$1" = commit ] && [ -n "${TEST_COMMIT_STATUS-}" ]; then
    printf '%s\n' "$@"
    exit "$TEST_COMMIT_STATUS"
fi
exec "$TEST_REAL_GIT" "$@"
SH
    chmod 0755, "$self->{root}/bin/git" or die $!;
    $self->{env} = {
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
            "TEST_REAL_GIT"       => $GIT,
            "PATH"                => "$self->{root}/bin:$ENV{PATH}",
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
    assert_success( $self,
        fair( $self, [ '6', '--date1', '2024-01-01', '--date2', '2024-01-06' ], undef, '' ) );
    my $commits = commits($self);
    is_deeply( [ map { $_->[0] } @$commits ], [ map { "count: $_" } 41 .. 46 ], 'the counter continues' );
    my $previous = 0;
    for my $commit (@$commits) {
        cmp_ok( $commit->[1], '>',  $previous, 'commit dates are strictly increasing' );
        cmp_ok( $commit->[1], '>=', iso_epoch('2024-01-01T00:00:00Z'), 'date is within the lower bound' );
        cmp_ok( $commit->[1], '<=', iso_epoch('2024-01-06T00:00:00Z'), 'date is within the upper bound' );
        is( $commit->[1], $commit->[2], 'both dates match' );
        $previous = $commit->[1];
    }
}

sub test_date_flags_before_count {
    my ($self) = @_;
    assert_success( $self,
        fair( $self, [ '--date1', '2024-01-02', '--date2', '2024-01-03', '2' ], undef, '' ) );
    my $commits = commits($self);
    is( scalar @$commits, 2, 'flags before the count are parsed' );
    cmp_ok( $commits->[0][1],  '>=', iso_epoch('2024-01-02T00:00:00Z'), 'lower bound is respected' );
    cmp_ok( $commits->[-1][1], '<=', iso_epoch('2024-01-03T00:00:00Z'), 'upper bound is respected' );
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
    $self->{env}{TZ} = 'America/Vancouver';
    assert_success( $self,
        fair( $self, [ '--date1=2024-01-01', '2', '--date2=2024-01-02' ], $self->{root}, '' ) );
    my $commits = commits($self);
    cmp_ok( $commits->[0][1], '>=', iso_epoch('2024-01-01T00:00:00-08:00'),
        'local lower bound is respected' );
    cmp_ok(
        $commits->[-1][1],
        '<=',
        iso_epoch('2024-01-02T00:00:00-08:00'),
        'local upper bound is respected'
    );
}

sub test_single_dated_commit_stays_in_range {
    my ($self) = @_;
    assert_success( $self, fair( $self, [ '--date1', '2024-01-01', '--date2', '2024-01-02' ], undef, '' ) );
    my $commit = commits($self)->[0];
    cmp_ok( $commit->[1], '>=', iso_epoch('2024-01-01T00:00:00Z'), 'one commit respects the lower bound' );
    cmp_ok( $commit->[1], '<=', iso_epoch('2024-01-02T00:00:00Z'), 'one commit respects the upper bound' );
    is( $commit->[1], $commit->[2], 'both dates match' );
}

sub test_local_midnight_bounds_follow_daylight_saving_time {
    my ($self) = @_;
    $self->{env}{TZ} = 'America/Vancouver';
    assert_success( $self,
        fair( $self, [ '2', '--date1', '2024-03-10', '--date2', '2024-03-11' ], undef, '' ) );
    my $commits = commits($self);
    cmp_ok(
        $commits->[0][1],
        '>=',
        iso_epoch('2024-03-10T00:00:00-08:00'),
        'spring lower bound uses standard time'
    );
    cmp_ok(
        $commits->[-1][1],
        '<=',
        iso_epoch('2024-03-11T00:00:00-07:00'),
        'spring upper bound uses daylight time'
    );
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
    ( is_deeply( scalar( @{$commits} ), 3 ) or die "assertion failed\n" );
    is( $commits->[-1][0], 'count: 43', 'the next call continues the counter' );
    cmp_ok( $commits->[-1][1], '>', 1700000000, 'the next call uses the recent schedule' );
}

sub test_without_dates_keeps_default_and_explicit_counts {
    my ($self) = @_;
    my $before = time;
    assert_success( $self, fair( $self, [],    undef, '' ) );
    assert_success( $self, fair( $self, ['2'], undef, '' ) );
    my $commits = commits($self);
    is_deeply(
        [ map { $_->[0] } @$commits ],
        [ 'count: 41', 'count: 42', 'count: 43' ],
        'default and explicit counts continue the counter'
    );
    for my $commit (@$commits) {
        cmp_ok( $commit->[1], '>=', $before - 14 * 86400, 'default dates remain in the recent past' );
        cmp_ok( $commit->[1], '<=', time,                 'default dates are not in the future' );
        is( $commit->[1], $commit->[2], 'author and committer dates match' );
    }
    cmp_ok( $commits->[-1][1], '<=', time, 'the final commit stays in the past' );
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
    assert_success( $self, fair( $self, ['2'], undef, '' ) );
    assert_success( $self, fair( $self, [],    undef, '' ) );
    my @dates = split /\n/, git( $self, [ 'log', '--format=%at' ], undef )->{stdout};
    assert_daily_limit( \@dates );
    my $today = int( time / 86400 );
    cmp_ok( scalar( grep { int( $_ / 86400 ) < $today } @dates ),
        '>=', 2, 'a crowded current day sends new activity into the recent past' );
}

sub test_default_schedule_preserves_inherited_dates {
    my ($self) = @_;
    my $timestamp = iso_epoch('2024-01-02T01:00:00+14:00');
    seed_commits( $self, $timestamp, 128, '+1400' );
    $self->{env}{GIT_AUTHOR_DATE} = "\@$timestamp +1400";
    my $before = time;
    assert_success( $self,
        fair( $self, [], undef, 'test "$GIT_AUTHOR_DATE" = \'@1704106800 +1400\'; or exit 91' ) );
    cmp_ok( commits($self)->[-1][1],
        '>=', $before, 'the default schedule ends now rather than using an inherited date' );
}

sub test_default_schedule_has_varied_activity {
    my ($self) = @_;
    my $before = time;
    my $result = run_command(
        [
            $PERL, '-e',       q{my $file = shift; require $file; print "$_\n" for generate_dates(@ARGV);},
            $FAIR, '--recent', '1000'
        ],
        { cwd => $self->{repo}, env => $self->{env}, check => 1, timeout => 10 }
    );
    my @dates = split /\n/, $result->{stdout};
    is( scalar @dates, 1000, 'the recent schedule contains the requested count' );
    cmp_ok( $dates[-1], '<=', time, 'the schedule stays within its captured current time' );
    cmp_ok( $dates[-1], '<=', time, 'the schedule does not enter the future' );
    my $counts = count_values( [ map { int( $_ / 86400 ) } @dates ] );
    cmp_ok( max( values %$counts ),  '<', 64,  'default activity does not manufacture crowded days' );
    cmp_ok( scalar( keys %$counts ), '<', 100, 'the recent schedule leaves quiet days' );
    cmp_ok( scalar( keys %{ count_values( [ values %$counts ] ) } ), '>', 3,
        'active days have varied loads' );
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

    my $counts = count_values( [ map { int( $_ / 86400 ) } @dates ] );
    cmp_ok( max( values %$counts ),  '<', 64, 'redistributed days stay below the crowded threshold' );
    cmp_ok( scalar( keys %$counts ), '>', 5,  'activity is spread over multiple days' );
    cmp_ok( $dates[-1], '<=', iso_epoch('2035-07-04T12:00:00Z'), 'redistribution adds no later dates' );
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
        [
            $PERL, '-e',
            q{srand shift; my $file = shift; require $file; print "$_\n" for generate_dates(@ARGV);},
            $seed, $FAIR, $start, $end, $count
        ],
        { "cwd" => $self->{repo}, "env" => $env, "timeout" => 10 }
    );
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

sub test_dated_schedule_varies_activity {
    my ($self) = @_;
    for my $seed ( 1, 2, 42, 1234 ) {
        my $dates  = dates( $self, '2024-01-01', '2024-04-01', 1000, { seed => $seed } );
        my $counts = count_values( [ map { int( $_ / 86400 ) } @$dates ] );
        cmp_ok( max( values %$counts ),  '<', 64, 'roomy ranges avoid crowded days' );
        cmp_ok( scalar( keys %$counts ), '<', 70, 'roomy ranges retain quiet days' );
        cmp_ok( scalar( keys %{ count_values( [ values %$counts ] ) } ), '>', 3, 'daily loads vary' );
        cmp_ok( $dates->[0],  '>=', iso_epoch('2024-01-01T00:00:00Z'),           'lower bound is respected' );
        cmp_ok( $dates->[-1], '<=', iso_epoch('2024-04-01T00:00:00Z'),           'upper bound is respected' );
    }
}

sub test_schedule_changes_with_random_seed {
    my ($self) = @_;
    my ($args);
    $args = [ "2024-01-01", "2024-04-01", 400 ];
    is_deeply(
        dates( $self, @$args, { seed => 42 } ),
        dates( $self, @$args, { seed => 42 } ),
        'seeded schedules repeat'
    );
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
    my $dates = dates( $self, '2024-01-01', '2024-01-02', 129, {} );
    assert_daily_limit($dates);
    for my $count ( 130, 9999 ) {
        my $result = generate( $self, '2024-01-01', '2024-01-02', $count, 42, 'UTC' );
        isnt( $result->{returncode}, 0, 'fixed date bounds reject impossible counts' );
        like( $result->{stderr}, qr/128 commits per day/, 'the error explains the hard limit' );
        is( $result->{stdout}, '', 'an impossible range emits no partial schedule' );
    }
}

sub test_maximum_count {
    my ($self) = @_;
    for my $seed ( 42, 2037 ) {
        my $dates = dates( $self, '2024-01-01', '2027-01-01', 99999, { seed => $seed } );
        assert_daily_limit($dates);
        cmp_ok( $dates->[0],  '>=', iso_epoch('2024-01-01T00:00:00Z'), 'maximum count respects lower bound' );
        cmp_ok( $dates->[-1], '<=', iso_epoch('2027-01-01T00:00:00Z'), 'maximum count respects upper bound' );
    }

    my $result = run_command(
        [ $FISH, '--no-config', '-c', <<'FISH' ],
set -p fish_function_path "$TEST_DOTFILES/fish/functions"
set -g fair "$TEST_FAIR_REPO"
set -g dotfiles "$TEST_DOTFILES"
set -lx TEST_COMMIT_STATUS 73
fair 99999
FISH
        { cwd => $self->{repo}, env => $self->{env}, timeout => 10 }
    );
    is( $result->{returncode}, 73, 'the maximum count reaches the first commit with a recent schedule' );
    like( $result->{stdout}, qr/commit/, 'the default range expands to fit a large count' );
    is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $self->{initial}, 'the maximum-count check leaves HEAD unchanged' );
    $result = generate( $self, '2024-01-01', '2024-01-03', 100000, 42, 'UTC' );
    isnt( $result->{returncode}, 0, 'the date generator rejects a count above the limit' );
}

sub test_one_day_ranges_keep_count_and_bounds {
    my ($self) = @_;
    for my $count ( 2, 3, 50, 128, 129 ) {
        my $dates = dates( $self, '2024-01-01', '2024-01-02', $count, {} );
        assert_daily_limit($dates);
        cmp_ok( $dates->[0],  '>=', iso_epoch('2024-01-01T00:00:00Z'), 'lower bound is respected' );
        cmp_ok( $dates->[-1], '<=', iso_epoch('2024-01-02T00:00:00Z'), 'upper bound is respected' );
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
    for my $bounds ( [ '1970-01-01', '1970-01-02' ], [ '2024-02-29', '2024-03-01' ] ) {
        my $dates = dates( $self, @$bounds, 2, {} );
        cmp_ok( $dates->[0],  '>=', iso_epoch("$bounds->[0]T00:00:00Z"), 'lower bound is valid' );
        cmp_ok( $dates->[-1], '<=', iso_epoch("$bounds->[1]T00:00:00Z"), 'upper bound is valid' );
    }
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

sub test_flexible_schedules_avoid_existing_busy_days {
    my ($self) = @_;
    my $result = run_command(
        [ $PERL, '-e', <<'SCRIPT', $FAIR ],
use strict;
use warnings;
my $file = shift;
require $file;
srand 42;
$SIG{__WARN__} = sub { die @_ };
for my $load (50, 128) {
    my %occupied = map { $_ => $load } 100 .. 5100;
    my @dates = schedule(5086 * 86400, 5100 * 86400 + 40000, 300, \%occupied, 0, 1);
    die 'wrong count' unless @dates == 300;
    my %days;
    for my $date (@dates) {
        die 'busy day reused' if $date >= 100 * 86400;
        die 'crowded result' if ++$days{int($date / 86400)} >= 64;
    }
}
SCRIPT
        { cwd => $self->{repo}, env => $self->{env}, timeout => 10 }
    );
    assert_success( $self, $result );
}

sub test_helper_help_and_completions {
    my ($self) = @_;
    for my $flag ( '-h', '--help' ) {
        my $result = run_command( [ $FAIR, $flag ], { cwd => $self->{root}, env => $self->{env} } );
        is( $result->{returncode}, 0, $result->{stderr} );
        like( $result->{stdout}, qr/^Usage: fair/, 'the combined helper documents its usage' );
    }
    my $result = run_command( [ $FISH, '--no-config', '-c', <<'FISH' ], { env => $self->{env} } );
set -p fish_function_path "$TEST_DOTFILES/fish/functions"
set -p fish_complete_path "$TEST_DOTFILES/fish/completions"
test -z "$(complete -c fair)"; or exit 1
complete -C 'fair --he'
complete -C 'fair --s'
complete -C 'fair --date'
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/^--help\t/m,  'help is completed' );
    like( $result->{stdout}, qr/^--sort\t/m,  'history sorting is completed on demand' );
    like( $result->{stdout}, qr/^--date1\t/m, 'the first date is completed' );
    like( $result->{stdout}, qr/^--date2\t/m, 'the last date is completed' );
}

run_cases(
    {
        test_helper_help_and_completions                              => \&test_helper_help_and_completions,
        "test_dated_commits_stay_ordered_in_range_and_set_both_dates" =>
          \&test_dated_commits_stay_ordered_in_range_and_set_both_dates,
        "test_date_flags_before_count"                 => \&test_date_flags_before_count,
        test_only_exact_counter_subjects_are_continued => \&test_only_exact_counter_subjects_are_continued,
        "test_date_only_values_use_local_timezone_and_forward_arguments" =>
          \&test_date_only_values_use_local_timezone_and_forward_arguments,
        "test_single_dated_commit_stays_in_range"                => \&test_single_dated_commit_stays_in_range,
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
        test_default_schedule_preserves_inherited_dates => \&test_default_schedule_preserves_inherited_dates,
        test_default_schedule_has_varied_activity       => \&test_default_schedule_has_varied_activity,
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
        "test_dated_schedule_varies_activity"          => \&test_dated_schedule_varies_activity,
        "test_schedule_changes_with_random_seed"       => \&test_schedule_changes_with_random_seed,
        test_range_capacity_rejects_without_output     => \&test_range_capacity_rejects_without_output,
        'test_maximum_count'                           => \&test_maximum_count,
        "test_one_day_ranges_keep_count_and_bounds"    => \&test_one_day_ranges_keep_count_and_bounds,
        test_non_utc_and_dst_ranges_enforce_the_utc_daily_limit =>
          \&test_non_utc_and_dst_ranges_enforce_the_utc_daily_limit,
        test_existing_author_dates_use_the_recorded_offset =>
          \&test_existing_author_dates_use_the_recorded_offset,
        "test_epoch_and_leap_day_are_valid"               => \&test_epoch_and_leap_day_are_valid,
        "test_invalid_calendar_dates_fail_without_output" =>
          \&test_invalid_calendar_dates_fail_without_output,
        test_only_yyyy_mm_dd_dates_are_accepted          => \&test_only_yyyy_mm_dd_dates_are_accepted,
        test_flexible_schedules_avoid_existing_busy_days =>
          \&test_flexible_schedules_avoid_existing_busy_days,
    },
    \&setUp
);
