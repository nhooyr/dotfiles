use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my $fish = which('fish') or die "Fish is required\n";
my $git  = which('git')  or die "Git is required\n";

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'github-completions-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $temporary = $self->{temporary};
    $self->{repo} = "$temporary/home/code/owner/repository";
    make_path( $self->{repo}, "$temporary/bin", "$temporary/functions" );
    my @wrappers = read_file("$root/fish/config.fish") =~ /^(function gacm(?:a|p)?\b.*?^end\n)/msg;
    write_file( "$temporary/wrappers.fish", join '', @wrappers );
    $self->{env} = {
        ( map { $_ => $ENV{$_} } grep { !/^GIT_/ } keys %ENV ),
        HOME                => "$temporary/home",
        PATH                => "$temporary/bin:$ENV{PATH}",
        GIT_CONFIG_NOSYSTEM => 1,
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_ALLOW_PROTOCOL  => '',
        XDG_CONFIG_HOME     => "$temporary/config",
        XDG_DATA_HOME       => "$temporary/data",
        XDG_CACHE_HOME      => "$temporary/cache",
        TEST_COMPLETIONS    => "$root/fish/completions",
        TEST_FUNCTIONS      => "$root/fish/functions",
        TEST_TEMPORARY      => $temporary,
        TEST_WRAPPERS       => "$temporary/wrappers.fish",
    };
    run_command( [ $git, 'init', '-q', $self->{repo} ], { env => $self->{env}, check => 1 } );
    write_file( "$self->{repo}/deleted file", 'tracked' );
    run_command( [ $git, '-C', $self->{repo}, 'add', '.' ], { env => $self->{env}, check => 1 } );
    run_command(
        [
            $git,     '-C',  $self->{repo}, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
            'commit', '-qm', 'Initial commit'
        ],
        { env => $self->{env}, check => 1 }
    );

    for my $command ( [ 'branch', 'completion-branch' ], [ 'tag', 'completion-tag' ] ) {
        run_command( [ $git, '-C', $self->{repo}, @$command ], { env => $self->{env}, check => 1 } );
    }
    unlink "$self->{repo}/deleted file" or die $!;
    for my $client (qw(gh ssh curl)) {
        write_file( "$temporary/bin/$client", <<'SH' );
#!/bin/sh
printf '%s\n' "$0" >> "$TEST_TEMPORARY/network"
exit 99
SH
        chmod 0755, "$temporary/bin/$client" or die $!;
    }
}

sub fish {
    my ( $self, $body, @arguments ) = @_;
    my $result = run_command(
        [ $fish, '--no-config', '-c', <<'FISH' . $body, '--', @arguments ],
set fish_function_path "$TEST_TEMPORARY/functions" "$TEST_FUNCTIONS" "$__fish_data_dir/functions" $fish_function_path
set fish_complete_path "$TEST_COMPLETIONS" "$__fish_data_dir/completions" $fish_complete_path
FISH
        { cwd => $self->{repo}, env => $self->{env}, check => 1 }
    );
    is( $result->{stderr}, '', 'completion has no diagnostics' );
    ok( !-e "$self->{temporary}/network", 'completion never invokes network clients' );
    return $result->{stdout};
}

sub local_candidates {
    my ($self) = @_;
    like( fish( $self, 'complete -C "$argv[1]"', 'ghe own' ),
        qr{^owner/repository\t}m, 'ghe offers local checkouts' );
    like( fish( $self, 'complete -C "$argv[1]"', 'ghc own' ),
        qr{^owner/repository\t}m, 'ghc offers existing local checkouts' );
    my $refs = fish( $self, 'complete -C "$argv[1]"', 'gho --copy completion-' );
    like( $refs, qr/^completion-branch\t/m, 'gho offers local branches after --copy' );
    like( $refs, qr/^completion-tag\t/m,    'gho offers local tags after --copy' );
    like(
        fish( $self, 'complete -C "$argv[1]"', 'gho -- deleted' ),
        qr/^deleted file\t/m,
        'gho offers deleted tracked paths and preserves spaces'
    );
    is( fish( $self, 'complete -C "$argv[1]"', 'gho HEAD ' ), '', 'gho stops after its target' );
}

sub lazy_helpers {
    my ($self) = @_;
    write_file( "$self->{temporary}/functions/__gh_complete_repositories.fish",
        'printf loaded > "$TEST_TEMPORARY/loaded"' . "\n"
          . read_file("$root/fish/functions/__gh_complete_repositories.fish") );
    like( fish( $self, <<'FISH' ), qr{^owner/repository\t}m, 'repository helper loads on demand' );
test ! -e "$TEST_TEMPORARY/loaded"; or exit 1
complete -C 'ghg --p' >/dev/null
test ! -e "$TEST_TEMPORARY/loaded"; or exit 2
complete -C 'ghe own'
test -s "$TEST_TEMPORARY/loaded"; or exit 3
FISH
}

sub native_git_wrappers {
    my ($self) = @_;
    my $output = fish( $self, <<'FISH' );
source "$TEST_WRAPPERS"
for query in 'git_log --oneline' 'git_rebase --interactive' 'gg --recurse-submodules' 'gacm --amend' 'gacma --no-edit' 'gacmp --amend'
    printf '%s\n' "$(complete -C "$query")"
end
FISH
    like( $output, qr/^--oneline$/m,             'git_log inherits native log completion' );
    like( $output, qr/^--interactive\t/m,        'git_rebase inherits native rebase completion' );
    like( $output, qr/^--recurse-submodules\t/m, 'gg inherits native grep completion' );
    is( scalar( () = $output =~ /^--amend\t/gm ), 2, 'gacm and gacmp inherit commit completion' );
    like( $output, qr/^--no-edit\t/m, 'gacma inherits amend completion' );
}

run_cases(
    {
        local_candidates    => \&local_candidates,
        lazy_helpers        => \&lazy_helpers,
        native_git_wrappers => \&native_git_wrappers,
    },
    \&setup
);
