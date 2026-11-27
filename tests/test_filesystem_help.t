use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my @helpers =
  qw(up realpathc reload colors note watchbell tex biglines dirali sshv multicd cdpath_add rootimg compgen);

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'filesystem-help-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$self->{temporary}/bin", "$self->{temporary}/config/fish" );
    write_file( "$self->{temporary}/config/fish/config.fish", 'touch "$TEST_CALLED"' . "\n" );
    my ($cdpath_add) = read_file("$root/fish/config.fish") =~ /^(function cdpath_add\b.*?^end\n)/msg;
    write_file( "$self->{temporary}/definitions.fish", $cdpath_add );
    $self->{env} = {
        %ENV,
        HOME             => "$self->{temporary}/home",
        PATH             => "$self->{temporary}/bin:$ENV{PATH}",
        XDG_CONFIG_HOME  => "$self->{temporary}/config",
        XDG_DATA_HOME    => "$self->{temporary}/data",
        TEST_CALLED      => "$self->{temporary}/called",
        TEST_FUNCTIONS   => "$root/fish/functions",
        TEST_COMPLETIONS => "$root/fish/completions",
        EDITOR           => 'editor',
        TEST_DEFINITIONS => "$self->{temporary}/definitions.fish",
    };
    for
      my $command (qw(mkdir realpath pbc hpath fswatch latexmk ssh nvim editor date awk sort sed less magick))
    {
        write_file( "$self->{temporary}/bin/$command", <<'SH' );
#!/bin/sh
printf '%s\n' "$0" >> "$TEST_CALLED"
exit 99
SH
        chmod 0755, "$self->{temporary}/bin/$command" or die $!;
    }
}

sub fish {
    my ( $self, $script, @args ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH' . $script, '--', @args ],
set -p fish_function_path "$TEST_FUNCTIONS"
set -p fish_complete_path "$TEST_COMPLETIONS"
source "$TEST_DEFINITIONS"
FISH
        { cwd => $self->{temporary}, env => $self->{env} }
    );
}

sub help_has_no_side_effects {
    my ($self) = @_;
    for my $name (@helpers) {
        for my $option (qw(--help -h)) {
            my $result = fish( $self, <<'FISH', $name, $option );
set -l before "$PWD"
set -g CDPATH unchanged
$argv[1] "$argv[2]"; or exit "$status"
test "$PWD" = "$before"; or exit 98
test "$CDPATH" = unchanged; or exit 99
FISH
            is( $result->{returncode}, 0, "$name $option succeeds" );
            like( $result->{stdout}, qr/^Usage: \Q$name\E(?: |\n)/, "$name $option prints its own usage" );
            is( $result->{stderr}, '', "$name $option has no diagnostics" );
        }
    }
    ok( !-e $self->{env}{TEST_CALLED}, 'help does not run normal work or reload configuration' );
}

sub help_completion_loads_on_demand {
    my ($self) = @_;
    for my $name (@helpers) {
        my $result = fish( $self, <<'FISH', $name );
test -z "$(complete -c "$argv[1]")"; or exit 97
complete -C "$argv[1] --he"
FISH
        is( $result->{returncode}, 0, "$name completion loads on demand" );
        like( $result->{stdout}, qr/^--help\t/m, "$name offers --help" );
        is( $result->{stderr}, '', "$name completion has no diagnostics" );
    }
}

sub nested_help_remains_a_command_argument {
    my ($self) = @_;
    make_path("$self->{temporary}/target");
    my $result = fish( $self, <<'FISH' );
function nested
    printf 'nested %s\n' $argv
end
set -l before "$PWD"
cdc target nested --help; or exit "$status"
test "$PWD" = "$before"; or exit 98
FISH
    is( $result->{returncode}, 0, 'nested command help succeeds and restores the caller directory' );
    is( $result->{stdout},     "nested --help\n", 'cdc does not consume its command help argument' );
}

sub help_with_other_flags_preserves_cdpath {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -g CDPATH unchanged
cdpath_add --prepend --help; or exit "$status"
test "$CDPATH" = unchanged; or exit 99
FISH
    is( $result->{returncode}, 0, 'help works with other CDPATH options without changing CDPATH' );
    like( $result->{stdout}, qr/^Usage: cdpath_add /, 'CDPATH usage is shown' );
}

run_cases(
    {
        help_has_no_side_effects               => \&help_has_no_side_effects,
        help_completion_loads_on_demand        => \&help_completion_loads_on_demand,
        nested_help_remains_a_command_argument => \&nested_help_remains_a_command_argument,
        help_with_other_flags_preserves_cdpath => \&help_with_other_flags_preserves_cdpath,
    },
    \&setup
);
