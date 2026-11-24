use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
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
        EDITOR           => shell_quote($editor) . ' --test-option',
        TMPDIR           => "$root/temp files",
        HOME             => $root,
        AQSNOW_DIRALIS   => 'HOME:TEST_PROJECT',
        TEST_PROJECT     => $self->{directory},
        TEST_EDITOR_LOG  => "$root/editor.json",
        TEST_RENAME      => '',
        TEST_EDITOR_FAIL => 0,
    };
}

sub invoke {
    my ( $self, @args ) = @_;
    return run_command( [ $program, @args ], { cwd => $self->{directory}, env => $self->{env} } );
}

sub script_path {
    my ( $self, $result ) = @_;
    is( $result->{returncode}, 0, $result->{stderr} );
    my @command = shellwords( $result->{stdout} );
    is( scalar @command, 1, 'prints one shell-quoted executable path' );
    ok( -x $command[0], 'the generated script is executable' );
    is_deeply(
        decode_json( read_file( $self->{env}{TEST_EDITOR_LOG} ) ),
        [ '--test-option', $command[0] ],
        'the editor receives its configured arguments and script path'
    );
    return $command[0];
}

sub lists_immediate_entries_and_quotes_names {
    my ($self) = @_;
    my $path   = script_path( $self, invoke($self) );
    my @lines  = split /\n/, read_file($path);
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
        [ sort( '.hidden', 'broken', 'link', q{literal ' $HOME;[x]}, 'nested', 'original' ) ],
        'includes hidden files, special names, directories, and broken links without recursing'
    );
    ok( -f "$self->{directory}/original", 'generation performs no file operations' );
    my $result = run_command( [$path], { cwd => $self->{root}, env => $self->{env} } );
    is( $result->{returncode}, 0, 'running an unchanged script succeeds without moving directory entries' );
    ok( -d "$self->{directory}/nested",   'an unchanged script leaves directories intact' );
    ok( -f "$self->{directory}/original", 'an unchanged script leaves files intact' );
}

sub recursion_keeps_children_before_parents {
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
        $position{'nested/deep/leaf'},
        '<',
        $position{'nested/deep'},
        'children precede their parent directory'
    );
    cmp_ok( $position{'nested/deep'}, '<', $position{'nested'}, 'nested directories precede their parent' );
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

sub usage_and_missing_editor {
    my ($self) = @_;
    my $result = invoke( $self, '--help' );
    is( $result->{returncode}, 0, 'help succeeds' );
    like( $result->{stdout}, qr/--recursive/, 'help describes recursive mode' );
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
        lists_immediate_entries_and_quotes_names    => \&lists_immediate_entries_and_quotes_names,
        recursion_keeps_children_before_parents     => \&recursion_keeps_children_before_parents,
        editor_changes_wait_for_manual_execution    => \&editor_changes_wait_for_manual_execution,
        editor_failure_keeps_script_without_command => \&editor_failure_keeps_script_without_command,
        usage_and_missing_editor                    => \&usage_and_missing_editor,
    },
    \&setup
);
