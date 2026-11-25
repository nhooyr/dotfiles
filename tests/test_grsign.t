use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'grsign-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{repo}      = "$self->{temporary}/repo";
    make_path( $self->{repo} );
    $self->{env} = {
        ( map { $_ => $ENV{$_} } grep { !/^GIT_/ } keys %ENV ),
        HOME                => "$self->{temporary}/home",
        PATH                => "$root/bin:$ENV{PATH}",
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => 1,
    };
    $self->{clock} = 1710000000;
}

sub git {
    my ( $self, @args ) = @_;
    my $result = run_command( [ 'git', @args ], { cwd => $self->{repo}, env => $self->{env}, check => 1 } );
    $result->{stdout} =~ s/\n\z//;
    return $result->{stdout};
}

sub dated {
    my ( $self, @args ) = @_;
    my %env = (
        %{ $self->{env} },
        GIT_AUTHOR_NAME     => 'Original Author',
        GIT_AUTHOR_EMAIL    => 'author@example.invalid',
        GIT_AUTHOR_DATE     => '@' . ++$self->{clock} . ' +0530',
        GIT_COMMITTER_NAME  => q{Tagger O'Example},
        GIT_COMMITTER_EMAIL => 'tagger@example.invalid',
        GIT_COMMITTER_DATE  => '@' . ++$self->{clock} . ' -0700',
    );
    return run_command( [ 'git', @args ], { cwd => $self->{repo}, env => \%env, check => 1 } )->{stdout};
}

sub commits {
    my ($self) = @_;
    my %commits;
    for my $oid ( split /\n/, git( $self, 'rev-list', '--branches', '--tags' ) ) {
        my $subject = git( $self, 'show', '-s', '--format=%s', $oid );
        $commits{$subject} = {
            oid      => $oid,
            metadata =>
              git( $self, 'show', '-s', '--format=%T%x00%an%x00%ae%x00%ai%x00%cn%x00%ce%x00%ci%x00%B', $oid ),
            parents => [
                map { git( $self, 'show', '-s', '--format=%s', $_ ) }
                  split / /,
                git( $self, 'show', '-s', '--format=%P', $oid )
            ],
        };
    }
    return \%commits;
}

sub tag_metadata {
    my ( $self, $name ) = @_;
    my $tag = run_command( [ 'git', 'cat-file', 'tag', $name ],
        { cwd => $self->{repo}, env => $self->{env}, check => 1 } )->{stdout};
    $tag =~ s/^object [^\n]+\n//;
    $tag =~ s/^-----BEGIN (?:PGP|SSH) SIGNATURE-----.*\z//ms;
    return $tag;
}

sub resigns_history_and_tags {
    my ($self) = @_;
    run_command( [ 'ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', "$self->{temporary}/key" ],
        { check => 1 } );
    write_file( "$self->{temporary}/allowed", '* ' . read_file("$self->{temporary}/key.pub") );
    git( $self, 'init',   '-q',         '-b', 'main' );
    git( $self, 'config', 'user.name',  'Test' );
    git( $self, 'config', 'user.email', 'test@example.invalid' );
    my $signing = "$self->{temporary}/signing";
    git( $self, 'config', '--file', $signing, 'gpg.format',                 'ssh' );
    git( $self, 'config', '--file', $signing, 'user.signingkey',            "$self->{temporary}/key" );
    git( $self, 'config', '--file', $signing, 'gpg.ssh.allowedSignersFile', "$self->{temporary}/allowed" );
    git( $self, 'config', 'includeIf.gitdir:' . absolute_path("$self->{repo}/.git") . '.path', $signing );
    dated( $self, 'commit', '-q', '--allow-empty', '-m', 'Root' );
    git( $self, 'checkout', '-qb', 'feature' );
    write_file( "$self->{repo}/feature", "feature\n" );
    git( $self, 'add', 'feature' );
    dated( $self, 'commit', '-qm', 'Feature' );
    git( $self, 'checkout', '-q', 'main' );
    write_file( "$self->{repo}/main", "main\n" );
    git( $self, 'add', 'main' );
    dated( $self, 'commit', '-qm', 'Main' );
    dated( $self, 'merge',  '-q',  '--no-ff', 'feature', '-m', 'Merge' );
    dated( $self, 'commit', '-q',  '--allow-empty', '-m', "Empty\n\nRetain this commit." );
    my $old_head = git( $self, 'rev-parse', 'HEAD' );
    git( $self, 'update-ref', 'refs/remotes/origin/main', $old_head );
    git( $self, 'tag',        'light',                    'feature' );
    my $tag_only = dated( $self, 'commit-tree', 'HEAD^{tree}', '-m', 'Tag only' );
    chomp $tag_only;
    write_file( "$self->{temporary}/message", "Annotation\n\nPreserve  spaces.\n\n" );
    dated( $self, 'tag', '-a', '--cleanup=verbatim', '-F', "$self->{temporary}/message", 'annotated',
        $tag_only );
    dated( $self, 'tag', '-s', '--cleanup=verbatim', '-F', "$self->{temporary}/message", 'signed' );
    dated( $self, 'tag', '-a', '-m', 'Inner tag', 'z-inner' );
    dated( $self, 'tag', '-a', '-m', 'Outer tag', 'a-outer', 'z-inner' );
    git( $self, 'update-ref', 'refs/tags/alias', git( $self, 'rev-parse', 'z-inner' ) );
    dated( $self, 'tag', '-a', '-m', 'Anonymous inner tag', 'temporary-inner' );
    my $anonymous = git( $self, 'rev-parse', 'temporary-inner' );
    dated( $self, 'tag', '-a', '-m', 'Anonymous outer tag', 'anonymous-outer', 'temporary-inner' );
    git( $self, 'tag', '-d', 'temporary-inner' );
    my $anonymous_metadata = tag_metadata( $self, $anonymous );
    my $before             = commits($self);
    my %tags =
      map { $_ => tag_metadata( $self, $_ ) } qw(annotated signed z-inner a-outer alias anonymous-outer);

    my $result = run_command( ["$root/bin/grsign"], { cwd => $self->{repo}, env => $self->{env} } );
    is( $result->{returncode}, 0, "history re-signing succeeds: $result->{stderr}" );
    my $after = commits($self);
    is_deeply(
        [ sort keys %$after ],
        [ sort keys %$before ],
        'all commits, including empty and tag-only commits, remain'
    );

    for my $subject ( sort keys %$before ) {
        is(
            $after->{$subject}{metadata},
            $before->{$subject}{metadata},
            "$subject retains tree, message, identities and dates"
        );
        is_deeply(
            $after->{$subject}{parents},
            $before->{$subject}{parents},
            "$subject retains its parent topology"
        );
        is( git( $self, 'show', '-s', '--format=%G?', $after->{$subject}{oid} ),
            'G', "$subject has a valid signature" );
    }
    for my $tag ( sort keys %tags ) {
        is( tag_metadata( $self, $tag ), $tags{$tag}, "$tag retains its message and tagger metadata" );
        is(
            run_command( [ 'git', 'verify-tag', $tag ], { cwd => $self->{repo}, env => $self->{env} } )
              ->{returncode},
            0,
            "$tag has a valid signature"
        );
    }
    is( git( $self, 'cat-file', '-t', 'light' ), 'commit', 'lightweight tags stay lightweight' );
    is(
        git( $self, 'rev-parse', 'light' ),
        git( $self, 'rev-parse', 'feature' ),
        'lightweight tag follows its rewritten branch'
    );
    my ($inner) = git( $self, 'cat-file', 'tag', 'a-outer' ) =~ /^object (.+)/;
    is( $inner, git( $self, 'rev-parse', 'z-inner' ), 'outer tag still points directly to the inner tag' );
    is( git( $self, 'rev-parse', 'alias' ), $inner,   'tag aliases still share the same tag object' );
    my ($anonymous_after) = git( $self, 'cat-file', 'tag', 'anonymous-outer' ) =~ /^object (.+)/;
    is( tag_metadata( $self, $anonymous_after ),
        $anonymous_metadata, 'anonymous inner tag keeps its metadata' );
    is(
        run_command( [ 'git', 'verify-tag', $anonymous_after ],
            { cwd => $self->{repo}, env => $self->{env} } )->{returncode},
        0,
        'anonymous inner tag has a valid signature'
    );
    is(
        run_command( [ 'git', 'rev-parse', '--verify', '--quiet', 'refs/tags/temporary-inner' ],
            { cwd => $self->{repo}, env => $self->{env} } )->{returncode},
        1,
        'anonymous inner tag does not gain a ref'
    );
    is( git( $self, 'rev-parse', 'refs/remotes/origin/main' ),
        $old_head, 'remote-tracking refs are unchanged' );
    my @backups = split /\n/,
      git( $self, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/original/' );
    ok( @backups, 'the first rewrite keeps original refs' );
    $result = run_command( ["$root/bin/grsign"], { cwd => $self->{repo}, env => $self->{env} } );
    is( $result->{returncode}, 0, "a second invocation succeeds: $result->{stderr}" );
    my %backups = map { $_ => 1 } split /\n/,
      git( $self, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/original/' );
    ok( !grep( !$backups{$_}, @backups ), 'repeating preserves every earlier backup ref' );
}

sub validates_arguments {
    my ($self) = @_;
    my $help =
      run_command( [ 'grsign', '--help' ], { cwd => $self->{repo}, env => $self->{env} } );
    is( $help->{returncode}, 0, 'help works without a repository' );
    like( $help->{stdout}, qr/Usage: grsign/, 'help identifies the command' );
    for my $argument ( '--unknown', '' ) {
        my $invalid =
          run_command( [ "$root/bin/grsign", $argument ], { cwd => $self->{repo}, env => $self->{env} } );
        is( $invalid->{returncode}, 2, 'unexpected arguments are rejected before rewriting' );
    }
}

run_cases(
    { resigns_history_and_tags => \&resigns_history_and_tags, validates_arguments => \&validates_arguments },
    \&setup
);
