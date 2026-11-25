# Burst scheduling and argument validation regressions for fair.
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
    my ( $self, $args, $cwd, $after ) = @_;
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
            "timeout" => 15
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

sub generate {
    my ( $self, $start, $end, $count, $seed, $tz ) = @_;
    my ($env);
    $env = { %{ ( \%ENV ) }, "TZ" => $tz };
    return run_command(
        [ $PERL, "-e", "srand(shift); do shift; die \$\@ if \$\@;", $seed, $DATES, $start, $end, $count ],
        { "env" => $env, "timeout" => 10 } );
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

sub test_large_count_fits_within_one_day {
    my ($self) = @_;
    my ( $dates, $end, $first, $start );
    $start = "2024-01-01";
    $end   = "2024-01-02";
    $dates = dates( $self, $start, $end, 9999, {} );
    $first = int( iso_epoch("${start}T00:00:00Z") );
    is_deeply(
        [ $dates->[0], $dates->[-1] ],
        [ $first,      $first + 86400 ],
        'a large count preserves both date boundaries'
    );
}

sub test_maximum_count {
    my ($self) = @_;
    for my $seed ( 42, 2037 ) {
        my $dates = dates( $self, '2024-01-01', '2024-01-03', 99999, { seed => $seed } );
        is_deeply(
            [ $dates->[0],                       $dates->[-1] ],
            [ iso_epoch('2024-01-01T00:00:00Z'), iso_epoch('2024-01-03T00:00:00Z') ],
            'the maximum count preserves both date boundaries'
        );
    }

    my $result = run_command(
        [ $FISH, '--no-config', '-c', <<'FISH' ],
set -p fish_function_path "$TEST_DOTFILES/fish/functions"
set -g fair "$TEST_FAIR_REPO"
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
    is( $result->{returncode}, 73, 'the maximum count reaches the first commit' );
    is(
        $result->{stdout},
        "commit\n--allow-empty\n--only\n-m\ncount: 41\n",
        'the stub stops before creating any commits'
    );
    is( trim( git( $self, [ 'rev-parse', 'HEAD' ], undef )->{stdout} ),
        $self->{initial}, 'the maximum-count check leaves HEAD unchanged' );
    $result = generate( $self, '2024-01-01', '2024-01-03', 100000, 42, 'UTC' );
    isnt( $result->{returncode}, 0, 'the date generator rejects a count above the limit' );
}

sub test_one_day_ranges_keep_count_and_endpoints {
    my ($self) = @_;
    my $first = int( iso_epoch("2024-01-01T00:00:00+00:00") );
    for my $count ( 2, 3, 50, 500 ) {
        my $dates = dates( $self, "2024-01-01", "2024-01-02", $count, {} );
        is_deeply(
            [ $dates->[0], $dates->[-1] ],
            [ $first,      $first + 86400 ],
            'short date ranges preserve their endpoints'
        );
    }
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
        "test_date_flags_before_count"                                   => \&test_date_flags_before_count,
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
        'test_sort_rejects_count_and_date_flags'            => \&test_sort_rejects_count_and_date_flags,
        'test_sort_stays_in_repository'                     => \&test_sort_stays_in_repository,
        'test_sort_orders_entire_branch'                    => \&test_sort_orders_entire_branch,
        'test_sort_initializes_counter_and_preserves_index' =>
          \&test_sort_initializes_counter_and_preserves_index,
        'test_sort_rejects_merge_history'                 => \&test_sort_rejects_merge_history,
        "test_busy_days_and_two_week_gaps"                => \&test_busy_days_and_two_week_gaps,
        "test_schedule_changes_with_random_seed"          => \&test_schedule_changes_with_random_seed,
        "test_large_count_fits_within_one_day"            => \&test_large_count_fits_within_one_day,
        'test_maximum_count'                              => \&test_maximum_count,
        "test_one_day_ranges_keep_count_and_endpoints"    => \&test_one_day_ranges_keep_count_and_endpoints,
        "test_epoch_and_leap_day_are_valid"               => \&test_epoch_and_leap_day_are_valid,
        "test_invalid_calendar_dates_fail_without_output" =>
          \&test_invalid_calendar_dates_fail_without_output,
        test_only_yyyy_mm_dd_dates_are_accepted => \&test_only_yyyy_mm_dd_dates_are_accepted,
    },
    \&setUp
);
