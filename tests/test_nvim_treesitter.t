use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my $nvim = which('nvim');

sub run_script {
    my ($body) = @_;
    plan skip_all => 'Neovim is needed for Treesitter regression tests' unless $nvim;
    my $tmp = tempdir( 'nvim-treesitter-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    write_file( "$tmp/case.lua", <<'LUA' . $body );
local plugins = vim.env.TEST_DOTFILES .. '/nvim/lua/plugins.lua'
local installs, waits, starts, package_added, on_wait = {}, {}, {}, false
local installed = true
local existing, runtimepath_sets = {}, 0
local set_option = vim.api.nvim_set_option_value
vim.api.nvim_set_option_value = function(name, ...)
    if name == 'runtimepath' then runtimepath_sets = runtimepath_sets + 1 end
    return set_option(name, ...)
end
vim.pack.add = function() package_added = true end
package.loaded['nvim-treesitter'] = {
    get_installed = function(kind)
        assert(kind == 'parsers')
        return vim.tbl_keys(existing)
    end,
    install = function(parsers)
        assert(package_added, 'the parser plugin loads before installation')
        installs[#installs + 1] = vim.deepcopy(parsers)
        return { wait = function(_, timeout)
            waits[#waits + 1] = timeout
            if on_wait then on_wait() end
            if installed then
                for _, parser in ipairs(parsers) do existing[parser] = true end
            end
            return installed
        end }
    end,
}
vim.treesitter.start = function() starts[#starts + 1] = vim.api.nvim_get_current_buf() end
local function eq(actual, expected)
    assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. ' ~= ' .. vim.inspect(expected))
end
local function buffer(filetype)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = filetype
    return buf
end
dofile(plugins)
LUA
    my $result = run_command(
        [ $nvim, '--headless', '-n', '-i', 'NONE', '-u', 'NONE', '-l', "$tmp/case.lua" ],
        {
            env => {
                %ENV,
                TEST_DOTFILES   => $root,
                XDG_CONFIG_HOME => "$tmp/config",
                XDG_DATA_HOME   => "$tmp/data",
                XDG_STATE_HOME  => "$tmp/state",
                XDG_CACHE_HOME  => "$tmp/cache",
            },
            timeout => 15,
        }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
}

sub install_whitelisted_filetype_on_open {
    run_script(<<'LUA');
eq(installs, {})
eq(waits, {})
buffer('lua')
buffer('rust')
eq(installs, {})
buffer('go')
eq(installs, { { 'go' } })
eq(waits, { 300000 })
LUA
}

sub go_features_only {
    run_script(<<'LUA');
vim.go.foldmethod = 'indent'
vim.go.foldexpr = '0'
vim.wo.foldlevel = 999
local buf = buffer('go')
eq(starts, { buf })
eq(vim.wo.foldexpr, 'v:lua.vim.treesitter.foldexpr()')
eq(vim.wo.foldmethod, 'expr')
eq(vim.wo.foldlevel, 999)
eq(vim.bo.indentexpr, "v:lua.require'nvim-treesitter'.indentexpr()")
eq(vim.go.foldmethod, 'indent')
eq(vim.go.foldexpr, '0')
buffer('lua')
eq(vim.wo.foldmethod, 'indent')
eq(vim.wo.foldexpr, '0')
buffer('rust')
eq(vim.wo.foldmethod, 'indent')
eq(vim.wo.foldexpr, '0')
eq(starts, { buf })
LUA
}

sub reload_keeps_one_handler {
    run_script(<<'LUA');
dofile(plugins)
local events = vim.api.nvim_get_autocmds({ group = 'aqsnow_treesitter', event = 'FileType' })
eq(#events, 1)
eq(events[1].pattern, 'go')
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow_treesitter', event = 'PackChanged' }), 0)
local buf = buffer('go')
eq(starts, { buf })
LUA
}

sub changed_buffers_do_not_receive_features {
    run_script(<<'LUA');
on_wait = function() vim.bo.filetype = 'lua' end
buffer('go')
eq(starts, {})
existing.go = nil
on_wait = function() vim.cmd.enew() end
buffer('go')
eq(starts, {})
LUA
}

sub failed_install_does_not_start_features {
    run_script(<<'LUA');
installed = false
buffer('go')
eq(starts, {})
eq(vim.bo.indentexpr, '')
eq(vim.wo.foldmethod, 'manual')
eq(runtimepath_sets, 0)
LUA
}

sub first_install_refreshes_runtime_lookup {
    run_script(<<'LUA');
local parser = vim.fn.stdpath('data') .. '/site/parser/go.so'
eq(vim.api.nvim_get_runtime_file('parser/go.so', false), {})
on_wait = function()
    vim.fn.mkdir(vim.fs.dirname(parser), 'p')
    vim.fn.writefile({}, parser)
    vim.cmd.enew()
end
buffer('go')
eq(vim.api.nvim_get_runtime_file('parser/go.so', false), { parser })
eq(starts, {})
eq(runtimepath_sets, 1)
on_wait = nil
buffer('go')
dofile(plugins)
buffer('go')
eq(runtimepath_sets, 1)
eq(#installs, 1)
eq(#starts, 2)
LUA
}

sub installed_parser_skips_install_and_refresh {
    run_script(<<'LUA');
existing.go = true
local buf = buffer('go')
eq(installs, {})
eq(runtimepath_sets, 0)
eq(starts, { buf })
LUA
}

run_cases(
    {
        install_whitelisted_filetype_on_open       => \&install_whitelisted_filetype_on_open,
        go_features_only                           => \&go_features_only,
        reload_keeps_one_handler                   => \&reload_keeps_one_handler,
        changed_buffers_do_not_receive_features    => \&changed_buffers_do_not_receive_features,
        failed_install_does_not_start_features     => \&failed_install_does_not_start_features,
        first_install_refreshes_runtime_lookup     => \&first_install_refreshes_runtime_lookup,
        installed_parser_skips_install_and_refresh => \&installed_parser_skips_install_and_refresh,
    }
);
