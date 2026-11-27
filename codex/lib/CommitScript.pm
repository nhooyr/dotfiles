package CommitScript;
use strict;
use warnings;
use Exporter 'import';
use Cwd            qw(abs_path);
use Digest::SHA    qw(sha256_hex);
use Fcntl          qw(:flock);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use Text::Wrap qw(wrap);
use JSON::PP;

our @EXPORT_OK = qw(generate snapshot_patch);

sub read_file {
    open my $file, '<:raw', $_[0] or die "Cannot read $_[0]: $!\n";
    local $/;
    return <$file> // '';
}

sub git {
    open my $pipe, '-|', 'git', '--no-pager', @_
      or die "Cannot run Git: $!\n";
    binmode $pipe;
    local $/;
    my $output = <$pipe> // '';
    close $pipe or die "Git failed: @_\n";
    return $output;
}

sub git_line {
    my $output = git(@_);
    $output =~ s/\n\z//;
    return $output;
}

sub snapshot_patch {
    my (@files) = @_;
    @files or die "A commit group needs at least one file.\n";
    my $temporary = tempdir( 'commitgen-index-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $root      = git_line( 'rev-parse', '--show-toplevel' );
    my $head      = git_line( 'rev-parse', 'HEAD' );
    local @ENV{qw(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE)};
    git( 'clone', '--quiet', '--shared', '--no-checkout', $root, "$temporary/checkout" );
    $ENV{GIT_DIR}        = "$temporary/checkout/.git";
    $ENV{GIT_WORK_TREE}  = $root;
    $ENV{GIT_INDEX_FILE} = "$temporary/index";
    git( 'read-tree', $head );
    git( 'add', '--all', '--', @files );
    return git( 'diff', '--cached', '--binary', '--full-index', '--no-ext-diff', 'HEAD', '--' );
}

sub message {
    my ($text) = @_;
    defined($text) && $text =~ /\S/ or die "A commit group needs a message.\n";
    $text                   =~ s/\r\n/\n/g;
    $text                   =~ s/\s+\z//;
    my ( $title, $body ) = split /\n/, $text, 2;
    length($title) <= 80 or die "Commit titles must fit within 80 columns.\n";
    return "$title\n" unless defined $body && $body =~ /\S/;
    $body =~ s/^\s+//;
    local $Text::Wrap::columns = 80;
    local $Text::Wrap::huge    = 'wrap';
    my @paragraphs = split /\n\s*\n/, $body;

    for (@paragraphs) {
        s/\s*\n\s*/ /g;
        $_ = wrap( '', '', $_ );
    }
    return "$title\n\n" . join( "\n\n", @paragraphs ) . "\n";
}

sub applies {
    my ( $checkout, @args ) = @_;
    my $pid = fork();
    defined $pid or die "Cannot fork: $!\n";
    if ( !$pid ) {
        open STDERR, '>', File::Spec->devnull or die $!;
        exec 'git', '--no-pager', '-C', $checkout, 'apply', '--check', '--index', @args;
        die "Cannot run Git: $!\n";
    }
    waitpid( $pid, 0 );
    return $? == 0;
}

sub generate {
    my (%args) = @_;
    my $groups = $args{groups};
    ref($groups) eq 'ARRAY' && @$groups or die "Provide at least one commit group.\n";
    my $root      = git_line( 'rev-parse', '--show-toplevel' );
    my $head      = git_line( 'rev-parse', 'HEAD' );
    my $path      = File::Spec->rel2abs( $args{path} // "$root/commit" );
    my $directory = abs_path( dirname($path) ) // die "Output directory does not exist.\n";
    File::Spec->abs2rel( $directory, abs_path($root) ) !~ /^\.\.(?:\/|$)/
      or die "The output must be inside the current repository.\n";
    abs_path( git_line( '-C', $directory, 'rev-parse', '--show-toplevel' ) ) eq abs_path($root)
      or die "The output belongs to another repository.\n";
    $path = "$directory/" . ( File::Spec->splitpath($path) )[2];
    my @identity = stat $path;
    my $previous = -e $path ? sha256_hex( read_file($path) ) : undef;

    if ( defined $args{expected_hash} ) {
        defined($previous) && $previous eq $args{expected_hash}
          or die "$path changed before generation; it was preserved.\n";
    }
    my $temporary = tempdir( 'commitgen-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $checkout  = "$temporary/checkout";
    local @ENV{qw(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE)};
    git( 'clone', '--quiet', '--shared', '--no-checkout', $root,      $checkout );
    git( '-C',    $checkout, 'checkout', '--quiet',       '--detach', $head );
    my $base = git_line( '-C', $checkout, 'rev-parse', 'HEAD' );
    my @prepared;

    for my $i ( 0 .. $#$groups ) {
        my $group = $groups->[$i];
        ref($group) eq 'HASH' or die "Invalid commit group.\n";
        my $patch = $group->{patch};
        defined($patch) && $patch =~ /\S/ or die "Commit group " . ( $i + 1 ) . " has no changes.\n";
        my $message    = message( $group->{message} );
        my $name       = $group->{name} // sprintf( '%02d-change.patch', $i + 1 );
        my $patch_path = "$temporary/group.patch";
        open my $file, '>:raw', $patch_path or die $!;
        print {$file} $patch or die $!;
        close $file          or die $!;
        my $forward = applies( $checkout, $patch_path );
        my $reverse = applies( $checkout, '--reverse', $patch_path );
        $forward || $reverse or die "$name does not apply to the commit sequence.\n";

        # Applying a mode-only patch in either direction can pass --check.
        my $before = git_line( '-C', $checkout, 'write-tree' );
        git( '-C', $checkout, 'apply', '--index', ( $forward ? () : '--reverse' ), $patch_path );
        my $after = git_line( '-C', $checkout, 'write-tree' );
        if ( $before eq $after && $reverse ) {
            git( '-C', $checkout, 'apply', '--index', '--reverse', $patch_path );
            $after   = git_line( '-C', $checkout, 'write-tree' );
            $forward = 0;
        }
        $before ne $after or die "$name contains no tree changes.\n";
        my @files = split /\0/,
          git( '-C', $checkout, 'diff', '--cached', '--no-renames', '--name-only', '-z', 'HEAD' );
        git( '-C', $checkout, 'apply', '--index', $patch_path ) unless $forward;
        if ($forward) {
            my $message_path = "$temporary/message";
            open my $file, '>:raw', $message_path or die $!;
            print {$file} $message or die $!;
            close $file            or die $!;
            git(
                '-C',     $checkout,
                '-c',     'user.name=Commit script validation',
                '-c',     'user.email=commit-script@example.invalid',
                '-c',     'commit.gpgsign=false',
                '-c',     'core.hooksPath=/dev/null',
                'commit', '--quiet',
                '--file', $message_path
            );
        }
        my $checkpoint =
          git( '-C', $checkout, 'diff', '--binary', '--full-index', '--no-ext-diff', $base, 'HEAD' );
        push @prepared,
          {
            name       => $name,
            patch      => $patch,
            message    => $message,
            files      => [ sort @files ],
            checkpoint => length($checkpoint) ? $checkpoint : $patch
          };
    }
    my $runtime = read_file( dirname(__FILE__) . '/CommitScript/runtime.pl' );
    my $json    = JSON::PP->new->canonical->ascii->encode( { groups => \@prepared } );
    $runtime =~ s/^__COMMIT_MANIFEST__$/$json/m or die "Missing runtime manifest marker.\n";
    my $source =
        '#!/bin/sh' . "\n"
      . 'exec perl -x "$0" "$@"'
      . "\n: <<'PERL'\n#!perl\n"
      . $runtime
      . "\n__END__\nPERL\n";
    my $fingerprint = sha256_hex($source);
    $source =~ s/^(my \$generated_fingerprint = ')0{64}(';)$/$1$fingerprint$2/m
      or die "Missing runtime fingerprint marker.\n";
    open my $lock, '>>', '/tmp/aqsnow-commit-' . sha256_hex($path) . '.lock' or die $!;
    flock( $lock, LOCK_EX ) or die $!;

    if ( -e $path ) {
        my @current = stat $path;
        defined($previous)
          && $previous eq sha256_hex( read_file($path) )
          && $identity[0] == $current[0]
          && $identity[1] == $current[1]
          or die "$path changed during generation; it was preserved.\n";
    }
    my ( $output, $staging ) = tempfile( '.commitgen-XXXXXX', DIR => $directory, UNLINK => 1 );
    binmode $output;
    print {$output} $source or die $!;
    close $output           or die $!;
    chmod 0755, $staging or die $!;
    rename $staging, $path or die "Cannot publish $path: $!\n";
    return $path;
}

1;
