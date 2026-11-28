use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub check_cache {
    my ( $replace, $linked ) = @_;
    my $temporary     = tempdir( 'nvim-cache-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $git_directory = $linked ? "$temporary/gitdir" : "$temporary/repo/.git";
    make_path( "$temporary/repo", $git_directory );
    write_file( "$temporary/repo/.git", "gitdir: ../gitdir\n" ) if $linked;
    write_file( "$temporary/repo/file", 'content' );
    write_file( "$temporary/check.lua", <<'LUA' );
vim.opt.runtimepath:prepend(vim.env.TEST_DOTFILES .. '/nvim')
vim.env.dotfiles = vim.env.TEST_DOTFILES
vim.cmd.edit(vim.env.TEST_REPO .. '/file')
local system, finished = vim.system, false
local function replace_repository()
    assert(vim.uv.fs_rename(vim.env.TEST_GIT_DIRECTORY, vim.env.TEST_GIT_DIRECTORY .. '.old'))
    vim.fn.mkdir(vim.env.TEST_GIT_DIRECTORY)
    vim.fn.writefile({ 'replacement' }, vim.env.TEST_REPO .. '/.fish_git_prompt', 'b')
end
vim.system = function(args, options, callback)
    if args[4]:find('git_prompt_cache', 1, true) then
        if vim.env.TEST_REPLACE == '1' then replace_repository() end
        return system(args, options, function(result)
            local expected = vim.env.TEST_REPLACE == '1' and 75 or 0
            assert(result.code == expected, result.stderr)
            callback(result)
            finished = true
        end)
    end
    assert(args[4]:find('/fish/functions/git_prompt.fish', 1, true), 'load the standalone Git prompt')
    vim.schedule(function()
        if vim.env.TEST_REPLACE == '2' then replace_repository() end
        callback({ code = 0, stdout = ' (old)' })
        if vim.env.TEST_REPLACE == '2' then vim.schedule(function() finished = true end) end
    end)
    return { is_closing = function() return true end }
end
require('gitprompt').setup()
assert(vim.wait(3000, function() return finished end), 'cache writer finishes')
local expected = vim.env.TEST_REPLACE ~= '0' and 'replacement' or ' (old)'
assert(table.concat(vim.fn.readfile(vim.env.TEST_REPO .. '/.fish_git_prompt', 'b')) == expected)
if vim.env.TEST_REPLACE ~= '0' then
    local cached = package.loaded['gitprompt.state'].prompts[vim.fn.resolve(vim.env.TEST_REPO)]
    assert(cached.prompt ~= ' (old)', 'a replaced repository rejects the in-memory result')
    assert(vim.b.vcs_prompt ~= ' (old)', 'a replaced repository never displays the old result')
end
vim.cmd.qa()
LUA
    my $result = run_command(
        [ which('nvim'), '--headless', '-u', 'NONE', '-n', '-i', 'NONE', '-l', "$temporary/check.lua" ],
        {
            env => {
                %ENV,
                TEST_DOTFILES      => $root,
                TEST_REPO          => "$temporary/repo",
                TEST_GIT_DIRECTORY => $git_directory,
                TEST_REPLACE       => $replace,
                NVIM_LOG_FILE      => "$temporary/nvim.log"
            },
            timeout => 10
        }
    );
    is( $result->{returncode}, 0, $result->{stderr} );
}

run_cases(
    {
        matching_repository_accepts_cache           => sub { check_cache(0) },
        replaced_repository_rejects_cache           => sub { check_cache(1) },
        replaced_repository_rejects_inflight_status => sub { check_cache(2) },
        matching_linked_repository_accepts_cache    => sub { check_cache( 0, 1 ) },
        replaced_gitdir_rejects_cache               => sub { check_cache( 1, 1 ) },
        replaced_gitdir_rejects_inflight_status     => sub { check_cache( 2, 1 ) },
    }
);
