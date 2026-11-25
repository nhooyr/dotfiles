use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'command-completions-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{root}      = absolute_path( $self->{temporary} );
    make_path( "$self->{root}/directory", "$self->{root}/data" );
    write_file( "$self->{root}/identity", 'fixture' );
    $self->{env} = {
        %ENV,
        HOME             => $self->{root},
        XDG_DATA_HOME    => "$self->{root}/data",
        PATH             => "$root/bin:$ENV{PATH}",
        TEST_COMPLETIONS => "$root/fish/completions",
    };
}

sub complete {
    my ( $self, $line ) = @_;
    my %env    = ( %{ $self->{env} }, TEST_LINE => $line );
    my $result = run_command(
        [ 'fish', '--no-config', '-c', <<'FISH' ],
set -g fish_function_path "$__fish_data_dir/functions"
set -g fish_complete_path "$TEST_COMPLETIONS" "$__fish_data_dir/completions"
set -g aqsnow_fzf_diralis project
function __fish_complete_user_at_hosts
    printf '%s\n' test-host
end
function __ssh_history_completions
end
complete -c rg -l fixture-option -d 'Existing rg completion'
function fzfp; end
complete -C "$TEST_LINE"
FISH
        { cwd => $self->{root}, env => \%env, check => 1 }
    );
    die $result->{stderr} if length $result->{stderr};
    return $result->{stdout};
}

sub sshf_delegates_after_forwarding_arguments {
    my ($self) = @_;
    like( complete( $self, 'sshf -L ' ), qr/^0\t/m, 'source port offers automatic allocation' );
    unlike( complete( $self, 'sshf -L ' ), qr/test-host/, 'source port does not complete a host' );
    unlike( complete( $self, 'sshf -L' ),
        qr/^-L[DRh]/m, 'forwarding modes require a port instead of clustered flags' );
    like( complete( $self, 'sshf -L 8080 ' ),
        qr/^test-host\t/m, 'host completion works without an optional destination port' );
    like( complete( $self, 'sshf -R 8080 80 ' ),
        qr/^test-host\t/m, 'host completion works after the optional destination port' );
    like( complete( $self, 'sshf -D -i ' ), qr/^identity$/m, 'SSH identity option completes files' );
    unlike( complete( $self, 'sshf -D -p ' ), qr/^identity/m, 'SSH port option excludes files' );
}

sub fzfp_tracks_two_argument_alias_options {
    my ($self) = @_;
    like( complete( $self, 'fzfp --dirali ' ), qr/^\$project\t/m, 'first alias argument completes names' );
    my $directories = complete( $self, q{fzfp --dirali '$project' } );
    like(
        $directories,
        qr/^\Q$self->{root}\E\/directory\/\t/m,
        'second alias argument completes absolute directories'
    );
    unlike( $directories, qr/^\$project\t/m, 'alias names do not leak into the directory argument' );
    like( complete( $self, q{fzfp --dirali '$project' /tmp . } ),
        qr/^\$project\t/m, 'both alias arguments leave the positional global alias intact' );
    like( complete( $self, q{fzfp -- . '' } ),
        qr/^-fd\t/m, 'type operands complete after the option separator' );
    is( complete( $self, q{fzfp . '' -f } ), '', 'no file operands follow the three positionals' );
}

sub vidir_completes_flags_and_one_directory {
    my ($self) = @_;
    like( complete( $self, 'vidir --' ), qr/^--recursive\t/m, 'recursive option is available' );
    my $directories = complete( $self, 'vidir --recursive ' );
    like( $directories, qr/^directory\/\t/m, 'directory completes after scan flags' );
    unlike( $directories, qr/^identity/m, 'ordinary files are excluded' );
    is( complete( $self, 'vidir directory ' ), '', 'only one directory operand is accepted' );
}

sub wrappers_inherit_native_completions {
    my ($self) = @_;
    like( complete( $self, 'pager --line' ), qr/^--line-num-width\t/m, 'pager inherits less options' );
    like( complete( $self, 'vgrep --fixture' ),
        qr/^--fixture-option\t/m, 'vgrep inherits installed rg completions' );
}

run_cases(
    {
        sshf_delegates_after_forwarding_arguments => \&sshf_delegates_after_forwarding_arguments,
        fzfp_tracks_two_argument_alias_options    => \&fzfp_tracks_two_argument_alias_options,
        vidir_completes_flags_and_one_directory   => \&vidir_completes_flags_and_one_directory,
        wrappers_inherit_native_completions       => \&wrappers_inherit_native_completions,
    },
    \&setup
);
