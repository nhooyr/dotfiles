use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{directory} = tempdir( 'cdc-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{directory} = absolute_path( $self->{directory} );
    make_path("$self->{directory}/target");
    $self->{env} = {
        %ENV,
        TEST_ROOT       => $self->{directory},
        TEST_DOTFILES   => $root,
        XDG_CONFIG_HOME => "$self->{directory}/config",
        XDG_DATA_HOME   => "$self->{directory}/data",
    };
}

sub fish {
    my ( $self, $body ) = @_;
    my $script = <<'FISH';
set -p fish_function_path "$TEST_DOTFILES/fish/functions"
FISH
    return run_command(
        [ 'fish', '--no-config', '-c', $script . $body ],
        {
            cwd => $self->{directory},
            env => $self->{env}
        }
    );
}

sub autoload_restores_cwd_and_command_status {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
function probe
    printf 'inside:%s\n' "$PWD"
    return 23
end
cdc "$TEST_ROOT/target" probe
printf 'status:%s\noutside:%s\n' "$status" "$PWD"
cdc "$TEST_ROOT/target"
printf 'cd-only:%s:%s\n' "$status" "$PWD"
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        $result->{stdout},
"inside:$self->{directory}/target\nstatus:23\noutside:$self->{directory}\ncd-only:0:$self->{directory}/target\n",
        'autoloaded cdc preserves command status, restores cwd, and supports plain cd'
    );
}

sub fair_and_tex_can_autoload_cdc {
    my ($self) = @_;
    write_file( "$self->{directory}/target/main.tex", 'document' );
    my $result = fish( $self, <<'FISH' );
set -g dotfiles "$TEST_DOTFILES"
set -g fair "$TEST_ROOT/target"
set -lx GIT_CONFIG_GLOBAL /dev/null
set -lx GIT_CONFIG_NOSYSTEM 1
set -lx GIT_AUTHOR_NAME 'Regression Test'
set -lx GIT_AUTHOR_EMAIL test@example.invalid
set -lx GIT_COMMITTER_NAME "$GIT_AUTHOR_NAME"
set -lx GIT_COMMITTER_EMAIL "$GIT_AUTHOR_EMAIL"
command git init --quiet "$fair"; or exit
command git -C "$fair" commit --quiet --allow-empty -m fixture; or exit
function git
    switch "$argv[1]"
        case show
            printf 'count: 4\n'
        case commit
            printf 'commit:%s\n' "$PWD"
            return 23
        case '*'
            return 99
    end
end
fair 1
printf 'fair:%s:%s\n' "$status" "$PWD"
function latexmk
    printf 'latexmk:%s\n' "$PWD"
end
function fswatch
    return 0
end
tex "$TEST_ROOT/target/main.tex"
printf 'tex:%s:%s\n' "$status" "$PWD"
FISH
    is( $result->{returncode}, 0,  $result->{stderr} );
    is( $result->{stderr},     '', 'autoloaded helpers do not report missing cdc' );
    is(
        $result->{stdout},
"commit:$self->{directory}/target\nfair:23:$self->{directory}\nlatexmk:$self->{directory}/target\ntex:0:$self->{directory}\n",
        'fair and tex use cdc in an unconfigured noninteractive Fish'
    );
}

run_cases(
    {
        autoload_restores_cwd_and_command_status => \&autoload_restores_cwd_and_command_status,
        fair_and_tex_can_autoload_cdc            => \&fair_and_tex_can_autoload_cdc,
    },
    \&setup
);
