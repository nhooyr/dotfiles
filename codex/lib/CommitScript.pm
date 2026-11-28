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

our @EXPORT_OK = qw(generate);

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
    my ( $checkout, $root, $head, $index, $files ) = @_;
    ref($files) eq 'ARRAY' && @$files or die "A commit group needs at least one file.\n";
    local %ENV = %ENV;
    $ENV{GIT_DIR}        = "$checkout/.git";
    $ENV{GIT_WORK_TREE}  = $root;
    $ENV{GIT_INDEX_FILE} = $index;
    git( '-C', $root, 'read-tree', $head );
    git( '-C', $root, 'add', '--all', '--', @$files );
    return git( '-C', $root, 'diff', '--cached', '--binary', '--full-index', '--no-ext-diff', $head, '--' );
}

sub output_state {
    my ($path) = @_;
    my @entry = lstat $path;
    return unless @entry;
    my @target = stat $path;
    my $hash   = sha256_hex( read_file($path) );
    my @after  = lstat $path;
    @after && $entry[0] == $after[0] && $entry[1] == $after[1] && $entry[2] == $after[2]
      or die "$path changed while it was being read; it was preserved.\n";
    return { identity => join( ':', @entry[ 0, 1, 2 ], @target[ 0, 1, 2 ] ), hash => $hash };
}

sub same_output {
    my ( $before, $after ) = @_;
    return !defined($before) && !defined($after) unless defined($before) && defined($after);
    return $before->{identity} eq $after->{identity} && $before->{hash} eq $after->{hash};
}

sub publish {
    my ( $staging, $path, $previous ) = @_;
    if ( !defined $previous ) {
        link $staging, $path or die "Cannot publish $path without replacing another file: $!\n";
        return;
    }
    my $recovery = tempdir( '.commitgen-backup-XXXXXX', DIR => dirname($path), CLEANUP => 0 );
    my $backup   = "$recovery/previous";
    if ( !rename $path, $backup ) {
        my $error = $!;
        rmdir $recovery;
        die "Cannot preserve $path before publication: $error\n";
    }
    my $unchanged = eval { same_output( $previous, output_state($backup) ) };
    if ( !$unchanged ) {
        my $restored = link $backup, $path;
        die "$path changed during publication; "
          . ( $restored ? 'it was restored' : 'the current output was preserved' )
          . ". Recovery copy: $backup\n";
    }
    if ( !link $staging, $path ) {
        my $error = $!;
        link $backup, $path;
        die "Cannot publish $path without replacing another file: $error. Recovery copy: $backup\n";
    }
    warn "Previous helper retained at $backup.\n";
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
        exec 'git', '--no-pager', '-C', $checkout, 'apply', '--check', '--index', '--whitespace=nowarn',
          @args;
        die "Cannot run Git: $!\n";
    }
    waitpid( $pid, 0 );
    return $? == 0;
}

sub generate {
    my (%args)    = @_;
    my $root      = abs_path( git_line( 'rev-parse', '--show-toplevel' ) );
    my $head      = git_line( 'rev-parse', 'HEAD' );
    my $path      = File::Spec->rel2abs( $args{path} // "$root/commit" );
    my $directory = abs_path( dirname($path) ) // die "Output directory does not exist.\n";
    File::Spec->abs2rel( $directory, abs_path($root) ) !~ /^\.\.(?:\/|$)/
      or die "The output must be inside the current repository.\n";
    abs_path( git_line( '-C', $directory, 'rev-parse', '--show-toplevel' ) ) eq abs_path($root)
      or die "The output belongs to another repository.\n";
    $path = "$directory/" . ( File::Spec->splitpath($path) )[2];
    my $previous = output_state($path);

    if ( defined $args{expected_hash} ) {
        defined($previous) && $previous->{hash} eq $args{expected_hash}
          or die "$path changed before generation; it was preserved.\n";
    }
    my %inputs;
    my $read_input = sub {
        my ($file) = @_;
        $file = File::Spec->rel2abs($file);
        my $text = read_file($file);
        my $hash = sha256_hex($text);
        !exists( $inputs{$file} ) || $inputs{$file} eq $hash
          or die "$file changed during generation; no helper was published.\n";
        $inputs{$file} = $hash;
        return $text;
    };
    my $groups = $args{groups};
    my $plan_directory;
    if ( defined $args{plan_file} ) {
        !defined($groups) or die "Provide groups or plan_file, not both.\n";
        my $plan_path = File::Spec->rel2abs( $args{plan_file} );
        my $plan      = decode_json( $read_input->($plan_path) );
        ref($plan) eq 'HASH' or die "The plan needs a groups array.\n";
        $groups         = $plan->{groups};
        $plan_directory = dirname($plan_path);
    }
    ref($groups) eq 'ARRAY' && @$groups or die "Provide at least one commit group.\n";
    my $temporary = tempdir( 'commitgen-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $checkout  = "$temporary/checkout";
    local %ENV = %ENV;
    delete @ENV{
        qw(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES)
    };
    git( 'clone', '--quiet', '--shared', '--no-checkout', $root,      $checkout );
    git( '-C',    $checkout, 'checkout', '--quiet',       '--detach', $head );
    my ( @prepared, @snapshots );

    for my $i ( 0 .. $#$groups ) {
        my $group = $groups->[$i];
        ref($group) eq 'HASH' or die "Invalid commit group.\n";
        my $patch;
        if ( exists $group->{patch} ) {
            !exists $group->{patch_file} or die "A group cannot contain patch and patch_file.\n";
            $patch = $group->{patch};
        }
        elsif ( exists $group->{patch_file} ) {
            !exists $group->{files} or die "Each group needs either files or patch_file.\n";
            my $file =
              $plan_directory
              ? File::Spec->rel2abs( $group->{patch_file}, $plan_directory )
              : File::Spec->rel2abs( $group->{patch_file} );
            $patch = $read_input->($file);
        }
        else {
            $patch = snapshot_patch( $checkout, $root, $head, "$temporary/snapshot-index", $group->{files} );
            push @snapshots, { files => [ @{ $group->{files} } ], patch => $patch };
        }
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
        git( '-C', $checkout, 'apply', '--index', '--whitespace=nowarn', ( $forward ? () : '--reverse' ),
            $patch_path );
        my $after = git_line( '-C', $checkout, 'write-tree' );
        if ( $before eq $after && $reverse ) {
            git( '-C', $checkout, 'apply', '--index', '--whitespace=nowarn', '--reverse', $patch_path );
            $after   = git_line( '-C', $checkout, 'write-tree' );
            $forward = 0;
        }
        $before ne $after or die "$name contains no tree changes.\n";
        my @files = split /\0/,
          git( '-C', $checkout, 'diff', '--cached', '--no-renames', '--name-only', '-z', 'HEAD' );
        git( '-C', $checkout, 'apply', '--index', '--whitespace=nowarn', $patch_path ) unless $forward;
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
        push @prepared,
          {
            name    => $name,
            patch   => $patch,
            message => $message,
            files   => \@files,
            reverse => $forward ? 0 : 1,
          };
    }
    my $runtime = read_file( dirname(__FILE__) . '/CommitScript/runtime.pl' );
    my $json    = JSON::PP->new->canonical->ascii->encode( { base => $head, groups => \@prepared } );
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

    git_line( '-C', $root, 'rev-parse', 'HEAD' ) eq $head
      or die "HEAD changed during generation; no helper was published.\n";
    for my $snapshot (@snapshots) {
        snapshot_patch( $checkout, $root, $head, "$temporary/snapshot-index", $snapshot->{files} ) eq
          $snapshot->{patch}
          or die "Selected files changed during generation; no helper was published.\n";
    }
    for my $file ( keys %inputs ) {
        sha256_hex( read_file($file) ) eq $inputs{$file}
          or die "$file changed during generation; no helper was published.\n";
    }
    git_line( '-C', $root, 'rev-parse', 'HEAD' ) eq $head
      or die "HEAD changed during generation; no helper was published.\n";
    same_output( $previous, output_state($path) )
      or die "$path changed during generation; it was preserved.\n";
    my ( $output, $staging ) = tempfile( '.commitgen-XXXXXX', DIR => $directory, UNLINK => 0 );
    binmode $output;
    print {$output} $source or die $!;
    close $output           or die $!;
    chmod 0755, $staging or die $!;
    my $staged  = output_state($staging);
    my $success = eval { publish( $staging, $path, $previous ); 1 };
    my $error   = $@;
    unlink $staging if eval { same_output( $staged, output_state($staging) ) };
    die $error unless $success;
    return $path;
}

1;
