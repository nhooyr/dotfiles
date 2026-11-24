use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $sshf = absolute_path("$FindBin::Bin/../bin/sshf");
my $node = which('node');

sub setup {
    my ($self) = @_;
    plan skip_all => 'Node is needed to mock the native JavaScript bridge'
      unless $node;
    $self->{temporary} = tempdir( 'sshf-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{state}     = "$self->{temporary}/state.json";
    $self->{snapshot}  = "$self->{temporary}/saved.plist";
    make_path("$self->{temporary}/bin");
    $self->{env} = {
        %ENV,
        PATH             => "$self->{temporary}/bin:$ENV{PATH}",
        SSHF_TEST_STATE  => $self->{state},
        SSHF_TEST_NODE   => $node,
        SSHF_TEST_DRIVER => "$self->{temporary}/bridge.js"
    };
    write_file( "$self->{temporary}/bin/osascript", <<'SH' );
#!/bin/sh
exec "$SSHF_TEST_NODE" "$SSHF_TEST_DRIVER" "$@"
SH
    write_file( "$self->{temporary}/bin/networksetup", <<'SH' );
#!/bin/sh
printf 'Unexpected networksetup call\n' >&2
exit 1
SH
    chmod 0755, "$self->{temporary}/bin/osascript", "$self->{temporary}/bin/networksetup";

    # Run the production JXA with mocked Foundation/SystemConfiguration APIs.
    # No macOS preferences, SSH connection, sudo, or Keychain access is involved.
    write_file( "$self->{temporary}/bridge.js", <<'JS' );
const fs = require('fs');
const vm = require('vm');
const filename = process.env.SSHF_TEST_STATE;
const state = JSON.parse(fs.readFileSync(filename, 'utf8'));
const args = process.argv.slice(2);
if (args.slice(0, 3).join(' ') !== '-l JavaScript -') throw Error('Unexpected osascript arguments');
const argv = args.slice(3), action = argv[0];
state.calls ||= [];
function record(operation) {
    state.calls.push(action + ':' + operation);
    fs.writeFileSync(filename, JSON.stringify(state));
}
function succeeds(operation) {
    record(operation);
    const key = action + ':' + operation;
    if (state.failures && state.failures[key]) {
        state.failures[key]--;
        fs.writeFileSync(filename, JSON.stringify(state));
        return false;
    }
    return true;
}
const clone = value => JSON.parse(JSON.stringify(value));
class Scalar {
    constructor(value) { this.value = value; }
    get boolValue() { return Boolean(this.value); }
}
const raw = value => value instanceof Dictionary || value instanceof Scalar ? value.value : value;
const wrap = value => value && typeof value === 'object' && !Array.isArray(value)
    ? new Dictionary(value) : new Scalar(value);
class Dictionary {
    constructor(value = {}) { this.value = clone(value); }
    isNil() { return false; }
    get allKeys() { return Object.keys(this.value); }
    get count() { return Object.keys(this.value).length; }
    get mutableCopy() { return new Dictionary(this.value); }
    setObjectForKey(value, key) { this.value[raw(key)] = clone(raw(value)); }
    objectForKey(key) { return wrap(this.value[raw(key)]); }
    removeObjectForKey(key) { delete this.value[raw(key)]; }
    writeToFileAtomically(path) {
        if (!succeeds('snapshot')) return false;
        fs.writeFileSync(raw(path), JSON.stringify(this.value), {mode: 0o600});
        return true;
    }
}
function $(value) { return wrap(value); }
$.NSMutableDictionary = {get dictionary() { return new Dictionary(); }};
$.NSDictionary = {
    get dictionary() { return new Dictionary(); },
    dictionaryWithContentsOfFile(path) { return new Dictionary(JSON.parse(fs.readFileSync(raw(path), 'utf8'))); }
};
$.SCError = () => -1;
$.SCPreferencesCreate = () => ({current: clone(state.current)});
$.SCPreferencesLock = () => succeeds('lock');
$.SCPreferencesUnlock = () => record('unlock');
$.SCPreferencesPathGetValue = prefs => prefs.current === null ? null : new Dictionary(prefs.current);
$.SCPreferencesPathSetValue = (prefs, path, value) => {
    if (!succeeds('set')) return false;
    prefs.current = clone(raw(value));
    return true;
};
$.SCPreferencesPathRemoveValue = prefs => {
    if (!succeeds('remove')) return false;
    prefs.current = null;
    return true;
};
$.SCPreferencesCommitChanges = prefs => {
    if (!succeeds('commit')) return false;
    state.current = clone(prefs.current);
    fs.writeFileSync(filename, JSON.stringify(state));
    return true;
};
$.SCPreferencesApplyChanges = () => {
    if (!succeeds('apply')) return false;
    if (action === 'install') {
        state.installed = clone(state.current);
        if (state.during_tunnel) Object.assign(state.current, state.during_tunnel);
        fs.writeFileSync(filename, JSON.stringify(state));
    }
    return true;
};
const context = {ObjC: {import() {}, deepUnwrap: raw,
    castRefToObject: value => value === null ? {isNil: () => true} : value}, $};
try {
    vm.createContext(context);
    vm.runInContext(fs.readFileSync(0, 'utf8'), context);
    context.run(argv);
} catch (error) {
    console.error(error.message);
    process.exitCode = 1;
}
JS
}

sub run_proxy {
    my ( $self, $original, $options ) = @_;
    write_file( $self->{state}, encode_json( { current => $original, %{ $options // {} } } ) );
    my $result = run_command(
        [ $sshf, '--proxy', 'Wi-Fi', 'test-service', $self->{snapshot} ],
        {
            env     => $self->{env},
            input   => "sshu -ND localhost:1080 example\n",
            timeout => 15
        }
    );
    return ( $result, decode_json( read_file( $self->{state} ) ) );
}

sub enabled_authenticated_proxy {
    my ($self) = @_;
    my $original = {
        SOCKSEnable   => 1,
        SOCKSProxy    => 'proxy.example',
        SOCKSPort     => 9050,
        SOCKSUser     => 'private-user',
        SOCKSPassword => 'private-password',
        HTTPEnable    => 1
    };
    my ( $result, $state ) = run_proxy( $self, $original );
    is( $result->{returncode}, 0, $result->{stderr} );
    is(
        $result->{stdout},
        "sshu -ND localhost:1080 example\n",
        'control output contains only the ready command'
    );
    is( $result->{stderr}, '', 'saving and restoring proxy settings is silent' );
    unlike(
        $result->{stderr} . $result->{stdout},
        qr/private-user|private-password/,
        'credentials are never printed'
    );
    is_deeply(
        $state->{installed},
        {
            SOCKSEnable => 1,
            SOCKSProxy  => 'localhost',
            SOCKSPort   => 1080,
            HTTPEnable  => 1
        },
        'temporary proxy is unauthenticated'
    );
    is_deeply( $state->{current}, $original, 'server, port, enabled state, and authentication are restored' );
    is( ( stat $self->{snapshot} )[2] & 0777, 0600, 'snapshot is private' );
}

sub disabled_proxy {
    my ($self) = @_;
    my $original = { SOCKSEnable => 0, SOCKSProxy => 'disabled.example', SOCKSPort => 9000 };
    my ( $result, $state ) = run_proxy( $self, $original );
    is( $result->{returncode}, 0, $result->{stderr} );
    is_deeply( $state->{current}, $original, 'disabled proxy retains its original host and port' );
    is( $result->{stderr}, '', 'disabled proxy settings are saved silently' );
}

sub absent_settings {
    my ($self) = @_;
    my ( $result, $state ) = run_proxy( $self, undef );
    is( $result->{returncode}, 0,     $result->{stderr} );
    is( $state->{current},     undef, 'an originally absent proxy dictionary is removed' );
}

sub unrelated_changes_survive {
    my ($self) = @_;
    my ( $result, $state ) = run_proxy(
        $self,
        { SOCKSEnable   => 0, HTTPProxy => 'old-http' },
        { during_tunnel => { HTTPProxy => 'new-http', HTTPPort => 8080 } }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
    is_deeply(
        $state->{current},
        { SOCKSEnable => 0, HTTPProxy => 'new-http', HTTPPort => 8080 },
        'only SOCKS keys are restored'
    );
}

sub setup_failures_restore {
    my ($self) = @_;
    my $original = { SOCKSEnable => 1, SOCKSProxy => 'original', SOCKSPort => 1234 };
    for my $operation (qw(lock set commit apply)) {
        unlink $self->{snapshot};
        my ( $result, $state ) = run_proxy( $self, $original, { failures => { "install:$operation" => 1 } } );
        isnt( $result->{returncode}, 0, "$operation failure is reported" );
        is( $result->{stdout}, '', "$operation failure never reports the tunnel as ready" );
        is_deeply( $state->{current}, $original, "$operation failure restores the original settings" );
        ok( grep( $_ eq 'restore:apply', @{ $state->{calls} } ), "$operation failure completes restoration" );
    }
}

sub snapshot_failure_does_not_modify {
    my ($self) = @_;
    my $original = { SOCKSEnable => 1, SOCKSProxy => 'original' };
    my ( $result, $state ) =
      run_proxy( $self, $original, { failures => { 'save:snapshot' => 1 } } );
    isnt( $result->{returncode}, 0, 'snapshot failure is reported' );
    is( $result->{stdout}, '', 'no ready command' );
    unlike( $result->{stderr}, qr/saved these/, 'does not claim an unsuccessful snapshot was saved' );
    is_deeply( $state->{current}, $original, 'snapshot failure changes nothing' );
    ok( !grep( /^(?:install|restore):/, @{ $state->{calls} } ), 'never installs without a snapshot' );
}

sub restore_failure_is_reported {
    my ($self)   = @_;
    my ($result) = run_proxy( $self, { SOCKSEnable => 0 }, { failures => { 'restore:commit' => 1 } } );
    isnt( $result->{returncode}, 0, 'restoration failure fails the proxy worker' );
    like(
        $result->{stderr},
        qr/could not restore the saved SOCKS proxy settings/,
        'restoration failure is explicit'
    );
    like(
        $result->{stderr},
        qr/private settings snapshot retained at \Q$self->{snapshot}\E/,
        'reports the private recovery snapshot'
    );
    ok( -f "$self->{snapshot}.failed", 'marks the snapshot for preservation by the outer cleanup' );
}

sub read_failure_does_not_modify {
    my ($self) = @_;
    my $original = { SOCKSEnable => 0 };
    my ( $result, $state ) =
      run_proxy( $self, $original, { failures => { 'save:lock' => 1 } } );
    isnt( $result->{returncode}, 0, 'settings inspection failure fails setup' );
    is_deeply( $state->{current}, $original,     'inspection failure changes nothing' );
    is_deeply( $state->{calls},   ['save:lock'], 'no preference write is attempted' );
}

sub native_property_list_round_trip {
    my ($self) = @_;
    plan skip_all => 'Native property-list bridging requires macOS'
      unless $^O eq 'darwin';
    my ($source) = read_file($sshf) =~ /<<'JXA'\n(.*?)\nJXA/s;
    die "Missing JXA helper\n" unless defined $source;
    my $preferences = "$self->{temporary}/preferences.plist";
    my $native      = "$self->{temporary}/native.js";
    my $env         = { %{ $self->{env} }, SSHF_TEST_PREFS => $preferences };

    # Use a real, isolated SCPreferences file and native dictionaries. Locking
    # and committing even a temporary preferences file require admin access;
    # replace only those boundaries with a direct write to this test file.
    $source = replace_literal(
        $source,
        "SCPreferencesCreate(null, \$('sshf'), null)",
"SCPreferencesCreate(null, \$('sshf'), \$.NSProcessInfo.processInfo.environment.objectForKey(\$('SSHF_TEST_PREFS')))"
    );
    $source = replace_literal( $source, '$.SCPreferencesLock(preferences, true)', 'true' );
    $source = replace_literal( $source, '$.SCPreferencesCommitChanges(preferences)',
'ObjC.castRefToObject($.SCPreferencesPathGetValue(preferences, $("/"))).writeToFileAtomically($.NSProcessInfo.processInfo.environment.objectForKey($("SSHF_TEST_PREFS")), true)'
    );
    $source = replace_literal( $source, '$.SCPreferencesApplyChanges(preferences)', 'true' );
    $source = replace_literal( $source, '$.SCPreferencesUnlock(preferences)',       'void 0' );
    write_file( $native,      $source );
    write_file( $preferences, <<'PLIST' );
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>NetworkServices</key><dict><key>test-service</key><dict><key>Proxies</key><dict>
<key>SOCKSEnable</key><integer>1</integer><key>SOCKSProxy</key><string>example.invalid</string>
<key>SOCKSPort</key><integer>9050</integer><key>SOCKSUser</key><string>dummy-user</string>
<key>SOCKSNativeData</key><data>AQID</data><key>SOCKSNativeBoolean</key><true/>
<key>HTTPEnable</key><integer>1</integer>
</dict></dict></dict></dict></plist>
PLIST

    for my $action (qw(save install restore)) {
        my $result = run_command(
            [ '/usr/bin/osascript', '-l', 'JavaScript', $native, $action, 'test-service', $self->{snapshot} ],
            { env => $env }
        );
        is( $result->{returncode}, 0,  "native $action succeeds: $result->{stderr}" );
        is( $result->{stdout},     '', "native $action prints no settings or credentials" );
    }
    write_file( "$self->{temporary}/compare.js", <<'JXA' );
ObjC.import('Foundation');
function run(argv) {
    var current = $.NSDictionary.dictionaryWithContentsOfFile($(argv[0]))
        .objectForKey($('NetworkServices')).objectForKey($('test-service')).objectForKey($('Proxies'));
    var original = $.NSDictionary.dictionaryWithContentsOfFile($(argv[1])).objectForKey($('proxies'));
    return current.isEqualToDictionary(original) ? 'equal' : 'different';
}
JXA
    my $comparison = run_command(
        [
            '/usr/bin/osascript', '-l',
            'JavaScript',         "$self->{temporary}/compare.js",
            $preferences,         $self->{snapshot}
        ],
        { env => $env }
    );
    is( $comparison->{returncode}, 0, $comparison->{stderr} );
    is( $comparison->{stdout}, "equal\n",
        'native types, absent keys, and authentication values survive the round trip' );
    write_file( $preferences, <<'PLIST' );
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>NetworkServices</key><dict><key>test-service</key><dict><key>UserDefinedName</key><string>Mock Wi-Fi</string></dict></dict></dict></plist>
PLIST
    for my $action (qw(save install restore)) {
        my $result = run_command(
            [ '/usr/bin/osascript', '-l', 'JavaScript', $native, $action, 'test-service', $self->{snapshot} ],
            { env => $env }
        );
        is( $result->{returncode}, 0, "native $action with absent settings succeeds: $result->{stderr}" );
    }
    my $absent =
      run_command( [ '/usr/bin/plutil', '-convert', 'json', '-o', '-', $preferences ], { env => $env } );
    is_deeply(
        decode_json( $absent->{stdout} ),
        {
            NetworkServices => { 'test-service' => { UserDefinedName => 'Mock Wi-Fi' } }
        },
        'native absent dictionary is restored'
    );
}

run_cases(
    {
        enabled_authenticated_proxy      => \&enabled_authenticated_proxy,
        disabled_proxy                   => \&disabled_proxy,
        absent_settings                  => \&absent_settings,
        unrelated_changes_survive        => \&unrelated_changes_survive,
        setup_failures_restore           => \&setup_failures_restore,
        snapshot_failure_does_not_modify => \&snapshot_failure_does_not_modify,
        restore_failure_is_reported      => \&restore_failure_is_reported,
        read_failure_does_not_modify     => \&read_failure_does_not_modify,
        native_property_list_round_trip  => \&native_property_list_round_trip,
    },
    \&setup
);
