#!/usr/bin/env perl
use strict;
use warnings;
use POSIX qw(WNOHANG);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

@ARGV == 6 or die "Usage: git_prompt_worker.pl FISH PROMPT_FILE DIRECTORY TOKEN PARENT ROOT\n";
my ($fish, $prompt, $directory, $token, $parent, $root) = @ARGV;
my $result = "$directory/vcs-prompt-$token";
my $control = "$directory/vcs-alive";
my $owns_group = 0;
END { stop() if $owns_group }

# Every descendant belongs to this private group, including Git's helpers.
setpgrp(0, 0) or die "setpgrp: $!\n";
$owns_group = 1;
sub stop {
    kill 'KILL', -$$;
    POSIX::_exit(1);
}
$SIG{HUP} = $SIG{INT} = $SIG{TERM} = \&stop;
pipe my $events, my $notify or die "pipe: $!\n";
fcntl($notify, F_SETFL, fcntl($notify, F_GETFL, 0) | O_NONBLOCK) or die "fcntl: $!\n";
$SIG{CHLD} = sub { syswrite $notify, '.', 1 };

sub owned {
    return 0 if getppid() != $parent;
    open my $file, '<', $control or return 0;
    my $owner = <$file> // '';
    chomp $owner;
    return $owner eq $token;
}

sub identity {
    return '' if $root eq '';
    my @stat = lstat "$root/.git";
    return @stat ? "$stat[0]:$stat[1]" : '';
}

owned() or stop();
my $identity = identity();
my $child = fork();
defined $child or die "fork: $!\n";
if (!$child) {
    $owns_group = 0;
    $SIG{HUP} = $SIG{INT} = $SIG{TERM} = $SIG{CHLD} = 'DEFAULT';
    close $events;
    close $notify;
    $ENV{GIT_OPTIONAL_LOCKS} = 0;
    open STDIN, '<', '/dev/null' or die "stdin: $!\n";
    open STDOUT, '>', $result or die "$result: $!\n";
    exec {$fish} $fish, '--no-config', '-c',
        'source "$argv[1]"; and aqsnow_vcs_prompt', $prompt;
    die "exec $fish: $!\n";
}

while (1) {
    owned() or stop();
    my $finished = waitpid($child, WNOHANG);
    last if $finished == $child;
    $finished == -1 and stop();
    # The pipe preserves an exit notification even if SIGCHLD precedes select().
    my $readable = '';
    vec($readable, fileno($events), 1) = 1;
    select $readable, undef, undef, 2;
    sysread $events, my $ignored, 4096 if vec($readable, fileno($events), 1);
}
my $status = $?;
owned() or stop();
my $code = ($status & 127) ? 128 + ($status & 127) : $status >> 8;
$code = 75 if identity() ne $identity;
open my $status_file, '>', "$result.status" or die "$result.status: $!\n";
print {$status_file} "$code\n";
close $status_file or die "$result.status: $!\n";
kill 'USR1', $parent if owned();
# Even a helper that ignores TERM must not survive a finished/cancelled request.
stop();
