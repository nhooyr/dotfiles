use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub preserves_git_whitespace {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'diff-highlight-ws-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $bin = "$self->{temporary}/bin";
    make_path($bin);
    write_file( "$bin/diff-highlight", "#!/bin/sh\nexec cat\n" );
    chmod 0755, "$bin/diff-highlight" or die $!;

    my %env = (
        %ENV,
        PATH                => "$bin:$ENV{PATH}",
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
        GIT_CONFIG_COUNT    => 1,
        GIT_CONFIG_KEY_0    => 'color.diff.whitespace',
    );
    my $other_changes = "\e[31m-key = \e[7;31mold\e[27m\e[m\n" . "\e[32m+key = \e[7;32mnew\e[27m\e[m\n";

    for my $case ( [ 'white red', "\e[37;41m" ], [ 'white yellow reverse', "\e[7;37;43m" ] ) {
        my ( $value, $color ) = @$case;
        $env{GIT_CONFIG_VALUE_0} = $value;
        my $added   = "\e[32m+\e[m\e[32mtext\e[m$color";
        my $removed = "\e[31m-\e[m$color";
        my $input =
            $other_changes
          . "$added\e[7;32m   \e[27m \e[m\n"
          . "$removed\e[7;31m  \e[m\e[27m\t\e[31mtext\e[m\n";
        my $expected = $other_changes . "$added    \e[m\n" . "$removed  \e[m\e[27m\t\e[31mtext\e[m\n";
        my $result   = run_command( ["$root/bin/diff-highlight-ws"],
            { cwd => $self->{temporary}, env => \%env, input => $input, check => 1 } );
        is( $result->{stdout}, $expected,
            "Git's $value whitespace style and ordinary highlights are preserved" );
    }
}

run_cases( { preserves_git_whitespace => \&preserves_git_whitespace } );
