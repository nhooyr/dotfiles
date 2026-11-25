use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub config_reload_refreshes_lua_modules {
    my $nvim   = which('nvim') or die 'Neovim is required';
    my $temp   = tempdir( 'nvim-loader-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $config = "$temp/nvim";
    make_path("$config/lua");
    copy_preserve( "$root/nvim/init.vim", "$config/init.vim" );
    for my $source ( grep { /\.lua$/ } @{ directory_entries("$root/nvim/lua") } ) {
        copy_preserve( $source, "$config/lua/" . basename($source) );
    }
    write_file( "$config/lua/loader_existing.lua", "return 'old'\n" );
    write_file( "$temp/init.vim",                  <<'VIM' );
let g:loaded_copilot = 1
execute 'set runtimepath^=' . fnameescape($TEST_CONFIG)
execute 'source' fnameescape($TEST_CONFIG . '/init.vim')
lua << EOF
vim.api.nvim_create_autocmd('VimEnter', { callback = function()
    vim.schedule(function()
        local ok, err = xpcall(function() dofile(vim.env.TEST_SCRIPT) end, debug.traceback)
        if not ok then io.stderr:write(err .. '\n') end
        vim.cmd(ok and 'qa!' or 'cq')
    end)
end })
EOF
VIM
    write_file( "$temp/case.lua", <<'LUA' );
local config = vim.env.TEST_CONFIG
assert(vim.loader.enabled, 'the Lua loader is enabled during startup')
assert(require('loader_existing') == 'old')
vim.fn.writefile({ "return 'new'" }, config .. '/lua/loader_new.lua')
assert(not pcall(require, 'loader_new'), 'the loader index starts without the new module')
vim.cmd.source(config .. '/init.vim')
assert(require('loader_new') == 'new', 'reload discovers new Lua modules')
vim.fn.writefile({ "return 'updated value'" }, config .. '/lua/loader_existing.lua')
assert(vim.uv.fs_rename(config .. '/lua/loader_new.lua', config .. '/lua/loader_renamed.lua'))
vim.cmd.source(config .. '/init.vim')
assert(require('loader_existing') == 'updated value', 'reload recompiles edited modules')
assert(require('loader_renamed') == 'new', 'reload discovers renamed modules')
LUA
    my $result = run_command(
        [ $nvim, '--headless', '-n', '-i', 'NONE', '-u', "$temp/init.vim" ],
        {
            cwd => $temp,
            env => {
                %ENV,
                HOME            => "$temp/home",
                XDG_CONFIG_HOME => "$temp/config",
                XDG_DATA_HOME   => "$temp/data",
                XDG_STATE_HOME  => "$temp/state",
                XDG_CACHE_HOME  => "$temp/cache",
                NVIM_LOG_FILE   => "$temp/nvim.log",
                TEST_CONFIG     => $config,
                TEST_SCRIPT     => "$temp/case.lua",
                dotfiles        => $root,
            },
            timeout => 15,
        }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
}

run_cases( { config_reload_refreshes_lua_modules => \&config_reload_refreshes_lua_modules } );
