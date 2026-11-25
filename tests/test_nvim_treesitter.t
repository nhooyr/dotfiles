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
local installed, starts, checked = { lua = true }, {}, {}
local native_add = vim.treesitter.language.add
vim.pack.add = function() end
package.preload['nvim-treesitter'] = function()
    error('highlighting must not manage parser installation')
end
vim.treesitter.language.add = function(language)
    checked[#checked + 1] = language
    return installed[language]
end
vim.treesitter.start = function(buf, language)
    starts[#starts + 1] = { buf, language }
end
local function eq(actual, expected)
    assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. ' ~= ' .. vim.inspect(expected))
end
local function buffer(filetype, buftype)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].buftype = buftype or ''
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
                XDG_CACHE_HOME  => "$tmp/cache"
            },
            timeout => 15
        }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
}

sub installed_parsers_only {
    run_script(<<'LUA');
vim.wo.foldmethod = 'manual'
local buf = buffer('lua')
local indent = vim.bo[buf].indentexpr
eq(starts, { { buf, 'lua' } })
eq(vim.wo.foldmethod, 'manual')
eq(vim.bo[buf].indentexpr, indent)
buffer('not_a_parser')
buffer('lua', 'nofile')
eq(checked, { 'lua', 'not_a_parser' })
eq(#starts, 1)
installed.bash = true
vim.treesitter.language.register('bash', 'sh')
buf = buffer('sh')
eq(starts[2], { buf, 'bash' })
assert(package.loaded.treesitter == nil, 'the removed helper is not loaded')
LUA
}

sub reload_keeps_one_highlighter {
    run_script(<<'LUA');
dofile(plugins)
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow_treesitter', event = 'FileType' }), 1)
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow_treesitter', event = 'PackChanged' }), 0)
vim.api.nvim_exec_autocmds('PackChanged', {
    data = { spec = { name = 'nvim-treesitter' }, kind = 'update' },
})
local buf = buffer('lua')
eq(starts, { { buf, 'lua' } })
LUA
}

sub missing_parser_is_ignored {
    run_script(<<'LUA');
vim.treesitter.language.add = native_add
buffer('nonexistent_test_language')
buffer('')
eq(starts, {})
LUA
}

run_cases(
    {
        installed_parsers_only       => \&installed_parsers_only,
        reload_keeps_one_highlighter => \&reload_keeps_one_highlighter,
        missing_parser_is_ignored    => \&missing_parser_is_ignored,
    }
);
