use strict;
use warnings;
use Cwd            qw(abs_path);
use Digest::SHA    qw(sha256_hex);
use Fcntl          qw(:DEFAULT :flock);
use File::Basename qw(dirname basename);
use File::Copy     qw(copy);
use File::Path     qw(make_path remove_tree);
use File::Temp     qw(tempdir);
use IPC::Open2     qw(open2);
use IO::Handle;
use JSON::PP qw(decode_json encode_json);

my $generated_fingerprint = '0000000000000000000000000000000000000000000000000000000000000000';
my $script                = abs_path($0);
my @identity              = stat $script;
my $usage                 = <<'USAGE';
Usage: ./commit [-h | --help | --completions fish]

Review and commit the prepared changes, preserving unrelated changes.
Branches may change when the same prepared patches still apply.
Rerun after interruption to resume. The helper moves to the Trash on success.
Load Fish completions on request: ./commit --completions fish | source
USAGE
if ( @ARGV == 1 && ( $ARGV[0] eq '-h' || $ARGV[0] eq '--help' ) ) {
    print $usage;
    exit 0;
}
if ( @ARGV == 2 && $ARGV[0] eq '--completions' && $ARGV[1] eq 'fish' ) {
    print <<'FISH';
complete -c commit -f
complete -c commit -s h -l help -d 'Show usage'
complete -c commit -l completions -x -a fish -d 'Print Fish completions'
FISH
    exit 0;
}
die $usage if @ARGV;
$| = 1;
$SIG{INT} = $SIG{TERM} = sub { die "Interrupted; rerun ./commit to resume.\n" };

sysopen my $lock, '/tmp/aqsnow-commit-' . sha256_hex($script) . '.lock', O_CREAT | O_RDWR, 0600
  or die "Cannot open the commit helper lock: $!\n";
flock( $lock, LOCK_EX )                         or die "Cannot lock the commit helper: $!\n";
chdir dirname($script)                          or die "Cannot enter the checkout: $!\n";
chdir capture( 'rev-parse', '--show-toplevel' ) or die "Cannot enter the repository: $!\n";
my $manifest = decode_json(<<'MANIFEST');
__COMMIT_MANIFEST__
MANIFEST
my $work = tempdir( 'review-commit.XXXXXXXX', TMPDIR => 1, CLEANUP => 1 );
my ( $index_lock, $index_lock_identity );

sub unlock_index {
    return unless defined $index_lock;
    my @current = lstat $index_lock;
    unlink $index_lock
      if @current && join( ':', @current[ 0, 1 ] ) eq $index_lock_identity;
    undef $index_lock;
}
END { unlock_index() }

sub capture_result {
    open my $pipe, '-|', 'git', '--no-pager', @_
      or die "Cannot run Git: $!\n";
    local $/;
    my $value   = <$pipe> // '';
    my $success = close $pipe;
    $value =~ s/\n\z//;
    return ( $success, $value );
}

sub capture {
    my ( $success, $value ) = capture_result(@_);
    $success or die "Git failed; rerun ./commit after resolving the error.\n";
    return $value;
}

sub run {
    system @_;
    $? == 0 or die "Command failed; rerun ./commit after resolving the error.\n";
}
sub git { run( 'git', '--no-pager', @_ ) }

sub read_file {
    open my $file, '<:raw', $_[0] or die "Cannot read $_[0]: $!\n";
    local $/;
    my $text = <$file> // '';
    close $file or die "Cannot finish reading $_[0]: $!\n";
    return $text;
}

sub write_file {
    open my $file, '>:raw', $_[0] or die "Cannot write $_[0]: $!\n";
    print {$file} $_[1] or die "Cannot write $_[0]: $!\n";
    close $file         or die "Cannot finish writing $_[0]: $!\n";
}

sub applies {
    my ( $cached, @args ) = @_;
    open my $saved, '>&', \*STDERR    or die "Cannot save stderr: $!\n";
    open STDERR,    '>',  '/dev/null' or die "Cannot redirect stderr: $!\n";
    my $status = system 'git', '--no-pager', 'apply', '--check',
      '--whitespace=nowarn', ( $cached ? '--cached' : () ), @args;
    open STDERR, '>&', $saved or die "Cannot restore stderr: $!\n";
    return 0 if $status != 0;
    my $patch = read_file( $args[-1] );
    return 1 unless $cached && $patch =~ /^old mode /m && $patch !~ /^(?:@@|GIT binary patch)/m;

    # Git accepts mode-only patches in either direction; require an actual change.
    my $source = $ENV{GIT_INDEX_FILE} // capture( 'rev-parse', '--git-path', 'index' );
    my $trial  = "$work/mode-index";
    copy( $source, $trial ) or die "Cannot check file modes: $!\n";
    local $ENV{GIT_INDEX_FILE} = $trial;
    my $before = capture('write-tree');
    git( 'apply', '--cached', '--quiet', @args );
    return capture('write-tree') ne $before;
}

sub finish {
    if ( !-e $script ) {
        print "Commit sequence complete; helper already removed.\n";
        return;
    }
    my $directory = tempdir( '.commitgen-finish-XXXXXXXX', DIR => dirname($script) );
    my $held      = "$directory/" . basename($script);
    my $success   = eval {
        rename $script, $held or die "Cannot preserve the helper before cleanup: $!\n";
        my @current_identity = stat $held;
        my $text             = -f $held && !-l $held ? read_file($held) : '';
        my ($declared)       = $text =~ /^my \$generated_fingerprint = '([0-9a-f]{64})';$/m;
        my $markers = $text =~ s/^(my \$generated_fingerprint = ')[0-9a-f]{64}(';)$/$1 . ('0' x 64) . $2/meg;
        if (  !@current_identity
            || $current_identity[0] != $identity[0]
            || $current_identity[1] != $identity[1]
            || !defined($declared)
            || $markers != 1
            || $declared ne $generated_fingerprint
            || sha256_hex($text) ne $generated_fingerprint )
        {
            if ( restore_helper( $held, $script ) ) {
                print "Commit sequence complete; keeping the modified or replaced helper.\n";
            }
            else {
                print "Commit sequence complete; preserving the replaced helper at $held.\n";
            }
        }
        else {
            print "Commit sequence complete; moving ./commit to the Trash.\n";
            run( 'trash', $held );
        }
        1;
    };
    if ( !$success ) {
        my $error = $@;
        restore_helper( $held, $script ) if -e $held || -l $held;
        rmdir $directory;
        die $error . "The helper is retained at " . ( -e $held ? $held : $script ) . ".\n";
    }
    rmdir $directory;
}

sub restore_helper {
    my ( $held, $path ) = @_;
    my $restored = -l $held ? symlink( readlink($held), $path ) : link( $held, $path );
    return 0 unless $restored;
    unlink $held or die "Cannot remove the restored helper's backup: $!\n";
    return 1;
}

my @groups     = @{ $manifest->{groups} };
my $repository = capture( 'rev-parse', '--show-toplevel' );
my $git_dir    = capture( 'rev-parse', '--absolute-git-dir' );
my $common_dir = capture( 'rev-parse', '--path-format=absolute', '--git-common-dir' );
my $index_path = capture( 'rev-parse', '--path-format=absolute', '--git-path', 'index' );
my $progress   = capture( 'rev-parse', '--path-format=absolute', '--git-path', 'aqsnow-commit-progress' );
make_path($progress);
my $script_key = sha256_hex($script);
my $pending    = "$progress/pending-$script_key.json";
make_path("$progress/messages");

sub message_path {
    return "$progress/messages/$script_key-" . sha256_hex( $_[0]{patch} . "\0" . $_[0]{message} );
}
sub receipt { return "$progress/" . sha256_hex( $_[0]{patch} ); }
my %completed;
sub completed { return $completed{ receipt( $_[0] ) }; }

sub record_completion {
    my ( $group, $commit ) = @_;
    my $path = receipt($group);
    write_file( "$path.tmp", ( $commit // capture( 'rev-parse', 'HEAD' ) ) . "\n" );
    rename "$path.tmp", $path or die "Cannot record completion: $!\n";
    $completed{$path} = 1;
}

sub save_pending {
    write_file( "$pending.tmp", encode_json( $_[0] ) );
    rename "$pending.tmp", $pending or die "Cannot record the pending commit: $!\n";
}

sub candidate_commit {
    my ($state) = @_;
    local %ENV = %ENV;
    $ENV{GIT_DIR}        = "$state->{attempt}/git";
    $ENV{GIT_COMMON_DIR} = $common_dir;
    $ENV{GIT_INDEX_FILE} = "$state->{attempt}/index";
    return capture( 'rev-parse', 'HEAD' );
}

sub preserve_attempt {
    my ( $state, $group ) = @_;
    my $candidate = candidate_commit($state);
    if ( $candidate ne $state->{base} ) {
        capture( 'show', '-s', '--format=%P', $candidate ) eq $state->{base}
          && capture( 'rev-parse', "$candidate^{tree}" ) eq $state->{tree}
          or die "The reviewed commit changed unexpectedly; recovery files remain at $state->{attempt}.\n";
        $state->{candidate} = $candidate;
        my ( $exists, $saved ) = capture_result( 'rev-parse', '--verify', '--quiet', $state->{recovery_ref} );
        if ( !$exists ) {
            git( 'update-ref', $state->{recovery_ref}, $candidate, '0' x length($candidate) );
        }
        else {
            $saved eq $candidate or die "The recovery ref changed; preserving $state->{attempt}.\n";
        }
        write_file( message_path($group), capture( 'show', '-s', '--format=%B', $candidate ) . "\n" );
    }
    elsif ( -f "$state->{attempt}/git/COMMIT_EDITMSG" ) {
        write_file( message_path($group), read_file("$state->{attempt}/git/COMMIT_EDITMSG") );
    }
    save_pending($state);
}

sub publish_index {
    my ($state) = @_;
    return unless defined $state->{index_before};
    my $current   = sha256_hex( read_file($index_path) );
    my @lock      = lstat "$index_path.lock";
    my $owns_lock = @lock && join( ':', @lock[ 0, 1 ] ) eq $state->{lock_identity};
    if ( $current eq $state->{index_before} && $owns_lock ) {
        sha256_hex( read_file("$index_path.lock") ) eq $state->{index_after}
          or die "The pending index changed; recovery files remain at $state->{attempt}.\n";
        rename "$index_path.lock", $index_path or die "Cannot publish the Git index: $!\n";
    }
    elsif ( $current eq $state->{index_after} ) {
        unlink "$index_path.lock" if $owns_lock;
    }
    else {
        unlink "$index_path.lock" if $owns_lock;
        die "The index changed before publication; preserving it and recovery files at $state->{attempt}.\n";
    }
    undef $index_lock;
    unlink "$state->{attempt}/index.lock";
}

sub finish_attempt {
    my ( $state, $group ) = @_;
    record_completion( $group, $state->{candidate} );
    git( 'update-ref', '-d', $state->{recovery_ref}, $state->{candidate} );
    unlink $pending or die "Cannot clear the completed commit: $!\n";
    unlink message_path($group);
    remove_tree( $state->{attempt} );
}

sub recover_pending {
    return unless -f $pending;
    my $state = decode_json( read_file($pending) );
    my ($group) = grep { sha256_hex( $_->{patch} ) eq $state->{patch} } @groups;
    $group or die "The pending commit is absent from this helper; restore its prepared group.\n";
    preserve_attempt( $state, $group );
    if ( defined $state->{candidate} ) {
        my ( $seen, $history ) = capture_result( 'reflog', 'show', '--format=%H', 'HEAD' );
        if ( $state->{published}
            || ( $seen && grep { $_ eq $state->{candidate} } split /\n/, $history ) )
        {
            finish_attempt( $state, $group );
            return;
        }
    }
    my @lock = lstat "$index_path.lock";
    unlink "$index_path.lock"
      if @lock
      && defined( $state->{lock_identity} )
      && join( ':', @lock[ 0, 1 ] ) eq $state->{lock_identity};
    rename $pending, "$state->{attempt}/state.json" or die "Cannot preserve the interrupted attempt: $!\n";
}

sub plan_trees {
    local $ENV{GIT_INDEX_FILE} = "$work/plan-index";
    git( 'read-tree', $manifest->{base} );
    my $plan_base = capture('write-tree');
    my $before    = $plan_base;
    my $path      = "$work/plan.patch";
    my @trees;

    # Replay the validated plan to recover each patch's original preimage.
    for my $group (@groups) {
        write_file( $path, $group->{patch} );
        git( 'apply', '--cached', '--whitespace=nowarn', ( $group->{reverse} ? '--reverse' : () ), $path );
        my $after = capture('write-tree');
        if ( $group->{reverse} ) {
            push @trees, [ $after, $before ];
            git( 'read-tree', $before );
        }
        else {
            push @trees, [ $before, $after ];
            $before = $after;
        }
    }
    return ( $plan_base, @trees );
}

sub merge_trees {
    my ( $base, $current, $target ) = @_;
    return $target  if $current eq $base;
    return $current if $current eq $target || $base eq $target;
    my ( $clean, $merged ) =
      capture_result( 'merge-tree', '--write-tree', '--no-messages', "--merge-base=$base", $current,
        $target );
    return $clean ? $merged : undef;
}

recover_pending();
%completed = ();
my ( $plan_base, @plan_trees ) = plan_trees();
my $head_tree = capture( 'rev-parse', 'HEAD^{tree}' );
for my $i ( reverse 0 .. $#groups ) {
    next unless -f receipt( $groups[$i] );
    my ( $before, $after ) = @{ $plan_trees[$i] };

    # Check the cumulative result because later groups may edit earlier changes.
    my $base   = $after eq $plan_base ? $before : $plan_base;
    my $merged = merge_trees( $base, $head_tree, $after );
    next unless defined($merged) && $merged eq $head_tree;
    $completed{ receipt( $groups[$_] ) } = 1 for 0 .. $i;
    last;
}

sub prepare_remaining {
    my ( $start, $head ) = @_;
    my $head_tree = capture( 'rev-parse', "$head^{tree}" );
    my $tree      = $head_tree;
    my $expected;
    for my $i ( $start .. $#groups ) {
        my $group = $groups[$i];
        next if completed($group);
        my ( $before, $after ) = @{ $plan_trees[$i] };
        my $merged = merge_trees( $before, $tree, $after )
          // die "The remaining changes conflict with HEAD in $group->{name}; nothing was staged.\n";
        if ( $merged ne $tree && $tree ne $before ) {
            my %allowed = map { $_ => 1 } @{ $group->{files} };
            my @changed = split /\0/, capture( 'diff', '--no-renames', '--name-only', '-z', $tree, $merged );
            !grep( { !$allowed{$_} } @changed )
              or die "$group->{name} changes unexpected paths; nothing was staged.\n";
        }
        $expected = $merged if $i == $start && $merged ne $tree;
        $tree     = $merged;
    }
    if ( $tree ne $head_tree ) {
        my $net_patch = capture( 'diff', '--binary', '--full-index', '--no-ext-diff', $head_tree, $tree );
        my $path      = "$work/final.patch";
        write_file( $path, "$net_patch\n" );
        ( applies( 0, '--reverse', $path ) || applies( 1, '--reverse', $path ) )
          or die
          "The working tree and index do not contain the final prepared changes; nothing was staged.\n";
    }
    return ( $expected, $tree );
}

sub publish_commit {
    my ($state) = @_;
    local $SIG{PIPE} = 'IGNORE';
    my ( $from, $to );
    my $pid = open2( $from, $to, 'git', '--no-pager', 'update-ref', '--stdin',
        '--create-reflog', '-m', 'commitgen: publish reviewed commit' );
    $to->autoflush(1);
    my $success = eval {
        print {$to} "start\n" or die "Cannot start reference transaction.\n";
        my $started = <$from> // '';
        $started eq "start: ok\n" or die "Cannot start reference transaction.\n";
        print {$to} "update HEAD $state->{candidate} $state->{base}\nprepare\n"
          or die "Cannot prepare reference transaction.\n";
        my $prepared = <$from> // '';
        $prepared eq "prepare: ok\n"
          or die "HEAD changed during review; the reviewed commit is retained at $state->{recovery_ref}.\n";
        read_file("$git_dir/HEAD") eq $state->{head_content}
          or die "The checked-out branch changed during review; no commit was published.\n";
        sha256_hex( read_file($index_path) ) eq $state->{index_before}
          or die "The Git index changed despite its lock; no commit was published.\n";
        $state->{publication_attempted} = 1;
        save_pending($state);

        # Publish the index while HEAD is locked; never replace it after another commit can land.
        publish_index($state);
        $state->{index_published} = 1;
        save_pending($state);
        print {$to} "commit\n" or die "Cannot publish reference transaction.\n";
        my $committed = <$from> // '';
        $committed eq "commit: ok\n" or die "Reference publication failed; recovery data was retained.\n";
        1;
    };
    my $error = $@;
    print {$to} "abort\n" unless $success;
    close $to;
    close $from;
    waitpid( $pid, 0 );
    die $error unless $success;
    $state->{published} = 1;
    save_pending($state);
}

GROUP: for my $i ( 0 .. $#groups ) {
    my $group = $groups[$i];
    next GROUP if completed($group);
    my $head_content = read_file("$git_dir/HEAD");
    my $head         = capture( 'rev-parse', 'HEAD' );
    my ( $expected, $final ) = prepare_remaining( $i, $head );
    read_file("$git_dir/HEAD") eq $head_content && capture( 'rev-parse', 'HEAD' ) eq $head
      or die "HEAD changed during preparation; rerun ./commit.\n";
    if ( !defined $expected ) {
        record_completion( $group, $head );
        next GROUP;
    }
    my $commit_index = "$work/commit-index";
    {
        local $ENV{GIT_INDEX_FILE} = $commit_index;
        git( 'read-tree', $expected );
    }
    my $attempt = tempdir( "attempt-$script_key-XXXXXXXX", DIR => $progress );
    make_path("$attempt/git");
    write_file( "$attempt/git/HEAD", "$head\n" );
    copy( $commit_index, "$attempt/index" ) or die "Cannot retain the prepared index: $!\n";
    my $message = message_path($group);
    write_file( $message, $group->{message} ) unless -f $message;
    my $state = {
        patch        => sha256_hex( $group->{patch} ),
        base         => $head,
        tree         => $expected,
        head_content => $head_content,
        attempt      => $attempt,
        recovery_ref => 'refs/commitgen/' . $script_key . '/' . basename($attempt),
    };
    save_pending($state);
    printf "\033[1mStep %d/%d: %s\033[0m\n", $i + 1, scalar(@groups), $group->{name};
    my $success = eval {
        {
            local %ENV = %ENV;
            $ENV{GIT_DIR}        = "$attempt/git";
            $ENV{GIT_COMMON_DIR} = $common_dir;
            $ENV{GIT_WORK_TREE}  = $repository;
            $ENV{GIT_INDEX_FILE} = "$attempt/index";
            git( 'commit', '--verbose', '--edit', '--file', $message );
        }
        preserve_attempt( $state, $group );
        defined( $state->{candidate} ) or die "No reviewed commit was created.\n";
        capture( 'rev-parse', 'HEAD' ) eq $head && read_file("$git_dir/HEAD") eq $head_content
          or die "HEAD changed during review; the reviewed commit is retained at $state->{recovery_ref}.\n";

        sysopen my $locked, "$attempt/index.lock", O_CREAT | O_EXCL | O_WRONLY, 0666
          or die "Cannot prepare the index lock: $!\n";
        my @lock = stat $locked;
        $index_lock_identity = join( ':', @lock[ 0, 1 ] );
        $state->{lock_identity} = $index_lock_identity;
        save_pending($state);
        link "$attempt/index.lock", "$index_path.lock"
          or die "Cannot lock the Git index: $!\n";
        $index_lock = "$index_path.lock";
        my $before_bytes = read_file($index_path);
        write_file( "$attempt/before.index", $before_bytes );
        copy( "$attempt/before.index", "$attempt/after.index" )
          or die "Cannot retain the current index: $!\n";
        {
            local $ENV{GIT_INDEX_FILE} = "$attempt/after.index";
            my $before = capture('write-tree');
            my ( $clean, $merged ) =
              capture_result( 'merge-tree', '--write-tree', "--merge-base=$head", $expected, $before );
            if ( !$clean ) {
                my ($compatible) =
                  capture_result( 'merge-tree', '--write-tree', "--merge-base=$final", $head, $before );
                $compatible
                  or die "Staged changes conflict with the prepared sequence; no commit was published.\n";
                $merged = capture( 'merge-tree', '--write-tree', '-Xtheirs',
                    "--merge-base=$head", $expected, $before );
            }
            my ($tree)  = split /\n/, $merged;
            my $changes = capture( 'diff', '--binary', '--full-index', '--no-ext-diff', $before, $tree );
            if ( length $changes ) {
                write_file( "$work/staged.patch", "$changes\n" );
                git( 'apply', '--cached', '--whitespace=nowarn', "$work/staged.patch" );
            }
        }
        my $after_bytes = read_file("$attempt/after.index");
        binmode $locked;
        print {$locked} $after_bytes or die "Cannot prepare the locked index: $!\n";
        close $locked                or die "Cannot finish the locked index: $!\n";
        $state->{index_before} = sha256_hex($before_bytes);
        $state->{index_after}  = sha256_hex($after_bytes);
        save_pending($state);
        publish_commit($state);
        finish_attempt( $state, $group );
        1;
    };
    if ( !$success ) {
        my $error = $@;
        if ( $state->{publication_attempted} ) {
            undef $index_lock;
        }
        else {
            unlock_index();
            preserve_attempt( $state, $group );
            rename $pending, "$attempt/state.json"
              or die "Cannot retain the interrupted attempt: $!\n";
        }
        die $error . "Recovery files: $attempt\n";
    }
}
finish();
