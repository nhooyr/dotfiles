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
    plan skip_all => 'Neovim is needed to test the editor helpers' unless $nvim;
    $self->{temporary} = tempdir( 'nvim-helpers-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $tmp = $self->{temporary};
    make_path("$tmp/home");
    write_file( "$tmp/original.txt", "original\n" );
    $self->{env} = {
        %ENV,
        HOME                   => "$tmp/home",
        XDG_CONFIG_HOME        => "$tmp/config",
        XDG_DATA_HOME          => "$tmp/data",
        XDG_STATE_HOME         => "$tmp/state",
        XDG_CACHE_HOME         => "$tmp/cache",
        NVIM_LOG_FILE          => "$tmp/nvim.log",
        AQSNOW_DIRALIS         => 'HOME',
        AQSNOW_FISH_RENDEZVOUS => "$tmp/request",
        dotfiles               => $root,
        TEST_DOTFILES          => $root,
        TEST_ORIGINAL          => "$tmp/original.txt",
        TEST_SCRIPT            => "$tmp/case.lua",
    };
    write_file( "$tmp/init.vim", <<'VIM' );
let $MYVIMRC = expand('<sfile>:p')
let g:test_config_sources = get(g:, 'test_config_sources', 0) + 1
execute 'set runtimepath^=' . fnameescape($TEST_DOTFILES . '/nvim')
execute 'source' fnameescape($TEST_DOTFILES . '/nvim/init.vim')
lua << EOF
vim.api.nvim_create_autocmd('VimEnter', { callback = function()
    vim.schedule(function()
        local ok, err = xpcall(function() dofile(vim.env.TEST_SCRIPT) end, debug.traceback)
        if not ok then io.stderr:write(err .. '\n') end
        vim.api.nvim_command(ok and 'qa!' or 'cq')
    end)
end })
EOF
VIM
}

sub run_script {
    my ( $self, $body ) = @_;
    write_file( $self->{env}{TEST_SCRIPT}, <<'LUA' . $body );
local function eq(actual, expected, message)
    assert(vim.deep_equal(actual, expected), message .. '\nexpected: '
        .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual))
end
local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end
LUA
    my $result = run_command(
        [
            $nvim, '--headless', '-n', '-i', 'NONE', '-u', "$self->{temporary}/init.vim",
            $self->{env}{TEST_ORIGINAL}
        ],
        { env => $self->{env}, cwd => $self->{temporary}, timeout => 15 }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
}

sub startup_and_config_paths {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
eq(vim.g.aqsnow_orig_file, vim.fn.resolve(vim.env.TEST_ORIGINAL), 'startup records the original file')
assert(package.loaded.rendezvous == nil, 'rendezvous stays unloaded at startup')
assert(package.loaded.vidir == nil, 'vidir stays unloaded at startup')
assert(package.loaded.grep == nil, 'startup does not load a grep module')
local grepprg = vim.fn.shellescape(vim.env.TEST_DOTFILES .. '/bin/vgrep')
eq(vim.o.grepprg, grepprg, 'grep uses the fixed vgrep wrapper')
eq(vim.o.grepformat, '%f:%l:%c:%m', 'grep uses ripgrep line and column fields')
eq(vim.fn.exists(':Vidir'), 2, 'Vidir command remains available')
for _, mode in ipairs({ 'n', 'i' }) do
    assert(vim.fn.maparg('<M-CR>', mode):find("require('rendezvous').quit_and_run()", 1, true),
        'run mapping routes to the lazy helper in ' .. mode)
    assert(vim.fn.maparg('<M-v>', mode):find("require('rendezvous').fzf_path_widget()", 1, true),
        'picker mapping routes to the lazy helper in ' .. mode)
end
local name = assert(vim.fn.maparg([[\s]], 'n'):match('<SNR>%d+_is_config_file'))
local is_config = vim.fn[name]
local config = vim.env.TEST_DOTFILES .. '/nvim'
local registrations = #vim.api.nvim_get_autocmds({ group = 'aqsnow' })
eq(is_config(vim.env.MYVIMRC), 1, 'the active init file is watched')
eq(is_config(config .. '/lua/rendezvous.lua'), 1, 'new Lua helpers are watched')
eq(is_config(config .. '/lua/nested/future.lua'), 1, 'nested Lua helpers are watched')
eq(is_config(config .. '/lua/helper.txt'), 0, 'other extensions are excluded')
eq(is_config(config .. '/lua-other/helper.lua'), 0, 'directory prefix lookalikes are excluded')
eq(is_config(vim.env.TEST_ORIGINAL .. '.lua'), 0, 'unrelated Lua files are excluded')
vim.api.nvim_buf_set_name(0, vim.env.TEST_ORIGINAL .. '.other')
vim.cmd('source ' .. vim.fn.fnameescape(config .. '/init.vim'))
eq(vim.g.aqsnow_orig_file, vim.fn.resolve(vim.env.TEST_ORIGINAL), 'reload preserves the original file')
assert(package.loaded.rendezvous == nil and package.loaded.vidir == nil, 'reload preserves lazy loading')
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow' }), registrations, 'reload does not duplicate autocmds')
vim.cmd('cd ' .. vim.fn.fnameescape(vim.env.HOME))
vim.cmd('doautocmd CmdlineEnter :')
eq(vim.o.grepprg, grepprg, 'directory and command-line changes keep the same grep command')
eq(vim.o.grepformat, '%f:%l:%c:%m', 'directory and command-line changes keep the same grep format')
LUA
}

sub coalesced_config_reload {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local sources = vim.g.test_config_sources
for _, file in ipairs({ 'snips.lua', 'gitcommit.lua' }) do
    vim.cmd('doautocmd <nomodeline> BufWritePost '
        .. vim.fn.fnameescape(vim.env.TEST_DOTFILES .. '/nvim/lua/' .. file))
end
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow', event = 'SafeState' }), 1,
    'multiple config writes queue one reload')
vim.api.nvim_exec_autocmds('SafeState', {})
eq(vim.g.test_config_sources, sources + 1, 'queued config writes produce one source operation')
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow', event = 'SafeState' }), 0,
    'the pending reload is removed after running')
LUA
}

sub nested_module_reload {
    my ($self) = @_;
    my $copy = "$self->{temporary}/config-copy";
    make_path("$copy/nvim/lua/nested");
    copy_preserve( "$root/nvim/init.vim", "$copy/nvim/init.vim" );
    for my $source ( grep { /\.lua$/ } @{ directory_entries("$root/nvim/lua") } ) {
        copy_preserve( $source, "$copy/nvim/lua/" . basename($source) );
    }
    write_file( "$copy/nvim/lua/nested/helper.lua", 'return {}' );
    write_file( "$copy/nvim/lua/nested/init.lua",   'return {}' );
    local $self->{env}{TEST_DOTFILES} = $copy;
    run_script( $self, <<'LUA' );
for _, name in ipairs({ 'nested', 'nested.init', 'nested.helper' }) do package.loaded[name] = {} end
local unrelated = {}
package.loaded.unrelated = unrelated
vim.cmd('source ' .. vim.fn.fnameescape(vim.env.TEST_DOTFILES .. '/nvim/init.vim'))
for _, name in ipairs({ 'nested', 'nested.init', 'nested.helper' }) do
    assert(package.loaded[name] == nil, 'reload invalidates ' .. name)
end
assert(package.loaded.unrelated == unrelated, 'reload preserves unrelated Lua modules')
LUA
}

sub first_commit_summary_width {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
vim.cmd.enew()
vim.api.nvim_buf_set_name(0, 'COMMIT_EDITMSG')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep('x', 90), '', '# Commit message' })
vim.bo.filetype = 'gitcommit'
eq(vim.bo.textwidth, 80, 'commit editing uses an 80-column width')
eq(vim.fn.synIDattr(vim.fn.synID(1, 75, 1), 'name'), 'gitcommitSummary',
    'the first commit buffer uses the configured summary width')
eq(vim.fn.synIDattr(vim.fn.synID(1, 81, 1), 'name'), 'gitcommitOverflow',
    'summary overflow begins after column 80')
LUA
}

sub ripgrep_quickfix {
    my ($self) = @_;
    plan skip_all => 'ripgrep is needed to test quickfix search' unless which('rg');
    my $directory = "$self->{temporary}/search";
    make_path($directory);
    write_file( "$directory/visible.txt", "header\nprefix Needle value\nprefix needle value\n" );
    write_file( "$directory/.hidden.txt", "  needle hidden\n" );
    write_file( "$directory/ignored.txt", "needle ignored\n" );
    write_file( "$directory/.ignore",     "ignored.txt\n" );
    $self->{env}{TEST_SEARCH} = $directory;
    run_script( $self, <<'LUA' );
vim.cmd('cd ' .. vim.fn.fnameescape(vim.env.TEST_SEARCH))
vim.cmd('silent grep needle .')
local matches = {}
for _, item in ipairs(vim.fn.getqflist()) do
    assert(item.valid == 1, 'ripgrep result is valid')
    matches[#matches + 1] = {
        vim.fn.fnamemodify(vim.fn.bufname(item.bufnr), ':t'), item.lnum, item.col, item.text,
    }
end
table.sort(matches, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[2] < b[2]
end)
eq(matches, {
    { '.hidden.txt', 1, 3, '  needle hidden' },
    { 'visible.txt', 2, 8, 'prefix Needle value' },
    { 'visible.txt', 3, 8, 'prefix needle value' },
}, 'search outside Git includes hidden files, respects ignores, and preserves quickfix positions')
vim.cmd('silent grep Needle .')
local items = vim.fn.getqflist()
eq(#items, 1, 'uppercase pattern is case-sensitive')
eq({ items[1].lnum, items[1].col }, { 2, 8 }, 'uppercase search keeps the correct quickfix position')
LUA
}

sub rendezvous_routes {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local calls, accepted = {}, 0
vim.cmd.wall = function() calls[#calls + 1] = 'wall' end
vim.cmd.qall = function() calls[#calls + 1] = 'qall' end
vim.fn['copilot#Accept'] = function(fallback)
    eq(fallback, '', 'Copilot receives the empty fallback')
    accepted = accepted + 1
    return 'accepted'
end
local request = vim.env.AQSNOW_FISH_RENDEZVOUS
feed('<M-CR>')
assert(package.loaded.rendezvous ~= nil, 'the first run mapping loads its helper')
eq(vim.fn.readfile(request), { 'exec' }, 'the original nonempty file requests execution')
eq(calls, { 'wall', 'qall' }, 'run saves before quitting')
eq(accepted, 0, 'Normal mode does not accept Copilot')

vim.fn.delete(request)
vim.api.nvim_buf_set_name(0, vim.env.TEST_ORIGINAL .. '.other')
feed('<M-CR>')
eq(vim.fn.filereadable(request), 0, 'other files do not request execution')
feed('<M-v>')
eq(vim.fn.readfile(request), { '<M-v>' }, 'picker requests are independent of the original file')

vim.fn.delete(request)
vim.api.nvim_buf_set_name(0, vim.env.TEST_ORIGINAL)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
feed('<M-CR>')
eq(vim.fn.filereadable(request), 0, 'empty original files do not request execution')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'run ' })
feed('A<M-CR>')
eq(accepted, 1, 'Insert mode accepts Copilot exactly once')
eq(vim.api.nvim_get_current_line(), 'run accepted', 'accepted text reaches the buffer')
eq(vim.fn.readfile(request), { 'exec' }, 'Insert mode still requests execution')
feed('A<M-v>')
eq(accepted, 1, 'the Insert-mode picker does not accept Copilot')
eq(vim.fn.readfile(request), { '<M-v>' }, 'Insert mode routes the picker request')
LUA
}

sub rendezvous_error_order {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local helper, saved, quit = require('rendezvous'), 0, false
vim.cmd.wall = function() error('save failed') end
vim.cmd.qall = function() quit = true end
local ok, err = pcall(helper.quit_and_run)
assert(not ok and err:find('save failed', 1, true), 'save errors are propagated')
assert(not quit, 'save failure prevents quitting')
eq(vim.fn.filereadable(vim.env.AQSNOW_FISH_RENDEZVOUS), 0, 'save failure sends no request')

vim.cmd.wall = function() saved = saved + 1 end
vim.env.AQSNOW_FISH_RENDEZVOUS = vim.env.TEST_ORIGINAL .. '/missing/request'
ok = pcall(helper.fzf_path_widget)
assert(not ok, 'request write errors are propagated')
eq(saved, 1, 'the buffer is saved before attempting the request')
assert(not quit, 'request failure prevents quitting')

vim.env.AQSNOW_FISH_RENDEZVOUS = nil
helper.fzf_path_widget()
eq(saved, 2, 'without a rendezvous path the helper still saves')
assert(quit, 'without a rendezvous path the helper still quits')
LUA
}

run_cases(
    {
        startup_and_config_paths   => \&startup_and_config_paths,
        coalesced_config_reload    => \&coalesced_config_reload,
        nested_module_reload       => \&nested_module_reload,
        first_commit_summary_width => \&first_commit_summary_width,
        ripgrep_quickfix           => \&ripgrep_quickfix,
        rendezvous_routes          => \&rendezvous_routes,
        rendezvous_error_order     => \&rendezvous_error_order,
    },
    \&setup
);
