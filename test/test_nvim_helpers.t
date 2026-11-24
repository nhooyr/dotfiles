use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root    = absolute_path("$FindBin::Bin/..");
my $nvim    = which('nvim');
my $dirvish = ( $ENV{XDG_DATA_HOME} || "$ENV{HOME}/.local/share" ) . '/nvim/site/pack/core/opt/vim-dirvish';

sub setup {
    my ($self) = @_;
    plan skip_all => 'Neovim is needed to test the editor helpers' unless $nvim;
    die "Dirvish is not installed: $dirvish\n" unless -d $dirvish;
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
        TEST_DIRVISH           => $dirvish,
        TEST_ORIGINAL          => "$tmp/original.txt",
        TEST_SCRIPT            => "$tmp/case.lua",
    };
    write_file( "$tmp/init.vim", <<'VIM' );
let $MYVIMRC = expand('<sfile>:p')
let g:test_config_sources = get(g:, 'test_config_sources', 0) + 1
execute 'set runtimepath^=' . fnameescape($TEST_DOTFILES . '/nvim')
lua << EOF
vim.pack.add = function(specs, options)
    vim.g.test_plugin_specs = specs
    vim.g.test_plugin_options = options
    if not vim.tbl_contains(vim.opt.runtimepath:get(), vim.env.TEST_DIRVISH) then
        vim.opt.runtimepath:prepend(vim.env.TEST_DIRVISH)
    end
end
EOF
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
    my ( $self, $body, $arguments ) = @_;
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
            '--',  @{ $arguments // [ $self->{env}{TEST_ORIGINAL} ] }
        ],
        { env => $self->{env}, cwd => $self->{temporary}, timeout => 15 }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
}

sub startup_and_config_paths {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
eq(vim.g.aqsnow_orig_file, vim.fn.resolve(vim.env.TEST_ORIGINAL), 'startup records the original file')
eq(vim.g.test_plugin_specs, {
    { src = 'https://github.com/nhooyr/copilot.vim.git', version = 'fix-partial-accept-preview' },
    'https://github.com/justinmk/vim-dirvish.git',
}, 'native packages preserve the patched Copilot fork and include Dirvish')
eq(vim.g.test_plugin_options, { confirm = false }, 'package setup installs without an interactive prompt')
eq(vim.o.packlockfile, vim.env.TEST_DOTFILES .. '/nvim/nvim-pack-lock.json', 'package revisions use the tracked lockfile')
eq(vim.g.loaded_dirvish, 1, 'Dirvish loads during startup')
eq(vim.g.loaded_nvim_dir_plugin, 0, 'Dirvish disables the native directory browser')
assert(not vim.o.autochdir, 'directories change only when explicitly requested')
local remote = false
for _, event in ipairs(vim.api.nvim_get_autocmds({ group = 'Network', event = 'BufReadCmd' })) do
    remote = remote or event.pattern == 'scp://*'
end
assert(remote, 'netrw keeps the scp handler for sshv')
assert(package.loaded.rendezvous == nil, 'rendezvous stays unloaded at startup')
assert(package.loaded.vidir == nil, 'vidir stays unloaded at startup')
assert(package.loaded.snippets == nil, 'snippets stay unloaded until completion or expansion')
assert(package.loaded.filelinecol == nil, 'file locations stay unloaded for ordinary files')
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
    assert(vim.fn.maparg('<M-o>', mode):find("fzf_path_widget('recent')", 1, true),
        'recent picker mapping routes to the lazy helper in ' .. mode)
end
eq(vim.fn.maparg('<M-r>', 'n'), 'cgn', 'Alt-r retains its existing mapping')
eq(vim.fn.maparg('<M-g>', 'n'), ":silent grep ''<Left>", 'Alt-g opens the grep prompt without an explicit root')
assert(vim.fn.maparg('<M-f>', 'i'):find('copilot#AcceptWord', 1, true), 'Insert Alt-f still accepts Copilot words')
eq(vim.fn.maparg([[\f]], 'n'), ':Find ', 'Leader-f opens the regex search prompt')
eq(vim.fn.maparg('<M-f>', 'n'), ':Findg **<Left>', 'Alt-f starts a glob with the cursor between stars')
eq(vim.fn.exists(':Findr'), 0, 'the separate basic-regex command is removed')
eq(vim.fn.exists(':Finde'), 0, 'the separate extended-regex command is removed')
eq(vim.fn.maparg([[\g]], 'n'), vim.fn.maparg('<M-g>', 'n'), 'Leader-g and Alt-g open the same grep prompt')
local name = assert(vim.fn.maparg([[\s]], 'n'):match('<SNR>%d+_is_config_file'))
local is_config = vim.fn[name]
local config = vim.env.TEST_DOTFILES .. '/nvim'
local registrations = #vim.api.nvim_get_autocmds({ group = 'aqsnow' })
eq(is_config(config .. '/init.vim'), 1, 'the config init file is watched')
eq(is_config(vim.env.MYVIMRC), 0, 'an external init wrapper is not a config file')
eq(is_config(config .. '/lua/plugins.lua'), 1, 'the package declaration is watched')
eq(is_config(config .. '/after/ftplugin/example.vim'), 1, 'nested Vim config files are watched')
eq(is_config(config .. '/settings.txt'), 0, 'other filetypes are not watched')
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

sub filename_display {
    my ($self) = @_;
    make_path("$self->{temporary}/project");
    $self->{env}{AQSNOW_DIRALIS} = 'HOME:TEST_PROJECT';
    $self->{env}{HOME}           = absolute_path( $self->{env}{HOME} );
    $self->{env}{TEST_PROJECT}   = absolute_path("$self->{temporary}/project");
    run_script( $self, <<'LUA' );
local helper = require('dirali')
local function check(expected, description)
    eq(helper.filename(), expected, description)
    for _, format in ipairs({ vim.o.statusline, vim.o.titlestring }) do
        local rendered = vim.api.nvim_eval_statusline(format, { maxwidth = 10000 }).str
        assert(rendered:find(expected, 1, true), description .. ': ' .. rendered)
    end
end
local path = vim.api.nvim_buf_get_name(0)
eq(vim.api.nvim_eval_statusline('%f', {}).str, 'original.txt', 'the native name is cwd-relative')
check(path, 'unaliased files use absolute paths in the statusline and title')
for _, alias in ipairs({ { 'HOME', '~' }, { 'TEST_PROJECT', '$TEST_PROJECT' } }) do
    vim.cmd.enew()
    vim.api.nvim_buf_set_name(0, vim.env[alias[1]] .. '/notes.txt')
    check(alias[2] .. '/notes.txt', 'directory aliases remain abbreviated')
end
vim.cmd.enew()
check(vim.api.nvim_eval_statusline('%f', {}).str, 'unnamed buffers retain the native label')
vim.bo.buftype = 'nofile'
vim.cmd('cd ' .. vim.fn.fnameescape(vim.fs.dirname(path)))
vim.api.nvim_buf_set_name(0, path .. '.scratch')
check(vim.api.nvim_eval_statusline('%f', {}).str, 'special buffers retain the native label')
LUA
}

sub quickfix_directory_aliases {
    my ($self) = @_;
    $self->{env}{HOME} = absolute_path( $self->{env}{HOME} );
    make_path("$self->{env}{HOME}/project");
    $self->{env}{TEST_PROJECT}   = absolute_path("$self->{env}{HOME}/project");
    $self->{env}{AQSNOW_DIRALIS} = 'HOME:TEST_PROJECT';
    run_script( $self, <<'LUA' );
local home, project = vim.env.HOME, vim.env.TEST_PROJECT
local outside = vim.fn.resolve(vim.env.TEST_ORIGINAL)
vim.cmd.cd(project)
local items = {
    { filename = 'code.lua', lnum = 2, end_lnum = 4, type = 'E', nr = 7, text = '  first\n  line' },
    { filename = home .. '/notes.txt', lnum = 5, text = 'home' },
    { filename = outside, lnum = 6, text = 'outside' },
    { filename = project .. '/help.txt', lnum = 7, type = '\1', text = 'help' },
    { filename = project .. '/code.lua', lnum = 8, module = 'compiler', text = 'module' },
}
local expected = {
    '$TEST_PROJECT/code.lua|2-4 error   7| first line',
    '~/notes.txt|5| home',
    outside .. '|6| outside',
    'help.txt|7| help',
    'compiler|8| module',
}
vim.fn.setqflist({}, ' ', { items = items })
local format = require('quickfix').fmt
eq(format({ quickfix = 1, id = 0, start_idx = 1, end_idx = #items }), expected,
    'quickfix abbreviates absolute paths while preserving help, modules, ranges, and types')
eq(vim.api.nvim_buf_get_name(vim.fn.getqflist()[1].bufnr), project .. '/code.lua',
    'display aliases do not change the file opened by quickfix')
vim.fn.setloclist(0, {}, ' ', { items = items })
eq(format({ quickfix = 0, winid = vim.api.nvim_get_current_win(), id = 0, start_idx = 1, end_idx = #items }),
    expected, 'location lists use the same directory aliases')
LUA
}

sub quickfix_title_directory_aliases {
    my ($self) = @_;
    $self->{env}{HOME} = absolute_path( $self->{env}{HOME} );
    make_path("$self->{env}{HOME}/project space");
    $self->{env}{TEST_PROJECT}   = absolute_path("$self->{env}{HOME}/project space");
    $self->{env}{AQSNOW_DIRALIS} = 'HOME:TEST_PROJECT';
    run_script( $self, <<'LUA' );
local home, project = vim.env.HOME, vim.env.TEST_PROJECT
local outside = vim.fn.resolve(vim.env.TEST_ORIGINAL)
local title = ":'" .. project .. "/bin/vgrep' -P 'me' " .. home .. '/notes ' .. outside
local expected = ":'$TEST_PROJECT/bin/vgrep' -P 'me' ~/notes " .. outside
vim.fn.setqflist({}, ' ', { title = title, items = { { filename = outside, lnum = 1, text = 'match' } } })
vim.cmd.copen()
eq(require('quickfix').title(), ' ' .. expected, 'quoted paths and unquoted paths use the longest directory alias')
local display = vim.api.nvim_eval_statusline(vim.wo.statusline, { maxwidth = 500 }).str
assert(display:find(expected, 1, true), 'the quickfix statusline displays the shortened title: ' .. display)
eq(vim.w.quickfix_title, title, 'formatting preserves the window title')
eq(vim.fn.getqflist({ title = 0 }).title, title, 'formatting preserves the underlying quickfix title')
vim.cmd.cclose()
vim.fn.setloclist(0, {}, ' ', { title = title, items = { { filename = outside, lnum = 1, text = 'match' } } })
vim.cmd.lopen()
display = vim.api.nvim_eval_statusline(vim.wo.statusline, { maxwidth = 500 }).str
assert(display:find(expected, 1, true), 'location-list statuslines abbreviate paths too: ' .. display)
eq(vim.fn.getloclist(0, { title = 0 }).title, title, 'formatting preserves the underlying location-list title')
vim.w.quickfix_title = nil
eq(require('quickfix').title(), '', 'a missing title remains empty')
LUA
}

sub new_files_are_modified {
    my ($self) = @_;
    my $file = "$self->{temporary}/new parent/empty file.txt";
    $self->{env}{TEST_NEW_FILE} = $file;
    run_script( $self, <<'LUA', [$file] );
local file = vim.env.TEST_NEW_FILE
assert(vim.bo.modified, 'a new named file starts modified')
assert(vim.api.nvim_eval_statusline('%m', {}).str ~= '', 'the new file has a modified indicator')
vim.api.nvim_exec_autocmds('User', { pattern = 'AqsnowAutosave' })
vim.api.nvim_exec_autocmds('FocusLost', {})
eq(vim.fn.filereadable(file), 0, 'autosave does not create a new file')
eq(vim.fn.isdirectory(vim.fs.dirname(file)), 0, 'autosave does not create its parent directory')
assert(vim.bo.modified, 'the file stays modified until explicitly saved')
vim.cmd.write()
eq(vim.fn.filereadable(file), 1, 'the first write creates the empty file and its parents')
assert(not vim.bo.modified, 'the first write clears the modified flag')
vim.cmd.enew()
assert(not vim.bo.modified, 'an unnamed buffer stays unmodified')
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_ORIGINAL))
assert(not vim.bo.modified, 'an existing file stays unmodified')
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_ORIGINAL .. ':1:1'))
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)), vim.fn.resolve(vim.env.TEST_ORIGINAL),
    'file locations still open their existing target')
assert(not vim.bo.modified, 'a file-location placeholder does not dirty its target')
vim.cmd('Dirvish ' .. vim.fn.fnameescape(vim.fs.dirname(file)))
assert(not vim.bo.modified, 'a directory buffer stays unmodified')
LUA
}

sub file_locations {
    my ($self)  = @_;
    my $file    = "$self->{temporary}/file name.fish";
    my $literal = "$self->{temporary}/literal:4";
    write_file( $file,    "abcdefghij\n" x 25 );
    write_file( $literal, "literal filename\n" );
    $self->{env}{TEST_LOCATION} = $file;
    $self->{env}{TEST_LITERAL}  = $literal;
    run_script( $self, <<'LUA', [ 'file name.fish:17:5', "$file:3", "$file:999:999", $literal ] );
local file = vim.fn.resolve(vim.env.TEST_LOCATION)
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)), file, 'startup opens the file without its location suffix')
eq(vim.api.nvim_win_get_cursor(0), { 17, 4 }, 'line and column arguments are one-based')
eq(vim.g.aqsnow_orig_file, file, 'run-and-quit still recognizes the original file')
eq(vim.bo.filetype, 'fish', 'the real file gets its normal filetype')
vim.cmd.next()
eq(vim.api.nvim_win_get_cursor(0), { 3, 0 }, 'line-only arguments start at the first column')
vim.cmd.next()
eq(vim.api.nvim_win_get_cursor(0), { 25, 9 }, 'locations past the file end are clamped')
vim.cmd.next()
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)), vim.fn.resolve(vim.env.TEST_LITERAL),
    'an existing filename ending in a number is opened literally')
eq(vim.api.nvim_get_current_line(), 'literal filename', 'literal filename contents are preserved')
vim.cmd.first()
eq(vim.api.nvim_win_get_cursor(0), { 17, 4 }, 'revisiting a location reapplies its position')
for _, buffer in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local name = vim.fn.resolve(buffer.name)
    assert(name == file or name == vim.fn.resolve(vim.env.TEST_LITERAL),
        'location placeholders must not remain listed: ' .. buffer.name)
end
LUA
}

sub coalesced_config_reload {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local sources = vim.g.test_config_sources
for _, file in ipairs({ 'snippets.lua', 'gitcommit.lua' }) do
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
    copy_preserve( "$root/nvim/$_", "$copy/nvim/$_" ) for qw(init.vim nvim-pack-lock.json);
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

sub commit_title_prefix {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
vim.cmd.enew()
vim.api.nvim_buf_set_name(0, 'COMMIT_EDITMSG')
local helper = require('gitcommit')
local expansion
vim.snippet.expand = function(text) expansion = text end
local function title(entries)
    local lines = { '', '# Changes to be committed:' }
    for _, entry in ipairs(entries) do lines[#lines + 1] = '#\t' .. entry end
    lines[#lines + 1] = '#'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    expansion = nil
    helper.prefill_title()
    return expansion
end
eq(title({ 'modified: src/nvim/bufwrite.c', 'modified: test/functional/ex_cmds/cd_spec.lua' }),
    'src/nvim/bufwrite.c: ${1:desc}', 'unrelated files use the first path')
eq(title({ 'modified: test/functional/ex_cmds/cd_spec.lua', 'modified: src/nvim/bufwrite.c' }),
    'test/functional/ex_cmds/cd_spec.lua: ${1:desc}', 'fallback respects file order')
eq(title({ 'modified: nvim/init.vim' }),
    'nvim/init.vim: ${1:desc}', 'one file uses its full path')
eq(title({ 'modified: nvim/lua/one.lua', 'modified: nvim/lua/two.lua' }),
    'nvim/lua: ${1:desc}', 'a common directory takes priority')
eq(title({ 'modified: autoload/copilot.vim', 'modified: test/copilot_partial_accept.lua' }),
    'copilot: ${1:desc}', 'shared path words still take priority over the first file')
eq(title({ 'modified: index.html', 'modified: more/links.html' }),
    'html: ${1:desc}', 'file extensions count as shared path words')
eq(title({ 'modified: a/foo-bar.js', 'modified: b/foo-bar.test.js' }),
    'foo-bar: ${1:desc}', 'shared chunks retain their internal separators')
eq(title({ 'modified: a/foo_bar-one.lua', 'modified: b/foo_bar-two.lua' }),
    'foo_bar: ${1:desc}', 'splitting narrows only as far as the shared chunk')
eq(title({ 'modified: a/init.vim', 'modified: b/init.vim' }),
    'init.vim: ${1:desc}', 'whole shared path components take priority over their words')
eq(title({ 'modified: a/component.js', 'modified: b/component.test.js', 'modified: c/other.js' }),
    'component: ${1:desc}', 'longer shared chunks take priority over more frequent short words')
eq(title({ 'modified: a/alpha-beta.js', 'modified: b/alpha-beta.lua' }),
    'alpha-beta: ${1:desc}', 'compound words stay intact across different extensions')
eq(title({ 'modified: a/.config', 'modified: b/.config' }),
    '.config: ${1:desc}', 'whole components retain leading punctuation')
eq(title({ 'modified: a/alpha-bravo.js', 'modified: b/alpha.lua', 'modified: c/bravo.txt',
    'modified: d/bravo.css' }),
    'bravo: ${1:desc}', 'equally long chunks prefer more matching files')
eq(title({ 'modified: a/alpha-bravo.js', 'modified: b/alpha.lua', 'modified: c/bravo.txt' }),
    'alpha: ${1:desc}', 'equal length and frequency preserve the first occurrence')
eq(title({ 'renamed: old/location.lua -> nvim/lua/new.lua', 'modified: nvim/lua/other.lua' }),
    'nvim/lua: ${1:desc}', 'renames use the destination directory')
eq(title({ 'copied: old/location.lua -> other/new.lua' }),
    'other/new.lua: ${1:desc}', 'copies use the destination path')
LUA
}

sub diff_original_preserves_unsaved_changes {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'unsaved edit' })
local original = vim.api.nvim_get_current_buf()
vim.cmd.DiffOrig()
eq(vim.fn.readfile(vim.env.TEST_ORIGINAL), { 'original' }, 'comparing does not write the original file')
eq(vim.api.nvim_get_current_buf(), original, 'comparison returns to the original buffer')
assert(vim.bo.modified, 'the original edit remains unsaved')
local contents = {}
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    assert(vim.wo[win].diff, 'both comparison windows use diff mode')
    contents[#contents + 1] = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end
table.sort(contents, function(a, b) return a[1] < b[1] end)
eq(contents, { { 'original' }, { 'unsaved edit' } }, 'comparison shows disk contents beside unsaved edits')
LUA
}

sub terminal_shortcut_enters_terminal_mode {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
vim.o.shell = 'cat'
local entered
vim.api.nvim_create_autocmd('TermEnter', { once = true, callback = function()
    vim.schedule(function()
        entered = vim.fn.mode()
        vim.api.nvim_input('<C-]>')
    end)
end })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Leader>e', true, false, true), 'xt!', false)
eq(vim.bo.buftype, 'terminal', 'the shortcut opens a terminal buffer')
eq(entered, 't', 'the shortcut enters terminal mode')
eq(vim.fn.mode(), 'n', 'Ctrl-] returns to Normal mode')
LUA
}

sub terminal_editor_handoff {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local cwd = vim.fn.getcwd() .. '/shell cwd'
vim.fn.mkdir(cwd, 'p')
local name = "file's | % #.txt"
vim.fn.writefile({ 'first' }, cwd .. '/' .. name)
vim.fn.writefile({ 'second' }, cwd .. '/-leading.txt')
local init, socket = cwd .. '/init.lua', cwd .. '/server'
vim.fn.writefile({
    "vim.opt.runtimepath:prepend(vim.env.TEST_DOTFILES .. '/nvim')",
    'vim.o.splitbelow = true; vim.o.splitright = true',
    "vim.cmd.terminal('cat'); vim.cmd.startinsert()",
}, init)
local server = vim.system({ vim.v.progpath, '--headless', '-n', '-i', 'NONE', '-u', init, '--listen', socket })
vim.api.nvim_create_autocmd('VimLeavePre', { once = true, callback = function() server:kill(15) end })
assert(vim.wait(1000, function() return vim.uv.fs_stat(socket) ~= nil end), 'server starts')
local channel = vim.fn.sockconnect('pipe', socket, { rpc = true })
local function call(method, ...) return vim.rpcrequest(channel, method, ...) end
local function eval(expression) return call('nvim_eval', expression) end
assert(vim.wait(1000, function() return eval('&buftype') == 'terminal' end), 'server opens terminal')
assert(vim.wait(1000, function() return eval('mode()') == 't' end), 'server enters Terminal mode')
local terminal, terminal_win = call('nvim_get_current_buf'), call('nvim_get_current_win')
local job = eval('b:terminal_job_id')
local function open(...)
    local command = { 'fish', '--no-config', '-c',
        'source "$TEST_DOTFILES/fish/functions/nvim.fish"; nvim $argv', '--' }
    vim.list_extend(command, { ... })
    local result = vim.system(command, { cwd = cwd, env = { NVIM = socket } }):wait(3000)
    eq(result.code, 0, result.stderr)
end
open('--', name, '-leading.txt')
eq(eval('mode()'), 'n', 'opening a file leaves Terminal mode')
eq(call('nvim_get_current_win'), terminal_win, 'editing reuses the terminal window')
eq(call('nvim_buf_get_name', 0), cwd .. '/' .. name, 'relative paths use the shell cwd and stay literal')
eq(eval('argv()'), { cwd .. '/' .. name, cwd .. '/-leading.txt' }, 'all supplied files enter the argument list')
eq(eval('jobwait([' .. job .. '], 0)'), { -1 }, 'the hidden terminal process stays alive')
call('nvim_set_current_buf', terminal)
open('-o', '--', name)
local horizontal = call('nvim_get_current_win')
assert(call('nvim_win_get_position', horizontal)[1] > call('nvim_win_get_position', terminal_win)[1],
    'horizontal split opens below the terminal')
open('-O', '--', '-leading.txt')
local vertical = call('nvim_get_current_win')
assert(call('nvim_win_get_position', vertical)[2] > call('nvim_win_get_position', horizontal)[2],
    'vertical split opens to the right')
eq(#call('nvim_tabpage_list_wins', 0), 3, 'each split adds exactly one window')
open()
eq(call('nvim_buf_get_name', 0), '', 'bare nvim opens an unnamed buffer without waiting for stdin')
pcall(call, 'nvim_command', 'qa!')
server:wait(1000)
local command, nvim_cmd = nil, vim.api.nvim_cmd
vim.api.nvim_cmd = function(request) command = request end
require('terminal').open({ 'edit', cwd, 'scp://server/path' })
vim.api.nvim_cmd = nvim_cmd
eq(command.args, { 'scp://server/path' }, 'remote URLs are not prefixed with the local cwd')
LUA
}

sub directory_navigation {
    my ($self) = @_;
    my $directory = "$self->{temporary}/parent dir/child";
    make_path($directory);
    write_file( "$directory/file.txt", "content\n" );
    $self->{env}{TEST_NAV_DIRECTORY} = $directory;
    run_script( $self, <<'LUA' );
local directory = vim.env.TEST_NAV_DIRECTORY
local cwd = vim.fn.getcwd()
vim.cmd('edit ' .. vim.fn.fnameescape(directory .. '/file.txt'))
eq(vim.fn.getcwd(), cwd, 'opening a file does not change the working directory')
vim.cmd.Cdh()
eq(vim.fn.resolve(vim.fn.getcwd()), vim.fn.resolve(directory), 'Cdh changes to the current file parent')
vim.cmd.cd(cwd)
feed('-')
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)):gsub('/+$', ''), vim.fn.resolve(directory),
    'normal - opens the file parent with spaces')
eq(vim.bo.filetype, 'dirvish', 'local folders use Dirvish')
eq(vim.fn.getcwd(), cwd, 'browsing a directory preserves the selected working directory')
vim.cmd.Cdh()
eq(vim.fn.resolve(vim.fn.getcwd()), vim.fn.resolve(directory), 'Cdh changes to the displayed directory')
vim.cmd.cd(cwd)
vim.bo.filetype = 'directory'
vim.cmd.Cdh()
eq(vim.fn.resolve(vim.fn.getcwd()), vim.fn.resolve(directory), 'Cdh does not depend on the directory viewer')
vim.bo.filetype = 'dirvish'
vim.cmd.cd(cwd)
feed('-')
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)):gsub('/+$', ''), vim.fn.resolve(vim.fs.dirname(directory)),
    'directory - opens its parent')
vim.cmd('edit ' .. vim.fn.fnameescape(directory .. '/file.txt'))
feed('2-')
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)):gsub('/+$', ''), vim.fn.resolve(vim.fs.dirname(directory)),
    'Dirvish parent navigation supports counts')
vim.cmd('edit /')
feed('-')
eq(vim.api.nvim_buf_get_name(0), '/', 'parent navigation stays at the filesystem root')
vim.bo.filetype = 'netrw'
local mapping = vim.fn.maparg('q', 'n', false, true)
eq({ mapping.buffer, mapping.nowait }, { 1, 1 }, 'netrw q remains local and immediate')
vim.cmd.split()
feed('q')
eq(#vim.api.nvim_tabpage_list_wins(0), 1, 'netrw q closes the current window')
LUA
}

sub vidir_directory_arguments {
    my ($self) = @_;
    my $root = "$self->{temporary}/project";
    make_path( "$root/child space", "$root/target/deep" );
    write_file( "$root/file.txt",          'contents' );
    write_file( "$root/child space/entry", 'contents' );
    write_file( "$root/target/entry",      'contents' );
    symlink 'target/deep', "$root/link" or die $!;
    $self->{env}{TEST_VIDIR_ROOT} = $root;
    run_script( $self, <<'LUA' );
local root = vim.fn.resolve(vim.env.TEST_VIDIR_ROOT)
local function target(command, expected)
    vim.cmd(command)
    local directory = vim.bo.filetype == 'dirvish' and vim.api.nvim_buf_get_name(0) or vim.b.shdo_directory
    eq(vim.fs.normalize(directory), expected, 'Vidir selects the requested directory')
    if vim.bo.filetype == 'sh' then vim.cmd('buffer! ' .. vim.b.shdo_listing) end
end
vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/file.txt'))
target('Vidir', root)
vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/child space'))
target('Vidir', root .. '/child space')
vim.cmd.enew()
vim.cmd.cd(root)
target('Vidir', root)
target([[Vidir child\ space]], root .. '/child space')
target('Vidir link/..', root .. '/target')
local before, errors = vim.api.nvim_get_current_buf(), {}
vim.notify = function(message) errors[#errors + 1] = message end
vim.cmd('Vidir missing')
eq(vim.api.nvim_get_current_buf(), before, 'invalid arguments do not open a buffer')
eq(vim.fn.isdirectory(root .. '/missing'), 0, 'invalid arguments do not create a directory')
assert(#errors == 1, 'invalid arguments report an error')
assert(vim.tbl_contains(vim.fn.getcompletion('Vidir child', 'cmdline'), 'child space/'),
    'Vidir completes directories')
LUA
}

sub vidir_buffer_directory {
    my ($self) = @_;
    my $directory = "$self->{temporary}/rename's dir";
    make_path($directory);
    write_file( "$directory/entry", 'content' );
    $self->{env}{TEST_VIDIR_DIRECTORY} = $directory;
    run_script( $self, <<'LUA' );
local directory = vim.fn.resolve(vim.env.TEST_VIDIR_DIRECTORY)
local cwd = vim.fn.getcwd()
vim.cmd('Vidir ' .. vim.fn.fnameescape(directory))
local buffer, path = vim.api.nvim_get_current_buf(), vim.api.nvim_buf_get_name(0)
eq(vim.bo.filetype, 'sh', 'Shdo opens a shell script')
eq(#vim.api.nvim_tabpage_list_wins(0), 1, 'Shdo replaces the listing in the same window')
eq(vim.fn.filereadable(path), 1, 'Shdo creates its temporary file immediately')
eq(vim.b.shdo_directory, directory, 'the script remembers its target directory')
eq(vim.fn.getcwd(), cwd, 'opening the script preserves the selected working directory')
eq(vim.fn.haslocaldir(), 0, 'Shdo does not leave a window-local directory')
eq(vim.api.nvim_buf_get_lines(buffer, 0, 1, false), { 'set -eu' },
    'scripts stop on errors without needing a shebang')
assert(not vim.bo.undofile, 'temporary scripts do not create persistent undo files')
vim.cmd.write()
eq(vim.fn.filereadable(directory .. '/entry'), 1, 'writing only saves the script')
vim.api.nvim_set_current_buf(vim.b.shdo_listing)
eq(vim.bo.filetype, 'dirvish', 'leaving the script returns to Dirvish')
eq(vim.fn.getcwd(), cwd, 'the directory window retains the original working directory')
LUA
}

sub vidir_quotes_shell_directory {
    my ($self)    = @_;
    my $directory = "$self->{temporary}/project space's dir";
    my @names     = ( q{$cash}, q{quote's" name}, q{a;b}, 'plain' );
    make_path( $directory, "$self->{temporary}/bin" );
    write_file( "$directory/$_",             'contents' ) for @names;
    write_file( "$self->{temporary}/bin/mv", '#!' . perl_executable() . "\n" . <<'MOCK' );
use strict;
use warnings;
use Cwd qw(getcwd);
use JSON::PP;
open my $log, '>>', $ENV{TEST_MOVE_LOG} or die $!;
print {$log} encode_json({cwd => getcwd, args => \@ARGV}), "\n";
MOCK
    chmod 0755, "$self->{temporary}/bin/mv";
    local $self->{env}{PATH} = "$self->{temporary}/bin:$ENV{PATH}";
    $self->{env}{TEST_VIDIR_DIRECTORY} = $directory;
    $self->{env}{TEST_MOVE_LOG}        = "$self->{temporary}/moves";
    run_script( $self, <<'LUA' );
vim.cmd('Vidir ' .. vim.fn.fnameescape(vim.env.TEST_VIDIR_DIRECTORY))
require('shdo').run()
eq(vim.v.shell_error, 0, 'generated commands execute successfully')
eq(vim.bo.filetype, 'dirvish', 'successful execution returns to the listing')
LUA
    my @calls = map { decode_json($_) } split /\n/, read_file( $self->{env}{TEST_MOVE_LOG} );
    is_deeply(
        [ sort map { $_->{args}[2] } @calls ],
        [ sort @names ],
        'shell metacharacters remain literal filenames'
    );

    for my $call (@calls) {
        is( $call->{cwd}, absolute_path($directory), 'each command runs in the original directory' );
        is_deeply(
            $call->{args},
            [ '-v', '--', $call->{args}[2], $call->{args}[2] ],
            'each filename stays one argument'
        );
    }
}

sub vidir_refresh_after_success {
    my ($self) = @_;
    my $directory = "$self->{temporary}/rename's dir";
    make_path( $directory, "$self->{temporary}/bin" );
    write_file( "$directory/original",       "original\n" );
    write_file( "$directory/other",          "other\n" );
    write_file( "$self->{temporary}/bin/mv", '#!' . perl_executable() . "\n" . <<'MOCK' );
use strict;
use warnings;
@ARGV == 4 && $ARGV[0] eq '-v' && $ARGV[1] eq '--' or die 'unexpected mv arguments';
my ($from, $to) = @ARGV[2, 3];
exit 0 if $from eq $to;
rename $from, $to or die $!;
MOCK
    chmod 0755, "$self->{temporary}/bin/mv";
    local $self->{env}{PATH} = "$self->{temporary}/bin:$ENV{PATH}";
    $self->{env}{TEST_VIDIR_DIRECTORY} = $directory;
    run_script( $self, <<'LUA' );
local directory = vim.fn.resolve(vim.env.TEST_VIDIR_DIRECTORY)
vim.cmd('Vidir ' .. vim.fn.fnameescape(directory))
local buffer = vim.api.nvim_get_current_buf()
local commands = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
for i, command in ipairs(commands) do
    if command:find("'original'", 1, true) then commands[i] = "mv -v -- 'original' 'renamed'" end
end
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, commands)
vim.fn.setreg('a', 'named sentinel')
vim.fn.setreg('"', 'unnamed sentinel')
vim.cmd.write()
eq(vim.fn.filereadable(directory .. '/original'), 1, 'saving does not execute the script')
feed('<M-CR>')
eq(vim.v.shell_error, 0, 'Alt-Enter runs the saved commands')
eq(vim.fn.filereadable(directory .. '/renamed'), 1, 'the rename ran')
eq(vim.fn.filereadable(directory .. '/original'), 0, 'the old filename is gone')
eq(vim.bo.filetype, 'dirvish', 'successful execution returns to the listing')
assert(vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), directory .. '/renamed'),
    'successful execution refreshes the directory listing')
vim.cmd('Vidir ' .. vim.fn.fnameescape(directory))
local failed_buffer = vim.api.nvim_get_current_buf()
local failing = { 'set -eu', 'false', 'touch should-not-exist' }
vim.api.nvim_buf_set_lines(failed_buffer, 0, -1, false, failing)
feed('<M-CR>')
assert(vim.v.shell_error ~= 0, 'the failed command reports an error')
eq(vim.api.nvim_get_current_buf(), failed_buffer, 'failure keeps the script open')
eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), failing, 'failure preserves commands for correction')
eq(vim.fn.filereadable(directory .. '/should-not-exist'), 0, 'commands after the failure do not run')
eq(vim.fn.getreg('a'), 'named sentinel', 'named registers are preserved')
eq(vim.fn.getreg('"'), 'unnamed sentinel', 'the unnamed register is preserved')
LUA
}

sub shdo_preserves_windows_and_shell {
    my ($self) = @_;
    plan skip_all => 'fish is needed to test shell restoration' unless which('fish');
    my $directory = "$self->{temporary}/script directory";
    make_path($directory);
    write_file( "$directory/" . q{back\slash $cash}, 'content' );
    $self->{env}{TEST_SHDO_DIRECTORY} = $directory;
    run_script( $self, <<'LUA' );
local directory = vim.fn.resolve(vim.env.TEST_SHDO_DIRECTORY)
local other_window, other_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
local cwd, shell = vim.fn.getcwd(), vim.o.shell
vim.cmd.vsplit()
local window = vim.api.nvim_get_current_win()
vim.cmd('Dirvish ' .. vim.fn.fnameescape(directory))
local listing = vim.api.nvim_get_current_buf()
vim.o.shell = 'fish'
vim.cmd('%Shdo cp -- {} {}.copy')
eq(vim.o.shell, 'fish', 'Shdo restores the configured shell after generating commands')
eq(vim.api.nvim_get_current_win(), window, 'Shdo keeps the originating window')
eq(#vim.api.nvim_tabpage_list_wins(0), 2, 'Shdo does not leave an additional split')
eq(vim.api.nvim_win_get_buf(other_window), other_buffer, 'other windows keep their buffers')
eq(vim.fn.getcwd(), cwd, 'Shdo does not change the selected working directory')
eq(vim.fn.haslocaldir(), 0, 'Shdo does not leave a local working directory')
eq(vim.b.shdo_directory, directory, 'generic Shdo records the command directory')
eq(vim.api.nvim_buf_get_lines(0, 0, 1, false), { 'set -eu' }, 'generic Shdo receives the safety header')
assert(vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false),
    [[cp -- 'back\slash $cash' 'back\slash $cash'.copy]]),
    'commands use POSIX shell quoting: ' .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
feed('i<M-CR>')
eq(vim.v.shell_error, 0, 'Alt-Enter from Insert mode executes generic Shdo')
eq(vim.fn.filereadable(directory .. [[/back\slash $cash.copy]]), 1, 'the generated command uses the intended filename')
eq(vim.api.nvim_get_current_buf(), listing, 'success returns to the original listing')
vim.cmd('%Shdo true')
feed('Z!')
eq(vim.v.shell_error, 0, 'Z! runs through the same shell helper')
eq(vim.api.nvim_get_current_buf(), listing, 'Z! returns to the listing')
eq(vim.o.shell, 'fish', 'execution leaves the configured shell unchanged')
vim.o.shell = shell
LUA
}

sub gitstatus_dirvish_directory {
    my ($self) = @_;
    my $directory = "$self->{temporary}/directory repo";
    make_path("$directory/.git");
    $self->{env}{TEST_STATUS_DIRECTORY} = $directory;
    run_script( $self, <<'LUA' );
vim.api.nvim_exec_autocmds('User', { pattern = 'AqsnowGitStatusStop' })
package.loaded.gitstatus, package.loaded['gitstatus.state'] = nil, nil
local calls = {}
vim.system = function(_, options, callback)
    calls[#calls + 1] = options.cwd
    vim.schedule(function() callback({ code = 0, stdout = ' (directory-main)' }) end)
    return { is_closing = function() return true end }
end
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_STATUS_DIRECTORY))
eq(vim.bo.filetype, 'dirvish', 'fixture opens Dirvish')
assert(vim.bo.buftype ~= '', 'directory browser is a special buffer')
require('gitstatus').setup()
assert(vim.wait(1000, function() return vim.b.vcs_prompt == ' (directory-main)' end, 1),
    'Dirvish receives its repository status')
eq(#calls, 1, 'Dirvish requests status once')
eq(vim.fn.resolve(calls[1]), vim.fn.resolve(vim.env.TEST_STATUS_DIRECTORY),
    'status runs in the directory being browsed')
LUA
}

sub recording_mode_color {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
for _, register in ipairs({ 'a', 'b' }) do
    vim.cmd('normal! q' .. register)
    eq(vim.fn.reg_recording(), register, 'macro recording starts')
    eq(vim.api.nvim_get_hl(0, { name = 'ModeMsg' }).ctermfg, 4,
        'the first and subsequent recordings use the recording color')
    vim.cmd('normal! q')
    eq(vim.fn.reg_recording(), '', 'macro recording stops')
    eq(vim.api.nvim_get_hl(0, { name = 'ModeMsg' }).ctermfg, 2, 'stopping restores the normal color')
end
LUA
}

sub snippet_completion_reload {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
assert(package.loaded.snippets == nil, 'snippets begin unloaded')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
feed('itod<C-n><C-n><C-y><Esc>')
eq(vim.api.nvim_get_current_line(), 'TODO: desc', 'accepting snippet completion expands it')
vim.snippet.stop()
feed('<Esc>')
local count = #vim.api.nvim_get_autocmds({ group = 'aqsnow.snippets', event = 'CompleteDone' })
eq(count, 1, 'completion has one snippet handler')
vim.cmd('source ' .. vim.fn.fnameescape(vim.env.TEST_DOTFILES .. '/nvim/init.vim'))
assert(package.loaded.snippets == nil, 'reload leaves snippets lazy')
local helper = require('snippets')
local expansions, expand = 0, helper.expand
helper.expand = function()
    expansions = expansions + 1
    expand()
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed('itod<C-n><C-n><C-y><Esc>')
eq(vim.api.nvim_get_current_line(), 'TODO: desc', 'completion still expands after reload')
eq(expansions, 1, 'completion uses the current module exactly once')
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow.snippets', event = 'CompleteDone' }), count,
    'reload does not duplicate snippet completion handlers')
LUA
}

sub gitstatus_lifecycle {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local function timers()
    local ids = {}
    for _, timer in ipairs(vim.fn.timer_info()) do
        if timer['repeat'] == -1 then ids[#ids + 1] = timer.id end
    end
    return ids
end
local function handlers()
    return #vim.api.nvim_get_autocmds({ group = 'aqsnow.gitstatus' })
end
local helper = require('gitstatus')
local registered = handlers()
assert(registered > 0, 'Git status registers its handlers at startup')
eq(timers(), {}, 'Git status does not poll on a repeating timer')
helper.setup()
eq(handlers(), registered, 'repeated setup does not duplicate handlers')
local state = package.loaded['gitstatus.state']
vim.bo.buftype = 'nofile'
local target = vim.api.nvim_create_buf(true, false)
local directory = vim.fs.dirname(vim.env.TEST_ORIGINAL) .. '/write target'
vim.api.nvim_buf_set_name(target, directory .. '/file.txt')
for _, event in ipairs({ 'BufWritePost', 'FileWritePost' }) do
    state.pending[directory] = nil
    vim.api.nvim_exec_autocmds(event, { group = 'aqsnow.gitstatus', buffer = target })
    eq(state.pending[directory], true, event .. ' invalidates the written buffer directory')
end
vim.api.nvim_exec_autocmds('User', { pattern = 'AqsnowGitStatusStop' })
eq(handlers(), 0, 'stop removes its handlers')
helper.setup()
eq(handlers(), registered, 'setup restores its handlers once')
vim.cmd('source ' .. vim.fn.fnameescape(vim.env.TEST_DOTFILES .. '/nvim/init.vim'))
assert(package.loaded['gitstatus.state'] == state, 'config reload preserves cached Git status')
eq(timers(), {}, 'config reload does not introduce a polling timer')
eq(handlers(), registered, 'config reload leaves one set of handlers')
LUA
}

sub gitstatus_event_queue {
    my ($self) = @_;
    my $repo = "$self->{temporary}/status repo";
    for my $directory ( $repo, "$repo-other" ) {
        make_path("$directory/.git");
        write_file( "$directory/file.txt", "content\n" );
    }
    write_file( "$repo/.fish_git_prompt", 'old cached prompt' );
    make_path("$repo-other/nested");
    write_file( "$repo-other/nested/file.txt", "content\n" );
    $self->{env}{TEST_STATUS_REPO}  = $repo;
    $self->{env}{TEST_STATUS_OTHER} = "$repo-other";
    run_script( $self, <<'LUA' );
vim.api.nvim_exec_autocmds('User', { pattern = 'AqsnowGitStatusStop' })
package.loaded.gitstatus = nil
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_STATUS_REPO .. '/file.txt'))
local now, serial, calls, timers = 0, 0, {}, {}
vim.uv.hrtime = function() return now * 1e6 end
vim.fn.timer_start = function(delay, callback, options)
    assert(not options or options['repeat'] ~= -1, 'refresh timers must not repeat')
    serial = serial + 1
    timers[serial] = { due = now + delay, callback = callback }
    return serial
end
vim.fn.timer_stop = function(id) timers[id] = nil end
local system = vim.system
vim.system = function(command, options, callback)
    if command[4]:find('aqsnow_vcs_prompt_cache', 1, true) then
        local process = system(command, options)
        callback(process:wait())
        return process
    end
    calls[#calls + 1] = { time = now, cwd = options.cwd, env = options.env, done = callback }
    return { is_closing = function() return true end }
end
local function wait_for(check, message)
    assert(vim.wait(1000, check, 1), message)
end
local function timer_count()
    return vim.tbl_count(timers)
end
local function event(name)
    vim.api.nvim_exec_autocmds(name, { group = 'aqsnow.gitstatus' })
end
local function finish(index, result)
    calls[index].done(result or { code = 0, stdout = ' (result-' .. index .. ')' })
    local done = false
    vim.schedule(function() vim.schedule(function() done = true end) end)
    wait_for(function() return done end, 'process completion is handled')
end
local function disk_prompt(directory)
    local path = directory .. '/.fish_git_prompt'
    return vim.fn.filereadable(path) == 1 and table.concat(vim.fn.readfile(path, 'b'), '\n') or nil
end
local function advance(time)
    now = time
    for id, timer in pairs(vim.deepcopy(timers)) do
        if timer.due <= now then
            timers[id] = nil
            timer.callback(id)
        end
    end
end
local helper = require('gitstatus')
helper.setup()
wait_for(function() return #calls == 1 end, 'startup refreshes once')
eq(vim.fn.resolve(calls[1].cwd), vim.fn.resolve(vim.env.TEST_STATUS_REPO),
    'status is computed in the current repository')
eq(calls[1].env.TERM, nil, 'status inherits terminal capabilities for Fish colors')
local colored = '\27[32m (main)\27[0m'
finish(1, { code = 0, stdout = colored .. '\n' })
eq(disk_prompt(vim.env.TEST_STATUS_REPO), colored, 'live status preserves colors without a trailing newline')
local cache_inode = vim.uv.fs_stat(vim.env.TEST_STATUS_REPO .. '/.fish_git_prompt').ino
eq(timer_count(), 0, 'completion alone does not queue another refresh')

now = 100
for _, name in ipairs({ 'BufWritePost', 'FileReadPost', 'ShellCmdPost',
    'FocusGained', 'FocusLost', 'WinEnter', 'WinLeave' }) do event(name) end
wait_for(function() return timer_count() == 1 end, 'a burst queues one timer')
eq(#calls, 1, 'writes and focus changes respect the cooldown')
advance(1999)
eq(#calls, 1, 'the queued refresh waits for the full interval')
advance(2000)
wait_for(function() return #calls == 2 end, 'one trailing refresh handles the burst')
finish(2, { code = 0, stdout = colored })
eq(vim.uv.fs_stat(vim.env.TEST_STATUS_REPO .. '/.fish_git_prompt').ino, cache_inode,
    'unchanged status does not replace the cache file')
eq(timer_count(), 0, 'the burst leaves no recurring timer')
advance(9000)
eq(#calls, 2, 'an idle editor does not refresh')

event('BufReadPost')
wait_for(function() return #calls == 3 end, 'a later read refreshes immediately')
now = 9100
event('BufWritePost')
event('FocusLost')
advance(12000)
eq(#calls, 3, 'an in-flight request is never duplicated')
finish(3)
wait_for(function() return #calls == 4 end, 'a dirty in-flight request gets one follow-up')
eq(disk_prompt(vim.env.TEST_STATUS_REPO), colored, 'an obsolete result leaves the cache intact')
finish(4, { code = 1, stdout = 'failure output' })
eq(disk_prompt(vim.env.TEST_STATUS_REPO), colored, 'failed status leaves the cache intact')
eq(timer_count(), 0, 'the follow-up becomes idle after completion')

now = 12100
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_STATUS_OTHER .. '/nested/file.txt'))
wait_for(function() return timer_count() == 1 end, 'switching repositories queues one refresh')
eq(#calls, 4, 'another repository shares the same cooldown')
advance(14000)
wait_for(function() return #calls == 5 end, 'the queued refresh updates the new repository')
eq(vim.fn.resolve(calls[5].cwd), vim.fn.resolve(vim.env.TEST_STATUS_OTHER),
    'the queued refresh follows the current repository')
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_STATUS_REPO .. '/file.txt'))
finish(5)
eq(disk_prompt(vim.env.TEST_STATUS_OTHER), ' (result-5)',
    'a result is written to its original repository after switching buffers')
eq(disk_prompt(vim.env.TEST_STATUS_REPO), colored, 'another repository is not overwritten')
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_STATUS_OTHER .. '/nested/file.txt'))

now = 14100
vim.fn.mkdir(vim.env.TEST_STATUS_OTHER .. '/nested/.git')
vim.fn.writefile({ 'previous nested status' }, vim.env.TEST_STATUS_OTHER .. '/nested/.fish_git_prompt', 'b')
event('ShellCmdPost')
wait_for(function() return timer_count() == 1 end, 'repository changes queue a refresh')
advance(16000)
wait_for(function() return #calls == 6 end, 'a shell command discovers a newly created repository')
eq(vim.fn.resolve(calls[6].cwd), vim.fn.resolve(vim.env.TEST_STATUS_OTHER .. '/nested'),
    'repository lookup does not reuse the old parent root')
finish(6, { code = 0, stdout = '' })
eq(disk_prompt(vim.env.TEST_STATUS_OTHER .. '/nested'), 'previous nested status',
    'empty status leaves the cache intact')

now = 16100
vim.api.nvim_exec_autocmds('CmdlineLeave', { group = 'aqsnow.gitstatus', pattern = ':' })
eq(timer_count(), 0, 'a command waits until it has executed')
vim.api.nvim_exec_autocmds('SafeState', { group = 'aqsnow.gitstatus' })
wait_for(function() return timer_count() == 1 end, 'a completed command queues a refresh')
vim.api.nvim_exec_autocmds('CmdlineLeave', { group = 'aqsnow.gitstatus', pattern = ':' })
vim.api.nvim_exec_autocmds('User', { pattern = 'AqsnowGitStatusStop' })
eq(timer_count(), 0, 'stopping clears a queued refresh')
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow.gitstatus', event = 'SafeState' }), 0,
    'stopping clears deferred command refreshes')
advance(20000)
eq(#calls, 6, 'a stopped instance cannot refresh later')
helper.setup()
wait_for(function() return #calls == 7 end, 'restarting can request fresh status')
vim.api.nvim_exec_autocmds('User', { pattern = 'AqsnowGitStatusStop' })
finish(7)
eq(disk_prompt(vim.env.TEST_STATUS_OTHER .. '/nested'), 'previous nested status',
    'a stopped request leaves the cache intact')
for index = 2, #calls do
    assert(calls[index].time - calls[index - 1].time >= 2000, 'refresh starts stay two seconds apart')
end
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

sub markdown_checkbox_abbreviation {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
vim.cmd.enew()
vim.bo.filetype = 'markdown'
vim.schedule(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(' <Esc>', true, false, true), 't', false)
end)
vim.api.nvim_feedkeys('i[]', 'xt!', false)
eq(vim.api.nvim_get_current_line(), '- [ ] ', 'Markdown expands an empty bracket pair to a checkbox')
vim.cmd.enew({ bang = true })
vim.bo.filetype = 'text'
vim.schedule(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(' <Esc>', true, false, true), 't', false)
end)
vim.api.nvim_feedkeys('i[]', 'xt!', false)
eq(vim.api.nvim_get_current_line(), '[] ', 'other filetypes keep literal brackets')
LUA
}

sub find_files_quickfix {
    my ($self) = @_;
    plan skip_all => 'fd is needed to test filename search' unless which('fd');
    my $directory = "$self->{temporary}/find-files";
    make_path( map { "$directory/$_" } qw(nested src/deep ignored .git config empty target .hidden-dir) );
    symlink 'target', "$directory/linked" or die $!;
    for my $name (
        'top.lua',            '.hidden.lua',         'nested/child.lua',      'src/direct.lua',
        'src/deep/child.lua', 'odd name|part.lua',   'ignored/no.lua',        '.git/no.lua',
        'skip.lua',           'config/settings.txt', 'a+b.txt',               'aaab.txt',
        'literal[1].txt',     'literal1.txt',        '.hidden-dir/child.txt', 'Upper.LUA',
        'upper-other.lua'
      )
    {
        write_file( "$directory/$name", "contents\n" );
    }
    write_file( "$directory/.gitignore", "ignored/\n" );
    write_file( "$directory/.ignore",    "skip.lua\n" );
    $self->{env}{TEST_SEARCH} = $directory;
    run_script( $self, <<'LUA' );
local root = vim.fn.resolve(vim.env.TEST_SEARCH)
vim.cmd.cd(root)
local function search(pattern, command)
    local id = vim.fn.getqflist({ id = 0 }).id
    vim.cmd((command or 'Find') .. ' ' .. pattern)
    assert(vim.wait(3000, function() return vim.fn.getqflist({ id = 0 }).id ~= id end), 'Find finishes')
    eq(vim.bo.filetype, 'qf', 'Find opens quickfix')
    eq(vim.fn.resolve(vim.fn.getcwd()), root, 'quickfix retains the search directory')
    local paths = {}
    for _, item in ipairs(vim.fn.getqflist()) do
        eq({ item.lnum, item.col, item.valid }, { 1, 1, 1 }, 'each result opens at the first line')
        paths[#paths + 1] = vim.api.nvim_buf_get_name(item.bufnr):sub(#root + 2):gsub('/$', '')
    end
    table.sort(paths)
    return paths
end
eq(search('*.lua', 'Findg'), { '.hidden.lua', 'Upper.LUA', 'nested/child.lua', 'odd name|part.lua',
    'src/deep/child.lua', 'src/direct.lua', 'top.lua', 'upper-other.lua' },
    'lowercase globs include mixed-case names while preserving hidden and ignore rules')
eq(search('*.LUA', 'Findg'), { 'Upper.LUA' }, 'uppercase makes a glob case-sensitive')
eq(search('upper'), { 'Upper.LUA', 'upper-other.lua' }, 'lowercase regexes ignore case')
eq(search('Upper'), { 'Upper.LUA' }, 'uppercase regexes are case-sensitive')
eq(search('upper', 'Findf'), { 'Upper.LUA', 'upper-other.lua' }, 'lowercase fixed strings ignore case')
eq(search('UPPER', 'Findf'), {}, 'uppercase fixed strings are case-sensitive')
eq(search('^upper'), { 'Upper.LUA', 'upper-other.lua' }, 'anchored regexes match basenames')
eq(search('src/**/*.lua', 'Findg'), { 'src/deep/child.lua', 'src/direct.lua' },
    'relative globs match full paths and globstar matches zero or more directories')
eq(vim.fn.getqflist({ title = 0 }).title, 'Findg src/**/*.lua', 'glob titles retain the original pattern')
eq(search(root .. '/src/*.lua', 'Findg'), { 'src/direct.lua' }, 'absolute glob patterns remain absolute')
eq(search('config'), { 'config' }, 'bare words match directory names without matching child basenames')
eq(search('.hidden-dir', 'Findf'), { '.hidden-dir' }, 'hidden directories are searchable')
eq(search('ignored*', 'Findg'), {}, 'ignore rules exclude directories and their contents')
eq(search('**/.git/*', 'Findg'), {}, 'Git metadata directories stay excluded')
eq(search('linked'), { 'linked' }, 'symlink directories are searchable')
eq(search('odd*', 'Findg'), { 'odd name|part.lua' }, 'spaces and pipes remain literal filenames')
eq(search('odd name|part.lua', 'Findf'), { 'odd name|part.lua' }, 'literal spaces and bars remain command arguments')
eq(search([[^a\+b\.txt$]]), { 'a+b.txt' }, 'escaped plus is literal in the default regex mode')
eq(search([[^a+b\.txt$]]), { 'aaab.txt' }, 'plus is a quantifier in the default regex mode')
eq(search('[1]', 'Findf'), { 'literal[1].txt' }, 'fixed strings keep regex and glob metacharacters literal')
eq(search('src/direct.lua', 'Findf'), { 'src/direct.lua' }, 'fixed strings accept a literal existing path')
eq(search('missing*', 'Findg'), {}, 'no matches clears the new quickfix list')
vim.cmd.colder()
eq(vim.fn.getqflist({ title = 0 }).title, 'Findf src/direct.lua', 'previous searches remain in quickfix history')
local errors, id = {}, vim.fn.getqflist({ id = 0 }).id
vim.notify = function(message) errors[#errors + 1] = message end
for _, command in ipairs({ 'Find [', 'Findg [' }) do
    local count = #errors
    vim.cmd(command)
    assert(vim.wait(3000, function() return #errors > count end), 'invalid patterns report an error')
    eq(vim.fn.getqflist({ id = 0 }).id, id, 'invalid patterns preserve the quickfix list')
end
eq(search('^empty$'), { 'empty' }, 'regexes match directory names without display suffixes')
eq(search('empty'), { 'empty' }, 'empty directories are searchable')
vim.cmd.cfirst()
eq(vim.bo.filetype, 'dirvish', 'quickfix opens Dirvish')
LUA
}

sub find_files_async_results {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
vim.api.nvim_exec_autocmds('User', { pattern = 'AqsnowGitStatusStop' })
local calls, errors = {}, {}
vim.system = function(command, options, callback)
    local call = { command = command, options = options, callback = callback }
    call.process = { kill = function(_, signal) call.signal = signal end }
    calls[#calls + 1] = call
    return call.process
end
vim.notify = function(message) errors[#errors + 1] = message end
local find = require('find').run
local cwd = vim.fn.getcwd()
find('first')
find('second')
eq(calls[1].signal, 15, 'a newer Find cancels the old process')
eq(calls[2].command[#calls[2].command - 1], '--', 'patterns follow the option separator')
eq(calls[2].command[#calls[2].command], 'second', 'fd receives the regex pattern directly')
eq(calls[2].options.cwd, cwd, 'fd runs from the search directory')
vim.cmd.cd('/')
calls[2].callback({ code = 0, stdout = 'second.lua\n', stderr = '' })
calls[1].callback({ code = 0, stdout = 'first.lua\n', stderr = '' })
assert(vim.wait(3000, function() return vim.fn.getqflist({ title = 0 }).title == 'Find second' end))
eq(#vim.fn.getqflist(), 1, 'stale search results do not replace the latest list')
eq(vim.api.nvim_buf_get_name(vim.fn.getqflist()[1].bufnr), cwd .. '/second.lua', 'results use the search cwd')
local id = vim.fn.getqflist({ id = 0 }).id
find('[')
calls[3].callback({ code = 1, stdout = '', stderr = 'invalid regex\n' })
assert(vim.wait(3000, function() return #errors > 0 end))
eq(errors, { 'invalid regex' }, 'fd pattern errors are reported')
eq(vim.fn.getqflist({ id = 0 }).id, id, 'failed searches preserve the previous list')
find('src/**/*.lua', 'g')
assert(vim.tbl_contains(calls[4].command, '-g'), 'Findg enables fd glob matching')
assert(vim.tbl_contains(calls[4].command, '--full-path'), 'slash-containing patterns match full paths')
eq(calls[4].command[#calls[4].command], '**/src/**/*.lua', 'relative globs can match the absolute search path')
find('newer')
eq(calls[4].signal, 15, 'a new search cancels the active glob scan')
calls[5].callback({ code = 0, stdout = 'newer.txt\n', stderr = '' })
calls[4].callback({ code = 0, stdout = 'old.lua\n', stderr = '' })
assert(vim.wait(3000, function() return vim.fn.getqflist({ title = 0 }).title == 'Find newer' end))
eq(vim.fn.fnamemodify(vim.fn.bufname(vim.fn.getqflist()[1].bufnr), ':t'), 'newer.txt',
    'stale glob results do not replace a newer search')
find('[1]', 'F')
assert(vim.tbl_contains(calls[6].command, '-F'), 'Findf enables fd fixed-string matching')
calls[6].callback({ code = 0, stdout = 'literal[1].txt\n', stderr = '' })
assert(vim.wait(3000, function() return vim.fn.getqflist({ title = 0 }).title == 'Findf [1]' end))
eq(#calls, 6, 'each search launches one fd process without a separate filter')
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

calls = {}
feed('<M-o>')
eq(vim.fn.readfile(request), { 'recent' }, 'recent files request their own picker')
eq(calls, { 'wall', 'qall' }, 'recent files save before quitting')

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
feed('A<M-o>')
eq(vim.fn.readfile(request), { 'recent' }, 'Insert mode routes the recent picker request')
LUA
}

sub clipboard_mappings {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local clipboard = { {}, 'v' }
local function copy(lines, kind) clipboard = { lines, kind } end
local function paste() return clipboard end
vim.g.clipboard = {
    name = 'test', copy = { ['+'] = copy, ['*'] = copy },
    paste = { ['+'] = paste, ['*'] = paste }, cache_enabled = 0,
}
for _, case in ipairs({
    { 'Yw', 'alpha ', { '  alpha beta', 'next' } },
    { '<M-y>w', 'alpha ', { '  alpha beta', 'next' } },
    { 'YY', 'alpha beta', { '  alpha beta', 'next' } },
    { 'viwY', 'alpha', { '  alpha beta', 'next' } },
    { 'Dw', 'alpha ', { '  beta', 'next' } },
    { 'DD', 'alpha beta', { 'next' } },
    { 'viwD', 'alpha', { '   beta', 'next' } },
}) do
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '  alpha beta', 'next' })
    vim.api.nvim_win_set_cursor(0, { 1, 2 })
    vim.fn.setreg('+', 'sentinel')
    feed(case[1])
    eq(vim.fn.getreg('+'), case[2], case[1] .. ' copies to the clipboard without a newline')
    eq(vim.fn.getregtype('+'), 'v', case[1] .. ' uses the characterwise clipboard')
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), case[3], case[1] .. ' preserves or cuts the text')
    if case[1] == 'YY' then
        eq(vim.api.nvim_win_get_cursor(0), { 1, 2 }, 'YY restores the original cursor')
    end
end
LUA
}

sub copilot_word_mapping {
    my ($self) = @_;
    make_path("$self->{temporary}/autoload");
    my $autoload = "$self->{temporary}/autoload/copilot.vim";
    write_file( $autoload, <<'VIM' );
function! copilot#AcceptWord(fallback) abort
    let g:test_copilot_calls = get(g:, 'test_copilot_calls', 0) + 1
    let g:test_copilot_fallback = a:fallback
    return get(g:, 'test_copilot_word', '') ==# '' ? a:fallback : g:test_copilot_word
endfunction
VIM
    $self->{env}{TEST_COPILOT_AUTOLOAD} = $autoload;
    run_script( $self, <<'LUA' );
local mapping = vim.fn.maparg('<M-f>', 'i', false, true)
assert(mapping.rhs, 'Alt-f has an insert-mode mapping')
local function attempt(keys)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc x tail' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed(keys)
    return { vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0), vim.fn.mode(1) }
end
vim.cmd('iunmap <M-f>')
local native = attempt('iQ<M-f>x')
vim.fn.mapset('i', false, mapping)
eq(vim.fn.exists('*copilot#AcceptWord'), 0, 'the test begins without Copilot')
eq(attempt('iQ<M-f>x'), native, 'without Copilot, Alt-f retains its native behavior')

vim.cmd('iabbrev Q ZOO')
vim.cmd('iunmap <M-f>')
local abbreviated = attempt('iQ<M-f>x')
vim.fn.mapset('i', false, mapping)
eq(abbreviated[1], 'ZOOabc x tail', 'native Alt-f expands insert abbreviations')
eq(attempt('iQ<M-f>x'), abbreviated, 'without Copilot, Alt-f preserves abbreviation expansion')

vim.cmd('source ' .. vim.fn.fnameescape(vim.env.TEST_COPILOT_AUTOLOAD))
eq(attempt('iQ<M-f>x'), abbreviated, 'without a suggestion, Alt-f retains its native behavior')
eq(vim.g.test_copilot_fallback, vim.api.nvim_replace_termcodes('<C-]><Esc>f', true, false, true),
    'Copilot receives the native fallback')
vim.g.test_copilot_word = 'accepted'
eq(attempt('i<M-f><Esc>')[1], 'acceptedabc x tail', 'Alt-f inserts the word returned by Copilot')
eq(vim.g.test_copilot_calls, 2, 'each mapped keypress calls AcceptWord once')
LUA
}

sub copilot_line_mapping {
    my ($self) = @_;
    make_path("$self->{temporary}/autoload");
    my $autoload = "$self->{temporary}/autoload/copilot.vim";
    write_file( $autoload, <<'VIM' );
function! copilot#AcceptLine(fallback) abort
    let g:test_copilot_calls = get(g:, 'test_copilot_calls', 0) + 1
    let g:test_copilot_fallback = a:fallback
    return get(g:, 'test_copilot_line', '') ==# '' ? a:fallback : g:test_copilot_line
endfunction
VIM
    $self->{env}{TEST_COPILOT_AUTOLOAD} = $autoload;
    run_script( $self, <<'LUA' );
local function attempt()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc tail' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed('iQ<C-e>x<Esc>')
    return vim.api.nvim_get_current_line()
end
local function popup()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local states = {}
    _G.test_popup_open = function() vim.fn.complete(1, { 'alpha', 'alpine' }) end
    _G.test_popup_record = function()
        states[#states + 1] = { vim.fn.pumvisible(), vim.api.nvim_get_current_line() }
    end
    feed('ia<Cmd>lua test_popup_open()<CR><C-n><Cmd>lua test_popup_record()<CR>'
        .. '<C-e><Cmd>lua test_popup_record()<CR><Esc>')
    eq(states, { { 1, 'alpha' }, { 0, 'a' } }, 'Ctrl-e cancels completion without accepting it')
end
eq(vim.fn.exists('*copilot#AcceptLine'), 0, 'the test begins without Copilot')
eq(attempt(), 'Qabc tailx', 'without Copilot, Ctrl-e moves to the end of the line')
popup()
vim.cmd('source ' .. vim.fn.fnameescape(vim.env.TEST_COPILOT_AUTOLOAD))
eq(attempt(), 'Qabc tailx', 'without a suggestion, Ctrl-e moves to the end of the line')
eq(vim.g.test_copilot_fallback, vim.api.nvim_replace_termcodes('<C-o>$', true, false, true),
    'Copilot receives the end-of-line fallback')
vim.g.test_copilot_line = 'accepted line'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'tail' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed('i<C-e><Esc>')
eq(vim.api.nvim_get_current_line(), 'accepted linetail', 'Ctrl-e inserts the line returned by Copilot')
eq(vim.g.test_copilot_calls, 2, 'each non-popup keypress calls AcceptLine once')
popup()
eq(vim.g.test_copilot_calls, 2, 'completion cancellation takes priority over Copilot')
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
        startup_and_config_paths                => \&startup_and_config_paths,
        filename_display                        => \&filename_display,
        quickfix_directory_aliases              => \&quickfix_directory_aliases,
        quickfix_title_directory_aliases        => \&quickfix_title_directory_aliases,
        new_files_are_modified                  => \&new_files_are_modified,
        file_locations                          => \&file_locations,
        coalesced_config_reload                 => \&coalesced_config_reload,
        nested_module_reload                    => \&nested_module_reload,
        first_commit_summary_width              => \&first_commit_summary_width,
        commit_title_prefix                     => \&commit_title_prefix,
        diff_original_preserves_unsaved_changes => \&diff_original_preserves_unsaved_changes,
        directory_navigation                    => \&directory_navigation,
        terminal_shortcut_enters_terminal_mode  => \&terminal_shortcut_enters_terminal_mode,
        terminal_editor_handoff                 => \&terminal_editor_handoff,
        vidir_buffer_directory                  => \&vidir_buffer_directory,
        vidir_directory_arguments               => \&vidir_directory_arguments,
        vidir_quotes_shell_directory            => \&vidir_quotes_shell_directory,
        vidir_refresh_after_success             => \&vidir_refresh_after_success,
        shdo_preserves_windows_and_shell        => \&shdo_preserves_windows_and_shell,
        gitstatus_dirvish_directory             => \&gitstatus_dirvish_directory,
        recording_mode_color                    => \&recording_mode_color,
        snippet_completion_reload               => \&snippet_completion_reload,
        gitstatus_lifecycle                     => \&gitstatus_lifecycle,
        gitstatus_event_queue                   => \&gitstatus_event_queue,
        ripgrep_quickfix                        => \&ripgrep_quickfix,
        find_files_quickfix                     => \&find_files_quickfix,
        markdown_checkbox_abbreviation          => \&markdown_checkbox_abbreviation,
        find_files_async_results                => \&find_files_async_results,
        rendezvous_routes                       => \&rendezvous_routes,
        clipboard_mappings                      => \&clipboard_mappings,
        copilot_word_mapping                    => \&copilot_word_mapping,
        copilot_line_mapping                    => \&copilot_line_mapping,
        rendezvous_error_order                  => \&rendezvous_error_order,
    },
    \&setup
);
