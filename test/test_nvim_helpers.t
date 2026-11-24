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
assert(package.loaded.rendezvous == nil, 'rendezvous stays unloaded at startup')
assert(package.loaded.vidir == nil, 'vidir stays unloaded at startup')
assert(package.loaded.snips == nil, 'snippets stay unloaded until completion or expansion')
assert(package.loaded.fileline == nil, 'file locations stay unloaded for ordinary files')
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

sub directory_navigation {
    my ($self) = @_;
    my $directory = "$self->{temporary}/parent dir/child";
    make_path($directory);
    write_file( "$directory/file.txt", "content\n" );
    $self->{env}{TEST_NAV_DIRECTORY} = $directory;
    run_script( $self, <<'LUA' );
local directory = vim.env.TEST_NAV_DIRECTORY
vim.cmd('edit ' .. vim.fn.fnameescape(directory .. '/file.txt'))
feed('-')
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)):gsub('/+$', ''), vim.fn.resolve(directory),
    'normal - opens the file parent with spaces')
eq(vim.bo.filetype, 'directory', 'local folders use the native directory browser')
feed('-')
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)):gsub('/+$', ''), vim.fn.resolve(vim.fs.dirname(directory)),
    'directory - opens its parent')
vim.cmd('edit ' .. vim.fn.fnameescape(directory .. '/file.txt'))
feed('2-')
eq(vim.fn.resolve(vim.api.nvim_buf_get_name(0)):gsub('/+$', ''), vim.fn.resolve(vim.fs.dirname(directory)),
    'native parent navigation supports counts')
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

sub vidir_buffer_directory {
    my ($self) = @_;
    my $directory = "$self->{temporary}/rename dir";
    make_path( $directory, "$self->{temporary}/bin" );
    write_file( "$directory/entry",           "content\n" );
    write_file( "$self->{temporary}/bin/gls", "#!/bin/sh\nprintf '%s\\n' entry\n" );
    chmod 0755, "$self->{temporary}/bin/gls";
    local $self->{env}{PATH} = "$self->{temporary}/bin:$ENV{PATH}";
    $self->{env}{TEST_VIDIR_DIRECTORY} = $directory;
    run_script( $self, <<'LUA' );
local directory = vim.env.TEST_VIDIR_DIRECTORY
vim.cmd('cd ' .. vim.fn.fnameescape(directory))
vim.cmd.Vidir()
local buffer = vim.api.nvim_get_current_buf()
eq(vim.fn.resolve(vim.b.vidir_dir), vim.fn.resolve(directory), 'Vidir records its directory')
eq(vim.fn.resolve(vim.fn.getcwd()), vim.fn.resolve(directory), 'Vidir starts in its directory')
eq(vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
    { '#!/bin/sh', 'set -eu', "mv -v -- 'entry' 'entry'" }, 'Vidir retains its existing command list')
for _ = 1, 3 do
    vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_ORIGINAL))
    eq(vim.fn.resolve(vim.fn.getcwd()), vim.fn.resolve(vim.fs.dirname(vim.env.TEST_ORIGINAL)),
        'ordinary files use their own directory')
    vim.cmd.buffer(buffer)
    eq(vim.fn.resolve(vim.fn.getcwd()), vim.fn.resolve(directory), 'returning to Vidir restores its directory')
end
LUA
}

sub vidir_refresh_after_success {
    my ($self)    = @_;
    my $directory = "$self->{temporary}/rename dir";
    my $bin       = "$self->{temporary}/bin";
    make_path( $directory, $bin );
    write_file( "$directory/original", "original\n" );
    write_file( "$directory/other",    "other\n" );
    write_file( "$bin/gls",            '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
my $path = $ARGV[-1] =~ /^-/ ? '.' : $ARGV[-1];
opendir my $directory, $path or die $!;
print "$_\n" for sort grep { $_ ne '.' && $_ ne '..' } readdir $directory;
PERL
    write_file( "$bin/mv", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
@ARGV == 4 && $ARGV[0] eq '-v' && $ARGV[1] eq '--' or die 'unexpected mv arguments';
my ( $from, $to ) = @ARGV[ 2, 3 ];
exit 0 if $from eq $to;
rename $from, $to or die $!;
PERL
    chmod 0755, "$bin/gls", "$bin/mv";
    local $self->{env}{PATH} = "$bin:$ENV{PATH}";
    $self->{env}{TEST_VIDIR_DIRECTORY} = $directory;
    run_script( $self, <<'LUA' );
local directory = vim.env.TEST_VIDIR_DIRECTORY
vim.cmd('cd ' .. vim.fn.fnameescape(directory))
vim.cmd.Vidir()
local buffer = vim.api.nvim_get_current_buf()
local function lines() return vim.api.nvim_buf_get_lines(buffer, 0, -1, false) end
local function rename_command(from, to)
    local commands, found = lines(), false
    for i, command in ipairs(commands) do
        if command == "mv -v -- '" .. from .. "' '" .. from .. "'" then
            commands[i], found = "mv -v -- '" .. from .. "' '" .. to .. "'", true
        end
    end
    assert(found, 'the file has a generated rename command')
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, commands)
end
vim.fn.setreg('a', 'named sentinel')
vim.fn.setreg('"', 'unnamed sentinel')
rename_command('original', 'renamed')
local pending = lines()
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_ORIGINAL))
vim.cmd('cd ' .. vim.fn.fnameescape(directory))
vim.cmd.Vidir()
eq(vim.api.nvim_get_current_buf(), buffer, 'reentry keeps the existing rename buffer')
eq(lines(), pending, 'reentry preserves unapplied edits')
assert(vim.bo.modified, 'unapplied commands remain modified')
eq(vim.fn.filereadable(directory .. '/original'), 1, 'reentry does not execute commands')
vim.cmd.write()
eq(vim.fn.filereadable(directory .. '/renamed'), 1, 'the requested rename ran')
eq(vim.fn.filereadable(directory .. '/original'), 0, 'the old filename is gone')
assert(vim.tbl_contains(lines(), "mv -v -- 'renamed' 'renamed'"), 'success refreshes the command list')
assert(not vim.bo.modified, 'the refreshed command list is unmodified')
vim.cmd.write()
eq(vim.v.shell_error, 0, 'applying the refreshed list does not retry the old source')
rename_command('other', 'second')
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_ORIGINAL))
vim.cmd.wall()
eq(vim.fn.resolve(vim.fn.getcwd()), vim.fn.resolve(vim.fs.dirname(vim.env.TEST_ORIGINAL)),
    'wall restores the visible buffer directory')
eq(vim.fn.filereadable(directory .. '/second'), 1, 'wall executes commands in the rename directory')
assert(vim.tbl_contains(lines(), "mv -v -- 'second' 'second'"), 'wall refreshes the rename directory')
vim.cmd.buffer(buffer)
local failing = { '#!/bin/sh', 'set -eu', 'false', "mv -v -- 'renamed' 'never'" }
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, failing)
vim.cmd.write()
assert(vim.v.shell_error ~= 0, 'the failed command reports an error')
eq(lines(), failing, 'failed commands remain available for correction')
assert(vim.bo.modified, 'the failed command list stays modified')
eq(vim.fn.filereadable(directory .. '/never'), 0, 'commands after the failure do not run')
eq(vim.fn.getreg('a'), 'named sentinel', 'named registers are preserved')
eq(vim.fn.getreg('"'), 'unnamed sentinel', 'the unnamed register is preserved')
LUA
}

sub gitstatus_native_directory {
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
eq(vim.bo.filetype, 'directory', 'fixture opens the native directory browser')
assert(vim.bo.buftype ~= '', 'directory browser is a special buffer')
require('gitstatus').setup()
assert(vim.wait(1000, function() return vim.b.vcs_prompt == ' (directory-main)' end, 1),
    'native directory receives its repository status')
eq(#calls, 1, 'native directory requests status once')
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
assert(package.loaded.snips == nil, 'snippets begin unloaded')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
feed('itod<C-n><C-n><C-y><Esc>')
eq(vim.api.nvim_get_current_line(), 'TODO: desc', 'accepting snippet completion expands it')
vim.snippet.stop()
feed('<Esc>')
local count = #vim.api.nvim_get_autocmds({ group = 'aqsnow.snips', event = 'CompleteDone' })
eq(count, 1, 'completion has one snippet handler')
vim.cmd('source ' .. vim.fn.fnameescape(vim.env.TEST_DOTFILES .. '/nvim/init.vim'))
assert(package.loaded.snips == nil, 'reload leaves snippets lazy')
local helper = require('snips')
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
eq(#vim.api.nvim_get_autocmds({ group = 'aqsnow.snips', event = 'CompleteDone' }), count,
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
vim.system = function(_, options, callback)
    calls[#calls + 1] = { time = now, cwd = options.cwd, done = callback }
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
local function finish(index)
    calls[index].done({ code = 0, stdout = ' (result-' .. index .. ')' })
    local done = false
    vim.schedule(function() done = true end)
    wait_for(function() return done end, 'process completion is handled')
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
finish(1)
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
finish(2)
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
finish(4)
eq(timer_count(), 0, 'the follow-up becomes idle after completion')

now = 12100
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_STATUS_OTHER .. '/nested/file.txt'))
wait_for(function() return timer_count() == 1 end, 'switching repositories queues one refresh')
eq(#calls, 4, 'another repository shares the same cooldown')
advance(14000)
wait_for(function() return #calls == 5 end, 'the queued refresh updates the new repository')
eq(vim.fn.resolve(calls[5].cwd), vim.fn.resolve(vim.env.TEST_STATUS_OTHER),
    'the queued refresh follows the current repository')
finish(5)

now = 14100
vim.fn.mkdir(vim.env.TEST_STATUS_OTHER .. '/nested/.git')
event('ShellCmdPost')
wait_for(function() return timer_count() == 1 end, 'repository changes queue a refresh')
advance(16000)
wait_for(function() return #calls == 6 end, 'a shell command discovers a newly created repository')
eq(vim.fn.resolve(calls[6].cwd), vim.fn.resolve(vim.env.TEST_STATUS_OTHER .. '/nested'),
    'repository lookup does not reuse the old parent root')
finish(6)

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
        file_locations                          => \&file_locations,
        coalesced_config_reload                 => \&coalesced_config_reload,
        nested_module_reload                    => \&nested_module_reload,
        first_commit_summary_width              => \&first_commit_summary_width,
        commit_title_prefix                     => \&commit_title_prefix,
        diff_original_preserves_unsaved_changes => \&diff_original_preserves_unsaved_changes,
        directory_navigation                    => \&directory_navigation,
        vidir_buffer_directory                  => \&vidir_buffer_directory,
        vidir_refresh_after_success             => \&vidir_refresh_after_success,
        gitstatus_native_directory              => \&gitstatus_native_directory,
        recording_mode_color                    => \&recording_mode_color,
        snippet_completion_reload               => \&snippet_completion_reload,
        gitstatus_lifecycle                     => \&gitstatus_lifecycle,
        gitstatus_event_queue                   => \&gitstatus_event_queue,
        ripgrep_quickfix                        => \&ripgrep_quickfix,
        rendezvous_routes                       => \&rendezvous_routes,
        copilot_word_mapping                    => \&copilot_word_mapping,
        copilot_line_mapping                    => \&copilot_line_mapping,
        rendezvous_error_order                  => \&rendezvous_error_order,
    },
    \&setup
);
