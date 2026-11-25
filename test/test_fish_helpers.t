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
} qw(aqsnow_fzf_diralis_add aqsnow_init_rendezvous aqsnow_run_requested realpathc __grep_smart_case grep reload);
for my $name (qw(fd fdg)) {
    my ($alias) = $config =~ /^(alias \Q$name\E=.+)$/m;
    die "Missing $name alias" unless defined $alias;
    $helpers .= "$alias\n";
}
$helpers .= read_file("$root/fish/functions/rootimg.fish");
$helpers .= read_file("$root/fish/functions/sshv.fish");
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
        TEST_CD         => "$root/fish/cd.fish",
        TERM            => 'dumb',
    };
}

sub fish {
    my ( $self, $body, $flags ) = @_;
    $flags //= [];
    return run_command(
        [ 'fish', '--no-config', @$flags, '-c', "$helpers\n$body" ],
        {
            cwd   => $self->{root},
            env   => $self->{env},
            check => 1,
        }
    );
}

sub sshv_preserves_remote_paths {
    my ($self) = @_;
    make_path("$self->{root}/project files");
    my $literal = q{project's $(touch injected); files};
    make_path("$self->{root}/$literal");
    $self->{env}{TEST_REMOTE_PATH} = $literal;
    my $result = fish( $self, <<'FISH' );
function ssh
    command sh -c "$argv[3]"
end
function nvim
    printf '%s\n' $argv
end
sshv server
sshv user@server 'project files'
sshv user@server 'project files/'
sshv server "$TEST_ROOT/project files"
sshv server /etc/hosts
sshv server "$TEST_REMOTE_PATH"
sshv 2>/dev/null
printf '%s\n' "$status"
sshv server first second 2>/dev/null
printf '%s\n' "$status"
FISH
    is(
        $result->{stdout},
        "--\nscp://server/\n--\nscp://user\@server/project files/\n--\nscp://user\@server/project files/\n"
          . "--\nscp://server/$self->{root}/project files/\n--\nscp://server//etc/hosts\n"
          . "--\nscp://server/$literal/\n1\n1\n",
        'remote directories gain a slash while files, quoted paths, and invalid calls remain correct'
    );
    ok( !-e "$self->{root}/injected", 'remote path metacharacters remain literal' );
}

sub sshv_expands_only_remote_home_prefixes {
    my ($self) = @_;
    my $home = "$self->{root}/remote home's \$(literal)";
    make_path( "$home/notes", "$self->{root}/\$HOME" );
    write_file( "$home/report's [draft].txt", 'remote file' );
    write_file( "$self->{root}/\$HOME/notes", 'literal variable path' );
    write_file( "$self->{root}/~someone",     'literal named tilde path' );
    $self->{env}{TEST_REMOTE_HOME} = $home;
    my $result = fish( $self, <<'FISH' );
function ssh
    HOME="$TEST_REMOTE_HOME" command sh -c "$argv[3]"
end
function nvim
    printf '%s\n' $argv
end
sshv server '~'
sshv server '~/'
sshv server '~/notes'
sshv server "~/report's [draft].txt"
sshv server '$HOME/notes'
sshv server '~someone'
FISH
    is(
        $result->{stdout},
        "--\nscp://server/~/\n--\nscp://server/~/\n--\nscp://server/~/notes/\n"
          . "--\nscp://server/~/report's [draft].txt\n--\nscp://server/\$HOME/notes\n"
          . "--\nscp://server/~someone\n",
        'remote home prefixes expand only for the probe while editor URLs and other paths stay literal'
    );
    is( $result->{stderr}, '', 'quoted remote home paths have no filesystem errors' );
}

sub sshv_stops_on_ssh_failure {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
function ssh
    printf 'ssh: Connection refused\n' >&2
    return 255
end
function nvim
    printf 'editor opened\n'
end
sshv server
printf '%s\n' "$status"
FISH
    is( $result->{stdout}, "255\n", 'SSH failure is returned without opening the editor' );
    is( $result->{stderr}, "ssh: Connection refused\n", 'the SSH diagnostic is preserved' );
}

sub sshv_stops_on_missing_paths {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
function ssh
    command sh -c "$argv[3]"
end
function nvim
    printf 'editor opened\n'
end
sshv server 'missing path'
printf '%s\n' "$status"
FISH
    like( $result->{stdout}, qr/\A[1-9][0-9]*\n\z/,
        'a missing remote path fails without opening the editor' );
    like(
        $result->{stderr},
        qr/missing path.*No such file|No such file.*missing path/,
        'the remote filesystem error is preserved'
    );
}

sub nvim_preserves_native_command_line_options {
    my ($self) = @_;
    $self->{env}{TEST_NVIM_WRAPPER} = "$root/fish/functions/nvim.fish";
    write_file( "$self->{root}/bin/nvim", '#!' . perl_executable() . "\n" . <<'PERL' );
use JSON::PP;
open my $log, '>>', "$ENV{TEST_ROOT}/nvim-calls" or die $!;
print {$log} encode_json(\@ARGV), "\n";
exit 23;
PERL
    chmod 0755, "$self->{root}/bin/nvim";
    my $result = fish( $self, <<'FISH' );
source "$TEST_NVIM_WRAPPER"
set -e NVIM
nvim -- 'outside file'
printf '%s\n' "$status"
set -gx NVIM "$TEST_ROOT/socket"
nvim -u NONE 'inside file'
printf '%s\n' "$status"
nvim -
printf '%s\n' "$status"
nvim +42 'inside file'
printf '%s\n' "$status"
FISH
    is_deeply(
        [ map { decode_json($_) } split /\n/, read_file("$self->{root}/nvim-calls") ],
        [ [ '--', 'outside file' ], [ '-u', 'NONE', 'inside file' ], ['-'], [ '+42', 'inside file' ] ],
        'ordinary launches and native options reach Neovim unchanged'
    );
    is( $result->{stdout}, "23\n23\n23\n23\n", 'native exit statuses are preserved' );
}

sub nvim_preserves_piped_standard_input {
    my ($self) = @_;
    $self->{env}{TEST_NVIM_WRAPPER} = "$root/fish/functions/nvim.fish";
    write_file( "$self->{root}/bin/nvim", '#!' . perl_executable() . "\n" . <<'PERL' );
use JSON::PP;
open my $log, '>', "$ENV{TEST_ROOT}/nvim-calls" or die $!;
print {$log} encode_json(\@ARGV);
local $/;
print <STDIN>;
exit 23;
PERL
    chmod 0755, "$self->{root}/bin/nvim";
    my $result = fish( $self, <<'FISH' );
source "$TEST_NVIM_WRAPPER"
set -gx NVIM "$TEST_ROOT/socket"
printf 'piped text\n' | nvim
printf '%s\n' "$status"
FISH
    is( $result->{stdout}, "piped text\n23\n", 'piped input and the native exit status are preserved' );
    is_deeply( decode_json( read_file("$self->{root}/nvim-calls") ),
        [], 'piped input launches Neovim without an RPC request' );
}

sub fd_defaults_respect_ignores_and_follow_symlinks {
    my ($self) = @_;
    plan skip_all => 'fd is needed to test filename search' unless which('fd');
    make_path( "$self->{root}/ignored", "$self->{root}/target" );
    write_file( "$self->{root}/.gitignore",    "ignored/\n" );
    write_file( "$self->{root}/.hidden",       'contents' );
    write_file( "$self->{root}/ignored/found", 'contents' );
    write_file( "$self->{root}/target/found",  'contents' );
    symlink 'target', "$self->{root}/link" or die $!;
    my $result = fish( $self, <<'FISH' );
fd --type file -- '^[.]|found' | sort
printf 'glob:\n'
fdg '*found*' | sort
FISH
    is(
        $result->{stdout},
        ".gitignore\n.hidden\nlink/found\ntarget/found\nglob:\nlink/found\ntarget/found\n",
        'fd and fdg follow links and respect ignores outside Git, including hidden paths'
    );

    make_path("$self->{root}/.git");
    write_file( "$self->{root}/.git/found", 'contents' );
    $result = fish( $self, q{fdg '*found*' | sort} );
    is( $result->{stdout}, "link/found\ntarget/found\n",
        'fdg inherits fd ignore rules and excludes .git inside Git repositories' );
}

sub find_names_respect_ignores {
    my ($self) = @_;
    plan skip_all => 'fd is needed to test filename search' unless which('fd');
    make_path("$self->{root}/match-dir");
    write_file( "$self->{root}/.gitignore",         "ignored*\n" );
    write_file( "$self->{root}/ignored-match-file", 'contents' );
    write_file( "$self->{root}/match-file",         'contents' );
    write_file( "$self->{root}/.match-hidden",      'contents' );
    write_file( "$self->{root}/Match-upper",        'contents' );
    my $result = fish( $self, <<'FISH' );
fdg '*match*' | sort
printf 'uppercase:\n'
fdg '*Match*'
printf 'glob:\n'
fdg 'match-?ile'
FISH
    is(
        $result->{stdout},
        ".match-hidden\nMatch-upper\nmatch-dir/\nmatch-file\nuppercase:\nMatch-upper\nglob:\nmatch-file\n",
        'fdg finds files, directories and hidden entries with glob smart case while respecting ignores'
    );
}

sub rendezvous_routes_both_file_pickers {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -gx AQSNOW_FISH_RENDEZVOUS "$TEST_ROOT/request"
function fzf_accept_and_run
    printf '%s\n' $argv
end
for request in '<M-v>' recent exec
    printf '%s\n' "$request" > "$AQSNOW_FISH_RENDEZVOUS"
    aqsnow_run_requested
    printf '%s\n' "$status"
    test ! -e "$AQSNOW_FISH_RENDEZVOUS"; or exit 1
end
FISH
    is(
        $result->{stdout},
        "fzf-path-widget\n1\nfzf-recent-widget\n1\n0\n",
        'normal and recent pickers consume their requests without executing the command'
    );
}

sub aliases_added_after_initialization_are_exported {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -eg aqsnow_fzf_diralis
aqsnow_fzf_diralis_add HOME
aqsnow_init_rendezvous; or exit 1
set -l original "$__aqsnow_rendezvous_dir"
set -g project "$TEST_ROOT"
aqsnow_fzf_diralis_add project; or exit 2
aqsnow_fzf_diralis_add project; or exit 3
fish --no-config -c 'printf "%s\n%s\n" "$AQSNOW_DIRALIS" "$project"'
aqsnow_init_rendezvous; or exit 4
test "$original" = "$__aqsnow_rendezvous_dir"; or exit 5
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
printf '%s\n' "$status"
FISH
    like( $result->{stdout}, qr/^[1-9][0-9]*\n$/, 'failed resolution returns a failing status' );
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

sub reload_skips_history_merge_in_private_mode {
    my ($self) = @_;
    make_path("$self->{root}/config/fish");
    write_file( "$self->{root}/config/fish/config.fish", "set -g loaded yes\n" );
    my $result = fish( $self, <<'FISH', ['--private'] );
reload; or exit 1
printf '%s\n' "$loaded"
FISH
    is( $result->{stdout}, "yes\n", 'private reload still sources the configuration' );
    is( $result->{stderr}, '',      'private reload does not attempt the forbidden history merge' );
}

sub reload_merges_history_and_preserves_source_failures {
    my ($self) = @_;
    make_path("$self->{root}/config/fish");
    write_file( "$self->{root}/config/fish/config.fish", "set -g loaded yes\n" );
    my $result = fish( $self, <<'FISH' );
set -e fish_private_mode
function history
    printf '%s\n' $argv
end
reload; or exit 1
printf '%s\n' "$loaded"
FISH
    is( $result->{stdout}, "merge\nyes\n",
        'ordinary reload still merges history after sourcing configuration' );
    write_file( "$self->{root}/config/fish/config.fish", "return 7\n" );
    $result = fish( $self, <<'FISH' );
set -e fish_private_mode
function history
    printf 'unexpected merge\n'
end
reload
printf '%s\n' "$status"
FISH
    is( $result->{stdout}, "7\n", 'source failure is returned without running history merge' );
}

sub cdf_completes_files_while_retaining_cd_wrapping {
    my ($self) = @_;
    make_path("$self->{root}/alpha_dir");
    write_file( "$self->{root}/alpha_file.txt", 'contents' );
    my $result = fish( $self, <<'FISH' );
function abbrali
end
source "$TEST_CD"; or exit 1
complete -C 'cdf alpha'
complete -c cdf
FISH
    like( $result->{stdout}, qr/^alpha_dir\//m,      'directory completion is retained' );
    like( $result->{stdout}, qr/^alpha_file\.txt$/m, 'regular files are also offered' );
    like( $result->{stdout}, qr/--wraps[= ]'?cd'?/,  'cdf still inherits the cd completions' );
}

sub configured_temp_directory_is_aliased {
    my ($self) = @_;
    $self->{env}{TEST_DOTFILES} = $root;
    my ($registration) = $config =~ /^(aqsnow_fzf_diralis_add .+)$/m;
    my $result = fish( $self, $registration . "\n" . <<'FISH' );
set -p fish_function_path "$TEST_DOTFILES/fish/functions"
fish --no-config -c 'contains -- TMPDIR $(string split : -- "$AQSNOW_DIRALIS"); or exit 1'; or exit
aqsnow_fzf_path_alias "$TMPDIR/example"
FISH
    is( $result->{returncode}, 0, 'the configured temporary-directory alias reaches child processes' );
    is( $result->{stdout}, "\$TMPDIR/example\0", 'temporary paths use the automatically registered alias' );
}

sub alias_registration_updates_the_exported_name_list {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -eg aqsnow_fzf_diralis
aqsnow_fzf_diralis_add HOME
aqsnow_fzf_diralis_add aqsnow_test_late aqsnow_test_late
printf '%s\n' "$AQSNOW_DIRALIS"
set -qx aqsnow_test_late; or exit 1
test -z "$aqsnow_test_late"
FISH
    is( $result->{stdout},     "HOME:aqsnow_test_late\n", 'registration immediately exports unique names' );
    is( $result->{returncode}, 0, 'unset aliases are marked exported before their values are assigned' );
}

sub alias_values_defined_later_keep_the_export_attribute {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -eg aqsnow_fzf_diralis
aqsnow_fzf_diralis_add HOME
aqsnow_fzf_diralis_add aqsnow_test_late
set -g aqsnow_test_late /first
sh -c 'printf "%s\n" "$aqsnow_test_late"'
set -g aqsnow_test_late /second
sh -c 'printf "%s\n" "$aqsnow_test_late"'
set -gu aqsnow_test_late /third
aqsnow_fzf_diralis_add aqsnow_test_late
sh -c 'printf "%s\n" "$aqsnow_test_late"'
FISH
    is( $result->{stdout}, "/first\n/second\n/third\n",
        'later assignments retain export and re-registration exports explicitly unexported values' );
}

sub alias_registration_appends_only_new_names {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -eg aqsnow_fzf_diralis
set -gx AQSNOW_DIRALIS inherited:stale
aqsnow_fzf_diralis_add HOME first HOME
printf '%s\n' "$AQSNOW_DIRALIS"
set -g changes 0
function name_changed --on-variable AQSNOW_DIRALIS
    set -g changes "$(math "$changes + 1")"
end
aqsnow_fzf_diralis_add first HOME
aqsnow_fzf_diralis_add
printf '%s\n' "$changes"
aqsnow_fzf_diralis_add second second third
printf '%s\n' "$AQSNOW_DIRALIS"
sh -c 'printf "%s\n" "$AQSNOW_DIRALIS"'
printf '%s\n' "$(count $aqsnow_fzf_diralis)"
FISH
    is(
        $result->{stdout},
        "HOME:first\n0\nHOME:first:second:third\nHOME:first:second:third\n4\n",
        'fresh registration discards inherited names, preserves order, and does not rewrite duplicates'
    );
}

sub initialized_alias_exports_are_not_rewritten {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -eg aqsnow_fzf_diralis
aqsnow_fzf_diralis_add HOME
set -gx aqsnow_test_exported /existing
aqsnow_fzf_diralis_add aqsnow_test_exported
set -g changes 0
function name_changed --on-variable AQSNOW_DIRALIS
    set -g changes "$(math "$changes + 1")"
end
function value_changed --on-variable aqsnow_test_exported
    set -g changes "$(math "$changes + 1")"
end
aqsnow_fzf_diralis_add HOME aqsnow_test_exported
aqsnow_fzf_diralis_add aqsnow_test_exported
aqsnow_init_rendezvous
aqsnow_init_rendezvous
printf '%s\n' "$changes"
FISH
    is( $result->{stdout}, "0\n", 'registration and initialization do not rewrite exported names or values' );
}

sub alias_reregistration_refreshes_resolved_paths {
    my ($self) = @_;
    make_path( "$self->{root}/first", "$self->{root}/second" );
    symlink 'first', "$self->{root}/logical" or die $!;
    my $result = fish( $self, <<'FISH' );
source "$(path dirname -- "$TEST_CD")/functions/aqsnow_fzf_path_alias.fish"
set -g aqsnow_fzf_diralis
set -g project "$TEST_ROOT/logical"
aqsnow_fzf_diralis_add project
aqsnow_fzf_path_alias "$TEST_ROOT/first/file"
command rm -- "$project"
command ln -s second "$project"
aqsnow_fzf_diralis_add project
aqsnow_fzf_path_alias "$TEST_ROOT/second/file"
set -g project "$TEST_ROOT/first"
aqsnow_fzf_path_alias "$TEST_ROOT/first/file"
FISH
    is(
        $result->{stdout},
        "\$project/file\0" x 3,
        're-registration and changed values refresh resolved aliases'
    );
}

run_cases(
    {
        alias_reregistration_refreshes_resolved_paths   => \&alias_reregistration_refreshes_resolved_paths,
        fd_defaults_respect_ignores_and_follow_symlinks => \&fd_defaults_respect_ignores_and_follow_symlinks,
        find_names_respect_ignores                      => \&find_names_respect_ignores,
        rendezvous_routes_both_file_pickers             => \&rendezvous_routes_both_file_pickers,
        sshv_preserves_remote_paths                     => \&sshv_preserves_remote_paths,
        sshv_stops_on_ssh_failure                       => \&sshv_stops_on_ssh_failure,
        sshv_expands_only_remote_home_prefixes          => \&sshv_expands_only_remote_home_prefixes,
        sshv_stops_on_missing_paths                     => \&sshv_stops_on_missing_paths,
        nvim_preserves_native_command_line_options      => \&nvim_preserves_native_command_line_options,
        nvim_preserves_piped_standard_input             => \&nvim_preserves_piped_standard_input,
        configured_temp_directory_is_aliased            => \&configured_temp_directory_is_aliased,
        alias_registration_updates_the_exported_name_list =>
          \&alias_registration_updates_the_exported_name_list,
        alias_registration_appends_only_new_names            => \&alias_registration_appends_only_new_names,
        alias_values_defined_later_keep_the_export_attribute =>
          \&alias_values_defined_later_keep_the_export_attribute,
        initialized_alias_exports_are_not_rewritten     => \&initialized_alias_exports_are_not_rewritten,
        cdf_completes_files_while_retaining_cd_wrapping => \&cdf_completes_files_while_retaining_cd_wrapping,
        mcd_rejects_multiple_arguments_before_creating_anything =>
          \&mcd_rejects_multiple_arguments_before_creating_anything,
        mcd_enters_one_literal_directory                    => \&mcd_enters_one_literal_directory,
        reload_skips_history_merge_in_private_mode          => \&reload_skips_history_merge_in_private_mode,
        reload_merges_history_and_preserves_source_failures =>
          \&reload_merges_history_and_preserves_source_failures,
        aliases_added_after_initialization_are_exported => \&aliases_added_after_initialization_are_exported,
        realpath_failure_does_not_clear_the_clipboard   => \&realpath_failure_does_not_clear_the_clipboard,
        realpath_success_preserves_spaces_and_leading_dashes =>
          \&realpath_success_preserves_spaces_and_leading_dashes,
        grepw_uses_an_extended_whitespace_quantifier => \&grepw_uses_an_extended_whitespace_quantifier,
        rootimg_treats_a_leading_dash_as_a_filename  => \&rootimg_treats_a_leading_dash_as_a_filename,
    },
    \&setup
);
