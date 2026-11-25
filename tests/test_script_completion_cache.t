use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use JSON::PP    ();
use Time::HiRes qw(time sleep utime);

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'script-flags-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{script}    = "$self->{temporary}/tool";
    $self->{env} = { %ENV, HOME => "$self->{temporary}/home", PROBE_COUNT => "$self->{temporary}/count" };
}

sub script {
    my ( $path, $body ) = @_;
    make_path( dirname($path) );
    write_file( $path, '#!' . perl_executable() . "\n" . $body );
    chmod 0755, $path or die $!;
}

sub complete {
    my ( $self, $path ) = @_;
    return run_command( [ perl_executable(), "$root/fish/compgen.pl", $path // $self->{script} ],
        { env => $self->{env}, input => 'not passed to the script' } );
}

sub caches_flags_and_uses_no_stdin {
    my ($self) = @_;
    script( $self->{script}, <<'PERL' );
die 'unexpected arguments' unless @ARGV == 1 && $ARGV[0] eq '--help';
die 'stdin was inherited' if read(STDIN, my $input, 1);
open my $count, '>>', $ENV{PROBE_COUNT} or die $!; print {$count} 'x'; close $count;
print "Usage: tool [-h] [--alpha] [--output=FILE]\n--alpha --alpha\nnot-a-flag -prose\n";
print STDERR "--stderr\n";
PERL
    for ( 1 .. 2 ) {
        my $result = complete($self);
        is( $result->{returncode}, 0,                                   'flag discovery succeeds' );
        is( $result->{stdout},     "--alpha\n--output\n--stderr\n-h\n", 'flags are sorted and deduplicated' );
        is( $result->{stderr},     '', 'probe output is kept out of the terminal' );
    }
    is( read_file( $self->{env}{PROBE_COUNT} ), 'x', 'unchanged script is probed once' );
    symlink $self->{script}, "$self->{temporary}/alias" or die $!;
    is(
        complete( $self, "$self->{temporary}/alias" )->{stdout},
        complete($self)->{stdout},
        'symlink uses the same flags'
    );
    is( read_file( $self->{env}{PROBE_COUNT} ), 'x', 'physical path shares the cache' );
    my $cache = JSON::PP->new->decode(
        read_file("$self->{env}{HOME}/.local/share/fish/compgen/cache.json") );
    ok(
        exists $cache->{ absolute_path( $self->{script} ) },
        'the cache key is the readable full source path'
    );
}

sub invalidates_same_size_subsecond_edits {
    my ($self) = @_;
    my $second = int(time) - 10;
    script( $self->{script}, 'print "--alpha\n";' );
    utime $second + .1, $second + .1, $self->{script};
    is( complete($self)->{stdout}, "--alpha\n", 'initial version is cached' );
    script( $self->{script}, 'print "--bravo\n";' );
    utime $second + .2, $second + .2, $self->{script};
    is( complete($self)->{stdout},
        "--bravo\n", 'same-size edit within the same second invalidates the cache' );
}

sub separates_paths_with_the_same_basename {
    my ($self) = @_;
    my @paths;
    for my $case ( [ 'first folder', 'first' ], [ 'second café', 'second' ] ) {
        my ( $folder, $flag ) = @$case;
        my $path = "$self->{temporary}/$folder/tool";
        script( $path, qq{print "--$flag\\n";} );
        is( complete( $self, $path )->{stdout}, "--$flag\n", 'each physical script has its own cache' );
        my $physical = absolute_path($path);
        utf8::decode($physical);
        push @paths, $physical;
    }
    my $cache = JSON::PP->new->decode(
        read_file("$self->{env}{HOME}/.local/share/fish/compgen/cache.json") );
    is_deeply(
        [ sort keys %$cache ],
        [ sort @paths ],
        'JSON preserves full paths including spaces and Unicode'
    );
}

sub caches_negative_results {
    my ($self) = @_;
    script( $self->{script}, <<'PERL' );
open my $count, '>>', $ENV{PROBE_COUNT} or die $!; print {$count} 'x'; close $count;
print STDERR "No help available\n"; exit 7;
PERL
    for ( 1 .. 2 ) {
        my $result = complete($self);
        is( $result->{stdout}, '', 'unhelpful output produces no flags' );
        is( $result->{stderr}, '', 'failed probes stay quiet' );
    }
    is( read_file( $self->{env}{PROBE_COUNT} ), 'x', 'empty results are cached' );
}

sub ignores_files_outside_executable_script_scope {
    my ($self) = @_;
    $self->{env}{PROBE_SENTINEL} = "$self->{temporary}/probed";
    for my $case ( [ 'non-executable', "#!/bin/sh\n", 0644 ], [ 'no-shebang', '', 0755 ] ) {
        my ( $name, $header, $mode ) = @$case;
        my $path = "$self->{temporary}/$name";
        write_file( $path, $header . 'printf touched >"$PROBE_SENTINEL"; printf "%s\\n" --flag' );
        chmod $mode, $path or die $!;
        my $result = complete( $self, $path );
        is( $result->{stdout}, '', "$name produces no flags" );
        is( $result->{stderr}, '', "$name is ignored quietly" );
        ok( !-e $self->{env}{PROBE_SENTINEL}, "$name is never executed" );
    }
}

sub times_out_and_stops_descendants {
    my ($self) = @_;
    $self->{env}{HEARTBEAT} = "$self->{temporary}/heartbeat";
    script( $self->{script}, <<'PERL' );
use Time::HiRes qw(sleep);
my $child = fork(); die $! unless defined $child;
if (!$child) {
    while (1) {
        open my $heartbeat, '>', $ENV{HEARTBEAT} or die $!;
        print {$heartbeat} ++$count; close $heartbeat; sleep .02;
    }
}
sleep 100;
PERL
    my $started = time;
    my $result  = complete($self);
    cmp_ok( time - $started, '<', 2, 'help probing is bounded' );
    is( $result->{stdout}, '', 'timed-out help produces no flags' );
    is( $result->{stderr}, '', 'timeout produces no terminal error' );
    ok( -s $self->{env}{HEARTBEAT}, 'the probe spawned a running child' );
    my $before = read_file( $self->{env}{HEARTBEAT} );
    sleep .15;
    is( read_file( $self->{env}{HEARTBEAT} ), $before, 'the spawned child stopped' );
    $started = time;
    is( complete($self)->{stdout}, '', 'timeout is cached as an empty result' );
    cmp_ok( time - $started, '<', .5, 'a cached timeout does not wait again' );
}

run_cases(
    {
        caches_flags_and_uses_no_stdin                => \&caches_flags_and_uses_no_stdin,
        invalidates_same_size_subsecond_edits         => \&invalidates_same_size_subsecond_edits,
        separates_paths_with_the_same_basename        => \&separates_paths_with_the_same_basename,
        caches_negative_results                       => \&caches_negative_results,
        ignores_files_outside_executable_script_scope => \&ignores_files_outside_executable_script_scope,
        times_out_and_stops_descendants               => \&times_out_and_stops_descendants,
    },
    \&setup
);
