use strict;
use warnings;
use File::Basename qw(dirname);
use JSON::PP       qw(decode_json);

my ( $kind, @args ) = @ARGV;
if ( $kind eq 'git' ) {
    my $i = 0;
    while ( $i < @args ) {
        if    ( $args[$i] =~ /\A(?:-C|-c|--git-dir|--work-tree)\z/ ) { $i += 2; }
        elsif ( $args[$i] =~ /^-/ )                                  { ++$i; }
        else                                                         { last; }
    }
    my $command = $args[$i] // '';
    die "the command under test must never push\n" if $command eq 'push';
    if ( $command eq 'clone' && $ENV{TEST_CLONE_FAILURE} ) {
        if ( $ENV{TEST_CLONE_FAILURE} eq 'nonempty' ) {
            my $path = dirname( $args[-1] ) . '/unrelated.txt';
            open my $file, '>', $path or die "$path: $!\n";
            print {$file} "keep unrelated file\n";
            close $file or die "$path: $!\n";
        }
        exit 37;
    }
    if ( $command =~ /\A(?:clone|fetch|ls-remote)\z/ ) {
        die "fixture is offline\n" if $ENV{TEST_OFFLINE};
        my %value_options = map { $_ => 1 }
          qw(-b --branch --depth --deepen --filter -c --config -o --origin --upload-pack --exec --server-option --shallow-since --shallow-exclude --reference --separate-git-dir);
        my $j = $i + 1;
        while ( $j < @args ) {
            if    ( $args[$j] eq '--' )           { ++$j; last; }
            if    ( $value_options{ $args[$j] } ) { $j += 2; }
            elsif ( $args[$j] =~ /^-/ )           { ++$j; }
            else                                  { last; }
        }
        if ( $j >= @args ) {
            die "network command without a source\n" unless $command eq 'fetch';
            push @args, 'origin';
        }
        my $source = $args[$j];
        if ( $source !~ m{[:/]} ) {
            open my $git, '-|', $ENV{TEST_REAL_GIT}, @args[ 0 .. $i - 1 ], 'remote', 'get-url', '--', $source
              or die $!;
            local $/;
            $source = <$git>;
            close $git or die "remote get-url failed\n";
            $source =~ s/\s+$//;
        }
        my %allowed = map { $_ => 1 } (
            'https://github.com/test-owner/test-repo.git',
            'http://github.com/test-owner/test-repo.git',
            'git@github.com:test-owner/test-repo.git',
            'ssh://git@github.com:22/test-owner/test-repo.git',
            'ssh://git@ssh.github.com:443/test-owner/test-repo.git',
            @{ decode_json( $ENV{TEST_EXTRA_URLS} ) },
        );
        die "unmapped remote blocked: $source\n" unless $allowed{$source};
        my $remote = $ENV{TEST_REMOTE};
        utf8::encode($remote);
        $remote =~ s{([^A-Za-z0-9/_.~-])}{sprintf '%%%02X', ord $1}ge;
        unshift @args, '-c', "url.file://$remote.insteadOf=$source";
    }
    exec { $ENV{TEST_REAL_GIT} } $ENV{TEST_REAL_GIT}, @args;
    die "git: $!\n";
}
if ( $kind eq 'gh' ) {
    if ( @args >= 2 && $args[0] eq 'repo' && $args[1] eq 'create' ) {
        print $ENV{TEST_REPO_CREATE_STDOUT};
        print STDERR $ENV{TEST_REPO_CREATE_STDERR};
        exit $ENV{TEST_REPO_CREATE_STATUS};
    }
    my ($endpoint) = grep { /^repos\// } @args;
    $endpoint //= '';
    my $response = decode_json( $ENV{TEST_GH_RESPONSES} )->{$endpoint};
    die "unmapped gh request: $endpoint\n" unless defined $response;
    print "$response\n";
    exit;
}
exit( $ENV{TEST_DISPATCH_STATUS} // 0 ) if $kind eq 'dispatch';
die "unexpected mock executable\n" unless $kind eq 'editor' || $kind eq 'open';
