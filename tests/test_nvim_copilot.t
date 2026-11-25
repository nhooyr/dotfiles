use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub run_script {
    my ( $body, $startup ) = @_;
    my $nvim    = which('nvim') or die 'Neovim is required';
    my $temp    = tempdir( 'nvim-copilot-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $package = "$temp/data/nvim/site/pack/test/opt/copilot.vim";
    make_path( "$package/plugin", "$package/autoload/copilot" );
    write_file( "$package/plugin/copilot.vim", <<'VIM' );
let g:test_loads = get(g:, 'test_loads', 0) + 1
let g:loaded_copilot = 1
command! -bang -range=-1 -nargs=? Copilot let g:test_command = [<line1>, <line2>, <range>, <bang>0, <q-args>, <q-mods>]
augroup test_copilot
    autocmd!
    autocmd InsertEnter * call copilot#OnInsertEnter()
augroup END
VIM
    write_file( "$package/autoload/copilot.vim", <<'VIM' );
function! copilot#Init() abort
    let g:test_initializations = get(g:, 'test_initializations', 0) + 1
endfunction
function! copilot#OnFileType() abort
    call copilot#util#Defer({ -> add(g:test_events, 'attached') })
endfunction
function! copilot#OnInsertEnter() abort
    if index(g:test_events, 'attached') < 0
        throw 'suggestion requested before attachment'
    endif
    call add(g:test_events, 'suggest')
endfunction
VIM
    write_file( "$package/autoload/copilot/util.vim", <<'VIM' );
function! copilot#util#Defer(fn) abort
    call timer_start(0, { -> call(a:fn, []) })
endfunction
VIM
    write_file( "$temp/case.lua", <<'LUA' . $body );
local source = vim.env.TEST_ROOT .. '/nvim/lua/plugins.lua'
vim.pack.add = function() error('startup must not install plugins') end
vim.pack.update = function() error('startup must not update plugins') end
vim.g.test_events = {}
dofile(source)
assert(vim.fn.exists(':Copilot') == 0, 'Copilot command is not loaded at startup')
assert(vim.g.test_loads == nil, 'Copilot package is not loaded at startup')
LUA
    my $result = run_command(
        [
            $nvim, '--headless', '-n', '-i', 'NONE',
            ( $startup ? ( '-u', "$temp/case.lua" ) : ( '-u', 'NONE', '-l', "$temp/case.lua" ) )
        ],
        {
            env => {
                %ENV,
                TEST_ROOT       => $root,
                HOME            => "$temp/home",
                XDG_DATA_HOME   => "$temp/data",
                XDG_CONFIG_HOME => "$temp/config",
                XDG_CACHE_HOME  => "$temp/cache",
                XDG_STATE_HOME  => "$temp/state",
                NVIM_LOG_FILE   => "$temp/nvim.log",
            },
            timeout => 15,
        }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
}

sub first_insert_loads_and_requests_a_suggestion {
    run_script(<<'LUA');
dofile(source)
assert(#vim.api.nvim_get_autocmds({ group = 'aqsnow_copilot' }) == 2)
local timer = vim.g.aqsnow_copilot_timer
vim.api.nvim_exec_autocmds('InsertEnter', {})
assert(vim.g.test_loads == 1)
assert(vim.g.aqsnow_copilot_timer == nil, 'entering Insert mode cancels background warmup')
assert(vim.deep_equal(vim.fn.timer_info(timer), {}))
assert(vim.wait(1000, function() return #vim.g.test_events == 2 end))
assert(vim.deep_equal(vim.g.test_events, { 'attached', 'suggest' }))
assert(#vim.api.nvim_get_autocmds({ group = 'aqsnow_copilot' }) == 0)
vim.api.nvim_exec_autocmds('InsertEnter', {})
assert(vim.g.test_loads == 1)
dofile(source)
assert(#vim.api.nvim_get_autocmds({ group = 'aqsnow_copilot' }) == 0)
vim.api.nvim_exec_autocmds('InsertEnter', {})
assert(vim.g.test_loads == 1, 'subsequent insert and reload use the real plugin')
assert(vim.g.test_initializations == 1)
LUA
}

sub manual_command_loads_the_real_command {
    run_script(<<'LUA');
local timer = vim.g.aqsnow_copilot_timer
vim.cmd('silent 1,1Copilot! status')
assert(vim.g.test_loads == 1)
assert(vim.g.aqsnow_copilot_timer == nil, 'the explicit command cancels background warmup')
assert(vim.deep_equal(vim.fn.timer_info(timer), {}))
assert(vim.deep_equal(vim.g.test_command, { 1, 1, 2, 1, 'status', 'silent' }), vim.inspect(vim.g.test_command))
assert(#vim.api.nvim_get_autocmds({ group = 'aqsnow_copilot' }) == 0)
assert(vim.wait(1000, function() return #vim.g.test_events == 1 end))
vim.api.nvim_exec_autocmds('InsertEnter', {})
assert(vim.deep_equal(vim.g.test_events, { 'attached', 'suggest' }))
LUA
}

sub background_warmup_survives_reload {
    run_script(<<'LUA');
local original_timer = vim.g.aqsnow_copilot_timer
assert(original_timer ~= nil, 'startup schedules a warmup')
dofile(source)
assert(vim.deep_equal(vim.fn.timer_info(original_timer), {}), 'reload cancels the old warmup')
assert(vim.g.aqsnow_copilot_timer ~= original_timer)
assert(vim.wait(1000, function() return #vim.g.test_events == 1 end))
assert(vim.g.test_loads == 1 and vim.g.test_initializations == 1)
assert(vim.deep_equal(vim.g.test_events, { 'attached' }))
assert(vim.g.aqsnow_copilot_timer == nil)
dofile(source)
assert(vim.g.aqsnow_copilot_timer == nil, 'an already-loaded plugin needs no warmup')
vim.api.nvim_exec_autocmds('InsertEnter', {})
assert(vim.deep_equal(vim.g.test_events, { 'attached', 'suggest' }))
LUA
}

sub warmup_waits_until_after_startup {
    run_script( <<'LUA', 1 );
assert(vim.v.vim_did_enter == 0)
assert(vim.g.aqsnow_copilot_timer == nil, 'startup only registers the warmup')
vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
        assert(vim.g.aqsnow_copilot_timer ~= nil)
        assert(vim.g.test_loads == nil, 'VimEnter does not load Copilot synchronously')
        vim.schedule(function()
            local ok, err = pcall(function()
                assert(vim.wait(1000, function() return #vim.g.test_events == 1 end))
                assert(vim.g.test_loads == 1 and vim.g.test_initializations == 1)
            end)
            if not ok then io.stderr:write(err .. '\n') end
            vim.cmd(ok and 'qa!' or 'cq')
        end)
    end,
})
LUA
}

run_cases(
    {
        first_insert_loads_and_requests_a_suggestion => \&first_insert_loads_and_requests_a_suggestion,
        manual_command_loads_the_real_command        => \&manual_command_loads_the_real_command,
        background_warmup_survives_reload            => \&background_warmup_survives_reload,
        warmup_waits_until_after_startup             => \&warmup_waits_until_after_startup,
    }
);
