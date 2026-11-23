use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use POSIX qw(WNOHANG);
use Time::HiRes qw(time sleep);

my $root = absolute_path("$FindBin::Bin/..");
my $source = read_file("$root/nvim/app/install.sh");

sub setup {
    my ($s) = @_;
    die "Unsafe system mutation in installer\n" if $source =~ /\b(?:lsregister|killall|CFPreferencesSetAppValue)\b/;
    $s->{temporary} = tempdir('nvim-install-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    $s->{home} = "$s->{temporary}/home";
    $s->{bin} = "$s->{temporary}/bin";
    $s->{script} = "$s->{temporary}/source/nvim/app/install.sh";
    $s->{app} = "$s->{home}/Applications/nvim.app";
    $s->{cache} = "$s->{home}/Library/Caches/dotfiles";
    $s->{lock} = "$s->{cache}/nvim-app-install.lock";
    my $log = "$s->{temporary}/calls";
    make_path($s->{bin}, dirname($s->{script}), "$s->{temporary}/source/bin", "$s->{temporary}/handlers");
    write_file($s->{script}, $source);
    write_file(dirname($s->{script}) . "/$_", 'fixture') for qw(nvim.applescript icon.png);
    $s->{env} = {%ENV, HOME => $s->{home}, PATH => "$s->{bin}:/usr/bin:/bin",
        TEST_DIR => $s->{temporary}, TEST_LOG => $log, TEST_MV => which('mv'), TEST_DATE => which('date')};
    write_file("$s->{bin}/mock", '#!' . perl_executable() . "\n" . <<'MOCK');
use strict;
use warnings;
use File::Basename qw(basename);
use File::Path qw(make_path);
use JSON::PP;
use Time::HiRes qw(sleep);
sub write_file { open my $f, '>', $_[0] or die $!; print {$f} $_[1]; close $f or die $!; }
my $name = basename($0);
if ($name eq 'timeout') {
    die "Missing timeout\n" unless shift(@ARGV) eq '--kill-after=2';
    my $limit = shift @ARGV;
    my $command = basename($ARGV[0]);
    die "Wrong timeout\n" unless $limit == ($command eq 'duti' && $ARGV[1] eq '-s' ? 120 : 30);
    open my $log, '>>', $ENV{TEST_LOG} or die $!;
    print {$log} encode_json([$command, @ARGV[1 .. $#ARGV]]), "\n";
    close $log;
    my $key = $command eq 'duti' ? "duti $ARGV[1]" : $command;
    exit 124 if ($ENV{TEST_TIMEOUT} // '') eq $key;
    exit 7 if ($ENV{TEST_FAIL} // '') eq $key;
    if ($command eq 'mv') {
        my $phase = $ARGV[1] =~ m{/previous\.app$} ? 'restore'
            : $ARGV[2] eq "$ENV{HOME}/Applications/nvim.app" ? 'install' : 'backup';
        exit 9 if grep { $_ eq $phase } split /,/, $ENV{TEST_MOVE_FAIL} // '';
        $ARGV[0] = $ENV{TEST_MV};
    }
    exec {$ARGV[0]} @ARGV; die $!;
}
if ($name eq 'uname') { print "Darwin\n"; exit; }
if ($name eq 'date') {
    exec $ENV{TEST_DATE}, @ARGV unless $ENV{TEST_NO_UPDATE};
    my $now = 0;
    if (open my $f, '<', "$ENV{TEST_DIR}/clock") { $now = <$f>; close $f; }
    write_file("$ENV{TEST_DIR}/clock", $now + 120);
    print "$now\n"; exit;
}
if ($name eq 'hpath') { print while <>; exit; }
if ($name eq 'osacompile') {
    if ($ENV{TEST_BLOCK}) {
        write_file("$ENV{TEST_DIR}/started", '');
        sleep 0.01 until -e "$ENV{TEST_DIR}/release";
    }
    make_path("$ARGV[1]/Contents/Resources");
    write_file("$ARGV[1]/Contents/Info.plist", '{}'); exit;
}
if ($name eq 'sips' || $name eq 'iconutil') { write_file($ARGV[-1], 'image'); exit; }
if ($name eq 'codesign') {
    exit(-f "$ARGV[-1]/Contents/signed" ? 0 : 1) if $ARGV[0] eq '--verify';
    write_file("$ARGV[-1]/Contents/signed", ''); exit;
}
if ($name eq 'plutil') {
    open my $f, '<', $ARGV[-1] or die $!;
    my $data = decode_json(do { local $/; <$f> }); close $f;
    if ($ARGV[0] eq '-extract') { print $data->{$ARGV[1]}, "\n"; exit; }
    exit if $ARGV[0] eq '-lint';
    if ($ARGV[0] eq '-remove') { delete $data->{$ARGV[1]}; }
    elsif ($ARGV[0] eq '-replace') { $data->{$ARGV[1]} = $ARGV[2] eq '-json' ? decode_json($ARGV[3]) : $ARGV[3]; }
    else { die "Unexpected plutil arguments\n"; }
    write_file($ARGV[-1], encode_json($data)); exit;
}
if ($name eq 'osascript') {
    die "Wrong resolver\n" unless join(' ', @ARGV[0 .. 2]) eq '-l JavaScript -e';
    my %targets = map { $_ => 1 } @ARGV[4 .. $#ARGV];
    die "Missing resolver targets\n" unless $targets{'public.text'} && $targets{'.txt'} && $targets{'.text'} && $targets{'.ts'} && $targets{'.rst'};
    print "public.text\npublic.plain-text\npublic.source-code\npublic.typescript\n"; exit;
}
if ($name eq 'duti') {
    my $type = $ARGV[0] eq '-s' ? $ARGV[2] : $ARGV[1];
    die "Unresolved extension passed to duti\n" if $type =~ /^\./;
    my $path = "$ENV{TEST_DIR}/handlers/$type";
    if ($ARGV[0] eq '-s') {
        die "Invalid setter\n" unless @ARGV == 4 && $ARGV[1] eq 'ca.aqsnow.nvim' && $ARGV[3] eq 'all';
        $path .= '.pending' if ($ENV{TEST_DELAY} // '') eq $type;
        write_file($path, $ARGV[1]) unless $ENV{TEST_NO_UPDATE}; exit;
    }
    die "Wrong query\n" unless $ARGV[0] eq '-d';
    my $delayed = -f "$path.pending";
    rename "$path.pending", $path or die $! if $delayed;
    my $opened = open my $f, '<', $path;
    my $handler = $opened ? do { local $/; <$f> } : undef;
    $handler = 'other.editor' if $delayed;
    exit 1 if !defined($handler) && ($ENV{TEST_MISSING} // '') eq $type;
    $handler //= (grep { $_ eq $type } split / /, $ENV{TEST_OLD} // '') ? 'other.editor' : 'ca.aqsnow.nvim';
    print "$handler\n"; exit;
}
die "Unexpected command: $name\n";
MOCK
    chmod 0755, "$s->{bin}/mock";
    symlink "$s->{bin}/mock", "$s->{bin}/$_" or die $! for qw(timeout uname date osacompile sips iconutil plutil codesign osascript duti);
    symlink "$s->{bin}/mock", "$s->{temporary}/source/bin/hpath" or die $!;
}

sub install { my ($s, @args) = @_; run_command(['/bin/sh', $s->{script}, @args], {env => $s->{env}, timeout => 15}); }
sub calls {
    my ($s, $command, $flag) = @_;
    return wantarray ? () : 0 unless -f $s->{env}{TEST_LOG};
    return grep { (!defined($command) || $_->[0] eq $command) && (!defined($flag) || $_->[1] eq $flag) }
        map { decode_json($_) } split /\n/, read_file($s->{env}{TEST_LOG});
}
sub clear_calls { write_file($_[0]{env}{TEST_LOG}, ''); }
sub existing {
    my ($s, $stale) = @_;
    my $result = install($s);
    die $result->{stderr} if $result->{returncode};
    write_file("$s->{app}/preserved", 'original app');
    write_file($s->{script}, "$source\n# force rebuild\n") if $stale;
    clear_calls($s);
}
sub preserved { is(read_file("$_[0]{app}/preserved"), 'original app', 'existing app preserved'); }
sub cleaned {
    my ($s) = @_;
    ok(!-e $s->{lock}, 'lock released');
    is_deeply([glob "$s->{cache}/nvim-build.*"], [], 'staging cleaned');
}

sub preflight {
    my ($s) = @_;
    is(install($s, '--unsupported')->{returncode}, 2, 'unknown option rejected');
    is(scalar calls($s), 0, 'invalid option does no work');
    unlink "$s->{bin}/duti";
    local $s->{env}{PATH} = $s->{bin};
    like(install($s, '--set-defaults')->{stderr}, qr/brew install duti/, 'missing duti explained');
    unlink "$s->{bin}/timeout";
    like(install($s)->{stderr}, qr/brew install coreutils/, 'missing timeout explained');
    ok(!-e $s->{home}, 'dependency failures create no installation directories');
}
sub plain_install_and_fast_path {
    my ($s) = @_;
    my $result = install($s);
    is($result->{returncode}, 0, $result->{stderr});
    my ($build) = calls($s, 'osacompile');
    like($build->[2], qr{\Q$s->{cache}\E/nvim-build\.}, 'build is staged outside Applications');
    is(scalar calls($s, 'duti'), 0, 'plain install does not change defaults');
    write_file("$s->{app}/preserved", 'original app');
    my $plist = decode_json(read_file("$s->{app}/Contents/Info.plist"));
    is($plist->{CFBundleIdentifier}, 'ca.aqsnow.nvim', 'correct application identity');
    is_deeply($plist->{CFBundleDocumentTypes}[0]{LSItemContentTypes}, [qw(public.plain-text public.source-code)], 'text/source declarations only');
    clear_calls($s);
    $result = install($s);
    is($result->{returncode}, 0, $result->{stderr});
    like($result->{stdout}, qr/Already installed/, 'unchanged app uses fast path');
    is(scalar calls($s, 'osacompile'), 0, 'unchanged app not rebuilt');
    is(scalar calls($s, 'duti'), 0, 'plain install does not change defaults');
    preserved($s); cleaned($s);
}
sub defaults_skip_and_verify {
    my ($s) = @_;
    existing($s);
    $s->{env}{TEST_OLD} = 'public.text public.typescript';
    $s->{env}{TEST_MISSING} = 'public.text';
    $s->{env}{TEST_DELAY} = 'public.typescript';
    my $result = install($s, '--set-defaults');
    is($result->{returncode}, 0, $result->{stderr});
    is(scalar calls($s, 'osascript'), 1, 'all extensions resolved in one call');
    is_deeply([calls($s, 'duti', '-s')], [map { ['duti', '-s', 'ca.aqsnow.nvim', $_, 'all'] } qw(public.text public.typescript)], 'only missing/different resolved handlers are set');
    is(scalar(grep { $_->[2] eq 'public.typescript' } calls($s, 'duti', '-d')), 3, 'waits for delayed extension update without setting twice');
    is(scalar(grep { $_->[2] eq 'public.text' } calls($s, 'duti', '-d')), 2, 'UTI rechecked after setting');
    clear_calls($s);
    is(install($s, '--set-defaults')->{returncode}, 0, 'defaults repeat succeeds');
    is(scalar calls($s, 'duti', '-s'), 0, 'matching handlers skipped');
    is(scalar calls($s, 'osacompile'), 0, 'defaults update uses unchanged app');
    preserved($s); cleaned($s);
}
sub defaults_failures_stop_without_retry {
    my ($s) = @_;
    existing($s);
    $s->{env}{TEST_OLD} = 'public.text';
    for my $case ([TEST_FAIL => 'osascript', 7, 0], [TEST_TIMEOUT => 'osascript', 124, 0],
                  [TEST_FAIL => 'duti -s', 7, 1], [TEST_TIMEOUT => 'duti -s', 124, 1],
                  [TEST_NO_UPDATE => 1, 1, 1], [TEST_TIMEOUT => 'duti -d', 124, 0]) {
        local $s->{env}{$case->[0]} = $case->[1];
        clear_calls($s);
        my $result = install($s, '--set-defaults');
        is($result->{returncode}, $case->[2], "$case->[0]=$case->[1] propagates failure");
        is(scalar calls($s, 'duti', '-s'), $case->[3], 'no automatic setter retry');
        preserved($s); cleaned($s);
    }
}
sub build_and_verification_failures {
    my ($s) = @_;
    existing($s, 1);
    for my $case ([TEST_FAIL => 'sips', 7], [TEST_TIMEOUT => 'osacompile', 124], [TEST_TIMEOUT => 'codesign', 124]) {
        write_file($s->{script}, $source) if $case->[1] eq 'codesign';
        local $s->{env}{$case->[0]} = $case->[1];
        clear_calls($s);
        is(install($s)->{returncode}, $case->[2], "$case->[1] failure propagates");
        is(scalar calls($s, 'mv'), 0, 'failed build/verification never replaces app');
        preserved($s); cleaned($s);
    }
}
sub unrelated_app_is_preserved {
    my ($s) = @_;
    existing($s);
    write_file("$s->{app}/Contents/Info.plist", encode_json({CFBundleIdentifier => 'other.app'}));
    like(install($s)->{stderr}, qr/refusing to replace an unrelated app/, 'unrelated bundle rejected');
    is(scalar calls($s, 'osacompile'), 0, 'no rebuild');
    is(scalar calls($s, 'mv'), 0, 'no replacement');
    preserved($s); cleaned($s);
}
sub failed_replacement_restores_app {
    my ($s) = @_;
    existing($s, 1);
    $s->{env}{TEST_MOVE_FAIL} = 'install';
    isnt(install($s)->{returncode}, 0, 'replacement failure reported');
    is(scalar calls($s, 'mv'), 3, 'backup, failed replacement, and rollback attempted');
    preserved($s); cleaned($s);
}
sub failed_rollback_preserves_backup {
    my ($s) = @_;
    existing($s, 1);
    $s->{env}{TEST_MOVE_FAIL} = 'install,restore';
    like(install($s)->{stderr}, qr/previous app preserved at/, 'recovery location reported');
    my @backups = glob "$s->{cache}/nvim-build.*/previous.app/preserved";
    is(scalar @backups, 1, 'backup retained after rollback failure');
    is(read_file($backups[0]), 'original app', 'backup contents preserved');
    ok(!-e $s->{lock}, 'lock released even when backup retained');
}

sub blocked_install {
    my ($s) = @_;
    my $pid = fork(); die $! unless defined $pid;
    if (!$pid) {
        POSIX::setpgid(0, 0) or die $!;
        %ENV = (%{$s->{env}}, TEST_BLOCK => 1);
        open STDOUT, '>', '/dev/null' or die $!; open STDERR, '>&', STDOUT or die $!;
        exec '/bin/sh', $s->{script}; die $!;
    }
    my $deadline = time + 5;
    until (-e "$s->{temporary}/started") {
        if (time > $deadline) { kill 'KILL', -$pid; waitpid($pid, 0); die "build did not start\n"; }
        sleep 0.01;
    }
    return $pid;
}
sub wait_install {
    my ($pid) = @_;
    my $deadline = time + 10;
    while (waitpid($pid, WNOHANG) == 0) {
        if (time > $deadline) { kill 'KILL', -$pid; waitpid($pid, 0); die "installer did not finish\n"; }
        sleep 0.01;
    }
    return $?;
}
sub competing_run_is_rejected {
    my ($s) = @_;
    existing($s, 1);
    my $pid = blocked_install($s);
    my $result = install($s);
    ok(-d $s->{lock}, 'failed contender leaves the owner lock intact');
    write_file("$s->{temporary}/release", '');
    is(wait_install($pid), 0, 'first installer completes');
    like($result->{stderr}, qr/another installation is running/, 'competing installer rejected');
    cleaned($s);
}
sub interruption_cleans_up {
    my ($s) = @_;
    existing($s, 1);
    my $pid = blocked_install($s);
    kill 'TERM', -$pid;
    isnt(wait_install($pid), 0, 'interrupted installer fails');
    preserved($s); cleaned($s);
}

run_cases({map { $_ => __PACKAGE__->can($_) } qw(preflight plain_install_and_fast_path defaults_skip_and_verify
    defaults_failures_stop_without_retry build_and_verification_failures unrelated_app_is_preserved
    failed_replacement_restores_app failed_rollback_preserves_backup competing_run_is_rejected interruption_cleans_up)}, \&setup);
