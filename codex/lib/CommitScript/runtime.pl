use strict;
use warnings;
use Cwd            qw(abs_path);
use Digest::SHA    qw(sha256_hex);
use Fcntl          qw(:DEFAULT :flock);
use File::Basename qw(dirname);
use File::Copy     qw(copy);
use File::Path     qw(make_path);
use File::Temp     qw(tempdir);
use JSON::PP       qw(decode_json encode_json);

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
my $index_lock;
END { unlink $index_lock if defined $index_lock }

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

sub stage_index {
    my ( $path, $before, $after ) = @_;
    return if $before eq $after;
    sysopen my $output, "$path.lock", O_CREAT | O_EXCL | O_WRONLY, 0666
      or die "Cannot lock the Git index: $!\n";
    $index_lock = "$path.lock";
    read_file($path) eq $before
      or die "The Git index changed during preparation; rerun ./commit.\n";
    binmode $output;
    print {$output} $after or die "Cannot stage the prepared change: $!\n";
    close $output          or die "Cannot finish staging the prepared change: $!\n";
    rename $index_lock, $path or die "Cannot publish the Git index: $!\n";
    undef $index_lock;
}

sub finish {
    if ( !-e $script ) {
        print "Commit sequence complete; helper already removed.\n";
        return;
    }
    my @current_identity = stat $script;
    my $text             = read_file($script);
    my ($declared) = $text =~ /^my \$generated_fingerprint = '([0-9a-f]{64})';$/m;
    my $markers    = $text =~ s/^(my \$generated_fingerprint = ')[0-9a-f]{64}(';)$/$1 . ('0' x 64) . $2/meg;
    if (   $current_identity[0] != $identity[0]
        || $current_identity[1] != $identity[1]
        || !defined($declared)
        || $markers != 1
        || $declared ne $generated_fingerprint
        || sha256_hex($text) ne $generated_fingerprint )
    {
        print "Commit sequence complete; keeping the modified or replaced helper.\n";
        return;
    }
    print "Commit sequence complete; moving ./commit to the Trash.\n";
    run( 'trash', $script );
}

my @groups   = @{ $manifest->{groups} };
my $progress = capture( 'rev-parse', '--git-path', 'aqsnow-commit-progress' );
make_path($progress);
my $pending = "$progress/pending-" . sha256_hex($script) . '.json';
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

sub recover_pending {
    return unless -f $pending;
    my $state = decode_json( read_file($pending) );
    my ($group) = grep { sha256_hex( $_->{patch} ) eq $state->{patch} } @groups;
    $group or die "The pending commit is absent from this helper; restore its prepared group.\n";
    my $head = capture( 'rev-parse', 'HEAD' );
    my @tips = ($head);
    if ( $state->{ref} ne 'HEAD' ) {
        my ( $exists, $tip ) = capture_result( 'rev-parse', '--verify', '--quiet', $state->{ref} );
        push @tips, $tip if $exists && $tip ne $head;
    }
    for my $tip (@tips) {
        my ($descendant) = capture_result( 'merge-base', '--is-ancestor', $state->{base}, $tip );
        next unless $descendant;
        my ($commit) = split /\n/,
          capture( 'rev-list', '--first-parent', '--reverse', "$state->{base}..$tip" );
        next unless defined $commit;
        if (   capture( 'show', '-s', '--format=%P', $commit ) eq $state->{base}
            && capture( 'rev-parse', "$commit^{tree}" ) eq $state->{tree} )
        {
            record_completion( $group, $commit );
            unlink $pending or die "Cannot clear the pending commit: $!\n";
            return;
        }
    }
    if ( grep { $_ eq $state->{base} } @tips ) {
        unlink $pending or die "Cannot clear the interrupted attempt: $!\n";
        return;
    }
    die "The pending commit differs from the prepared change; keeping its recovery record.\n";
}
recover_pending();
%completed = ();
{
    local $ENV{GIT_INDEX_FILE} = "$work/progress-index";
    git( 'read-tree', 'HEAD' );
    for my $i ( reverse 0 .. $#groups ) {
        next unless -f receipt( $groups[$i] );
        my $checkpoint = $groups[$i]{checkpoint};
        write_file( "$work/checkpoint.patch", $checkpoint );
        next if length($checkpoint) && !applies( 1, '--reverse', "$work/checkpoint.patch" );
        $completed{ receipt( $groups[$_] ) } = 1 for 0 .. $i;
        last;
    }
}

sub verify_remaining {
    my ($start) = @_;
    my ( $net_patch, $tree );
    {
        local $ENV{GIT_INDEX_FILE} = "$work/series-index";
        git( 'read-tree', 'HEAD' );
        for my $group ( @groups[ $start .. $#groups ] ) {
            next if completed($group);
            my $path = "$work/series.patch";
            write_file( $path, $group->{patch} );
            my $forward = applies( 1, $path );
            my $reverse = applies( 1, '--reverse', $path );
            next if $reverse && !$forward;
            $forward && !$reverse or die "The remaining changes conflict with HEAD; nothing was staged.\n";
            git( 'apply', '--cached', '--whitespace=nowarn', $path );
        }
        $net_patch = capture( 'diff', '--cached', '--binary', '--full-index', 'HEAD' );
        $tree      = capture('write-tree');
    }
    return $tree unless length $net_patch;
    my $path = "$work/final.patch";
    write_file( $path, "$net_patch\n" );
    ( applies( 0, '--reverse', $path ) || applies( 1, '--reverse', $path ) )
      or die "The working tree and index do not contain the final prepared changes; nothing was staged.\n";
    return $tree;
}

GROUP: for my $i ( 0 .. $#groups ) {
    my $group = $groups[$i];
    next GROUP if completed($group);
    my $final        = verify_remaining($i);
    my @files        = @{ $group->{files} };
    my $head         = capture( 'rev-parse', 'HEAD' );
    my $patch        = "$work/change.patch";
    my $commit_index = "$work/commit-index";
    my $staged_index = "$work/staged-index";
    write_file( $patch, $group->{patch} );
    my $expected;
    {
        local $ENV{GIT_INDEX_FILE} = $commit_index;
        git( 'read-tree', $head );
        my $forward = applies( 1, $patch );
        my $reverse = applies( 1, '--reverse', $patch );
        if ( $reverse && !$forward ) { record_completion($group); next GROUP; }
        $forward && !$reverse
          or die "The prepared patch does not apply unambiguously to HEAD; no files were staged.\n";
        git( 'apply', '--cached', '--whitespace=nowarn', $patch );
        $expected = capture('write-tree');
        my $changed = capture( 'diff', '--cached', '--no-renames', '--name-only', $head );
        $changed eq join( "\n", sort @files )
          or die "The prepared patch changes unexpected paths; no files were staged.\n";
    }
    my $index_path     = capture( 'rev-parse', '--git-path', 'index' );
    my $original_index = read_file($index_path);
    copy( $index_path, $staged_index ) or die "Cannot prepare the Git index: $!\n";
    {
        local $ENV{GIT_INDEX_FILE} = $staged_index;
        my $before = capture('write-tree');
        my ( $clean, $merged ) =
          capture_result( 'merge-tree', '--write-tree', "--merge-base=$head", $expected, $before );
        if ( !$clean ) {
            my ($compatible) =
              capture_result( 'merge-tree', '--write-tree', "--merge-base=$final", $head, $before );
            $compatible or die "Staged changes conflict with the prepared sequence; nothing was staged.\n";

            # Keep already-staged later values when this commit introduces an intermediate value.
            $merged =
              capture( 'merge-tree', '--write-tree', '-Xtheirs', "--merge-base=$head", $expected, $before );
        }
        my ($tree)  = split /\n/, $merged;
        my $changes = capture( 'diff', '--binary', '--full-index', '--no-ext-diff', $before, $tree );
        if ( length $changes ) {
            write_file( "$work/staged.patch", "$changes\n" );
            git( 'apply', '--cached', '--whitespace=nowarn', "$work/staged.patch" );
        }
    }
    capture( 'rev-parse', 'HEAD' ) eq $head
      or die "HEAD changed during preparation; rerun ./commit.\n";
    stage_index( $index_path, $original_index, read_file($staged_index) );
    my $message = "$work/message";
    write_file( $message, $group->{message} );
    write_file(
        "$pending.tmp",
        encode_json(
            {
                patch => sha256_hex( $group->{patch} ),
                base  => $head,
                tree  => $expected,
                ref   => capture( 'rev-parse', '--symbolic-full-name', 'HEAD' ),
            }
        )
    );
    rename "$pending.tmp", $pending or die "Cannot record the pending commit: $!\n";
    printf "\033[1mStep %d/%d: %s\033[0m\n", $i + 1, scalar(@groups), $group->{name};
    my $success = eval {
        local $ENV{GIT_INDEX_FILE} = $commit_index;
        capture( 'rev-parse', 'HEAD' ) eq $head
          or die "HEAD changed before committing; rerun ./commit.\n";
        git( 'commit', '--verbose', '--edit', '--file', $message );
        1;
    };
    if ( !$success ) {
        my $error = $@;
        unlink $pending if capture( 'rev-parse', 'HEAD' ) eq $head;
        die $error;
    }
    capture( 'show', '-s', '--format=%P', 'HEAD' ) eq $head
      && capture( 'rev-parse', 'HEAD^{tree}' ) eq $expected
      or die "The commit differs from the prepared patch; keeping the helper.\n";
    record_completion($group);
    unlink $pending or die "Cannot clear the completed commit: $!\n";
}
finish();
