use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'fish-completions-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{directory} = "$self->{temporary}/parent.name/current";
    make_path( "$self->{directory}/folder", "$self->{temporary}/home" );
    write_file( "$self->{directory}/folder/inside.txt", '' );
    write_file( "$self->{directory}/$_",                '' ) for qw(image.png paper.tex readme.txt);
    $self->{env} = {
        %ENV,
        HOME             => "$self->{temporary}/home",
        XDG_CONFIG_HOME  => "$self->{temporary}/config",
        XDG_DATA_HOME    => "$self->{temporary}/data",
        TEST_COMPLETIONS => "$root/fish/completions",
        TEST_FUNCTIONS   => "$root/fish/functions",
    };
}

sub fish {
    my ( $self, $script, @args ) = @_;
    return run_command(
        [
            'fish',             '--no-config', '-c',
            <<'FISH' . $script, '--',          @args
set -g fish_function_path "$TEST_FUNCTIONS" "$__fish_data_dir/functions"
set -g fish_complete_path "$TEST_COMPLETIONS" "$__fish_data_dir/completions"
FISH
        ],
        { cwd => $self->{directory}, env => $self->{env}, check => 1 }
    );
}

sub completions {
    my ( $self, $line ) = @_;
    my $result = fish( $self, 'complete -C "$argv[1]"', $line );
    is( $result->{stderr}, '', "$line completes without diagnostics" );
    return [ map { ( split /\t/, $_, 2 )[0] } split /\n/, $result->{stdout} ];
}

sub lazy_loading {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
printf '%s\n' "$(count $(complete -c cdf))"
complete -C 'cdf ' >/dev/null
test -n "$(complete -c cdf)"; or exit 1
printf '%s\n' "$(count $(complete -c rootimg))"
not functions -q __fish_up_parents
FISH
    is( $result->{stdout}, "0\n0\n", 'only the requested completion file is loaded' );
}

sub paths_and_commands {
    my ($self) = @_;
    is_deeply( completions( $self, 'mcd ' ), ['folder/'], 'mcd completes only directories' );
    ok( contains_value( completions( $self, 'mcd -' ), '-m' ), 'mcd retains native mkdir completion' );
    is_deeply(
        completions( $self, 'cdf ' ),
        [qw(folder/ image.png paper.tex readme.txt)],
        'cdf completes files as well as directories'
    );
    ok( contains_value( completions( $self, 'cdf --' ), '--help' ), 'cdf retains native cd completion' );
    is_deeply( completions( $self, 'cdc ' ), ['folder/'], 'cdc starts with a directory' );
    ok( contains_value( completions( $self, 'cdc folder git --ver' ), '--version' ),
        'cdc delegates later arguments to the nested command' );
    is_deeply( completions( $self, 'cdc folder cat ' ),
        ['inside.txt'], 'cdc completes command arguments in the target directory' );
    fish( $self, 'set -l before "$PWD"; complete -C "cdc folder cat " >/dev/null; test "$PWD" = "$before"' );
    ok(
        contains_value( completions( $self, 'up parent' ), 'parent\\.name' ),
        'up completes literal parent directory names as regular expressions'
    );
}

sub typed_files_and_stdin {
    my ($self) = @_;
    is( completions( $self, 'rootimg ' )->[0], 'image.png', 'rootimg prioritizes image files' );
    ok( contains_value( completions( $self, 'rootimg --' ), '--help' ), 'rootimg completes its help option' );
    is_deeply( completions( $self, 'rootimg image.png ' ), [], 'rootimg takes one image' );
    is( completions( $self, 'tex ' )->[0], 'paper.tex', 'tex prioritizes TeX source files' );
    is_deeply( completions( $self, 'tex paper.tex ' ), [], 'tex takes one source file' );
    ok( contains_value( completions( $self, 'biglines ' ), '-' ),          'biglines offers standard input' );
    ok( contains_value( completions( $self, 'biglines ' ), 'readme.txt' ), 'biglines also completes files' );
    is_deeply( completions( $self, 'biglines readme.txt ' ), [], 'biglines takes one input' );
}

sub no_arguments_or_pattern {
    my ($self) = @_;
    is_deeply( completions( $self, "$_ " ), [], "$_ does not suggest unrelated files" )
      for qw(note scd reload colors watchbell);
}

sub custom_argument_types {
    my ($self) = @_;
    ok( contains_value( completions( $self, 'fair --' ), '--date1' ), 'fair offers date options' );
    is_deeply( completions( $self, 'fair --date1 ' ),      [], 'a date does not complete local files' );
    is_deeply( completions( $self, 'fair --sort ' ),       [], 'sort does not take a count or files' );
    is_deeply( completions( $self, 'fair --sort --date' ), [], 'sort excludes date options' );
    is_deeply( completions( $self, 'fair --date1 2026-11-01 --s' ), [], 'date options exclude sort' );
    ok( contains_value( completions( $self, 'fair --date1 2026-11-01 --date2 2026-11-30 ' ), '1' ),
        'fair completes the count after date options' );
    my $result = fish( $self, <<'FISH' );
function abbrali; end
function cdpath_add; end
complete -C 'abbrali shortcut git --ver'
set -g CDPATH /example/anchor
complete -C 'cdpath_add --after '
FISH
    like( $result->{stdout}, qr/^--version\t/m,       'abbrali completes the command after its name' );
    like( $result->{stdout}, qr{^/example/anchor\t}m, 'CDPATH insertion uses existing anchors' );
    unlike( $result->{stdout}, qr{^folder/}m, 'an anchor does not offer unrelated directories' );
    is_deeply( completions( $self, 'sshv example-host ' ),
        [], 'remote paths do not suggest local files or start a connection' );
}

sub native_wrapper_completions {
    my ($self) = @_;
    ok( contains_value( completions( $self, 'realpathc ' ), 'readme.txt' ),
        'realpathc retains normal path completion' );
    ok( contains_value( completions( $self, 'noti git --ver' ), '--version' ),
        'noti inherits command completion from time' );
    ok( contains_value( completions( $self, 'nvim --he' ), '--help' ), 'nvim inherits its native options' );
    ok( contains_value( completions( $self, 'touch -' ),   '-a' ),     'touch inherits its native options' );
}

sub installer_wiring {
    my ($self) = @_;
    like( read_file("$root/install.sh"),
        qr{^\./fish/install\.sh$}m, 'the root installer delegates Fish setup' );
    my %env = ( %{ $self->{env} }, NO_OVERWRITE => '' );
    my $run = sub {
        run_command( ["$root/fish/install.sh"], { cwd => $self->{temporary}, env => \%env } );
    };
    my $result = $run->();
    is( $result->{returncode}, 0, "the Fish installer works from another directory: $result->{stderr}" );
    my $config = "$self->{env}{HOME}/.config/fish";
    is( readlink("$config/$_"), "$root/fish/$_", "links $_" ) for qw(config.fish functions completions);

    write_file( "$self->{temporary}/custom.fish", '' );
    unlink "$config/config.fish" or die $!;
    symlink "$self->{temporary}/custom.fish", "$config/config.fish" or die $!;
    $result = $run->();
    is( $result->{returncode}, 0, "reinstallation succeeds: $result->{stderr}" );
    is(
        readlink("$config/config.fish"),
        "$self->{temporary}/custom.fish",
        'preserves an existing config symlink'
    );
    unlike(
        read_file("$root/fish/config.fish"),
        qr/^\s*complete\b[^\n]*\bcdf\b/m,
        'cdf completion is not registered eagerly during startup'
    );
}

run_cases(
    {
        lazy_loading               => \&lazy_loading,
        paths_and_commands         => \&paths_and_commands,
        typed_files_and_stdin      => \&typed_files_and_stdin,
        no_arguments_or_pattern    => \&no_arguments_or_pattern,
        custom_argument_types      => \&custom_argument_types,
        native_wrapper_completions => \&native_wrapper_completions,
        installer_wiring           => \&installer_wiring,
    },
    \&setup
);
