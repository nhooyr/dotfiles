use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my $nvim = which('nvim') or die "Neovim is required\n";

sub setup {
    my ($self) = @_;
    my $tmp = tempdir( 'directory-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$tmp/home/project/lua/deep", "$tmp/home/project/empty" );
    $tmp          = absolute_path($tmp);
    $self->{root} = $tmp;
    $self->{odd}  = q{literal % # $HOME [x] 'file.txt};
    write_file( "$tmp/home/project/$self->{odd}",         "literal\n" );
    write_file( "$tmp/home/project/visible.txt",          "visible\n" );
    write_file( "$tmp/home/project/.hidden",              "hidden\n" );
    write_file( "$tmp/home/project/lua/child.txt",        "child\n" );
    write_file( "$tmp/home/project/lua/deep/not-yet.txt", "deep\n" );
    write_file( "$tmp/home/outside.txt",                  "outside\n" );
    symlink 'lua', "$tmp/home/project/link" or die $!;
    $self->{env} = {
        %ENV,
        HOME           => "$tmp/home",
        XDG_STATE_HOME => "$tmp/state",
        XDG_DATA_HOME  => "$tmp/data",
        XDG_CACHE_HOME => "$tmp/cache",
        NVIM_LOG_FILE  => "$tmp/nvim.log",
        AQSNOW_DIRALIS => 'HOME:TEST_PROJECT',
        TEST_PROJECT   => "$tmp/home/project",
        TEST_DOTFILES  => $root,
        TEST_ODD       => $self->{odd},
    };
}

sub run_script {
    my ( $self, $body ) = @_;
    my $script = "$self->{root}/test.lua";
    write_file( $script, <<'LUA' . $body );
vim.opt.runtimepath:prepend(vim.env.TEST_DOTFILES .. '/nvim')
vim.o.hidden = true
vim.o.swapfile = false
vim.o.shell = 'sh'
local directory = require('ls')
directory.configure()
directory.setup()
local project = vim.env.TEST_PROJECT
local function eq(actual, expected, message)
    assert(vim.deep_equal(actual, expected), message .. '\nexpected: '
        .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual))
end
local function lines() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end
local function select(path)
    local row = vim.fn.index(lines(), path) + 1
    assert(row > 0, 'missing path: ' .. path)
    vim.fn.cursor(row, 1)
    return row
end
LUA
    my $result = run_command(
        [ $nvim, '--headless', '-u', 'NONE', '-n', '-i', 'NONE', '-l', $script ],
        { cwd => $self->{root}, env => $self->{env}, timeout => 15 }
    );
    is( $result->{returncode}, 0, 'viewer scenario completes' );
    diag $result->{stderr} if $result->{returncode};
}

sub listing_and_inline_expansion {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local cwd = vim.fn.getcwd()
directory.open(vim.env.HOME)
select('~/project/')
directory.open(project)
eq(vim.bo.filetype, 'directory', 'the local viewer owns directory buffers')
eq(vim.fn.getcwd(), cwd, 'browsing does not change cwd')
local seen_file = false
for _, path in ipairs(lines()) do
    if path:sub(-1) == '/' then assert(not seen_file, 'directories precede files') else seen_file = true end
end
select('$TEST_PROJECT/.hidden')
local row = select('$TEST_PROJECT/lua/')
eq(directory.selected(row, row)[1]:gsub('/+$', ''), project .. '/lua', 'selection resolves aliases')
eq(vim.fn.synconcealed(row, 1)[1], 1, 'the alias prefix is concealed normally')
eq(vim.fn.synconcealed(row, #'$TEST_PROJECT/' + 1)[1], 0, 'the directory basename stays visible')
directory.expand_directory()
select('$TEST_PROJECT/lua/child.txt')
assert(not table.concat(lines(), '\n'):find('not-yet.txt', 1, true), 'expansion stops after one level')
select('$TEST_PROJECT/lua/')
local expanded = lines()
directory.expand_directory()
eq(lines(), expanded, 'repeated expansion does not duplicate children')
vim.api.nvim_buf_set_lines(0, -1, -1, false, { '/unrelated-file_!%' })
select('$TEST_PROJECT/link/')
directory.expand_directory()
select('$TEST_PROJECT/link/child.txt')
eq(lines()[#lines()], '/unrelated-file_!%', 'expansion preserves unrelated edited rows')
select('$TEST_PROJECT/' .. vim.env.TEST_ODD)
local before = lines()
directory.expand_directory()
eq(lines(), before, 'expanding a file does nothing')
LUA
}

sub hidden_toggle_and_file_opening {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local cwd = vim.fn.getcwd()
directory.open(project)
directory.toggle_hidden()
assert(not table.concat(lines(), '\n'):find('/.hidden', 1, true), 'gh hides dotfiles')
directory.toggle_hidden()
select('$TEST_PROJECT/.hidden')
directory.toggle_hidden()
directory.reload()
select('$TEST_PROJECT/.hidden')
local row = select('$TEST_PROJECT/' .. vim.env.TEST_ODD)
directory.open(directory.selected(row, row)[1])
eq(vim.api.nvim_buf_get_name(0), project .. '/' .. vim.env.TEST_ODD, 'opening keeps filename characters literal')
eq(vim.fn.getline(1), 'literal', 'the intended file is opened')
eq(vim.fn.getcwd(), cwd, 'opening a file preserves cwd')
directory.parent(1)
eq(vim.bo.filetype, 'directory', 'parent navigation opens the viewer')
eq(vim.b.directory.path, project, 'parent navigation returns to the file parent')
local old_mapping = vim.fn.maparg('R', 'n', false, true).callback
package.loaded.ls = nil
directory = require('ls')
directory.configure()
directory.setup()
assert(vim.fn.maparg('R', 'n', false, true).callback ~= old_mapping, 'reload refreshes existing viewer mappings')
directory.open(project .. '/' .. vim.env.TEST_ODD)
vim.wo.wrap, vim.wo.conceallevel = true, 0
directory.open(project)
directory.open(project .. '/' .. vim.env.TEST_ODD, 'split')
eq({ vim.wo.wrap, vim.wo.conceallevel }, { true, 0 }, 'file splits inherit the normal window options')
vim.cmd('wincmd p')
eq({ vim.wo.wrap, vim.wo.conceallevel }, { false, 2 }, 'the directory window retains its display options')
LUA
}

sub shdo_bindings_select_all_or_visual_lines {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
require('shdo').setup()
directory.open(project)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '$TEST_PROJECT/visible.txt', '$TEST_PROJECT/lua/child.txt' })
local listing = vim.api.nvim_get_current_buf()
feed('!')
eq(vim.bo.filetype, 'sh', 'normal ! immediately opens a Shdo script')
eq(#lines(), 5, 'normal ! includes the entire listing')
eq(lines()[1], '#!/bin/sh', 'scripts have a POSIX shebang')
eq(lines()[4], 'mv -v -- $TEST_PROJECT/lua/child.txt $TEST_PROJECT/lua/child.txt', 'the default command moves each path')
vim.api.nvim_set_current_buf(listing)
vim.fn.cursor(1, 1)
feed('V!')
eq(vim.bo.filetype, 'sh', 'visual ! immediately opens a Shdo script')
eq(#lines(), 4, 'visual ! includes only selected entries')
eq(lines()[3], 'cd -- $TEST_PROJECT', 'scripts change to their directory using aliases')
eq(lines()[4], 'mv -v -- visible.txt visible.txt', 'simple relative filenames need no quotes')
vim.api.nvim_set_current_buf(listing)
eq(vim.fn.maparg([[\!]], 'n'), '!', 'Leader-! retains the normal filter operator')
eq(vim.fn.maparg([[\!]], 'x'), '!', 'Leader-! retains the visual filter operator')
LUA
}

sub shdo_quotes_relative_and_aliased_paths {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local shdo = require('shdo')
shdo.setup()
directory.open(project)
local listing = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '$TEST_PROJECT/' .. vim.env.TEST_ODD, '$TEST_PROJECT/visible.txt' })
shdo.generate({ args = 'test -f {}', line1 = 1, line2 = 2, bang = false })
eq(vim.b.shdo_directory, project, 'one-directory scripts use their shared parent')
assert(table.concat(lines(), '\n'):find(vim.fn.shellescape(vim.env.TEST_ODD), 1, true), 'relative names are shell quoted')
shdo.run()
eq(vim.api.nvim_get_current_buf(), listing, 'success returns to the original listing')
local cwd = vim.fn.getcwd()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '$TEST_PROJECT/' .. vim.env.TEST_ODD, '~/outside.txt' })
shdo.generate({ args = 'test -f {}', line1 = 1, line2 = 2, bang = false })
eq(vim.b.shdo_directory, cwd, 'mixed-directory scripts preserve the starting cwd')
local script = table.concat(lines(), '\n')
assert(script:find('$TEST_PROJECT/', 1, true), 'mixed-directory project paths retain their alias')
assert(script:find('~/', 1, true), 'mixed-directory home paths retain tilde abbreviation')
assert(script:find('test -f ~/outside.txt', 1, true), 'simple home paths need no quotes')
shdo.run()
eq(vim.api.nvim_get_current_buf(), listing, 'aliased commands execute and return to the listing')
local spaced = project .. '/space dir'
vim.fn.mkdir(spaced)
vim.fn.writefile({}, spaced .. '/~')
vim.fn.writefile({}, spaced .. '/$HOME')
vim.env.TEST_SPACED = spaced
vim.env.AQSNOW_DIRALIS = vim.env.AQSNOW_DIRALIS .. ':TEST_SPACED'
package.loaded.dirali = nil
vim.api.nvim_buf_set_lines(0, 0, -1, false, { spaced .. '/~', spaced .. '/$HOME' })
shdo.generate({ args = 'test -f {}', line1 = 1, line2 = 2, bang = false })
eq(lines()[3], 'cd -- "$TEST_SPACED"', 'alias values containing spaces are quoted')
eq(lines()[4], "test -f '$HOME'", 'literal variable-looking filenames remain literal')
eq(lines()[5], "test -f '~'", 'literal tilde filenames remain literal')
shdo.run()
eq(vim.v.shell_error, 0, 'the standalone script handles quoted aliases and literal filenames')
LUA
}

sub shdo_keeps_scripts_in_jump_history {
    my ($self) = @_;
    run_script( $self, <<'LUA' );
local shdo = require('shdo')
directory.open(project)
local listing = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '$TEST_PROJECT/visible.txt' })
shdo.generate({ args = 'test -f {}', line1 = 1, line2 = 1, bang = false })
local script, commands = vim.api.nvim_get_current_buf(), lines()
shdo.run()
eq(vim.api.nvim_get_current_buf(), listing, 'success returns to the listing')
assert(vim.api.nvim_buf_is_loaded(script), 'the executed script stays loaded')
feed('<C-o>')
eq(vim.api.nvim_get_current_buf(), script, 'Ctrl-O returns to the executed script')
eq(lines(), commands, 'the executed script keeps its commands')
LUA
}

run_cases(
    {
        listing_and_inline_expansion             => \&listing_and_inline_expansion,
        hidden_toggle_and_file_opening           => \&hidden_toggle_and_file_opening,
        shdo_bindings_select_all_or_visual_lines => \&shdo_bindings_select_all_or_visual_lines,
        shdo_quotes_relative_and_aliased_paths   => \&shdo_quotes_relative_and_aliased_paths,
        shdo_keeps_scripts_in_jump_history       => \&shdo_keeps_scripts_in_jump_history,
    },
    \&setup
);
