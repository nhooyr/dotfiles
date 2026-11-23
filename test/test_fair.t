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
my $CONFIG =
  read_file( join_path( join_path( $DOTFILES, "fish" ), "config.fish" ) );
my $FAIR = (
    (
        "function fair" . split_literal(
            split_literal( $CONFIG, "function fair", 1 )->[1], '
end
', 1
        )->[0]
    )
    . '
end
'
);

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
            $FAIR . '
function git
    if test "$argv[1]" = push
        return 0
    end
    command git $argv
end
function cdc
    cd -- "$argv[1]"; or return
    $argv[2..-1]
end
set -g fair_repo "$TEST_FAIR_REPO"
set -g dotfiles "$TEST_DOTFILES"
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

sub test_explicit_timezone_offsets_and_flags_before_count {
    my ($self) = @_;
    my ( $ignored, $author, $end, $start, $value );
    $start = "2024-01-02T01:00:00+02:00";
    $end   = "2024-01-02T01:30:00-03:00";
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
            [ map { my $value = $_; int( iso_epoch($value) ) } @{ [ $start, $end ] } ]
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
    assert_success( $self,
        fair( $self, [ "--date1", "2024-01-01T00:00:00Z", "--date2", "2024-01-01T00:00:10Z" ], undef, "" ) );
    $midpoint = int( iso_epoch("2024-01-01T00:00:05+00:00") );
    ( is_deeply( commits($self), [ [ "count: 41", $midpoint, $midpoint ] ] ) or die "assertion failed\n" );
}

sub test_minimum_interval_preserves_strict_order {
    my ($self) = @_;
    my ( $ignored, $author, $date, $dates );
    assert_success(
        $self,
        fair(
            $self, [ "3", "--date1", "2024-01-01T00:00:00Z", "--date2", "2024-01-01T00:00:02Z" ],
            undef, ""
        )
    );
    $dates = [
        map {
            my $unused_7 = ($_)->[0];
            my $author   = ($_)->[1];
            my $unused_8 = ($_)->[2];
            $author
        } @{ commits($self) }
    ];
    (
        is_deeply( [ map { my $date = $_; ( $date - $dates->[0] ) } @{$dates} ], [ 0, 1, 2 ] )
          or die "assertion failed\n"
    );
}

sub test_missing_invalid_or_insufficient_dates_do_not_make_commits {
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
        [ "4",       "--date1",    "2024-01-01T00:00:00Z", "--date2", "2024-01-01T00:00:02Z" ],
        ["0"],
        ["10000"],
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
    $start = "2024-01-01T00:00:00Z";
    $end   = "2024-04-01T00:00:00Z";
    $first = int( iso_epoch($start) );
    $last  = int( iso_epoch($end) );
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

sub test_dense_range_uses_every_available_second {
    my ($self) = @_;
    my ( $dates, $end, $first, $start );
    $start = "2024-01-01T00:00:00Z";
    $end   = "2024-01-01T02:46:38Z";
    $dates = dates( $self, $start, $end, 9999, {} );
    $first = int( iso_epoch($start) );
    ( is_deeply( $dates, [ $first .. ( ( $first + 9999 ) - 1 ) ] ) or die "assertion failed\n" );
}

sub test_short_ranges_keep_count_bounds_and_endpoints {
    my ($self) = @_;
    my ( $count, $dates, $end, $first, $seconds );
    $first = int( iso_epoch("2024-01-01T00:00:00+00:00") );
    for my $item_223 ( @{ [ [ 2, 1 ], [ 3, 2 ], [ 50, 600 ], [ 500, 3600 ] ] } ) {
        $count   = ($item_223)->[0];
        $seconds = ($item_223)->[1];
        {
            $end   = epoch_iso( ( $first + $seconds ) );
            $dates = dates( $self, "2024-01-01T00:00:00Z", $end, $count, {} );
            (
                is_deeply( [ $dates->[0], $dates->[ -(1) ] ], [ $first, ( $first + $seconds ) ] )
                  or die "assertion failed\n"
            );
        }
    }
}

sub test_epoch_and_leap_day_are_valid {
    my ($self) = @_;
    my ($dates);
    (
        is_deeply( dates( $self, "1970-01-01T00:00:00Z", "1970-01-01T00:00:01Z", 2, {} ), [ 0, 1 ] )
          or die "assertion failed\n"
    );
    $dates = dates( $self, "2024-02-29", "2024-03-01", 2, {} );
    ( is_deeply( ( $dates->[1] - $dates->[0] ), 86400 ) or die "assertion failed\n" );
}

sub test_invalid_calendar_dates_and_times_fail_without_output {
    my ($self) = @_;
    my ( $result, $start );
    for $start (
        @{
            [
                "2024-13-01",           "2023-02-29",
                "2024-04-31",           "2024-01-01T25:00:00Z",
                "2024-01-01T00:60:00Z", "2024-01-01T00:00:00+24:00"
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

run_cases(
    {
        "test_dated_commits_stay_ordered_in_range_and_set_both_dates" =>
          \&test_dated_commits_stay_ordered_in_range_and_set_both_dates,
        "test_explicit_timezone_offsets_and_flags_before_count" =>
          \&test_explicit_timezone_offsets_and_flags_before_count,
        "test_date_only_values_use_local_timezone_and_forward_arguments" =>
          \&test_date_only_values_use_local_timezone_and_forward_arguments,
        "test_single_commit_defaults_to_midpoint"      => \&test_single_commit_defaults_to_midpoint,
        "test_minimum_interval_preserves_strict_order" => \&test_minimum_interval_preserves_strict_order,
        "test_missing_invalid_or_insufficient_dates_do_not_make_commits" =>
          \&test_missing_invalid_or_insufficient_dates_do_not_make_commits,
        "test_dated_commits_restore_inherited_dates_for_next_call" =>
          \&test_dated_commits_restore_inherited_dates_for_next_call,
        "test_without_dates_keeps_default_and_explicit_counts" =>
          \&test_without_dates_keeps_default_and_explicit_counts,
        "test_busy_days_and_two_week_gaps"                  => \&test_busy_days_and_two_week_gaps,
        "test_schedule_changes_with_random_seed"            => \&test_schedule_changes_with_random_seed,
        "test_dense_range_uses_every_available_second"      => \&test_dense_range_uses_every_available_second,
        "test_short_ranges_keep_count_bounds_and_endpoints" =>
          \&test_short_ranges_keep_count_bounds_and_endpoints,
        "test_epoch_and_leap_day_are_valid"                         => \&test_epoch_and_leap_day_are_valid,
        "test_invalid_calendar_dates_and_times_fail_without_output" =>
          \&test_invalid_calendar_dates_and_times_fail_without_output,
    },
    \&setUp
);
