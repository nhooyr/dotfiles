use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use Digest::SHA qw(sha256_hex);
use Fcntl       qw(:flock);

my $root = absolute_path("$FindBin::Bin/..");
my $git  = which('git');

sub setup {
    my ($self) = @_;
    $self->{temporary} = absolute_path( tempdir( 'commitgen-XXXXXX', TMPDIR => 1, CLEANUP => 1 ) );
    $self->{repo}      = "$self->{temporary}/repo with 'quotes'";
    make_path( $self->{repo}, "$self->{temporary}/bin", "$self->{temporary}/tmp" );
    $self->{env} = {
        %ENV,
        PATH                => "$self->{temporary}/bin:$ENV{PATH}",
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
        GIT_AUTHOR_NAME     => 'Commit Test',
        GIT_AUTHOR_EMAIL    => 'test@example.invalid',
        GIT_COMMITTER_NAME  => 'Commit Test',
        GIT_COMMITTER_EMAIL => 'test@example.invalid',
        GIT_EDITOR          => "$self->{temporary}/bin/editor",
        TMPDIR              => "$self->{temporary}/tmp",
        TEST_ROOT           => $self->{temporary},
        TEST_REPO           => $self->{repo},
    };
    write_file( "$self->{temporary}/bin/editor", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
use JSON::PP qw(encode_json);
my $log = "$ENV{TEST_ROOT}/editor-calls";
my $count = 1;
if (open my $previous, '<', $log) { ++$count while <$previous>; close $previous; }
open my $message, '<', $ARGV[0] or die $!;
my $text = do { local $/; <$message> };
close $message;
open my $calls, '>>', $log or die $!;
print {$calls} encode_json({text => $text, args => \@ARGV}), "\n";
close $calls;
if ($ENV{TEST_EDITOR_ACTION}) {
    system $^X, $ENV{TEST_EDITOR_ACTION}, $ARGV[0];
    die "editor action failed\n" if $?;
}
if ($ENV{TEST_REPLACE_SCRIPT}) {
    open my $replacement, '>', "$ENV{TEST_REPO}/replacement" or die $!;
    print {$replacement} "#!/bin/sh\nprintf 'replacement\\n'\n";
    close $replacement;
    chmod 0755, "$ENV{TEST_REPO}/replacement" or die $!;
    rename "$ENV{TEST_REPO}/replacement", "$ENV{TEST_REPO}/commit" or die $!;
}
exit(($ENV{TEST_FAIL_EDITOR} // 0) == $count ? 1 : 0);
PERL
    write_file( "$self->{temporary}/bin/trash", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
if ($ENV{TEST_TRASH_REPLACE}) {
    open my $file, '>', "$ENV{TEST_REPO}/replacement" or die $!;
    print {$file} "late replacement\n";
    close $file or die $!;
    rename "$ENV{TEST_REPO}/replacement", "$ENV{TEST_REPO}/commit" or die $!;
}
my $destination = "$ENV{TEST_ROOT}/trashed-commit";
unlink $destination if -e $destination;
rename $ARGV[0], $destination or die $!;
open my $log, '>>', "$ENV{TEST_ROOT}/trash-calls" or die $!;
print {$log} "$ARGV[0]\n";
close $log;
PERL
    chmod 0755, "$self->{temporary}/bin/editor", "$self->{temporary}/bin/trash" or die $!;
    git( $self, 'init',   '--quiet',        '--initial-branch', 'main' );
    git( $self, 'config', 'commit.gpgsign', 'false' );
    git( $self, 'config', 'core.filemode',  'true' );

    for my $name (qw(one two unrelated)) {
        write_file( "$self->{repo}/$name.txt", "$name original\n" );
    }
    git( $self, 'add', '.' );
    git( $self, 'commit', '--quiet', '-m', 'Initial' );
    $self->{base} = git( $self, 'rev-parse', 'HEAD' );
}

sub git {
    my ( $self, @arguments ) = @_;
    return trim(
        run_command( [ $git, '--no-pager', @arguments ],
            { cwd => $self->{repo}, env => $self->{env}, check => 1 } )->{stdout}
    );
}

sub generate {
    my ( $self, $groups, @arguments ) = @_;
    write_file( "$self->{temporary}/plan.json", encode_json( { groups => $groups } ) );
    return run_command(
        [ $self->{generator} // "$root/codex/commitgen", @arguments, "$self->{temporary}/plan.json" ],
        { cwd => $self->{repo}, env => $self->{env}, timeout => 30 } );
}

sub run_commit {
    my ( $self, @arguments ) = @_;
    return run_command( [ "$self->{repo}/commit", @arguments ],
        { cwd => $self->{repo}, env => $self->{env}, timeout => 30 } );
}

sub groups {
    return [
        { name => '01-one.patch', files => ['one.txt'], message => "one.txt: Update one\n\nChange one.\n" },
        { name => '02-two.patch', files => ['two.txt'], message => "two.txt: Update two\n\nChange two.\n" },
    ];
}

sub prepare_two {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    write_file( "$self->{repo}/two.txt", "two prepared\n" );
    my $result = generate( $self, groups() );
    is( $result->{returncode}, 0, $result->{stderr} );
    ok( -x "$self->{repo}/commit", 'generator publishes an executable helper' );
}

sub prepare_one {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    my $result = generate( $self, [ groups()->[0] ] );
    is( $result->{returncode}, 0, $result->{stderr} );
}

sub concurrent_action {
    my ( $self, $body ) = @_;
    my $path = "$self->{temporary}/concurrent-action.pl";
    write_file( $path, <<'PERL' . $body . <<'END' );
use strict;
use warnings;
use File::Copy qw(copy);
delete @ENV{qw(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR)};
sub git {
    system $ENV{TEST_REAL_GIT}, '--no-pager', '-C', $ENV{TEST_REPO}, @_;
    die "concurrent Git action failed\n" if $?;
}
sub capture_git {
    open my $pipe, '-|', $ENV{TEST_REAL_GIT}, '--no-pager', '-C', $ENV{TEST_REPO}, @_ or die $!;
    my $text = do { local $/; <$pipe> };
    close $pipe or die "concurrent Git query failed\n";
    chomp $text;
    return $text;
}
sub write_file {
    open my $file, '>', $_[0] or die $!;
    print {$file} $_[1];
    close $file or die $!;
}
PERL
copy "$ENV{TEST_REPO}/.git/index", "$ENV{TEST_ROOT}/concurrent-index" or die $!;
write_file("$ENV{TEST_ROOT}/concurrent-head", capture_git('rev-parse', 'HEAD'));
END
    $self->{env}{TEST_REAL_GIT} = $git;
    return $path;
}

sub editor_action {
    my ( $self, $body ) = @_;
    $self->{env}{TEST_EDITOR_ACTION} = concurrent_action( $self, $body );
}

sub git_action {
    my ( $self, $trigger, $body ) = @_;
    $self->{env}{TEST_GIT_ACTION}  = concurrent_action( $self, $body );
    $self->{env}{TEST_GIT_TRIGGER} = $trigger;
    write_file( "$self->{temporary}/bin/git", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
my $trigger = $ENV{TEST_GIT_TRIGGER};
my $matches = $trigger eq 'snapshot'
    ? ((grep { $_ eq 'diff' } @ARGV) && (grep { $_ eq '--cached' } @ARGV))
    : $trigger eq 'publish'
    ? ((grep { $_ eq 'update-ref' } @ARGV) && (grep { $_ eq '--stdin' } @ARGV))
    : (grep { $_ eq $trigger } @ARGV);
my $marker = "$ENV{TEST_ROOT}/git-action-ran";
sub action {
    open my $file, '>', $marker or die $!;
    close $file;
    system $^X, $ENV{TEST_GIT_ACTION};
    die "Git action failed\n" if $?;
}
action() if $matches && !-e $marker && $trigger ne 'snapshot';
system $ENV{TEST_REAL_GIT}, @ARGV;
my $status = $?;
action() if !$status && $matches && !-e $marker && $trigger eq 'snapshot';
exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
PERL
    chmod 0755, "$self->{temporary}/bin/git" or die $!;
}

sub concurrent_index_preserved {
    my ($self) = @_;
    is(
        Digest::SHA->new(256)->addfile("$self->{repo}/.git/index")->hexdigest,
        Digest::SHA->new(256)->addfile("$self->{temporary}/concurrent-index")->hexdigest,
        'concurrent index content is preserved byte for byte'
    );
}

sub help_and_completion_are_read_only {
    my ($self) = @_;
    for my $flag (qw(-h --help)) {
        my $result =
          run_command( [ "$root/codex/commitgen", $flag ], { cwd => $self->{repo}, env => $self->{env} } );
        is( $result->{returncode}, 0, 'generator help succeeds' );
        like( $result->{stdout}, qr/^Usage: commitgen\b/m, 'generator prints usage' );
    }
    prepare_two($self);
    my $original = read_file("$self->{repo}/commit");
    for my $flag (qw(-h --help)) {
        my $result = run_commit( $self, $flag );
        is( $result->{returncode}, 0, 'generated helper help succeeds' );
        like( $result->{stdout}, qr/^Usage: .*commit\b/m, 'generated helper prints usage' );
    }
    my $completion = run_commit( $self, '--completions', 'fish' );
    is( $completion->{returncode}, 0, 'generated helper prints completions on request' );
    like( $completion->{stdout}, qr/^complete -c commit -s h -l help\b/m, 'completion offers help' );
    is( read_file("$self->{repo}/commit"), $original,     'help and completions preserve the helper' );
    is( git( $self, 'rev-parse', 'HEAD' ), $self->{base}, 'help and completions create no commits' );
    ok( !-e "$self->{temporary}/editor-calls", 'generation and help do not open the commit editor' );
}

sub commits_groups_and_cleans_up {
    my ($self) = @_;
    prepare_two($self);
    my $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    like(
        $result->{stdout},
        qr/\e\[1mStep 1\/2: 01-one\.patch\e\[0m/,
        'step heading is bold and resets immediately'
    );
    is(
        git( $self, 'log', '--reverse', '--format=%s', "$self->{base}..HEAD" ),
        "one.txt: Update one\ntwo.txt: Update two",
        'each group becomes its own commit'
    );
    is( git( $self, 'status', '--porcelain' ), '', 'prepared changes are fully committed' );
    ok( !-e "$self->{repo}/commit",             'successful sequence moves the helper to Trash' );
    ok( -x "$self->{temporary}/trashed-commit", 'trashed helper remains recoverable' );
}

sub interrupted_sequence_resumes_after_branch_switch {
    my ($self) = @_;
    prepare_two($self);
    $self->{env}{TEST_FAIL_EDITOR} = 2;
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'second editor failure stops the sequence' );
    is(
        git( $self, 'log', '--reverse', '--format=%s', "$self->{base}..HEAD" ),
        'one.txt: Update one',
        'first group stays committed'
    );
    ok( -x "$self->{repo}/commit", 'failure retains the helper' );
    git( $self, 'switch', '--quiet', '-c', 'resumed' );
    delete $self->{env}{TEST_FAIL_EDITOR};
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        git( $self, 'log', '--reverse', '--format=%s', "$self->{base}..HEAD" ),
        "one.txt: Update one\ntwo.txt: Update two",
        'rerun commits only the unfinished group on the new branch'
    );
    my @editors = split /\n/, read_file("$self->{temporary}/editor-calls");
    is( scalar @editors, 3, 'completed group never reopens the editor' );
    copy_preserve( "$self->{temporary}/trashed-commit", "$self->{repo}/commit" );
    $result = run_commit($self);
    is( $result->{returncode}, 0, 'already-complete rerun succeeds' );
    ok( !-e "$self->{repo}/commit", 'already-complete rerun trashes the helper again' );
    is( git( $self, 'rev-list', '--count', "$self->{base}..HEAD" ),
        2, 'already-complete rerun creates no commits' );
}

sub retry_restores_only_the_commit_message {
    my ($self) = @_;
    git( $self, 'config', 'core.commentString', '//' );
    prepare_one($self);
    editor_action( $self, <<'PERL' );
my $path = shift;
open my $file, '<', $path or die $!;
my $text = do { local $/; <$file> };
close $file or die $!;
$text =~ s{\A.*?(?=^// Please enter the commit message)}{$ENV{TEST_DRAFT}}ms;
$text =~ s{^(// Changes to be committed:\n)}{$1//\tstat:       1 file changed\n}m;
write_file($path, $text);
PERL
    $self->{env}{TEST_DRAFT}       = '';
    $self->{env}{TEST_FAIL_EDITOR} = 1;
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'cancel a review with an empty message' );

    $self->{env}{TEST_DRAFT}       = "Edited title\n\nEdited body.\n\n// Editor note.\n\n";
    $self->{env}{TEST_FAIL_EDITOR} = 2;
    $result                        = run_commit($self);
    isnt( $result->{returncode}, 0, 'cancel a review with a saved message' );

    delete @{ $self->{env} }{qw(TEST_EDITOR_ACTION TEST_FAIL_EDITOR TEST_DRAFT)};
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    my @reviews = map { decode_json($_)->{text} } split /\n/, read_file("$self->{temporary}/editor-calls");
    like( $reviews[1], qr/\Aone\.txt: Update one\n\nChange one\.\n/, 'empty draft restores the suggestion' );
    like(
        $reviews[2],
        qr{\AEdited title\n\nEdited body\.\n\n// Editor note\.\n},
        'the edited message survives a retry'
    );

    for my $review ( @reviews[ 1, 2 ] ) {
        my @lines = split /\n/, $review;
        is( scalar( grep { $_ eq '// Changes to be committed:' } @lines ), 1, 'review has one status block' );
        is( scalar( grep { /^diff --git / } @lines ),                      1, 'review has one diff' );
        unlike( $review, qr{^//\tstat:}m, 'old stat decoration is discarded' );
    }
    is(
        git( $self, 'log', '-1', '--format=%B' ),
        "Edited title\n\nEdited body.",
        'Git commits the saved draft'
    );
}

sub unrelated_new_commit_does_not_pin_head {
    my ($self) = @_;
    prepare_two($self);
    git( $self, 'switch', '--quiet', '-c', 'new-base' );
    write_file( "$self->{repo}/unrelated.txt", "unrelated committed\n" );
    git( $self, 'add', 'unrelated.txt' );
    git( $self, 'commit', '--quiet', '-m', 'Unrelated' );
    my $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        git( $self, 'log', '--reverse', '--format=%s', "$self->{base}..HEAD" ),
        "Unrelated\none.txt: Update one\ntwo.txt: Update two",
        'helper accepts a new branch and unrelated HEAD changes'
    );
    is(
        read_file("$self->{repo}/unrelated.txt"),
        "unrelated committed\n",
        'unrelated committed content is preserved'
    );
}

sub partially_committed_group_commits_only_the_remainder {
    my ($self) = @_;
    my @original = map { "line $_\n" } 1 .. 30;
    write_file( "$self->{repo}/one.txt", join '', @original );
    git( $self, 'add', 'one.txt' );
    git( $self, 'commit', '--quiet', '-m', 'Long fixture' );
    my @partial = @original;
    $partial[2] = "already committed line\n";
    my @prepared = @partial;
    $prepared[5] = "remaining line\n";
    write_file( "$self->{repo}/one.txt", join '', @prepared );
    write_file( "$self->{repo}/two.txt", "two prepared\n" );
    my $result = generate( $self, [ { %{ groups()->[0] }, files => [qw(one.txt two.txt)] } ] );
    is( $result->{returncode}, 0, $result->{stderr} );

    write_file( "$self->{repo}/one.txt", join '', @partial );
    git( $self, 'add', 'one.txt', 'two.txt' );
    git( $self, 'commit', '--quiet', '-m', 'Part of the group' );
    write_file( "$self->{repo}/one.txt", join '', @prepared );
    write_file( "$self->{repo}/unrelated.txt", "unrelated staged\n" );
    git( $self, 'add', 'unrelated.txt' );
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is( git( $self, 'diff-tree', '--no-commit-id', '-r', '--name-only', 'HEAD' ),
        'one.txt', 'the already committed file is absent from the review commit' );
    is(
        git( $self, 'show', 'HEAD:one.txt' ),
        trim( join '', @prepared ),
        'only the outstanding hunk is added to the partially committed file'
    );
    is( git( $self, 'diff', '--cached', '--name-only' ),
        'unrelated.txt', 'the original staging is preserved' );
    is( git( $self, 'show', ':unrelated.txt' ), 'unrelated staged', 'staged content is unchanged' );
}

sub conflicting_later_group_stops_before_review {
    my ($self) = @_;
    prepare_two($self);
    write_file( "$self->{repo}/two.txt", "two conflicting\n" );
    git( $self, 'add', 'two.txt' );
    git( $self, 'commit', '--quiet', '-m', 'Conflicting change' );
    write_file( "$self->{repo}/two.txt",       "two prepared\n" );
    write_file( "$self->{repo}/unrelated.txt", "unrelated staged\n" );
    git( $self, 'add', 'unrelated.txt' );
    my $head   = git( $self, 'rev-parse', 'HEAD' );
    my $index  = read_file("$self->{repo}/.git/index");
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'the conflicting step stops the sequence' );
    like( $result->{stderr}, qr/conflict with HEAD/, 'the helper reports the conflict' );
    ok( !-e "$self->{temporary}/editor-calls", 'the conflict is found before review starts' );
    is( git( $self, 'rev-parse', 'HEAD' ),     $head,            'HEAD is unchanged' );
    is( read_file("$self->{repo}/.git/index"), $index,           'the index is unchanged' );
    is( read_file("$self->{repo}/two.txt"),    "two prepared\n", 'prepared content is unchanged' );
    ok( -x "$self->{repo}/commit", 'the helper remains available' );
}

sub same_file_staged_and_unstaged_changes_survive {
    my ($self) = @_;
    my @original = map { "line $_\n" } 1 .. 80;
    write_file( "$self->{repo}/one.txt", join '', @original );
    git( $self, 'add', 'one.txt' );
    git( $self, 'commit', '--quiet', '-m', 'Long fixture' );
    my @staged = @original;
    $staged[39] = "unrelated staged\n";
    write_file( "$self->{repo}/one.txt", join '', @staged );
    git( $self, 'add', 'one.txt' );
    my @prepared = @staged;
    $prepared[2] = "prepared change\n";
    write_file( "$self->{repo}/one.txt", join '', @prepared );
    write_file( "$self->{temporary}/selected.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    my @working = @prepared;
    $working[69] = "unrelated unstaged\n";
    write_file( "$self->{repo}/one.txt", join '', @working );
    my $result =
      generate( $self, [ { patch_file => 'selected.patch', message => 'one.txt: Apply selected change' } ] );
    is( $result->{returncode}, 0, $result->{stderr} );
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    my @committed = @original;
    $committed[2] = "prepared change\n";
    is(
        git( $self, 'show', 'HEAD:one.txt' ),
        trim( join '', @committed ),
        'commit contains only the selected hunk'
    );
    is( git( $self, 'show', ':one.txt' ), trim( join '', @prepared ),
        'unrelated staged hunk remains staged' );
    is(
        read_file("$self->{repo}/one.txt"),
        join( '', @working ),
        'unrelated unstaged hunk remains in the worktree'
    );
}

sub changed_prepared_content_stops_without_staging {
    my ($self) = @_;
    prepare_two($self);
    write_file( "$self->{repo}/one.txt", "one changed after generation\n" );
    my $before = git( $self, 'write-tree' );
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'changed selected content stops the sequence' );
    is( git( $self, 'write-tree' ), $before, 'validation failure preserves the original index' );
    is( git( $self, 'rev-parse', 'HEAD' ), $self->{base}, 'validation failure creates no commit' );
    ok( -x "$self->{repo}/commit", 'validation failure retains the helper' );
    is(
        read_file("$self->{repo}/one.txt"),
        "one changed after generation\n",
        'new worktree content is preserved'
    );
}

sub replaced_running_helper_is_preserved {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    my $result = generate( $self, [ groups()->[0] ] );
    is( $result->{returncode}, 0, $result->{stderr} );
    $self->{env}{TEST_REPLACE_SCRIPT} = 1;
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        read_file("$self->{repo}/commit"),
        "#!/bin/sh\nprintf 'replacement\\n'\n",
        'running helper preserves an atomic replacement'
    );
    ok( !-e "$self->{temporary}/trash-calls", 'replacement is not moved to Trash' );
    is( git( $self, 'log', '-1', '--format=%s' ), 'one.txt: Update one', 'prepared commit still succeeds' );
}

sub mode_only_change_commits_once {
    my ($self) = @_;
    chmod 0755, "$self->{repo}/one.txt" or die $!;
    my $result = generate( $self, [ groups()->[0] ] );
    is( $result->{returncode}, 0, $result->{stderr} );
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    like( git( $self, 'ls-tree', 'HEAD', 'one.txt' ),
        qr/^100755 /, 'mode-only patch changes the executable bit' );
    copy_preserve( "$self->{temporary}/trashed-commit", "$self->{repo}/commit" );
    $result = run_commit($self);
    is( $result->{returncode}, 0, 'mode-only rerun succeeds' );
    is( git( $self, 'rev-list', '--count', "$self->{base}..HEAD" ),
        1, 'mode-only change is never committed twice' );
}

sub interrupted_overlapping_groups_resume_from_journal {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one original\ncontext\nlast line\n" );
    git( $self, 'add', 'one.txt' );
    git( $self, 'commit', '--quiet', '-m', 'Long fixture' );
    my $base = git( $self, 'rev-parse', 'HEAD' );
    write_file( "$self->{repo}/one.txt", "one intermediate\ncontext\nlast line\n" );
    write_file( "$self->{temporary}/first.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    git( $self, 'add', 'one.txt' );
    write_file( "$self->{repo}/one.txt", "one final\ncontext\nlast line\n" );
    write_file( "$self->{temporary}/second.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    git( $self, 'reset', '--quiet', 'HEAD' );
    write_file( "$self->{repo}/two.txt", "two prepared\n" );
    my $result = generate(
        $self,
        [
            { patch_file => 'first.patch',  message => 'one.txt: Apply first change' },
            { patch_file => 'second.patch', message => 'one.txt: Apply second change' },
            groups()->[1],
        ]
    );
    is( $result->{returncode}, 0, $result->{stderr} );
    write_file( "$self->{repo}/one.txt", "one original\ncontext\nnew last line\n" );
    git( $self, 'add', 'one.txt' );
    git( $self, 'commit', '--quiet', '-m', 'Change nearby context' );
    write_file( "$self->{repo}/one.txt",      "one final\ncontext\nnew last line\n" );
    write_file( "$self->{temporary}/bin/git", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
system $ENV{TEST_REAL_GIT}, @ARGV;
my $status = $? >> 8;
if (!$status && (grep { $_ eq 'update-ref' } @ARGV) && (grep { $_ eq '--stdin' } @ARGV)) {
    my $path = "$ENV{TEST_ROOT}/commits-finished";
    my $count = 1;
    if (open my $previous, '<', $path) { ++$count while <$previous>; close $previous; }
    open my $finished, '>>', $path or die $!;
    print {$finished} "done\n";
    close $finished;
    kill 'KILL', getppid() if $count == 2;
}
exit $status;
PERL
    chmod 0755, "$self->{temporary}/bin/git" or die $!;
    $self->{env}{TEST_REAL_GIT} = $git;
    $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'interruption occurs after the second commit succeeds' );
    is(
        git( $self, 'log', '--reverse', '--format=%s', "$base..HEAD" ),
        "Change nearby context\none.txt: Apply first change\none.txt: Apply second change",
        'overlapping commits survive interruption'
    );
    ok( -x "$self->{repo}/commit", 'interruption preserves the helper' );
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        git( $self, 'log', '--reverse', '--format=%s', "$base..HEAD" ),
"Change nearby context\none.txt: Apply first change\none.txt: Apply second change\ntwo.txt: Update two",
        'journal recovers the completed overlapping group and commits only the remainder'
    );
    ok( !-e "$self->{repo}/commit", 'recovered sequence trashes the helper' );
}

sub invalid_later_group_preserves_existing_state {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    write_file( "$self->{temporary}/first.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    write_file( "$self->{repo}/one.txt", "one conflicting\n" );
    write_file( "$self->{temporary}/conflicting.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    write_file( "$self->{repo}/one.txt",       "one prepared\n" );
    write_file( "$self->{repo}/unrelated.txt", "unrelated staged\n" );
    git( $self, 'add', 'unrelated.txt' );
    write_file( "$self->{repo}/commit", "existing helper\n" );
    my $staged   = git( $self, 'diff', '--cached', '--binary' );
    my $unstaged = git( $self, 'diff', '--binary' );
    my $result   = generate(
        $self,
        [
            { patch_file => 'first.patch',       message => 'one.txt: Apply first change' },
            { patch_file => 'conflicting.patch', message => 'one.txt: Apply conflicting change' },
        ]
    );
    isnt( $result->{returncode}, 0, 'invalid later group rejects the plan' );
    is(
        read_file("$self->{repo}/commit"),
        "existing helper\n",
        'validation failure preserves existing output'
    );
    is( git( $self, 'rev-parse', 'HEAD' ),
        $self->{base}, 'validation commits do not change the original HEAD' );
    is( git( $self, 'diff', '--cached', '--binary' ),
        $staged, 'validation preserves unrelated staged changes' );
    is( git( $self, 'diff', '--binary' ), $unstaged, 'validation preserves working-tree changes' );
}

sub custom_output_is_standalone_and_wraps_messages {
    my ($self) = @_;
    my $installation = "$self->{temporary}/installation";
    make_path("$installation/codex/lib/CommitScript");
    for my $path ( 'codex/commitgen', 'codex/lib/CommitScript.pm', 'codex/lib/CommitScript/runtime.pl' ) {
        copy_preserve( "$root/$path", "$installation/$path" );
    }
    $self->{generator} = "$installation/codex/commitgen";
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    my $body   = join ' ', ('The prepared change remains reviewable after generation.') x 8;
    my $result = generate( $self, [ { files => ['one.txt'], message => "one.txt: Update one\n\n$body\n" } ],
        '--output', 'review helper' );
    is( $result->{returncode}, 0, $result->{stderr} );
    my $output = "$self->{repo}/review helper";
    ok( -x $output,                 'custom output path with spaces is executable' );
    ok( !-e "$self->{repo}/commit", 'custom output leaves the default path untouched' );
    remove_tree($installation);
    $result = run_command( [$output], { cwd => $self->{repo}, env => $self->{env}, timeout => 30 } );
    is( $result->{returncode}, 0, $result->{stderr} );
    my $message = git( $self, 'log', '-1', '--format=%B' );
    my ( $title, @body ) = split /\n/, $message;
    is( $title, 'one.txt: Update one', 'generation preserves the supplied title' );
    ok( !grep( { length($_) > 80 } @body ), 'generated commit body is wrapped to 80 columns' );
    is( join( ' ', grep { length } @body ), $body, 'wrapping preserves the supplied prose' );
    ok( !-e $output, 'standalone helper finishes without its generator or library' );
}

sub staged_final_state_allows_overlapping_groups {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one intermediate\n" );
    write_file( "$self->{temporary}/first.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    git( $self, 'add', 'one.txt' );
    write_file( "$self->{repo}/one.txt", "one final\n" );
    write_file( "$self->{temporary}/second.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    write_file( "$self->{repo}/unrelated.txt", "unrelated staged\n" );
    git( $self, 'add', 'one.txt', 'unrelated.txt' );
    my $result = generate(
        $self,
        [
            { patch_file => 'first.patch',  message => 'one.txt: Apply first change' },
            { patch_file => 'second.patch', message => 'one.txt: Apply second change' },
        ]
    );
    is( $result->{returncode}, 0, $result->{stderr} );
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        git( $self, 'log', '--reverse', '--format=%s', "$self->{base}..HEAD" ),
        "one.txt: Apply first change\none.txt: Apply second change",
        'staged final content permits separate overlapping commits'
    );
    is( git( $self, 'show', 'HEAD:one.txt' ), 'one final', 'overlapping sequence reaches its final content' );
    is( git( $self, 'diff', '--cached', '--name-only' ),
        'unrelated.txt', 'unrelated staging remains after the sequence' );
    is( git( $self, 'show', ':unrelated.txt' ), 'unrelated staged', 'unrelated staged content is preserved' );
}

sub conflicting_staged_content_preserves_index {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one intermediate\n" );
    write_file( "$self->{temporary}/first.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    git( $self, 'add', 'one.txt' );
    write_file( "$self->{repo}/one.txt", "one final\n" );
    write_file( "$self->{temporary}/second.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    write_file( "$self->{repo}/one.txt", "unplanned staged content\n" );
    git( $self, 'add', 'one.txt' );
    write_file( "$self->{repo}/one.txt", "one final\n" );
    my $result = generate(
        $self,
        [
            { patch_file => 'first.patch',  message => 'one.txt: Apply first change' },
            { patch_file => 'second.patch', message => 'one.txt: Apply second change' },
        ]
    );
    is( $result->{returncode}, 0, $result->{stderr} );
    my $index  = "$self->{repo}/.git/index";
    my $before = Digest::SHA->new(256)->addfile($index)->hexdigest;
    $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'unexpected staged content stops the sequence' );
    is( Digest::SHA->new(256)->addfile($index)->hexdigest, $before,
        'rejection leaves index bytes unchanged' );
    is( git( $self, 'rev-parse', 'HEAD' ),  $self->{base}, 'rejection leaves HEAD unchanged' );
    is( read_file("$self->{repo}/one.txt"), "one final\n", 'rejection preserves intended worktree content' );
    ok( -x "$self->{repo}/commit", 'rejection retains the helper for review' );
}

sub output_outside_repository_is_rejected {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    my $output = "$self->{temporary}/outside";
    my $result = generate( $self, [ groups()->[0] ], '--output', $output );
    isnt( $result->{returncode}, 0, 'output outside the repository is rejected' );
    ok( !-e $output, 'rejection publishes no unusable script' );
    is( git( $self, 'rev-parse', 'HEAD' ),  $self->{base},    'rejection leaves HEAD unchanged' );
    is( read_file("$self->{repo}/one.txt"), "one prepared\n", 'rejection preserves the selected change' );
}

sub generator_uses_the_runtime_lock {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    my $selected = [ groups()->[0] ];
    my $result   = generate( $self, $selected );
    is( $result->{returncode}, 0, $result->{stderr} );
    my $path   = "$self->{repo}/commit";
    my $before = read_file($path);
    $selected->[0]{message} = 'one.txt: Revise the suggested message';
    write_file( "$self->{temporary}/plan.json", encode_json( { groups => $selected } ) );
    my $lock_path = '/tmp/aqsnow-commit-' . sha256_hex( absolute_path($path) ) . '.lock';
    open my $lock, '>>', $lock_path or die $!;
    flock( $lock, LOCK_EX ) or die $!;
    eval {
        run_command(
            [ "$root/codex/commitgen", "$self->{temporary}/plan.json" ],
            { cwd => $self->{repo}, env => $self->{env}, timeout => 1 }
        );
    };
    like( $@, qr/Command timed out/, 'generator waits for the same per-script lock as the runtime' );
    is( read_file($path), $before, 'locked output is never replaced' );
    close $lock or die $!;
    $result = generate( $self, $selected );
    is( $result->{returncode}, 0, 'generation succeeds after releasing the lock' );
    isnt( read_file($path), $before, 'unlocked generation atomically publishes the updated helper' );
    unlink $lock_path or die $!;
}

sub concurrent_commit_during_editor_is_retained {
    my ($self) = @_;
    prepare_one($self);
    editor_action( $self, <<'PERL' );
write_file("$ENV{TEST_REPO}/unrelated.txt", "concurrent commit\n");
git('commit', '--quiet', '--only', '-m', 'Concurrent', '--', 'unrelated.txt');
PERL
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'concurrent commit stops the prepared commit' );
    concurrent_index_preserved($self);
    my $concurrent = read_file("$self->{temporary}/concurrent-head");
    is( git( $self, 'rev-parse', 'HEAD' ), $concurrent, 'concurrent commit remains the branch tip' );
    is(
        git( $self, 'show', 'HEAD:unrelated.txt' ),
        'concurrent commit',
        'concurrent committed content survives'
    );
    is( read_file("$self->{repo}/one.txt"), "one prepared\n", 'prepared worktree content is retained' );
    ok( -x "$self->{repo}/commit", 'contention retains the commit helper' );
}

sub concurrent_commit_before_git_starts_is_retained {
    my ($self) = @_;
    prepare_one($self);
    git_action( $self, 'commit', <<'PERL' );
write_file("$ENV{TEST_REPO}/unrelated.txt", "concurrent commit\n");
git('commit', '--quiet', '--only', '-m', 'Concurrent', '--', 'unrelated.txt');
PERL
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'concurrent update after the last precheck stops publication' );
    concurrent_index_preserved($self);
    my $concurrent = read_file("$self->{temporary}/concurrent-head");
    is( git( $self, 'rev-parse', 'HEAD' ),
        $concurrent, 'no stale prepared tree is committed over the new tip' );
    is(
        git( $self, 'show', 'HEAD:unrelated.txt' ),
        'concurrent commit',
        'concurrent content is not reverted'
    );
    is( git( $self, 'show', 'HEAD:one.txt' ),
        'one original', 'prepared commit is not published after contention' );
    ok( -x "$self->{repo}/commit", 'contention leaves the helper available for review' );
}

sub concurrent_commit_at_publication_is_retained {
    my ($self) = @_;
    prepare_one($self);
    git_action( $self, 'publish', <<'PERL' );
die "missing index lock at publication\n" unless -e "$ENV{TEST_REPO}/.git/index.lock";
$ENV{GIT_INDEX_FILE} = "$ENV{TEST_ROOT}/concurrent-commit-index";
git('read-tree', 'HEAD');
write_file("$ENV{TEST_REPO}/unrelated.txt", "concurrent publication\n");
git('add', 'unrelated.txt');
git('commit', '--quiet', '-m', 'Concurrent publication');
delete $ENV{GIT_INDEX_FILE};
PERL
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'HEAD changed at publication stops the prepared commit' );
    concurrent_index_preserved($self);
    is(
        git( $self, 'rev-parse', 'HEAD' ),
        read_file("$self->{temporary}/concurrent-head"),
        'concurrent publication remains the branch tip'
    );
    is(
        git( $self, 'show', 'HEAD:unrelated.txt' ),
        'concurrent publication',
        'compare-and-swap failure preserves concurrent committed content'
    );
    is( git( $self, 'show', 'HEAD:one.txt' ),
        'one original', 'prepared candidate is never installed over the concurrent publication' );
    is(
        read_file("$self->{repo}/one.txt"),
        "one prepared\n",
        'uncommitted prepared content remains available'
    );
}

sub same_oid_branch_switch_at_publication_preserves_refs {
    my ($self) = @_;
    git( $self, 'branch', 'other' );
    prepare_one($self);
    git_action( $self, 'publish', <<'PERL' );
die "missing index lock at publication\n" unless -e "$ENV{TEST_REPO}/.git/index.lock";
git('symbolic-ref', 'HEAD', 'refs/heads/other');
PERL
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'same-OID branch change at publication stops the prepared commit' );
    concurrent_index_preserved($self);
    is( git( $self, 'symbolic-ref', 'HEAD' ), 'refs/heads/other', 'concurrent HEAD target remains selected' );
    is( git( $self, 'rev-parse',    'refs/heads/main' ), $self->{base}, 'original branch remains unchanged' );
    is( git( $self, 'rev-parse',    'refs/heads/other' ),
        $self->{base}, 'new branch receives no prepared candidate' );
    is(
        read_file("$self->{repo}/one.txt"),
        "one prepared\n",
        'same-OID branch change preserves working content'
    );
}

sub concurrent_staging_during_editor_is_retained {
    my ($self) = @_;
    write_file( "$self->{repo}/two.txt", "previously staged\n" );
    git( $self, 'add', 'two.txt' );
    prepare_one($self);
    editor_action( $self, <<'PERL' );
write_file("$ENV{TEST_REPO}/two.txt", "changed staged content\n");
write_file("$ENV{TEST_REPO}/unrelated.txt", "new staged content\n");
git('add', 'two.txt', 'unrelated.txt');
PERL
    my $result = run_commit($self);
    is(
        git( $self, 'show', ':two.txt' ),
        'changed staged content',
        'staging changed during editing is retained'
    );
    is(
        git( $self, 'show', ':unrelated.txt' ),
        'new staged content',
        'new staging added during editing is retained'
    );
    is(
        read_file("$self->{repo}/two.txt"),
        "changed staged content\n",
        'concurrent staged file is not rewritten'
    );

    if ( $result->{returncode} ) {
        concurrent_index_preserved($self);
    }
}

sub concurrent_worktree_edits_during_editor_are_retained {
    my ($self) = @_;
    prepare_one($self);
    editor_action( $self, <<'PERL' );
write_file("$ENV{TEST_REPO}/one.txt", "edited during review\n");
write_file("$ENV{TEST_REPO}/unrelated.txt", "unrelated edit during review\n");
write_file("$ENV{TEST_REPO}/new.txt", "untracked edit during review\n");
PERL
    run_commit($self);
    is(
        read_file("$self->{repo}/one.txt"),
        "edited during review\n",
        'selected file edit made during review survives'
    );
    is(
        read_file("$self->{repo}/unrelated.txt"),
        "unrelated edit during review\n",
        'unrelated worktree edit survives'
    );
    is(
        read_file("$self->{repo}/new.txt"),
        "untracked edit during review\n",
        'new untracked content survives'
    );
}

sub branch_switch_during_editor_preserves_both_refs {
    my ($self) = @_;
    git( $self, 'branch', 'other' );
    prepare_one($self);
    editor_action( $self, <<'PERL' );
git('switch', '--quiet', 'other');
PERL
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'branch switch stops publication' );
    concurrent_index_preserved($self);
    is( git( $self, 'symbolic-ref', 'HEAD' ), 'refs/heads/other', 'concurrent branch selection is retained' );
    is( git( $self, 'rev-parse',    'refs/heads/main' ), $self->{base}, 'original branch is not changed' );
    is( git( $self, 'rev-parse',    'refs/heads/other' ),
        $self->{base}, 'new branch receives no unintended commit' );
    is(
        read_file("$self->{repo}/one.txt"),
        "one prepared\n",
        'branch switch retains prepared worktree content'
    );
}

sub generator_head_change_between_groups_is_rejected {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    write_file( "$self->{repo}/two.txt", "two prepared\n" );
    write_file( "$self->{repo}/commit",  "existing output\n" );
    git_action( $self, 'snapshot', <<'PERL' );
write_file("$ENV{TEST_REPO}/two.txt", "concurrent base\n");
git('commit', '--quiet', '--only', '-m', 'Concurrent base', '--', 'two.txt');
write_file("$ENV{TEST_REPO}/two.txt", "two prepared\n");
PERL
    my $result = generate( $self, groups() );
    isnt( $result->{returncode}, 0, 'generator rejects HEAD changes between group captures' );
    concurrent_index_preserved($self);
    is( read_file("$self->{repo}/commit"), "existing output\n", 'generation keeps the previous output' );
    is(
        git( $self, 'rev-parse', 'HEAD' ),
        read_file("$self->{temporary}/concurrent-head"),
        'concurrent HEAD survives generation'
    );
    is(
        git( $self, 'show', 'HEAD:two.txt' ),
        'concurrent base',
        'generation preserves the concurrent base content'
    );
    is(
        read_file("$self->{repo}/two.txt"),
        "two prepared\n",
        'generation retains worktree edits after the concurrent commit'
    );
}

sub generator_concurrent_output_changes_are_preserved {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    for my $operation (qw(replace remove)) {
        write_file( "$self->{repo}/commit", "existing output\n" );
        unlink "$self->{temporary}/git-action-ran";
        $self->{env}{TEST_OUTPUT_OPERATION} = $operation;
        git_action( $self, 'snapshot', <<'PERL' );
if ($ENV{TEST_OUTPUT_OPERATION} eq 'replace') {
    write_file("$ENV{TEST_REPO}/replacement", "concurrent output\n");
    rename "$ENV{TEST_REPO}/replacement", "$ENV{TEST_REPO}/commit" or die $!;
} else {
    unlink "$ENV{TEST_REPO}/commit" or die $!;
}
PERL
        my $result = generate( $self, [ groups()->[0] ] );
        isnt( $result->{returncode}, 0, "$operation during input capture stops publication" );
        concurrent_index_preserved($self);
        if ( $operation eq 'replace' ) {
            is(
                read_file("$self->{repo}/commit"),
                "concurrent output\n",
                'concurrent replacement is preserved'
            );
        }
        else {
            ok( !-e "$self->{repo}/commit", 'concurrently removed output is not recreated' );
        }
        is( git( $self, 'rev-parse', 'HEAD' ),
            $self->{base}, 'output contention creates no repository commit' );
    }
}

sub generator_selected_content_change_is_rejected {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt", "one prepared\n" );
    write_file( "$self->{repo}/commit",  "existing output\n" );
    git_action( $self, 'snapshot', <<'PERL' );
write_file("$ENV{TEST_REPO}/one.txt", "changed during capture\n");
PERL
    my $result = generate( $self, [ groups()->[0] ] );
    isnt( $result->{returncode}, 0, 'generator rejects selected content changed during capture' );
    concurrent_index_preserved($self);
    is(
        read_file("$self->{repo}/commit"),
        "existing output\n",
        'stale capture does not replace existing output'
    );
    is(
        read_file("$self->{repo}/one.txt"),
        "changed during capture\n",
        'concurrent selected-file edit is preserved'
    );
}

sub output_changed_after_final_check_is_preserved {
    my ($self) = @_;
    write_file( "$self->{repo}/one.txt",             "one prepared\n" );
    write_file( "$self->{temporary}/plan.json",      encode_json( { groups => [ groups()->[0] ] } ) );
    write_file( "$self->{temporary}/late-output.pl", <<'PERL' );
use strict;
use warnings;
use lib $ENV{TEST_COMMIT_LIB};
use CommitScript;
my ($plan, $output) = @ARGV;
my $original = \&CommitScript::output_state;
my $checks = 0;
no warnings 'redefine';
local *CommitScript::output_state = sub {
    my $state = $original->(@_);
    if ($_[0] eq $output && ++$checks == 2) {
        open my $file, '>', "$output.replacement" or die $!;
        print {$file} "late concurrent output\n";
        close $file or die $!;
        rename "$output.replacement", $output or die $!;
    }
    return $state;
};
CommitScript::generate(plan_file => $plan, path => $output);
PERL
    $self->{env}{TEST_COMMIT_LIB} = "$root/codex/lib";
    for my $existing ( 0, 1 ) {
        my $output = "$self->{repo}/commit";
        unlink $output;
        write_file( $output, "original output\n" ) if $existing;
        my $result = run_command(
            [
                perl_executable(),              "$self->{temporary}/late-output.pl",
                "$self->{temporary}/plan.json", $output
            ],
            { cwd => $self->{repo}, env => $self->{env}, timeout => 30 }
        );
        isnt( $result->{returncode}, 0, 'late output contention stops publication' );
        is(
            read_file($output),
            "late concurrent output\n",
            'output created or replaced after the final check is preserved'
        );
        is( git( $self, 'rev-parse', 'HEAD' ), $self->{base},
            'publication contention leaves HEAD unchanged' );
    }
}

sub replacement_created_at_trash_is_preserved {
    my ($self) = @_;
    prepare_one($self);
    $self->{env}{TEST_TRASH_REPLACE} = 1;
    my $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    ok( -f "$self->{repo}/commit", 'replacement created at cleanup remains at the original path' );
    is(
        read_file("$self->{repo}/commit"),
        "late replacement\n",
        'cleanup never trashes a concurrently replaced helper'
    );
    like( read_file("$self->{temporary}/trashed-commit"),
        qr/^#!\/bin\/sh\n/, 'only the completed generated helper is trashed' );
}

sub interrupted_index_preparation_recovers_owned_lock {
    my ($self) = @_;
    write_file( "$self->{repo}/two.txt", "unrelated staged\n" );
    git( $self, 'add', 'two.txt' );
    prepare_one($self);
    my $index  = "$self->{repo}/.git/index";
    my $before = Digest::SHA->new(256)->addfile($index)->hexdigest;
    write_file( "$self->{temporary}/bin/git", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
my $marker = "$ENV{TEST_ROOT}/killed-index-preparation";
if ((grep { $_ eq 'merge-tree' } @ARGV) && !-e $marker) {
    die "missing index lock at interruption\n" unless -e "$ENV{TEST_REPO}/.git/index.lock";
    open my $file, '>', $marker or die $!;
    close $file;
    kill 'KILL', getppid();
    exit 1;
}
exec $ENV{TEST_REAL_GIT}, @ARGV;
die $!;
PERL
    chmod 0755, "$self->{temporary}/bin/git" or die $!;
    $self->{env}{TEST_REAL_GIT} = $git;
    my $result = run_commit($self);
    isnt( $result->{returncode}, 0, 'interrupting index preparation stops the helper' );
    ok(
        -e "$self->{temporary}/killed-index-preparation",
        'interruption occurs after acquiring the index lock'
    );
    is( Digest::SHA->new(256)->addfile($index)->hexdigest,
        $before, 'interruption preserves original index bytes' );
    is( git( $self, 'rev-parse', 'HEAD' ), $self->{base}, 'interruption publishes no commit' );
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is( git( $self, 'show', 'HEAD:one.txt' ), 'one prepared',     'rerun completes the prepared commit' );
    is( git( $self, 'show', ':two.txt' ),     'unrelated staged', 'rerun preserves unrelated staging' );
    ok( !-e "$self->{repo}/.git/index.lock", 'rerun releases its recovered index lock' );
}

run_cases(
    {
        interrupted_index_preparation_recovers_owned_lock =>
          \&interrupted_index_preparation_recovers_owned_lock,
        replacement_created_at_trash_is_preserved       => \&replacement_created_at_trash_is_preserved,
        output_changed_after_final_check_is_preserved   => \&output_changed_after_final_check_is_preserved,
        concurrent_commit_during_editor_is_retained     => \&concurrent_commit_during_editor_is_retained,
        concurrent_commit_before_git_starts_is_retained => \&concurrent_commit_before_git_starts_is_retained,
        concurrent_commit_at_publication_is_retained    => \&concurrent_commit_at_publication_is_retained,
        same_oid_branch_switch_at_publication_preserves_refs =>
          \&same_oid_branch_switch_at_publication_preserves_refs,
        concurrent_staging_during_editor_is_retained => \&concurrent_staging_during_editor_is_retained,
        concurrent_worktree_edits_during_editor_are_retained =>
          \&concurrent_worktree_edits_during_editor_are_retained,
        branch_switch_during_editor_preserves_both_refs  => \&branch_switch_during_editor_preserves_both_refs,
        generator_head_change_between_groups_is_rejected =>
          \&generator_head_change_between_groups_is_rejected,
        generator_concurrent_output_changes_are_preserved =>
          \&generator_concurrent_output_changes_are_preserved,
        generator_selected_content_change_is_rejected    => \&generator_selected_content_change_is_rejected,
        generator_uses_the_runtime_lock                  => \&generator_uses_the_runtime_lock,
        output_outside_repository_is_rejected            => \&output_outside_repository_is_rejected,
        conflicting_staged_content_preserves_index       => \&conflicting_staged_content_preserves_index,
        invalid_later_group_preserves_existing_state     => \&invalid_later_group_preserves_existing_state,
        custom_output_is_standalone_and_wraps_messages   => \&custom_output_is_standalone_and_wraps_messages,
        staged_final_state_allows_overlapping_groups     => \&staged_final_state_allows_overlapping_groups,
        help_and_completion_are_read_only                => \&help_and_completion_are_read_only,
        commits_groups_and_cleans_up                     => \&commits_groups_and_cleans_up,
        interrupted_sequence_resumes_after_branch_switch =>
          \&interrupted_sequence_resumes_after_branch_switch,
        retry_restores_only_the_commit_message               => \&retry_restores_only_the_commit_message,
        unrelated_new_commit_does_not_pin_head               => \&unrelated_new_commit_does_not_pin_head,
        partially_committed_group_commits_only_the_remainder =>
          \&partially_committed_group_commits_only_the_remainder,
        conflicting_later_group_stops_before_review    => \&conflicting_later_group_stops_before_review,
        same_file_staged_and_unstaged_changes_survive  => \&same_file_staged_and_unstaged_changes_survive,
        changed_prepared_content_stops_without_staging => \&changed_prepared_content_stops_without_staging,
        replaced_running_helper_is_preserved           => \&replaced_running_helper_is_preserved,
        mode_only_change_commits_once                  => \&mode_only_change_commits_once,
        interrupted_overlapping_groups_resume_from_journal =>
          \&interrupted_overlapping_groups_resume_from_journal,
    },
    \&setup
);
