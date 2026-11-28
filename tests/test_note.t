use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $source = absolute_path("$FindBin::Bin/../fish/functions/note.fish");

sub setup {
    my ($self)    = @_;
    my $temporary = tempdir( 'note-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $editor    = "$temporary/editor with spaces";
    my $bin       = "$temporary/bin";
    make_path($bin);
    symlink "$FindBin::Bin/../bin/editor", "$bin/editor" or die $!;
    $self->{note} = "$temporary/notes ' \$literal; [work]/2026/11/25.md";
    $self->{log}  = "$temporary/editor.json";
    $self->{env}  = {
        %ENV,
        PATH     => "$bin:$ENV{PATH}",
        EDITOR   => 'false',
        VISUAL   => $editor,
        notes    => dirname( dirname( dirname( $self->{note} ) ) ),
        NOTE_LOG => $self->{log},
    };
    write_file( $editor, '#!' . perl_executable() . "\n" . <<'PERL_EDITOR' );
use strict; use warnings; use JSON::PP;
my $stdin;
if (grep { $_ eq '-' } @ARGV) { local $/; $stdin = <STDIN>; }
open my $out, '>', $ENV{NOTE_LOG} or die $!;
print {$out} encode_json({ args => \@ARGV, stdin => $stdin, note => $ENV{note} });
close $out or die $!;
exit 23;
PERL_EDITOR
    chmod 0755, $editor or die $!;
}

sub run_note {
    my ($self) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', <<'FISH', '--', $source ],
source "$argv[1]"
function date
    switch "$argv[1]"
        case '+%Y/%m/%d'
            printf '2026/11/25\n'
        case '+%B %d, %Y'
            printf 'November 25, 2026\n'
        case '+%A'
            printf 'Wednesday\n'
    end
end
note
FISH
        { env => $self->{env} }
    );
}

sub existing_note_preserves_literal_paths {
    my ($self) = @_;
    make_path( dirname( $self->{note} ) );
    write_file( $self->{note}, "Existing note\n" );
    my $result = run_note($self);
    is( $result->{returncode}, 23, 'returns the editor exit status' );
    is( $result->{stderr},     '', 'the editor path with spaces runs without errors' );
    my $record = decode_json( read_file( $self->{log} ) );
    is_deeply( $record->{args}, [ $self->{note} ], 'passes the literal note path' );
    is( $record->{stdin},           undef,             'existing notes do not receive generated input' );
    is( read_file( $self->{note} ), "Existing note\n", 'opening the note does not rewrite it' );
}

sub new_note_preserves_editor_arguments_and_input {
    my ($self) = @_;
    my $result = run_note($self);
    is( $result->{returncode}, 23, 'returns the editor exit status' );
    is( $result->{stderr},     '', 'the editor path with spaces runs without errors' );
    my $record = decode_json( read_file( $self->{log} ) );
    is_deeply(
        $record->{args},
        [ '-', '+execute "file " . fnameescape($note)', '+filetype detect', '+normal! G' ],
        'preserves stdin and the fixed Vim commands as separate arguments'
    );
    is( $record->{note}, $self->{note}, 'exports the literal note filename for the Vim command' );
    is(
        $record->{stdin},
        "# November 25, 2026\n* Wednesday *\n\n\n",
        'pipes the dated heading into the editor'
    );
    ok( !-e $self->{note}, 'the mock editor does not create the note' );
}

run_cases(
    {
        existing_note_preserves_literal_paths         => \&existing_note_preserves_literal_paths,
        new_note_preserves_editor_arguments_and_input => \&new_note_preserves_editor_arguments_and_input,
    },
    \&setup
);
