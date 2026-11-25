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
    my $tmp = tempdir('nvim-treesitter-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    write_file("$tmp/case.lua", <<'LUA' . $body);
vim.opt.runtimepath:prepend(vim.env.TEST_DOTFILES .. '/nvim')
local installs, pending, starts, updates, configured = {}, {}, {}, 0
package.loaded['nvim-treesitter'] = {
    setup = function(options)
        configured = options.install_dir
        assert(vim.fn.isdirectory(configured) == 1)
        vim.opt.runtimepath:prepend(configured)
    end,
    get_available = function() return { 'lua', 'bash' } end,
    install = function(languages)
        installs[#installs + 1] = languages
        return { await = function(_, callback) pending[#pending + 1] = callback end }
    end,
    update = function() updates = updates + 1 end,
}
vim.treesitter.language.add = function() return true end
vim.treesitter.start = function(buf, language) starts[#starts + 1] = { buf, language } end
local function eq(actual, expected)
    assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. ' ~= ' .. vim.inspect(expected))
end
local function complete(index, err, installed)
    pending[index](err, installed)
    vim.wait(20, function() return false end)
end
local function buffer(filetype, buftype)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].buftype = buftype or ''
    vim.bo[buf].filetype = filetype
    return buf
end
require('treesitter').setup()
LUA
    my $result = run_command(
        [ $nvim, '--headless', '-n', '-i', 'NONE', '-u', 'NONE', '-l', "$tmp/case.lua" ],
        { env => { %ENV, TEST_DOTFILES => $root, XDG_DATA_HOME => "$tmp/data" }, timeout => 15 }
    );
    is($result->{returncode}, 0, $result->{stderr});
}

sub install_and_highlight {
    run_script(<<'LUA');
vim.wo.foldmethod = 'manual'
local buf = buffer('lua')
local indent = vim.bo[buf].indentexpr
eq(installs, { { 'lua' } })
eq(starts, {})
complete(1, nil, true)
eq(starts, { { buf, 'lua' } })
eq(vim.wo.foldmethod, 'manual')
eq(vim.bo[buf].indentexpr, indent)
buffer('not_a_parser')
buffer('lua', 'nofile')
eq(#installs, 1)
LUA
}

sub stale_and_failed_installs {
    run_script(<<'LUA');
local buf = buffer('lua')
vim.bo[buf].filetype = 'not_a_parser'
complete(1, nil, true)
eq(starts, {})
buf = buffer('lua')
vim.api.nvim_buf_delete(buf, { force = true })
complete(2, nil, true)
eq(starts, {})
buffer('lua')
complete(3, nil, false)
eq(starts, {})
local notice
vim.notify = function(message) notice = message end
buffer('lua')
complete(4, 'installation failed', false)
eq(notice, 'installation failed')
eq(starts, {})
LUA
}

sub package_updates_and_reload {
    run_script(<<'LUA');
local loaded
vim.cmd.packadd = function(name) loaded = name end
require('treesitter').setup()
vim.api.nvim_exec_autocmds('PackChanged', { data = { spec = { name = 'other' }, kind = 'update' } })
vim.api.nvim_exec_autocmds('PackChanged', { data = { spec = { name = 'nvim-treesitter' }, kind = 'install' } })
eq(updates, 0)
vim.api.nvim_exec_autocmds('PackChanged', { data = { spec = { name = 'nvim-treesitter' }, kind = 'update' } })
eq(updates, 1)
eq(loaded, 'nvim-treesitter')
buffer('lua')
eq(#installs, 1)
LUA
}

sub parser_directory {
    run_script(<<'LUA');
local helper = require('treesitter')
helper.configure()
helper.configure()
eq(configured, vim.fn.stdpath('data') .. '/treesitter')
local count = 0
for _, path in ipairs(vim.opt.runtimepath:get()) do
    if path == configured then count = count + 1 end
end
eq(count, 1)
vim.fn.writefile({ 'installed' }, configured .. '/installed-parser')
eq(vim.api.nvim_get_runtime_file('installed-parser', false), { configured .. '/installed-parser' })
LUA
}

run_cases({
    install_and_highlight => \&install_and_highlight,
    stale_and_failed_installs => \&stale_and_failed_installs,
    package_updates_and_reload => \&package_updates_and_reload,
    parser_directory => \&parser_directory,
});
