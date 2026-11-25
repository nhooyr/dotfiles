use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my $nvim = which('nvim');

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'nvim-setup-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $directory = absolute_path( $self->{temporary} ) . '/source tree/nvim';
    my $bin       = "$self->{temporary}/bin";
    make_path( "$directory/app", "$directory/lua", "$directory/../bin",
        "$self->{temporary}/source tree/ci", $bin );
    copy_preserve( "$root/bin/$_",                  "$directory/../bin/$_" ) for qw(dotln hpath);
    copy_preserve( "$root/nvim/$_",                 "$directory/$_" )        for qw(init.vim vimrc);
    copy_preserve( "$root/nvim/install.sh",         "$directory/install.sh" );
    copy_preserve( "$root/nvim/lua/plugins.lua",    "$directory/lua/plugins.lua" );
    copy_preserve( "$root/nvim/lua/treesitter.lua", "$directory/lua/treesitter.lua" );
    copy_preserve( "$root/ci/test.sh",              "$self->{temporary}/source tree/ci/test.sh" );
    $self->{directory} = $directory;
    $self->{bin}       = $bin;
    $self->{env}       = {
        %ENV,
        PATH            => "$bin:/usr/bin:/bin",
        HOME            => "$self->{temporary}/home",
        GITHUB_ACTIONS  => '',
        TEST_CALLS      => "$self->{temporary}/calls",
        TEST_DIRECTORY  => $directory,
        XDG_CONFIG_HOME => "$self->{temporary}/config",
        XDG_DATA_HOME   => "$self->{temporary}/data",
        XDG_STATE_HOME  => "$self->{temporary}/state",
        XDG_CACHE_HOME  => "$self->{temporary}/cache",
    };
    write_file( "$bin/nvim", '#!' . perl_executable() . "\n" . <<'PERL' );
use JSON::PP;
$| = 1;
open my $log, '>>', $ENV{TEST_CALLS} or die $!;
print {$log} encode_json(['nvim', @ARGV]), "\n";
system('fzf', '--version') == 0 or die "fzf is unavailable\n" if $ENV{GITHUB_ACTIONS};
system('shfmt', '--version') == 0 or die "shfmt is unavailable\n" if $ENV{GITHUB_ACTIONS};
print "plugin progress\n";
if ($ENV{TEST_PLUGIN_FAIL}) {
    print STDERR "plugin failed\n";
    exit 7;
}
PERL
    write_file( "$directory/app/install.sh", '#!' . perl_executable() . "\n" . <<'PERL' );
use JSON::PP;
use Cwd qw(getcwd);
open my $log, '>>', $ENV{TEST_CALLS} or die $!;
print {$log} encode_json(['app', getcwd(), @ARGV]), "\n";
if ($ENV{TEST_APP_FAIL}) {
    print STDERR "app failed\n";
    exit 9;
}
print "app installed\n";
PERL
    chmod 0755, "$bin/nvim", "$directory/app/install.sh";
}

sub run_install {
    my ($self) = @_;
    return run_command(
        ["$self->{directory}/install.sh"],
        {
            cwd => $self->{temporary},
            env => $self->{env},
        }
    );
}

sub calls {
    my ($self) = @_;
    return [ map { decode_json($_) } split /\n/, read_file( $self->{env}{TEST_CALLS} ) ];
}

sub link_output {
    return
        "nvim: dotln: Linking ~/.config/nvim/init.vim\n"
      . "nvim: dotln: Linking ~/.config/nvim/lua\n"
      . "nvim: dotln: Linking ~/.vimrc\n";
}

sub installs_plugins_and_app_quietly {
    my ($self) = @_;
    my $result = run_install($self);
    is( $result->{returncode}, 0, 'installation succeeds' );
    is(
        $result->{stdout},
        link_output() . "dotfiles: nvim: install.sh: Updated plugins and parsers.\napp installed\n",
        'plugin progress is hidden while concise statuses remain'
    );
    is( $result->{stderr}, '', 'successful installation has no errors' );
    is_deeply(
        calls($self),
        [
            [ 'nvim', '--headless', '-u', 'NONE', '-n', '-i', 'NONE', '-l', './lua/plugins.lua', 'install' ],
            [ 'app',  $self->{directory}, '--set-defaults' ],
        ],
        'the installer handles plugins and app defaults from its own directory'
    );
    is( readlink("$self->{env}{HOME}/.config/nvim/init.vim"),
        "$self->{directory}/init.vim", 'links init.vim' );
    is( readlink("$self->{env}{HOME}/.config/nvim/lua"), "$self->{directory}/lua",
        'links Lua configuration' );
    is( readlink("$self->{env}{HOME}/.vimrc"), "$self->{directory}/vimrc", 'links vimrc' );
}

sub plugin_failure_stops_before_app_installation {
    my ($self) = @_;
    $self->{env}{TEST_PLUGIN_FAIL} = 1;
    my $result = run_install($self);
    isnt( $result->{returncode}, 0, 'plugin failure returns an error' );
    is( $result->{stdout}, link_output(),                      'failure does not print a success status' );
    is( $result->{stderr}, "plugin progress\nplugin failed\n", 'failure reveals captured diagnostics' );
    is( scalar @{ calls($self) }, 1,                           'the app installer is not called' );
}

sub app_failure_is_returned {
    my ($self) = @_;
    $self->{env}{TEST_APP_FAIL} = 1;
    my $result = run_install($self);
    is( $result->{returncode}, 9,              'app failure status is preserved' );
    is( $result->{stderr},     "app failed\n", 'app diagnostic remains visible' );
}

sub missing_nvim_fails_ci {
    my ($self) = @_;
    unlink "$self->{bin}/nvim" or die $!;
    symlink which('dirname'), "$self->{bin}/dirname" or die $!;
    $self->{env}{PATH} = $self->{bin};
    my $result = run_command(
        ["$self->{temporary}/source tree/ci/test.sh"],
        {
            cwd => $self->{temporary},
            env => $self->{env},
        }
    );
    is( $result->{returncode}, 127, 'CI fails when Neovim is missing' );
    like( $result->{stderr}, qr/nvim/, 'the missing dependency is identified' );
}

sub ci_installs_neovim_before_plugin_setup {
    my ($self) = @_;
    my $runner = "$self->{temporary}/runner";
    my $bundle = "$self->{temporary}/bundle";
    make_path( $runner, "$bundle/nvim-linux-x86_64/bin" );
    rename "$self->{bin}/nvim", "$bundle/nvim-linux-x86_64/bin/nvim" or die $!;
    run_command( [ 'tar', '-czf', "$runner/download.tar.gz", '-C', $bundle, 'nvim-linux-x86_64' ],
        { check => 1 } );
    write_file( "$bundle/fzf", "#!/bin/sh\nexit 0\n" );
    chmod 0755, "$bundle/fzf";
    run_command( [ 'tar', '-czf', "$runner/fzf-download.tar.gz", '-C', $bundle, 'fzf' ], { check => 1 } );
    write_file( "$self->{bin}/sudo", '#!' . perl_executable() . "\n" . <<'PERL' );
use FindBin;
if ($ARGV[0] eq 'apt-get' && grep { $_ eq 'shfmt' } @ARGV) {
    open my $tool, '>', "$FindBin::Bin/shfmt" or die $!;
    print {$tool} "#!/bin/sh\nexit 0\n";
    close $tool or die $!;
    chmod 0755, "$FindBin::Bin/shfmt" or die $!;
}
PERL
    write_file( "$self->{bin}/curl", '#!' . perl_executable() . "\n" . <<'PERL' );
use File::Copy qw(copy);
my %archives = (
    'https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-x86_64.tar.gz' => 'download.tar.gz',
    'https://github.com/junegunn/fzf/releases/download/v0.75.0/fzf-0.75.0-linux_amd64.tar.gz' => 'fzf-download.tar.gz',
);
die "unexpected download arguments\n" unless @ARGV == 5
    && $ARGV[0] eq '--fail' && $ARGV[1] eq '--location' && $ARGV[2] eq '--output'
    && exists $archives{$ARGV[4]};
copy "$ENV{RUNNER_TEMP}/$archives{$ARGV[4]}", $ARGV[3] or die $!;
PERL
    chmod 0755, "$self->{bin}/sudo", "$self->{bin}/curl";
    $self->{env}{GITHUB_ACTIONS}   = 1;
    $self->{env}{RUNNER_TEMP}      = $runner;
    $self->{env}{TEST_PLUGIN_FAIL} = 1;
    my $result = run_command( ["$self->{temporary}/source tree/ci/test.sh"], { env => $self->{env} } );
    is( $result->{returncode}, 7,                 'CI reaches Neovim and preserves plugin setup failures' );
    is( $result->{stderr},     "plugin failed\n", 'the provisioned Neovim ran' );
    ok( -x "$runner/fzf",        'the fzf archive was installed before plugin setup' );
    ok( -x "$self->{bin}/shfmt", 'shfmt was installed before running regression tests' );
    is_deeply(
        calls($self),
        [ [ 'nvim', '--headless', '-u', 'NONE', '-n', '-i', 'NONE', '-l', './nvim/lua/plugins.lua' ] ],
        'CI installs Neovim before plugin setup'
    );
}

sub native_lua_errors_fail_installation {
    my ($self) = @_;
    die 'Neovim is required' unless $nvim;
    unlink "$self->{bin}/nvim" or die $!;
    symlink $nvim, "$self->{bin}/nvim" or die $!;
    write_file( "$self->{directory}/lua/plugins.lua", "error('expected plugin setup failure')\n" );
    my $result = run_install($self);
    isnt( $result->{returncode}, 0, 'a real Lua initialization failure returns an error' );
    like( $result->{stderr}, qr/expected plugin setup failure/, 'the Lua diagnostic is visible' );
    ok( !-e $self->{env}{TEST_CALLS}, 'the app installer is not called after a Lua failure' );
}

sub package_file_sets_its_own_lock_path {
    my ($self) = @_;
    die 'Neovim is required' unless $nvim;
    my $check = <<'LUA';
local calls = {}
vim.loader.enable()
vim.opt.runtimepath:prepend(vim.env.TEST_DIRECTORY)
vim.fn.writefile({ 'return true' }, vim.env.TEST_DIRECTORY .. '/lua/before_update.lua')
assert(require('before_update'))
vim.pack.add = function(specs, opts)
    assert(vim.o.packlockfile == vim.env.TEST_DIRECTORY .. '/pack-lock.json')
    assert(opts.confirm == false)
    assert(#specs == 2)
    assert(specs[1].src == 'https://github.com/nhooyr/copilot.vim.git')
    assert(specs[1].version == 'refresh-partial-accept-preview')
    assert(specs[2].src == 'https://github.com/nvim-treesitter/nvim-treesitter')
    assert(specs[2].version == 'main')
    calls[#calls + 1] = 'plugins installed'
end
vim.pack.update = function(names, opts)
    assert(names == nil and opts.force == true)
    calls[#calls + 1] = 'plugins updated'
    vim.fn.writefile({ 'return true' }, vim.env.TEST_DIRECTORY .. '/lua/after_update.lua')
end
package.preload['nvim-treesitter'] = function()
    assert(require('after_update'), 'plugin updates refresh the module index before loading parser helpers')
    local function task(kind)
        return function(languages)
            assert(vim.deep_equal(languages, { 'go' }))
            calls[#calls + 1] = kind
            return { wait = function(_, timeout)
                assert(timeout == 300000)
                vim.fn.writefile(calls, vim.env.TEST_CALLS)
                return true
            end }
        end
    end
    return { install = task('parsers installed'), update = task('parsers updated') }
end
LUA
    my $mock = "$self->{temporary}/mock-pack.lua";
    write_file( $mock, $check );
    my $result = run_command(
        [
            $nvim,   '--headless', '-u', 'NONE', '-n', '-i', 'NONE',
            '--cmd', 'lua dofile(' . encode_json($mock) . ')',
            '-l',    "$self->{directory}/lua/plugins.lua", 'install'
        ],
        {
            cwd => $self->{temporary},
            env => $self->{env},
        }
    );
    is( $result->{returncode}, 0, "the package file is independent of caller cwd: $result->{stderr}" );
    is(
        read_file( $self->{env}{TEST_CALLS} ),
        "plugins installed\nplugins updated\nparsers installed\nparsers updated\n",
        'the explicit command installs and updates plugins before parsers'
    );
}

sub bundled_undotree_is_registered_lazily {
    my ($self) = @_;
    die 'Neovim is required' unless $nvim;
    my $script = "$self->{temporary}/undotree.lua";
    write_file( $script, <<'LUA' );
vim.pack.add = function() error('startup must not install plugins') end
vim.pack.update = function() error('startup must not update plugins') end
local packadd, loads = vim.cmd.packadd, 0
vim.cmd.packadd = function(name)
    if name == 'nvim.undotree' then loads = loads + 1 end
    return packadd(name)
end
for _ = 1, 2 do
    dofile(vim.env.TEST_DIRECTORY .. '/lua/plugins.lua')
    assert(vim.fn.exists(':Plug') == 2, 'the explicit install command is registered')
    assert(vim.fn.exists(':Undotree') == 2, 'the bundled command is registered')
    assert(package.loaded.undotree == nil, 'the undo-tree implementation stays lazy')
    assert(vim.g.loaded_undotree_plugin == nil, 'the bundled package stays unloaded')
end
vim.api.nvim_set_current_line('unsaved text')
vim.cmd.Undotree()
assert(package.loaded.undotree ~= nil, 'the command loads the implementation')
assert(vim.bo.filetype == 'nvim-undotree', 'the command opens the bundled undo tree')
assert(#vim.api.nvim_tabpage_list_wins(0) == 2, 'the undo tree opens one new window')
vim.cmd.close()
dofile(vim.env.TEST_DIRECTORY .. '/lua/plugins.lua')
vim.cmd.Undotree()
assert(loads == 1, 'the real command replaces the helper and survives config reloads')
assert(vim.bo.filetype == 'nvim-undotree', 'the real command still opens the undo tree')
vim.cmd('qa!')
LUA
    $self->{env}{NVIM_LOG_FILE} = "$self->{temporary}/nvim.log";
    my $result = run_command( [ $nvim, '--headless', '-u', 'NONE', '-n', '-i', 'NONE', '-l', $script ],
        { cwd => $self->{temporary}, env => $self->{env} } );
    is( $result->{returncode}, 0, "bundled undo-tree registration and lazy loading work: $result->{stderr}" );
}

sub installed_plugins_load_without_installing {
    my ($self) = @_;
    die 'Neovim is required' unless $nvim;
    my $packages = "$self->{env}{XDG_DATA_HOME}/nvim/site/pack/core/opt";
    for my $name (qw(copilot.vim nvim-treesitter)) {
        make_path("$packages/$name/plugin");
        write_file( "$packages/$name/plugin/loaded.lua", "vim.g['loaded_$name'] = true\n" );
    }
    my $init = "$self->{temporary}/init.lua";
    write_file( $init, <<'LUA' );
vim.pack.add = function() error('startup must not install plugins') end
dofile(vim.env.TEST_DIRECTORY .. '/lua/plugins.lua')
LUA
    my $result = run_command(
        [
            $nvim,                                                                             '--headless',
            '-u',                                                                              $init,
            '-n',                                                                              '-i',
            'NONE',                                                                            '-c',
            "lua assert(vim.g['loaded_copilot.vim'] and not vim.g['loaded_nvim-treesitter'])", '-c',
            "setfiletype go",                                                                  '-c',
            "lua assert(vim.g['loaded_nvim-treesitter'])",                                     '-c',
            'qa'
        ],
        { cwd => $self->{temporary}, env => $self->{env} }
    );
    is( $result->{returncode}, 0, "installed plugins load at startup or on first use: $result->{stderr}" );
}

run_cases(
    {
        installs_plugins_and_app_quietly             => \&installs_plugins_and_app_quietly,
        plugin_failure_stops_before_app_installation => \&plugin_failure_stops_before_app_installation,
        app_failure_is_returned                      => \&app_failure_is_returned,
        missing_nvim_fails_ci                        => \&missing_nvim_fails_ci,
        ci_installs_neovim_before_plugin_setup       => \&ci_installs_neovim_before_plugin_setup,
        native_lua_errors_fail_installation          => \&native_lua_errors_fail_installation,
        package_file_sets_its_own_lock_path          => \&package_file_sets_its_own_lock_path,
        bundled_undotree_is_registered_lazily        => \&bundled_undotree_is_registered_lazily,
        installed_plugins_load_without_installing    => \&installed_plugins_load_without_installing,
    },
    \&setup
);
