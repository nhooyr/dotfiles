use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub help_reaches_the_wrapped_command {
    my $temporary = tempdir( 'directory-help-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    for my $wrapper (qw(mcd cdf)) {
        for my $option (qw(-h --help)) {
            my $result = run_command(
                [
                    'fish',   '--no-config', '-c',
                    <<'FISH', '--', "$root/fish/functions/$wrapper.fish", $wrapper, $option
source "$argv[1]"
function mkdir
    printf 'mkdir <%s>\n' $argv
    return 23
end
function cd
    printf 'cd <%s>\n' $argv
    return 23
end
set -l before "$PWD"
$argv[2] "$argv[3]"
set -l code "$status"
test "$PWD" = "$before"; or exit 99
exit "$code"
FISH
                ],
                { cwd => $temporary }
            );
            is( $result->{returncode}, 23, "$wrapper $option preserves the wrapped command's status" );
            my $expected = $wrapper eq 'mcd' ? "mkdir <-p>\nmkdir <$option>\n" : "cd <$option>\n";
            is( $result->{stdout}, $expected, "$wrapper forwards $option without treating it as a path" );
            is( $result->{stderr}, '',        'help forwarding has no extra diagnostics' );
        }
    }
}

sub help_named_paths_are_still_literal {
    my $temporary = tempdir( 'directory-help-path-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $result    = run_command(
        [ 'fish', '--no-config', '-c', <<'FISH', '--', "$root/fish/functions" ],
source "$argv[1]/mcd.fish"
source "$argv[1]/cdf.fish"
set -l before "$PWD"
mcd ./--help; or exit 1
test "$PWD" -ef "$before/--help"; or exit 2
builtin cd -- "$before"; or exit 3
cdf ./--help/file; or exit 4
test "$PWD" -ef "$before/--help"; or exit 5
FISH
        { cwd => $temporary }
    );
    is( $result->{returncode}, 0, 'explicit help-named paths still work' );
    ok( -d "$temporary/--help", 'mcd creates the requested literal directory' );
    is( $result->{stderr}, '', 'literal paths have no diagnostics' );
}

run_cases(
    {
        help_reaches_the_wrapped_command   => \&help_reaches_the_wrapped_command,
        help_named_paths_are_still_literal => \&help_named_paths_are_still_literal,
    }
);
