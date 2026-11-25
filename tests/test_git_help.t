use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'git-help-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path("$self->{temporary}/bin");
    for my $name (qw(git pbpaste perl gh open pngpaste sips curl ssh)) {
        write_file( "$self->{temporary}/bin/$name", '#!' . perl_executable() . "\n" . <<'PERL' );
use File::Basename qw(basename);
use JSON::PP;
open my $log, '>>', $ENV{TEST_CALLS} or die $!;
print {$log} encode_json([basename($0), @ARGV]), "\n";
PERL
        chmod 0755, "$self->{temporary}/bin/$name" or die $!;
    }
    $self->{env} = {
        %ENV,
        HOME       => "$self->{temporary}/home",
        PATH       => "$self->{temporary}/bin:$ENV{PATH}",
        TEST_ROOT  => $root,
        TEST_CALLS => "$self->{temporary}/calls",
    };
}

sub fish {
    my ( $self, $body ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH' . $body ],
set -p fish_function_path "$TEST_ROOT/fish/functions"
set -p fish_complete_path "$TEST_ROOT/fish/completions"
FISH
        { cwd => $self->{temporary}, env => $self->{env}, check => 1 }
    );
}

sub help_does_not_run_commands {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
for action in cd cdc ga gcm gcma gp
    function $action
        printf 'unexpected function\n' >> "$TEST_CALLS"
        return 91
    end
end
set -l previous "$PWD"
for name in gbp gbins gbigdirs gcd scd fair ghg ghss ghe ghc gho
    for flag in --help -h
        set -l output "$($name $flag)"; or exit 1
        string match -q "Usage: $name*" -- "$output"; or exit 2
    end
    printf '%s\n' "$name"
end
test "$PWD" = "$previous"; or exit 3
FISH
    is( $result->{stderr},                       '', 'help has no errors outside a repository' );
    is( scalar( split /\n/, $result->{stdout} ), 11, 'every custom Git helper accepts both help spellings' );
    ok( !-e $self->{env}{TEST_CALLS},
        'help does not invoke Git, clipboard reads, directory changes, or commit actions' );
}

sub completion_offers_help {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
test -z "$(complete -c gbins)"; or exit 1
for name in gbp gbins gbigdirs gcd scd fair
    complete -C "$name --he" | string match -qr '^--help\t'; or exit 2
end
FISH
    is( $result->{stderr}, '', 'help completions load on demand without diagnostics' );
}

run_cases(
    {
        help_does_not_run_commands => \&help_does_not_run_commands,
        completion_offers_help     => \&completion_offers_help,
    },
    \&setup
);
