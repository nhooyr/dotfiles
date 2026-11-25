use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub check_cache {
    my ($replace) = @_;
    my $temporary = tempdir( 'nvim-cache-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path("$temporary/repo/.git");
    write_file( "$temporary/repo/file", 'content' );
    write_file( "$temporary/check.lua", <<'LUA' );
vim.opt.runtimepath:prepend(vim.env.TEST_DOTFILES .. '/nvim')
vim.env.dotfiles = vim.env.TEST_DOTFILES
vim.cmd.edit(vim.env.TEST_REPO .. '/file')
local system, finished = vim.system, false
vim.system = function(args, options, callback)
    if args[4]:find('aqsnow_vcs_prompt_cache', 1, true) then
        if vim.env.TEST_REPLACE == '1' then
            assert(vim.uv.fs_rename(vim.env.TEST_REPO .. '/.git', vim.env.TEST_REPO .. '/old.git'))
            vim.fn.mkdir(vim.env.TEST_REPO .. '/.git')
            vim.fn.writefile({ 'replacement' }, vim.env.TEST_REPO .. '/.fish_git_prompt', 'b')
        end
        return system(args, options, function(result)
            assert(result.code == 0, result.stderr)
            callback(result)
            finished = true
        end)
    end
    vim.schedule(function() callback({ code = 0, stdout = ' (old)' }) end)
    return { is_closing = function() return true end }
end
require('gitstatus').setup()
assert(vim.wait(3000, function() return finished end), 'cache writer finishes')
local expected = vim.env.TEST_REPLACE == '1' and 'replacement' or ' (old)'
assert(table.concat(vim.fn.readfile(vim.env.TEST_REPO .. '/.fish_git_prompt', 'b')) == expected)
vim.cmd.qa()
LUA
    my $result = run_command(
        [ which('nvim'), '--headless', '-u', 'NONE', '-n', '-i', 'NONE', '-l', "$temporary/check.lua" ],
        {
            env => {
                %ENV,
                TEST_DOTFILES => $root,
                TEST_REPO     => "$temporary/repo",
                TEST_REPLACE  => $replace,
                NVIM_LOG_FILE => "$temporary/nvim.log"
            },
            timeout => 10
        }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
}

run_cases(
    {
        matching_repository_accepts_cache => sub { check_cache(0) },
        replaced_repository_rejects_cache => sub { check_cache(1) },
    }
);
