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
local source = vim.env.TEST_DOTFILES .. '/nvim/lua/treesitter.lua'
local installs, updates, waits, starts = {}, {}, {}, {}
local existing, runtimepath_sets = {}, 0
local failure, on_wait
local set_option = vim.api.nvim_set_option_value
vim.api.nvim_set_option_value = function(name, ...)
    if name == 'runtimepath' then runtimepath_sets = runtimepath_sets + 1 end
    return set_option(name, ...)
end
local function task(kind)
    return { wait = function(_, timeout)
        waits[#waits + 1] = timeout
        if on_wait then on_wait() end
        return failure ~= kind
    end }
end
package.loaded['nvim-treesitter'] = {
    install = function(languages)
        installs[#installs + 1] = vim.deepcopy(languages)
        return task('install')
    end,
    update = function(languages)
        updates[#updates + 1] = vim.deepcopy(languages)
        return task('update')
    end,
}
vim.treesitter.language.add = function(language) return existing[language] end
vim.treesitter.start = function(buf) starts[#starts + 1] = buf end
local function eq(actual, expected)
    assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. ' ~= ' .. vim.inspect(expected))
end
local function buffer(filetype)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = filetype
    return buf
end
local install = dofile(source)
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

sub missing_parser_does_not_install {
    run_script(<<'LUA');
buffer('lua')
buffer('rust')
buffer('go')
buffer('go')
eq(installs, {})
eq(updates, {})
eq(waits, {})
eq(starts, {})
eq(runtimepath_sets, 0)
eq(vim.bo.indentexpr, '')
LUA
}

sub go_features_only {
    run_script(<<'LUA');
existing.go = true
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
buffer('rust')
eq(vim.wo.foldmethod, 'indent')
eq(vim.wo.foldexpr, '0')
eq(starts, { buf })
eq(installs, {})
eq(waits, {})
eq(runtimepath_sets, 0)
LUA
}

sub reload_keeps_one_handler {
    run_script(<<'LUA');
dofile(source)
local events = vim.api.nvim_get_autocmds({ group = 'aqsnow_treesitter', event = 'FileType' })
eq(#events, 1)
eq(events[1].pattern, 'go')
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow_treesitter', event = 'PackChanged' }), 0)
existing.go = true
local buf = buffer('go')
eq(starts, { buf })
LUA
}

sub explicit_install_and_update {
    run_script(<<'LUA');
install()
eq(installs, { { 'go' } })
eq(updates, { { 'go' } })
eq(waits, { 300000, 300000 })
eq(runtimepath_sets, 1)
eq(starts, {})
LUA
}

sub failed_install_is_reported {
    run_script(<<'LUA');
failure = 'install'
local ok, err = pcall(install)
eq(ok, false)
assert(err:find('Parser installation failed', 1, true), err)
eq(updates, {})
eq(runtimepath_sets, 0)
LUA
}

sub failed_update_is_reported {
    run_script(<<'LUA');
failure = 'update'
local ok, err = pcall(install)
eq(ok, false)
assert(err:find('Parser update failed', 1, true), err)
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
end
install()
eq(vim.api.nvim_get_runtime_file('parser/go.so', false), { parser })
eq(runtimepath_sets, 1)
LUA
}

run_cases(
    {
        missing_parser_does_not_install        => \&missing_parser_does_not_install,
        go_features_only                       => \&go_features_only,
        reload_keeps_one_handler               => \&reload_keeps_one_handler,
        explicit_install_and_update            => \&explicit_install_and_update,
        failed_install_is_reported             => \&failed_install_is_reported,
        failed_update_is_reported              => \&failed_update_is_reported,
        first_install_refreshes_runtime_lookup => \&first_install_refreshes_runtime_lookup,
    }
);
