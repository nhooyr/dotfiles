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
    write_file( "$self->{repo}/one.txt", "one intermediate\n" );
    write_file( "$self->{temporary}/first.patch",
        git( $self, 'diff', '--binary', '--full-index', '--', 'one.txt' ) . "\n" );
    git( $self, 'add', 'one.txt' );
    write_file( "$self->{repo}/one.txt", "one final\n" );
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
    write_file( "$self->{temporary}/bin/git", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
system $ENV{TEST_REAL_GIT}, @ARGV;
my $status = $? >> 8;
if (!$status && grep { $_ eq 'commit' } @ARGV) {
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
        git( $self, 'log', '--reverse', '--format=%s', "$self->{base}..HEAD" ),
        "one.txt: Apply first change\none.txt: Apply second change",
        'overlapping commits survive interruption'
    );
    ok( -x "$self->{repo}/commit", 'interruption preserves the helper' );
    $result = run_commit($self);
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        git( $self, 'log', '--reverse', '--format=%s', "$self->{base}..HEAD" ),
        "one.txt: Apply first change\none.txt: Apply second change\ntwo.txt: Update two",
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

run_cases(
    {
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
        unrelated_new_commit_does_not_pin_head         => \&unrelated_new_commit_does_not_pin_head,
        same_file_staged_and_unstaged_changes_survive  => \&same_file_staged_and_unstaged_changes_survive,
        changed_prepared_content_stops_without_staging => \&changed_prepared_content_stops_without_staging,
        replaced_running_helper_is_preserved           => \&replaced_running_helper_is_preserved,
        mode_only_change_commits_once                  => \&mode_only_change_commits_once,
        interrupted_overlapping_groups_resume_from_journal =>
          \&interrupted_overlapping_groups_resume_from_journal,
    },
    \&setup
);
