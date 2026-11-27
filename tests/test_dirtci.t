use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use POSIX qw(mkfifo);

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'dirtci-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $directory = $self->{temporary};
    make_path("$directory/bin");
    $self->{env} = {
        %ENV,
        PATH             => "$directory/bin:$root/bin:$ENV{PATH}",
        TEST_ROOT        => $directory,
        TEST_COMPLETIONS => "$root/fish/completions"
    };
    write_file( "$directory/bin/gh", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict; use warnings; use JSON::PP; use Fcntl qw(:flock);
die 'expected gh api' unless shift(@ARGV) eq 'api';
my $endpoint = shift @ARGV;
my (@options, %fields, $method);
while (@ARGV) {
    my $argument = shift @ARGV;
    if ($argument eq '-f' || $argument eq '-F') {
        my ($key, $value) = split /=/, shift(@ARGV), 2;
        $fields{$key} = $value;
    } elsif ($argument eq '--method') { $method = shift @ARGV; }
    else { push @options, $argument; }
}
open my $log, '>>', "$ENV{TEST_ROOT}/calls" or die $!;
flock($log, LOCK_EX) or die $!;
print {$log} encode_json({endpoint => $endpoint, fields => \%fields, options => \@options, method => $method}), "\n";
close $log;
open my $file, '<', "$ENV{TEST_ROOT}/responses.json" or die $!;
my $responses = decode_json(do { local $/; <$file> });
my $route = $endpoint . (defined $fields{page} ? "#$fields{page}" : '');
die "unexpected route: $route" unless exists $responses->{$route};
my $response = $responses->{$route};
my $barrier;
if ($ENV{TEST_BARRIER} && $endpoint =~ m{/owner/(alpha|beta)/actions/runs$}) {
    my $mode = $1 eq 'alpha' ? '<' : '>';
    alarm 10;
    open $barrier, $mode, $ENV{TEST_BARRIER} or die $!;
    if ($mode eq '<') { local $/; <$barrier>; }
    alarm 0;
}
if (ref($response) eq 'HASH' && exists $response->{error}) {
    print STDERR $response->{error}; exit 7;
}
print encode_json($response);
PERL
    chmod 0755, "$directory/bin/gh" or die $!;
}

sub repository {
    my ( $name, $branch, $sha ) = @_;
    return {
        nameWithOwner    => $name,
        defaultBranchRef => defined $branch ? { name => $branch, target => { oid => $sha } } : undef
    };
}

sub page { return { data => { viewer => { repositories => { nodes => [@_] } } } }; }

sub workflow {
    my ( $id, $workflow, $conclusion, $event ) = @_;
    return {
        id          => $id,
        workflow_id => $workflow,
        name        => "Workflow $workflow",
        status      => 'completed',
        conclusion  => $conclusion,
        event       => $event // 'push',
        html_url    => "https://runs/$id"
    };
}

sub responses {
    my ( $self, $routes ) = @_;
    write_file( "$self->{temporary}/responses.json", encode_json($routes) );
    unlink "$self->{temporary}/calls";
}

sub run {
    my ( $self, @arguments ) = @_;
    return run_command( [ "$root/bin/dirtci", @arguments ], { env => $self->{env} } );
}

sub calls {
    my ($self) = @_;
    return [] unless -f "$self->{temporary}/calls";
    return [ map { decode_json($_) } split /\n/, read_file("$self->{temporary}/calls") ];
}

sub selects_latest_workflows_on_default_heads {
    my ($self) = @_;
    responses(
        $self,
        {
            graphql => [
                page( repository( 'owner/beta',  'trunk',           'bbb' ), repository('owner/empty') ),
                page( repository( 'owner/alpha', 'release/current', 'aaa' ) )
            ],
            'repos/owner/alpha/actions/runs' => [
                {
                    workflow_runs => [
                        workflow( 10,  1, 'success' ),
                        workflow( 11,  1, 'failure' ),
                        workflow( 20,  2, 'cancelled' ),
                        workflow( 30,  3, 'failure' ),
                        workflow( 999, 1, 'failure', 'pull_request' ),
                        workflow( 998, 2, 'failure', 'merge_group' )
                    ]
                },
                {
                    workflow_runs => [
                        workflow( 35,  3, 'success' ),
                        workflow( 40,  4, 'neutral' ),
                        workflow( 50,  5, 'skipped' ),
                        workflow( 997, 1, 'failure', 'pull_request_target' )
                    ]
                },
            ],
            'repos/owner/beta/actions/runs' => [ { workflow_runs => [] } ],
        }
    );
    my $result = run($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        $result->{stdout},
        "owner/alpha [Workflow 1]: failure https://runs/11\n"
          . "owner/alpha [Workflow 2]: cancelled https://runs/20\n",
        'only the latest unsuccessful workflow runs are shown'
    );
    my $calls = calls($self);
    like(
        $calls->[0]{fields}{query},
        qr/ownerAffiliations:\s*OWNER/,
        'repository query requests owned repositories'
    );
    like( $calls->[0]{fields}{query},
        qr/isArchived:\s*false/, 'repository query excludes archived repositories' );
    like( $calls->[0]{fields}{query}, qr/isFork:\s*false/, 'repository query excludes forks' );
    is_deeply( $calls->[0]{options}, [ '--paginate', '--slurp' ], 'repository pages are collected' );
    is_deeply(
        [
            map  { [ $_->{endpoint}, $_->{method}, $_->{fields}, $_->{options} ] }
            sort { $a->{endpoint} cmp $b->{endpoint} } @$calls[ 1 .. $#$calls ]
        ],
        [
            [
                'repos/owner/alpha/actions/runs',
                'GET',
                { branch => 'release/current', head_sha => 'aaa', per_page => 100 },
                [ '--paginate', '--slurp' ]
            ],
            [
                'repos/owner/beta/actions/runs',                           'GET',
                { branch => 'trunk', head_sha => 'bbb', per_page => 100 }, [ '--paginate', '--slurp' ]
            ],
        ],
        'runs use each default branch and exact head; empty repositories are skipped'
    );
}

sub repository_requests_overlap {
    my ($self) = @_;
    $self->{env}{TEST_BARRIER} = "$self->{temporary}/barrier";
    mkfifo( $self->{env}{TEST_BARRIER}, 0600 ) or die $!;
    responses(
        $self,
        {
            graphql => [
                page( repository( 'owner/beta', 'main', 'bbb' ), repository( 'owner/alpha', 'main', 'aaa' ) )
            ],
            'repos/owner/alpha/actions/runs' => [ { workflow_runs => [ workflow( 1, 1, 'failure' ) ] } ],
            'repos/owner/beta/actions/runs'  => [ { workflow_runs => [ workflow( 2, 2, 'failure' ) ] } ],
        }
    );
    my $result = run($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        $result->{stdout},
        "owner/alpha [Workflow 1]: failure https://runs/1\n"
          . "owner/beta [Workflow 2]: failure https://runs/2\n",
        'repository requests overlap while output remains sorted'
    );
}

sub pending_runs_show_previous_results {
    my ($self) = @_;
    my @pending =
      map { +{ %{ workflow( $_ * 100, $_, undef ) }, status => $_ == 1 ? 'in_progress' : 'queued' } } 1 .. 3;
    responses(
        $self,
        {
            graphql                         => [ page( repository( 'owner/repo', 'main', 'head' ) ) ],
            'repos/owner/repo/actions/runs' => [ { workflow_runs => \@pending } ],
            'repos/owner/repo/actions/workflows/1/runs#1' => {
                workflow_runs => [
                    workflow( 100, 1, 'failure' ),
                    map { workflow( 1000 + $_, 1, 'failure', $_ % 2 ? 'pull_request' : 'merge_group' ) }
                      1 .. 99
                ]
            },
            'repos/owner/repo/actions/workflows/1/runs#2' =>
              { workflow_runs => [ workflow( 90, 1, 'failure' ) ] },
            'repos/owner/repo/actions/workflows/2/runs#1' =>
              { workflow_runs => [ workflow( 190, 2, 'success' ) ] },
            'repos/owner/repo/actions/workflows/3/runs#1' =>
              { workflow_runs => [ workflow( 290, 3, 'failure', 'pull_request' ) ] },
        }
    );
    my $result = run($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        $result->{stdout},
        "owner/repo [Workflow 1]: in_progress https://runs/100\n"
          . "         last completed: fail        https://runs/90\n"
          . "owner/repo [Workflow 2]: queued https://runs/200\n         last completed: success\n"
          . "owner/repo [Workflow 3]: queued https://runs/300\n         last completed: none\n",
        'pending output links unsuccessful history, omits successful URLs and reports missing history'
    );
    my @history = grep { $_->{endpoint} =~ m{/workflows/} } @{ calls($self) };
    is_deeply(
        [ map { [ $_->{endpoint}, $_->{fields}{page} ] } @history ],
        [
            [ 'repos/owner/repo/actions/workflows/1/runs', 1 ],
            [ 'repos/owner/repo/actions/workflows/1/runs', 2 ],
            [ 'repos/owner/repo/actions/workflows/2/runs', 1 ],
            [ 'repos/owner/repo/actions/workflows/3/runs', 1 ],
        ],
        'history pages continue past the current run and excluded events'
    );
    is_deeply(
        [
            map { [ $_->{method}, $_->{fields}{branch}, $_->{fields}{status}, $_->{fields}{per_page} ] }
              @history
        ],
        [ map { [ 'GET', 'main', 'completed', 100 ] } @history ],
        'history is restricted to completed runs on the branch'
    );
}

sub previous_run_columns {
    my ($self) = @_;
    my $pending = { %{ workflow( 200, 1, undef ) }, name => 'ci', status => 'queued' };
    for my $case ( [ failure => 'fail   ' ], [ cancelled => 'cancelled ' ] ) {
        responses(
            $self,
            {
                graphql => [ page( repository( 'nhooyr/dotfiles', 'main', 'head' ) ) ],
                'repos/nhooyr/dotfiles/actions/runs'               => [ { workflow_runs => [$pending] } ],
                'repos/nhooyr/dotfiles/actions/workflows/1/runs#1' =>
                  { workflow_runs => [ workflow( 100, 1, $case->[0] ) ] },
            }
        );
        my $result = run($self);
        is( $result->{returncode}, 0, $result->{stderr} );
        is(
            $result->{stdout},
            "nhooyr/dotfiles [ci]: queued https://runs/200\n"
              . "      last completed: $case->[1]https://runs/100\n",
            'previous status aligns with the current status without truncating longer conclusions'
        );
    }
}

sub help_and_invalid_arguments_do_not_query {
    my ($self) = @_;
    for my $argument ( '-h', '--help', '--unknown', 'repo' ) {
        my $result = run( $self, $argument );
        is(
            $result->{returncode} == 0,
            $argument eq '-h' || $argument eq '--help',
            'argument has expected status'
        );
        like( $result->{stdout}, qr/Usage: dirtci/, 'help names the command' ) if $result->{returncode} == 0;
    }
    is_deeply( calls($self), [], 'help and invalid arguments never call GitHub' );
}

sub api_failures_are_reported {
    my ($self) = @_;
    for my $endpoint ( 'graphql', 'repos/owner/repo/actions/runs',
        'repos/owner/repo/actions/workflows/1/runs#1' )
    {
        my $pending = { %{ workflow( 100, 1, undef ) }, status => 'queued' };
        my $routes  = {
            graphql                         => [ page( repository( 'owner/repo', 'main', 'head' ) ) ],
            'repos/owner/repo/actions/runs' => [ { workflow_runs => [$pending] } ]
        };
        $routes->{$endpoint} = { error => "API unavailable\n" };
        responses( $self, $routes );
        my $result = run($self);
        isnt( $result->{returncode}, 0, 'API failure returns an error' );
        like( $result->{stderr}, qr/API unavailable/, 'original API diagnostic is retained' );
    }
}

sub completions_load_only_when_requested {
    my ($self) = @_;
    my $result = run_command( [ 'fish', '--no-config', '-c', <<'FISH' ], { env => $self->{env} } );
set -g fish_complete_path "$TEST_COMPLETIONS" "$__fish_data_dir/completions"
test -z "$(complete -c dirtci)"; or exit 1
complete -C 'dirtci --h'
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/^--help\tShow help$/m, 'requesting completion loads the help flag' );
    is_deeply( calls($self), [], 'completion never queries GitHub' );
}

run_cases(
    {
        selects_latest_workflows_on_default_heads => \&selects_latest_workflows_on_default_heads,
        repository_requests_overlap               => \&repository_requests_overlap,
        pending_runs_show_previous_results        => \&pending_runs_show_previous_results,
        previous_run_columns                      => \&previous_run_columns,
        help_and_invalid_arguments_do_not_query   => \&help_and_invalid_arguments_do_not_query,
        api_failures_are_reported                 => \&api_failures_are_reported,
        completions_load_only_when_requested      => \&completions_load_only_when_requested
    },
    \&setup
);
