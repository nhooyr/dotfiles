use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root    = absolute_path("$FindBin::Bin/..");
my $config  = read_file("$root/fish/config.fish");
my $helpers = join "\n", map {
    my ($function) = $config =~ /^(function \Q$_\E\b.*?^end\n)/msg;
    die "Missing Fish function $_\n" unless defined $function;
    $function;
} qw(aqsnow_fzf_diralis_add aqsnow_init_rendezvous realpathc __grep_smart_case grep);
$helpers .= read_file("$root/fish/functions/rootimg.fish");
my $cd = read_file("$root/fish/cd.fish");
my ($mcd) = $cd =~ /^(function mcd\b.*?^end\n)/msg;
$helpers .= $mcd;

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'fish-helpers-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{root}      = absolute_path( $self->{temporary} );
    make_path("$self->{root}/bin");
    write_file( "$self->{root}/bin/pbcopy", <<'SH' );
#!/bin/sh
cat > "$TEST_ROOT/clipboard"
SH
    chmod 0755, "$self->{root}/bin/pbcopy";
    $self->{env} = {
        %ENV,
        PATH            => "$self->{root}/bin:$ENV{PATH}",
        TMPDIR          => $self->{root},
        XDG_CONFIG_HOME => "$self->{root}/config",
        XDG_DATA_HOME   => "$self->{root}/data",
        TEST_ROOT       => $self->{root},
        TEST_HPATH      => "$root/bin/hpath",
        TEST_PBC        => "$root/bin/pbc",
        TEST_GREP       => which('grep'),
        TERM            => 'dumb',
    };
}

sub fish {
    my ( $self, $body ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', "$helpers\n$body" ],
        {
            cwd   => $self->{root},
            env   => $self->{env},
            check => 1,
        }
    );
}

sub aliases_added_after_initialization_are_exported {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -g aqsnow_fzf_diralis HOME
aqsnow_init_rendezvous; or exit 1
set -l original "$__aqsnow_rendezvous_dir"
set -g project "$TEST_ROOT"
aqsnow_fzf_diralis_add project; or exit 2
aqsnow_fzf_diralis_add project; or exit 3
aqsnow_init_rendezvous; or exit 4
test "$original" = "$__aqsnow_rendezvous_dir"; or exit 5
fish --no-config -c 'printf "%s\n%s\n" "$AQSNOW_DIRALIS" "$project"'
FISH
    is(
        $result->{stdout},
        "HOME:project\n$self->{root}\n",
        'new aliases reach children without duplicating names or recreating the handoff directory'
    );
    is( $result->{stderr}, '', 'alias initialization has no diagnostics' );
}

sub realpath_failure_does_not_clear_the_clipboard {
    my ($self) = @_;
    write_file( "$self->{root}/clipboard", 'keep' );
    my $result = fish( $self, <<'FISH' );
function hpath
    command "$TEST_HPATH"
end
function pbc
    command "$TEST_PBC"
end
realpathc "$TEST_ROOT/missing-parent/file" 2>/dev/null
FISH
    is( $result->{stdout},                    '',     'failed resolution produces no output' );
    is( read_file("$self->{root}/clipboard"), 'keep', 'pbc preserves the clipboard after failed resolution' );
}

sub realpath_success_preserves_spaces_and_leading_dashes {
    my ($self) = @_;
    write_file( "$self->{root}/-file with spaces", 'contents' );
    my $result = fish( $self, <<'FISH' );
function hpath
    command "$TEST_HPATH"
end
function pbc
    tee "$TEST_ROOT/clipboard"
end
realpathc '-file with spaces'
FISH
    is( $result->{stdout}, "$self->{root}/-file with spaces\n",  'resolved path is still printed' );
    is( read_file("$self->{root}/clipboard"), $result->{stdout}, 'the same complete path is copied' );
}

sub grepw_uses_an_extended_whitespace_quantifier {
    my ($self)      = @_;
    my ($expansion) = $config =~ /^abbr -a --set-cursor grepw "([^"]+)"$/m;
    die "Missing grepw abbreviation\n" unless defined $expansion;
    my ($grepe) = $config =~ /^abbrali grepe (.+)$/m;
    die "Missing grepe alias\n" unless defined $grepe;
    $self->{env}{TEST_GREPE} = $grepe;
    $expansion =~ s/%/needle/;
    my $result = fish( $self, <<'FISH' . "\nprintf '  needle\\nneedle\\n +needle\\n' | $expansion\n" );
alias grepe "$TEST_GREPE"
function ggrep
    command "$TEST_GREP" $argv
end
FISH
    is( $result->{stdout}, "1:  needle\n", 'grepw matches indentation rather than a literal plus' );
}

sub rootimg_treats_a_leading_dash_as_a_filename {
    my ($self) = @_;
    for my $paths (
        [ '-photo with spaces.png',               './-photo with spaces-root.png' ],
        [ 'photo with spaces.png',                './photo with spaces-root.png' ],
        [ "$self->{root}/-photo with spaces.png", "$self->{root}/-photo with spaces-root.png" ],
      )
    {
        $self->{env}{TEST_IMAGE} = $paths->[0];
        my $result = fish( $self, <<'FISH' );
function magick
    printf '%s\0' $argv > "$TEST_ROOT/magick-arguments"
end
rootimg "$TEST_IMAGE"
FISH
        is_deeply(
            [ split /\0/, read_file("$self->{root}/magick-arguments") ],
            [ '--', $paths->[0], '-resize', '50%', $paths->[1] ],
            "ImageMagick receives $paths->[0] unchanged after the option separator"
        );
        is( $result->{stderr}, '', 'the image path produces no option diagnostics' );
    }
}

sub mcd_rejects_multiple_arguments_before_creating_anything {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
mcd -m 700 newdir 2>/dev/null
printf '%s\n' "$status"
mcd first second 2>/dev/null
printf '%s\n' "$status"
mcd 2>/dev/null
printf '%s\n' "$status"
printf '%s\n' "$PWD"
FISH
    is( $result->{stdout}, "1\n1\n1\n$self->{root}\n",
        'invalid argument counts fail without changing directory' );
    ok( !-e "$self->{root}/-m 700 newdir" && !-e "$self->{root}/first second",
        'invalid arguments create no directories' );
}

sub mcd_enters_one_literal_directory {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
mcd '-project name'; or exit 1
printf '%s\n' "$PWD"
FISH
    is(
        $result->{stdout},
        "$self->{root}/-project name\n",
        'a single leading-dash path with spaces is created and entered'
    );
    ok( -d "$self->{root}/-project name", 'the intended directory exists' );
}

run_cases(
    {
        mcd_rejects_multiple_arguments_before_creating_anything =>
          \&mcd_rejects_multiple_arguments_before_creating_anything,
        mcd_enters_one_literal_directory                    => \&mcd_enters_one_literal_directory,
        aliases_added_after_initialization_are_exported => \&aliases_added_after_initialization_are_exported,
        realpath_failure_does_not_clear_the_clipboard   => \&realpath_failure_does_not_clear_the_clipboard,
        realpath_success_preserves_spaces_and_leading_dashes =>
          \&realpath_success_preserves_spaces_and_leading_dashes,
        grepw_uses_an_extended_whitespace_quantifier => \&grepw_uses_an_extended_whitespace_quantifier,
        rootimg_treats_a_leading_dash_as_a_filename  => \&rootimg_treats_a_leading_dash_as_a_filename,
    },
    \&setup
);
