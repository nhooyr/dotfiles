#!/usr/bin/env perl
use strict;
use warnings;
use Cwd         qw(abs_path);
use JSON::PP    ();
use Time::HiRes qw(alarm stat);

if ( @ARGV == 1 && ( $ARGV[0] eq '-h' || $ARGV[0] eq '--help' ) ) {
    print "Usage: compgen.pl SCRIPT\nPrint cached flags from an executable script's --help.\n";
    exit;
}
exit 2 unless @ARGV == 1;
my $script = abs_path( $ARGV[0] );
exit unless defined $script && -f $script && -x $script;
open my $source, '<', $script or exit;
read( $source, my $shebang, 2 );
close $source;
exit unless $shebang eq '#!';

my @stat = stat $script;
exit unless @stat;
my $signature = join ':', @stat[ 0, 1, 7 ], map { sprintf '%.9f', $_ } @stat[ 9, 10 ];
my $directory = "$ENV{HOME}/.local/share/fish/compgen";
my $cache     = "$directory/cache.json";
my $key       = $script;
utf8::decode($key);
my $json = JSON::PP->new->utf8->canonical->pretty;

sub cache_entries {
    open my $saved, '<', $cache or return {};
    local $/;
    my $entries = eval { $json->decode( <$saved> // '' ) };
    return ref($entries) eq 'HASH' ? $entries : {};
}

my $entry = cache_entries()->{$key};
if ( $entry && $entry->{signature} eq $signature ) {
    print map { "$_\n" } @{ $entry->{flags} };
    exit;
}

sub help_output {
    require POSIX;
    pipe my $reader, my $writer or return '';
    my $pid = fork();
    return '' unless defined $pid;
    if ( !$pid ) {
        close $reader;
        setpgrp( 0, 0 ) or POSIX::_exit(127);
        open STDIN,  '<',  '/dev/null' or POSIX::_exit(127);
        open STDOUT, '>&', $writer     or POSIX::_exit(127);
        open STDERR, '>&', $writer     or POSIX::_exit(127);
        close $writer;
        exec {$script} $script, '--help' or POSIX::_exit(127);
    }
    close $writer;
    setpgrp( $pid, $pid );
    my $text     = '';
    my $finished = eval {
        local @SIG{qw(ALRM HUP INT TERM)} = ( sub { die } ) x 4;
        alarm 1;
        while ( sysread( $reader, my $chunk, 16384 ) ) {
            $text .= $chunk;
            last if length($text) >= 262144;
        }
        alarm 0;
        1;
    };
    alarm 0;
    kill 'KILL', -$pid;
    kill 'KILL', $pid;
    close $reader;
    waitpid( $pid, 0 );
    return $finished ? $text : '';
}

my %flags;
my $help = help_output();
while ( $help =~ /(?:^|[\s,;|()[\]])(--[A-Za-z0-9][A-Za-z0-9_-]*|-[A-Za-z0-9])(?=$|[\s,;|()[\]=])/g ) {
    $flags{$1} = 1;
}
my @flags = sort keys %flags;
print map { "$_\n" } @flags;
eval {
    require Fcntl;
    require File::Path;
    require File::Temp;
    File::Path::make_path($directory);
    open my $lock, '>>', "$directory/cache.lock" or die;
    flock( $lock, Fcntl::LOCK_EX() ) or die;
    my $entries = cache_entries();
    $entries->{$key} = { signature => $signature, flags => \@flags };
    my ( $file, $temporary ) = File::Temp::tempfile( 'flags-XXXXXX', DIR => $directory, UNLINK => 1 );
    print {$file} $json->encode($entries);
    close $file or die;
    rename $temporary, $cache or die;
};
