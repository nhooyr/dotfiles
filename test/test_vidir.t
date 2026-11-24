use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use File::Basename   qw(basename dirname);
use Text::ParseWords qw(shellwords);

my $program = absolute_path("$FindBin::Bin/../bin/vidir");

sub setup {
    my ($self) = @_;
    $self->{root} = tempdir( 'vidir-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $root = $self->{root};
    make_path( "$root/source dir/nested/deep", "$root/temp files", "$root/editor bin" );
    $self->{directory} = "$root/source dir";
    write_file( "$self->{directory}/original",             'content' );
    write_file( "$self->{directory}/.hidden",              'hidden' );
    write_file( "$self->{directory}/literal ' \$HOME;[x]", 'literal' );
    write_file( "$self->{directory}/nested/child",         'child' );
    write_file( "$self->{directory}/nested/deep/leaf",     'leaf' );
    symlink 'nested', "$self->{directory}/link"   or die $!;
    symlink 'absent', "$self->{directory}/broken" or die $!;
    my $editor = "$root/editor bin/editor";
    write_file( $editor, '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
use JSON::PP;
if ($ENV{TEST_RUN_IN_EDITOR}) {
    die "script is not executable in editor\n" unless -x $ARGV[-1];
    system { $ARGV[-1] } $ARGV[-1];
    die "script failed in editor\n" if $?;
    open my $marker, '>', "$ARGV[-1].ran" or die $!;
    close $marker;
}
open my $log, '>', $ENV{TEST_EDITOR_LOG} or die $!;
print {$log} encode_json(\@ARGV);
close $log;
open my $input, '<', $ARGV[-1] or die $!;
local $/;
my $script = <$input>;
close $input;
$script =~ s/^# mv -v -- original original$/mv -v -- original renamed/m if $ENV{TEST_RENAME};
open my $output, '>', "$ARGV[-1].new" or die $!;
print {$output} $script;
close $output;
rename "$ARGV[-1].new", $ARGV[-1] or die $!;
exit($ENV{TEST_EDITOR_FAIL} // 0);
PERL
    chmod 0755, $editor;
    $self->{env} = {
        %ENV,
        EDITOR              => shell_quote($editor) . ' --test-option',
        TMPDIR              => "$root/temp files",
        HOME                => $root,
        AQSNOW_DIRALIS      => 'HOME:TEST_PROJECT',
        TEST_PROJECT        => $self->{directory},
        TEST_EDITOR_LOG     => "$root/editor.json",
        TEST_RENAME         => '',
        TEST_EDITOR_FAIL    => 0,
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
    };
}

sub invoke {
    my ( $self, @args ) = @_;
    return run_command( [ $program, @args ], { cwd => $self->{directory}, env => $self->{env} } );
}

sub script_path {
    my ( $self, $result, $options ) = @_;
    $options //= ['--test-option'];
    is( $result->{returncode}, 0, $result->{stderr} );
    my $expanded = run_command(
        [ 'sh', '-c', q{printf '%s\0' } . $result->{stdout} ],
        { cwd => $self->{root}, env => $self->{env}, check => 1 }
    );
    my @command = split /\0/, $expanded->{stdout};
    is( scalar @command, 1, 'prints one shell-quoted executable path' );
    ok( -x $command[0], 'the generated script is executable' );
    is(
        absolute_path( dirname( $command[0] ) ),
        absolute_path("$self->{env}{TMPDIR}/vidir"),
        'scripts use the vidir temporary directory'
    );
    my @arguments = @{ decode_json( read_file( $self->{env}{TEST_EDITOR_LOG} ) ) };
    my $path      = pop @arguments;
    is_deeply( \@arguments, $options, 'the editor receives its configured arguments' );
    is(
        absolute_path($path),
        absolute_path( $command[0] ),
        'the printed command resolves to the edited script'
    );
    return $command[0];
}

sub lists_immediate_entries_and_quotes_names {
    my ($self) = @_;
    my $path = script_path( $self, invoke($self) );
    like(
        basename($path),
        qr/\Asource dir\.[A-Za-z0-9_]{6}\.sh\z/,
        'the short script name uses the directory basename'
    );
    my @lines = split /\n/, read_file($path);
    is_deeply(
        [ @lines[ 0 .. 2 ] ],
        [ '#!/bin/sh', 'set -eu', 'cd -- "$TEST_PROJECT"' ],
        'the script has a self-contained header with a safely quoted directory alias'
    );
    my @operands;
    for my $line ( @lines[ 3 .. $#lines ] ) {
        like( $line, qr/^# mv /, 'move commands start commented out' );
        $line =~ s/^# //;
        my @words = shellwords($line);
        is_deeply( [ @words[ 0 .. 2 ] ], [ 'mv', '-v', '--' ], 'each line uses the default mv command' );
        is( $words[3], $words[4], 'each filename is initially unchanged' );
        push @operands, $words[3];
    }
    is_deeply(
        \@operands,
        [ 'link', 'nested/', '.hidden', 'broken', q{literal ' $HOME;[x]}, 'original' ],
        'includes hidden files, special names, directories, and broken links without recursing'
    );
    ok( -f "$self->{directory}/original", 'generation performs no file operations' );
    my $result = run_command( [$path], { cwd => $self->{root}, env => $self->{env} } );
    is( $result->{returncode}, 0, 'running an unchanged script succeeds without moving directory entries' );
    ok( -d "$self->{directory}/nested",   'an unchanged script leaves directories intact' );
    ok( -f "$self->{directory}/original", 'an unchanged script leaves files intact' );
}

sub quotes_ascii_directory_aliases {
    my ($self) = @_;
    my $directory = "$self->{root}/scratch";
    make_path("$directory/nested");
    $self->{env}{TEST_PROJECT} = $directory;
    for my $suffix ( '', '/nested' ) {
        my $path  = script_path( $self, invoke( $self, "$directory$suffix" ) );
        my @lines = split /\n/, read_file($path);
        is(
            $lines[2],
            'cd -- "$TEST_PROJECT' . $suffix . '"',
            'ASCII-only environment aliases and suffixes stay double-quoted'
        );
    }
    $self->{env}{HOME}           = $directory;
    $self->{env}{AQSNOW_DIRALIS} = 'HOME';
    my $path  = script_path( $self, invoke( $self, $directory ) );
    my @lines = split /\n/, read_file($path);
    is( $lines[2], 'cd -- ~', 'HOME retains its unquoted tilde expansion' );
}

sub printed_script_uses_directory_aliases {
    my ($self) = @_;
    my $physical = "$self->{root}/physical temp";
    make_path("$physical/vidir");
    symlink 'physical temp', "$self->{root}/temp link" or die $!;
    $self->{env}{TMPDIR}       = "$self->{root}/temp link";
    $self->{env}{TEST_SCRIPTS} = "$self->{env}{TMPDIR}/vidir";
    $self->{directory}         = "$self->{root}/" . q{project's "$(touch injected)" `printf danger` [x]};
    make_path( $self->{directory} );

    for my $case (
        [ 'HOME:TMPDIR',              qr/\A"\$TMPDIR\/vidir\// ],
        [ 'HOME:TMPDIR:TEST_SCRIPTS', qr/\A"\$TEST_SCRIPTS\// ],
        [ 'HOME',                     qr/\A~\// ],
        [ '',                         qr/\A'\// ],
      )
    {
        $self->{env}{AQSNOW_DIRALIS} = $case->[0];
        my $result = invoke($self);
        like( $result->{stdout}, $case->[1],
            'the printed script uses the longest available directory alias' );
        my $path = script_path( $self, $result );
        my $run =
          run_command( [ 'sh', '-c', $result->{stdout} ], { cwd => $self->{root}, env => $self->{env} } );
        is( $run->{returncode}, 0, 'the printed command runs from another directory' );
        ok( -f $path,                     'executing the printed command retains the script' );
        ok( !-e "$self->{root}/injected", 'metacharacters in the basename stay literal' );
    }
}

sub listed_paths {
    my ($path) = @_;
    return [ map { ( shellwords($_) )[3] } grep { s/^# (?=mv )// } split /\n/, read_file($path) ];
}

sub directory_markers_keep_move_commands_usable {
    my ($self) = @_;
    make_path("$self->{directory}/directory space");
    my $path   = script_path( $self, invoke($self) );
    my $script = read_file($path);
    like(
        $script,
        qr/^# mv -v -- 'directory space\/' 'directory space\/'$/m,
        'directory markers stay inside shell quotes'
    );
    like( $script, qr/^# mv -v -- link link$/m, 'directory symlinks keep their link identity' );
    $script =~ s{^# mv -v -- 'directory space/' 'directory space/'$}
        {mv -v -- 'directory space/' 'renamed directory/'}m;
    write_file( $path, $script );
    my $result = run_command( [$path], { cwd => $self->{root}, env => $self->{env} } );
    is( $result->{returncode}, 0, $result->{stderr} );
    ok( -d "$self->{directory}/renamed directory", 'the marked directory can be renamed' );
    ok( !-e "$self->{directory}/directory space",  'the original directory moved' );
    ok( -l "$self->{directory}/link",              'the symlink remains a symlink' );
}

sub ordering_matches_ls {
    my ($self) = @_;
    make_path( "$self->{directory}/dir10", "$self->{directory}/dir2" );
    write_file( "$self->{directory}/file10", 'ten' );
    write_file( "$self->{directory}/file2",  'two' );
    my $script = script_path( $self, invoke($self) );
    my $ls = run_command( [ 'gls', '-1Avp', '--group-directories-first', '--zero', '--', $self->{directory} ],
        { env => { %{ $self->{env} }, LC_COLLATE => 'C' }, check => 1 } );
    my @expected = split /\0/, $ls->{stdout};
    is_deeply( listed_paths($script), \@expected, 'ordering matches the configured GNU ls exactly' );
    my @paths = @{ listed_paths($script) };
    is_deeply(
        [ @paths[ 0 .. 3 ] ],
        [ 'dir2/', 'dir10/', 'link', 'nested/' ],
        'directories and directory links sort numerically first'
    );
    my %position;
    @position{@paths} = 0 .. $#paths;
    cmp_ok( $position{file2}, '<', $position{file10}, 'regular files use numeric ordering' );
}

sub git_ignore_and_override {
    my ($self) = @_;
    run_command( [ 'git', '-C', $self->{directory}, 'init', '--quiet' ],
        { env => $self->{env}, check => 1 } );
    write_file( "$self->{directory}/.gitignore",      "*.tmp\nbuild/\n!keep.tmp\n" );
    write_file( "$self->{directory}/skip.tmp",        'skip' );
    write_file( "$self->{directory}/keep.tmp",        'keep' );
    write_file( "$self->{directory}/nested/skip.tmp", 'skip' );
    write_file( "$self->{directory}/tracked.tmp",     'tracked' );
    run_command( [ 'git', '-C', $self->{directory}, 'add', '-f', '--', 'tracked.tmp' ],
        { env => $self->{env}, check => 1 } );
    make_path("$self->{directory}/build");
    write_file( "$self->{directory}/build/output", 'skip' );
    my $paths = listed_paths( script_path( $self, invoke( $self, '-r' ) ) );
    ok( grep( $_ eq 'keep.tmp', @$paths ), 'negated ignore rules keep matching paths' );
    ok(
        !grep( m{\A(?:\.git(?:/|\z)|build(?:/|\z)|skip\.tmp\z|nested/skip\.tmp\z)}, @$paths ),
        'Git metadata and ignored files or directories are excluded recursively'
    );
    ok( !grep( $_ eq 'tracked.tmp', @$paths ), 'ignore rules also apply to tracked files' );
    $paths = listed_paths( script_path( $self, invoke( $self, '-r', '--no-ignore' ) ) );
    ok( grep( $_ eq 'skip.tmp',     @$paths ), '--no-ignore includes ignored files' );
    ok( grep( $_ eq 'build/output', @$paths ), '--no-ignore visits ignored directories' );
    ok( grep( $_ eq '.git/config',  @$paths ), '--no-ignore includes Git metadata' );
}

sub ignore_files_outside_git_do_not_filter {
    my ($self) = @_;
    write_file( "$self->{directory}/.gitignore", 'original' );
    my $paths = listed_paths( script_path( $self, invoke($self) ) );
    ok( grep( $_ eq 'original', @$paths ), 'ignore rules apply only inside Git repositories' );
}

sub persistent_ignore_batches_preserve_rules {
    my ($self) = @_;
    my $directory = $self->{directory};
    run_command( [ 'git', '-C', $directory, 'init', '--quiet' ], { env => $self->{env}, check => 1 } );
    write_file( "$directory/.gitignore",        "*.tmp\n!keep.tmp\n" );
    write_file( "$directory/nested/.gitignore", "keep.tmp\n!saved.tmp\n" );
    write_file( "$directory/nested/keep.tmp",   'ignored' );
    write_file( "$directory/nested/saved.tmp",  'included' );
    my @kept;

    for my $i ( 0 .. 399 ) {
        my $name = sprintf 'file%04d-%s.%s', $i, 'x' x 160, $i % 2 ? 'tmp' : 'txt';
        write_file( "$directory/$name", 'contents' );
        push @kept, $name if $i % 2 == 0;
    }
    my $long = join '/', map { 'd' x 120 } 1 .. 4;
    make_path("$directory/$long");
    write_file( "$directory/$long/keep.tmp", 'included' );
    write_file( "$directory/$long/skip.tmp", 'ignored' );
    make_path("$self->{root}/bin");
    write_file( "$self->{root}/bin/git", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
if (grep { $_ eq 'check-ignore' } @ARGV) {
    open my $log, '>>', $ENV{TEST_GIT_LOG} or die $!;
    print {$log} "$$\n";
    close $log;
}
exec $ENV{TEST_GIT}, @ARGV;
die $!;
PERL
    chmod 0755, "$self->{root}/bin/git";
    $self->{env}{TEST_GIT}     = which('git');
    $self->{env}{TEST_GIT_LOG} = "$self->{root}/git.log";
    $self->{env}{PATH}         = "$self->{root}/bin:$ENV{PATH}";
    my $paths = listed_paths( script_path( $self, invoke( $self, '-r' ) ) );
    is_deeply( [ grep { /^file/ } @$paths ],
        \@kept, 'large batches keep version ordering and filter ignored names without filling the pipes' );
    ok( grep( $_ eq 'nested/saved.tmp', @$paths ), 'nested negation rules are retained' );
    ok( !grep( $_ eq 'nested/keep.tmp', @$paths ), 'nested rules override a parent negation' );
    ok( grep( $_ eq "$long/keep.tmp",   @$paths ), 'paths longer than a pipe atomic write are handled' );
    ok( !grep( $_ eq "$long/skip.tmp",  @$paths ), 'long ignored paths remain excluded' );
    is( scalar( split /\n/, read_file( $self->{env}{TEST_GIT_LOG} ) ),
        1, 'all visited directories share one ignore process' );
}

sub invalid_ignore_replies_stop_before_editor {
    my ($self) = @_;
    make_path("$self->{root}/bin");
    write_file( "$self->{root}/bin/git", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
$| = 1;
if (grep { $_ eq 'rev-parse' } @ARGV) { print "true\n"; exit }
print STDERR "expected git failure\n";
if ($ENV{TEST_GIT_PARTIAL}) { print "source\0"; exit }
local $/ = "\0";
while (<STDIN>) { print "\0\0\0$_" }
exit 2;
PERL
    chmod 0755, "$self->{root}/bin/git";
    $self->{env}{PATH} = "$self->{root}/bin:$ENV{PATH}";
    for my $partial ( 0, 1 ) {
        $self->{env}{TEST_GIT_PARTIAL} = $partial;
        my $result = invoke($self);
        isnt( $result->{returncode}, 0, 'incomplete replies or Git failure stop the scan' );
        like( $result->{stderr}, qr/expected git failure/, 'Git diagnostics remain visible' );
        is( $result->{stdout}, '', 'failed checks do not print a script command' );
        ok( !-e $self->{env}{TEST_EDITOR_LOG}, 'failed checks do not open the editor' );
    }
}

sub includes_its_own_script {
    my ($self) = @_;
    $self->{env}{TMPDIR} = $self->{directory};
    my $script   = script_path( $self, invoke( $self, '-r' ) );
    my $relative = 'vidir/' . basename($script);
    ok(
        grep( $_ eq $relative, @{ listed_paths($script) } ),
        'streaming includes its own output as a commented command'
    );
}

sub scan_errors_stop_before_editor {
    my ($self) = @_;
    for my $tool (qw(gls git)) {
        my $directory = "$self->{root}/failing-$tool";
        make_path($directory);
        my $script = "#!/bin/sh\n";
        $script .= "if [ \"\$3\" = rev-parse ]; then printf 'true\\n'; exit 0; fi\n" if $tool eq 'git';
        $script .= "printf 'expected scan error\\n' >&2\nexit 2\n";
        write_file( "$directory/$tool", $script );
        chmod 0755, "$directory/$tool";
        local $self->{env}{PATH} = "$directory:$ENV{PATH}";
        my $result = invoke($self);
        isnt( $result->{returncode}, 0, "$tool failure is returned" );
        like( $result->{stderr}, qr/expected scan error/, "$tool diagnostic stays visible" );
        is( $result->{stdout}, '', 'a failed scan does not print an executable command' );
        ok( !-e $self->{env}{TEST_EDITOR_LOG}, 'a failed scan does not open the editor' );
    }
}

sub recursion_keeps_parents_before_children {
    my ($self) = @_;
    my $path = script_path( $self, invoke( $self, '-r' ) );
    my @paths;
    for my $line ( split /\n/, read_file($path) ) {
        next unless $line =~ s/^# (?=mv )//;
        push @paths, ( shellwords($line) )[3];
    }
    my %position;
    @position{@paths} = 0 .. $#paths;
    ok( exists $position{'nested/deep/leaf'}, 'recursive mode includes deeply nested files' );
    cmp_ok(
        $position{'nested/deep/'},
        '<',
        $position{'nested/deep/leaf'},
        'parent directories precede their children'
    );
    cmp_ok( $position{'nested/'}, '<', $position{'nested/deep/'}, 'parents precede nested directories' );
    ok( exists $position{'link'},   'directory symlinks are included' );
    ok( !grep( m{^link/}, @paths ), 'directory symlinks are not followed' );
    my $long_option = script_path( $self, invoke( $self, '--recursive', $self->{directory} ) );
    is( read_file($long_option), read_file($path),
        '--recursive and an explicit directory produce the same listing' );
}

sub editor_changes_wait_for_manual_execution {
    my ($self) = @_;
    $self->{env}{TEST_RENAME} = 1;
    my $path = script_path( $self, invoke($self) );
    ok( -f "$self->{directory}/original", 'saving the script leaves the original file in place' );
    ok( !-e "$self->{directory}/renamed", 'saving does not run the edited command' );
    my $result = run_command( [$path], { cwd => $self->{root}, env => $self->{env} } );
    is( $result->{returncode}, 0, $result->{stderr} );
    ok( -f "$self->{directory}/renamed",   'the printed executable performs the rename when run' );
    ok( !-e "$self->{directory}/original", 'the old path is gone after execution' );
    ok( -f $path,                          'the script remains available after execution' );
}

sub editor_failure_keeps_script_without_command {
    my ($self) = @_;
    $self->{env}{TEST_EDITOR_FAIL} = 7;
    my $result = invoke($self);
    is( $result->{returncode}, 7,  'the editor failure status is preserved' );
    is( $result->{stdout},     '', 'cancellation does not print a command to run' );
    my $arguments = decode_json( read_file( $self->{env}{TEST_EDITOR_LOG} ) );
    ok( -f $arguments->[-1], 'the script is retained after cancellation' );
    like( $result->{stderr}, qr/editor failed; script kept at/, 'the retained script is identified' );
}

sub script_is_executable_inside_editor {
    my ($self) = @_;
    $self->{env}{TEST_RUN_IN_EDITOR} = 1;
    my $path = script_path( $self, invoke($self) );
    ok( -f "$path.ran",                   'the editor can execute the generated script' );
    ok( -x $path,                         'atomic editor replacement remains executable after exit' );
    ok( -f "$self->{directory}/original", 'running the unchanged script performs no moves' );
}

sub editor_without_options {
    my ($self) = @_;
    $self->{env}{EDITOR} = shell_quote("$self->{root}/editor bin/editor");
    script_path( $self, invoke($self), [] );
}

sub empty_alias_does_not_change_script_directory {
    my ($self) = @_;
    $self->{env}{AQSNOW_DIRALIS} = 'HOME:EMPTY:TEST_PROJECT';
    $self->{env}{EMPTY}          = '';
    $self->{env}{TEST_RENAME}    = 1;
    my $path = script_path( $self, invoke($self) );
    like( read_file($path), qr/^cd -- "\$TEST_PROJECT"$/m, 'the script uses the nonempty directory alias' );
    my $other = "$self->{root}/other";
    make_path($other);
    write_file( "$other/original", 'unrelated' );
    run_command( [$path], { cwd => $other, env => $self->{env}, check => 1 } );
    is( read_file("$self->{directory}/renamed"), 'content', 'the script operates in its original directory' );
    is( read_file("$other/original"),            'unrelated', 'the invocation directory is untouched' );
}

sub usage_and_missing_editor {
    my ($self) = @_;
    my $result = invoke( $self, '--help' );
    is( $result->{returncode}, 0, 'help succeeds' );
    like( $result->{stdout}, qr/--recursive/,     'help describes recursive mode' );
    like( $result->{stdout}, qr/--no-ignore/,     'help describes overriding Git ignore rules' );
    like( $result->{stdout}, qr/GNU ls ordering/, 'help describes the configured ordering' );
    ok( !-e $self->{env}{TEST_EDITOR_LOG}, 'help does not open the editor' );
    $result = invoke( $self, 'missing' );
    isnt( $result->{returncode}, 0, 'a nonexistent directory is rejected' );
    make_path("$self->{directory}/-dash");
    my $path = script_path( $self, invoke( $self, '--', '-dash' ) );
    like(
        read_file($path),
        qr{cd -- "\$TEST_PROJECT/-dash"},
        '-- accepts a directory whose name starts with a dash'
    );
    delete $self->{env}{EDITOR};
    $result = invoke($self);
    isnt( $result->{returncode}, 0, 'missing EDITOR is rejected' );
    like( $result->{stderr}, qr/EDITOR is not set/, 'missing EDITOR is explained' );
}

run_cases(
    {
        lists_immediate_entries_and_quotes_names     => \&lists_immediate_entries_and_quotes_names,
        quotes_ascii_directory_aliases               => \&quotes_ascii_directory_aliases,
        printed_script_uses_directory_aliases        => \&printed_script_uses_directory_aliases,
        recursion_keeps_parents_before_children      => \&recursion_keeps_parents_before_children,
        editor_changes_wait_for_manual_execution     => \&editor_changes_wait_for_manual_execution,
        editor_failure_keeps_script_without_command  => \&editor_failure_keeps_script_without_command,
        editor_without_options                       => \&editor_without_options,
        script_is_executable_inside_editor           => \&script_is_executable_inside_editor,
        empty_alias_does_not_change_script_directory => \&empty_alias_does_not_change_script_directory,
        usage_and_missing_editor                     => \&usage_and_missing_editor,
        ordering_matches_ls                          => \&ordering_matches_ls,
        directory_markers_keep_move_commands_usable  => \&directory_markers_keep_move_commands_usable,
        git_ignore_and_override                      => \&git_ignore_and_override,
        persistent_ignore_batches_preserve_rules     => \&persistent_ignore_batches_preserve_rules,
        invalid_ignore_replies_stop_before_editor    => \&invalid_ignore_replies_stop_before_editor,
        ignore_files_outside_git_do_not_filter       => \&ignore_files_outside_git_do_not_filter,
        includes_its_own_script                      => \&includes_its_own_script,
        scan_errors_stop_before_editor               => \&scan_errors_stop_before_editor,
    },
    \&setup
);
