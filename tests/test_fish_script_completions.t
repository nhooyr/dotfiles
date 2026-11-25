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
    make_path( "$temporary/fish", "$temporary/work", "$temporary/completions" );
    for my $name ( 'work/build.sh', 'work/with space.sh', 'parent.sh' ) {
        write_file( "$temporary/$name", "#!/bin/sh\nexit 0\n" );
        chmod 0755, "$temporary/$name" or die $!;
    }
    write_file( "$temporary/work/file.txt",   'data' );
    write_file( "$temporary/fish/compgen.pl", <<'PERL' );
use strict; use warnings;
open my $calls, '>>', $ENV{TEST_CALLS} or die $!;
print {$calls} "$ARGV[0]\n";
print "--generated\n--verbose\n";
PERL
    $self->{temporary} = absolute_path($temporary);
    $self->{calls}     = "$temporary/calls";
    $self->{env}       = {
        %ENV,
        HOME                   => "$temporary/home",
        TEST_CALLS             => $self->{calls},
        TEST_ROOT              => $self->{temporary},
        TEST_SOURCE            => "$root/fish/functions/compgen.fish",
        TEST_RELOAD            => "$root/fish/functions/reload.fish",
        TEST_COMPLETIONS       => "$root/fish/completions",
        TEST_LOCAL_COMPLETIONS => "$temporary/completions",
        XDG_CONFIG_HOME        => "$temporary/config",
    };
}

sub fish {
    my ( $self, $script, @arguments ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH' . $script, '--', @arguments ],
set -gx dotfiles "$TEST_ROOT"
set -p fish_complete_path "$TEST_COMPLETIONS"
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
    compgen
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

sub skips_existing_manual_completions {
    my ($self) = @_;
    for my $kind (qw(basename path)) {
        my $result = fish( $self, <<'FISH', $kind );
if test "$argv[1]" = basename
    complete -c build.sh -l native
else
    complete -p "$(path resolve -- ./build.sh)" -l native
end
prime ./build.sh --
prime ./build.sh --
not set -q compgen_paths[1]; or exit 10
complete -C './build.sh --'
FISH
        is( $result->{returncode}, 0, $result->{stderr} );
        like( $result->{stdout}, qr/^--native$/m, "$kind completions remain available" );
        unlike( $result->{stdout}, qr/^--generated$/m, "$kind completions suppress generation" );
        ok( !-e $self->{calls}, "$kind completions prevent help probing" );
    }
}

sub skips_lazy_completion_files {
    my ($self) = @_;
    write_file( "$self->{temporary}/completions/build.sh.fish",
        'printf x >>"$TEST_ROOT/lazy-loads"' . "\ncomplete -c build.sh -l lazy\n" );
    my $result = fish( $self, <<'FISH' );
set -p fish_complete_path "$TEST_LOCAL_COMPLETIONS"
test -z "$(complete -c build.sh)"; or exit 10
prime ./build.sh --
prime ./build.sh --
not set -q compgen_paths[1]; or exit 11
complete -C './build.sh --'
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/^--lazy$/m, 'the existing completion file loads normally' );
    unlike( $result->{stdout}, qr/^--generated$/m, 'the completion file suppresses generation' );
    ok( !-e $self->{calls}, 'a completion file prevents help probing' );
    is( read_file("$self->{temporary}/lazy-loads"), 'x', 'the completion file is sourced once' );
}

sub skips_embedded_completion_files {
    my ($self) = @_;
    write_file( "$self->{temporary}/work/fish", "#!/bin/sh\nexit 0\n" );
    chmod 0755, "$self->{temporary}/work/fish" or die $!;
    my $result = fish( $self, <<'FISH' );
set -g fish_complete_path "$TEST_ROOT/no-completions"
prime ./fish --
prime ./fish --
not set -q compgen_paths[1]; or exit 10
complete --color never -c fish
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/ -l private\b/, 'the embedded Fish completion provider is loaded' );
    ok( !-e $self->{calls}, 'an embedded completion provider prevents help probing' );
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

sub reload_clears_only_generated_completions {
    my ($self) = @_;
    my $cache = "$self->{env}{HOME}/.local/share/fish/compgen/cache.json";
    make_path( dirname($cache), "$self->{temporary}/config/fish" );
    write_file( $cache,                                       '{"keep":"cached flags"}' );
    write_file( "$self->{temporary}/config/fish/config.fish", "set -g reloaded yes\n" );
    my $result = fish( $self, <<'FISH' );
source "$TEST_RELOAD"
set -e fish_private_mode
function history
    set -g history_action $argv
end
set -l relative './with space.sh'
set -l line "$(string escape -- "$relative") --"
set -l native_path "$(path resolve -- ./build.sh)"
complete -p "$native_path" -l path-native
complete -c build.sh -l basename-native
set -l path_rules "$(complete --color never -c "$native_path")"
set -l basename_rules "$(complete -c build.sh)"
test -n "$path_rules"; or exit 9
prime "$relative" --
complete -C "$line" >/dev/null
test "$(count $compgen_paths)" -eq 1; or exit 10
reload; or exit 11
test "$reloaded" = yes; or exit 12
test "$history_action" = merge; or exit 13
not set -q compgen_paths[1]; or exit 14
test "$(complete --color never -c "$native_path")" = "$path_rules"; or exit 15
test "$(complete -c build.sh)" = "$basename_rules"; or exit 16
not string match -q -- '*--generated*' "$(complete -C "$line")"; or exit 17
prime "$relative" --
prime "$relative" --
test "$(count $compgen_paths)" -eq 1; or exit 18
complete -C "$line"
complete -C './build.sh --'
FISH
    is( $result->{returncode}, 0, $result->{stderr} );
    like( $result->{stdout}, qr/^--generated$/m,   'generated flags can be registered again after reload' );
    like( $result->{stdout}, qr/^--path-native$/m, 'native exact-path flags remain available' );
    like( $result->{stdout}, qr/^--basename-native$/m, 'native basename flags remain available' );
    is( read_file($cache), '{"keep":"cached flags"}', 'reload keeps the on-disk cache intact' );
    is(
        read_file( $self->{calls} ),
        "$self->{temporary}/work/with space.sh\n" x 2,
        'the helper runs once before and once after reload'
    );
}

sub help_and_completions_are_lazy {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
test -z "$(complete -c compgen)"; or exit 10
compgen --help
compgen -h
test -z "$(complete -c compgen)"; or exit 11
complete -C 'compgen --he'
test -n "$(complete -c compgen)"; or exit 12
FISH
    is( $result->{returncode},                                    0, $result->{stderr} );
    is( scalar( () = $result->{stdout} =~ /^Usage: compgen$/mg ), 2, 'both help flags show usage' );
    like( $result->{stdout}, qr/^--help\t/m, 'help completion loads when requested' );
    ok( !-e $self->{calls}, 'help and its completion do not probe a script' );
}

run_cases(
    {
        completes_relative_absolute_and_quoted_paths => \&completes_relative_absolute_and_quoted_paths,
        skips_existing_manual_completions            => \&skips_existing_manual_completions,
        skips_lazy_completion_files                  => \&skips_lazy_completion_files,
        skips_embedded_completion_files              => \&skips_embedded_completion_files,
        empty_argument_includes_flags_and_files      => \&empty_argument_includes_flags_and_files,
        does_not_probe_commands_or_file_arguments    => \&does_not_probe_commands_or_file_arguments,
        reload_clears_only_generated_completions     => \&reload_clears_only_generated_completions,
        help_and_completions_are_lazy                => \&help_and_completions_are_lazy,
    },
    \&setup
);
