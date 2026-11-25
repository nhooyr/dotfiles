use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    my $temporary = tempdir( 'fish-script-completions-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$temporary/fish", "$temporary/work" );
    for my $name ( 'work/build.sh', 'work/with space.sh', 'parent.sh' ) {
        write_file( "$temporary/$name", "#!/bin/sh\nexit 0\n" );
        chmod 0755, "$temporary/$name" or die $!;
    }
    write_file( "$temporary/work/file.txt",           'data' );
    write_file( "$temporary/fish/complete_script.pl", <<'PERL' );
use strict; use warnings;
open my $calls, '>>', $ENV{TEST_CALLS} or die $!;
print {$calls} "$ARGV[0]\n";
print "--generated\n--verbose\n";
PERL
    $self->{temporary} = absolute_path($temporary);
    $self->{calls}     = "$temporary/calls";
    $self->{env}       = {
        %ENV,
        HOME        => "$temporary/home",
        TEST_CALLS  => $self->{calls},
        TEST_ROOT   => $self->{temporary},
        TEST_SOURCE => "$root/fish/functions/_complete_script.fish",
    };
}

sub fish {
    my ( $self, $script, @arguments ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH' . $script, '--', @arguments ],
set -gx dotfiles "$TEST_ROOT"
source "$TEST_SOURCE"
function prime --argument-names path token
    set -g test_command "$path"
    set -g test_token "$token"
    function commandline
        switch "$argv[1]"
            case -ct
                printf '%s' "$test_token"
            case -xpc
                printf '%s\n' "$test_command"
        end
    end
    _complete_script
    functions -e commandline
end
FISH
        { cwd => "$self->{temporary}/work", env => $self->{env} }
    );
}

sub completes_relative_absolute_and_quoted_paths {
    my ($self) = @_;
    for my $path ( './build.sh', '../parent.sh', "$self->{temporary}/work/build.sh", './with space.sh' ) {
        my $result = fish( $self, <<'FISH', $path );
prime "$argv[1]" --
complete -C "$(string escape -- "$argv[1]") --"
FISH
        is( $result->{returncode}, 0, $result->{stderr} );
        like( $result->{stdout}, qr/^--generated$/m, "$path gets generated flag completions" );
        like( $result->{stdout}, qr/^--verbose$/m,   "$path gets all generated flags" );
    }
}

sub preserves_native_completions_and_registers_once {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
complete -c build.sh -l native
prime ./build.sh --
prime ./build.sh --
complete -C './build.sh --'
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/^--native$/m,    'native completions remain available' );
    like( $result->{stdout}, qr/^--generated$/m, 'generated completions are added' );
    is(
        read_file( $self->{calls} ),
        "$self->{temporary}/work/build.sh\n",
        'the helper runs once per completion'
    );
}

sub empty_argument_includes_flags_and_files {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
prime ./build.sh ''
test ! -e "$TEST_CALLS"; or exit 99
complete -C './build.sh '
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/^--generated$/m, 'an empty argument offers generated flags' );
    like( $result->{stdout}, qr/^--verbose$/m,   'all generated flags remain available' );
    like( $result->{stdout}, qr/^file\.txt$/m,   'an empty argument still offers filenames' );
    is( read_file( $self->{calls} ), "$self->{temporary}/work/build.sh\n", 'the script helper runs once' );
}

sub does_not_probe_commands_or_file_arguments {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
prime git --
prime ./build.sh fi
complete -C './bui'
complete -C './build.sh fi'
prime ./build.sh --
complete -C './build.sh fi'
complete -C './build.sh -- --'
complete -C './build.sh -- '
complete -C 'cat --'
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/^\.\/build\.sh\t/m, 'command-name completion remains native' );
    like( $result->{stdout}, qr/^file\.txt$/m,      'file arguments still complete' );
    ok( !-e $self->{calls}, 'the helper is not run for command names, filenames, or arguments after --' );
}

run_cases(
    {
        completes_relative_absolute_and_quoted_paths    => \&completes_relative_absolute_and_quoted_paths,
        preserves_native_completions_and_registers_once => \&preserves_native_completions_and_registers_once,
        empty_argument_includes_flags_and_files         => \&empty_argument_includes_flags_and_files,
        does_not_probe_commands_or_file_arguments       => \&does_not_probe_commands_or_file_arguments,
    },
    \&setup
);
