use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my $nvim = which('nvim');

sub setup {
    my ($self) = @_;
    plan skip_all => 'Neovim is needed to test the Git editor' unless $nvim;
    $self->{temporary} = tempdir( 'nvim-commit-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{repo}      = "$self->{temporary}/repo";
    make_path( $self->{repo}, "$self->{temporary}/home" );
    my %env = %ENV;
    delete @env{ grep { /^GIT_/ } keys %env };
    $self->{env} = {
        %env,
        HOME                => "$self->{temporary}/home",
        XDG_CONFIG_HOME     => "$self->{temporary}/config",
        XDG_DATA_HOME       => "$self->{temporary}/data",
        XDG_STATE_HOME      => "$self->{temporary}/state",
        XDG_CACHE_HOME      => "$self->{temporary}/cache",
        NVIM_LOG_FILE       => "$self->{temporary}/nvim.log",
        AQSNOW_DIRALIS      => 'HOME',
        dotfiles            => $root,
        TEST_DOTFILES       => $root,
        TEST_NVIM           => $nvim,
        TEST_INIT           => "$self->{temporary}/init.vim",
        TEST_SNAPSHOT       => "$self->{temporary}/snapshot.json",
        GIT_EDITOR          => shell_quote("$self->{temporary}/editor"),
        GIT_CONFIG_GLOBAL   => '/dev/null',
        GIT_CONFIG_NOSYSTEM => '1',
    };
    write_file( "$self->{temporary}/editor", <<'SH' );
#!/bin/sh
exec "$TEST_NVIM" --headless -n -i NONE -u "$TEST_INIT" "$@"
SH
    chmod 0755, "$self->{temporary}/editor";
    write_file( $self->{env}{TEST_INIT}, <<'VIM' );
let g:loaded_copilot = 1
execute 'set runtimepath^=' . fnameescape($TEST_DOTFILES . '/nvim')
lua vim.pack.add = function() end
lua package.preload['nvim-treesitter'] = function() return { get_available = function() return {} end, setup = function() end } end
execute 'source' fnameescape($TEST_DOTFILES . '/nvim/init.vim')
lua << EOF
vim.api.nvim_create_autocmd('VimEnter', { callback = function()
    vim.defer_fn(function()
        if vim.env.TEST_REPLACEMENT then
            vim.api.nvim_feedkeys(vim.env.TEST_REPLACEMENT, 'xt', false)
        end
        if vim.env.TEST_REPEAT_SETUP then
            while vim.snippet.active() do vim.snippet.stop() end
            vim.api.nvim_buf_set_lines(0, 0, 1, false, { '' })
            require('gitcommit').setup()
        end
        if vim.env.TEST_SAVE then vim.api.nvim_buf_set_lines(0, 0, 1, false, { vim.env.TEST_SAVE }) end
        local snapshot = {
            lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            original = vim.fn.readfile(vim.api.nvim_buf_get_name(0)),
            cursor = vim.api.nvim_win_get_cursor(0),
            mode = vim.fn.mode(),
            commit_module_loaded = package.loaded.gitcommit ~= nil,
            textwidth = vim.bo.textwidth,
            snippet_active = vim.snippet.active(),
            selection = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = 'v' }),
        }
        vim.fn.writefile({ vim.json.encode(snapshot) }, vim.env.TEST_SNAPSHOT)
        if vim.env.TEST_SAVE then vim.cmd('write | qall') else vim.cmd.cquit() end
    end, 20)
end })
EOF
VIM
    git( $self, 'init',   '-q',                   '--template=' );
    git( $self, 'config', 'user.name',            'Test' );
    git( $self, 'config', 'user.email',           'test@example.invalid' );
    git( $self, 'config', 'commit.verbose',       'true' );
    git( $self, 'config', 'status.relativePaths', 'false' );
}

sub git {
    my ( $self, @args ) = @_;
    return run_command( [ 'git', '-C', $self->{repo}, @args ], { env => $self->{env}, check => 1 } )
      ->{stdout};
}

sub put {
    my ( $self, $path, $text ) = @_;
    make_path( dirname("$self->{repo}/$path") );
    write_file( "$self->{repo}/$path", $text );
}

sub seed {
    my ($self) = @_;
    put( $self, 'one.txt', "one\n" );
    put( $self, 'two.txt', "two\n" );
    git( $self, 'add', '.' );
    git( $self, 'commit', '-qm', 'Initial title' );
}

sub edit {
    my ( $self, @args ) = @_;
    unlink $self->{env}{TEST_SNAPSHOT};
    my $result = run_command( [ 'git', '-C', $self->{repo}, @args ], { env => $self->{env}, timeout => 15 } );
    is( $result->{returncode}, 1, 'editor aborts the Git operation' );
    unlike( $result->{stderr}, qr/Error detected|E\d+:|E5108/, 'Neovim has no startup errors' );
    die "Editor did not capture a snapshot:\n$result->{stderr}"
      unless -f $self->{env}{TEST_SNAPSHOT};
    return JSON::PP->new->decode( read_file( $self->{env}{TEST_SNAPSHOT} ) );
}

sub stat_lines {
    my ($snapshot) = @_;
    my ($start)    = grep { $snapshot->{lines}[$_] =~ /^#\tstat:/ } 0 .. $#{ $snapshot->{lines} };
    return [] unless defined $start;
    my $end = $start;
    $end++ while $snapshot->{lines}[$end] ne '#';
    return [ @{ $snapshot->{lines} }[ $start .. $end - 1 ] ];
}

sub without_stat {
    my ($snapshot) = @_;
    my @lines      = @{ $snapshot->{lines} };
    my ($start)    = grep { $lines[$_] =~ /^#\tstat:/ } 0 .. $#lines;
    if ( defined $start ) {
        my $end = $start;
        $end++ while $snapshot->{original}[$end] ne '#';
        splice @lines, $start, scalar @{ stat_lines($snapshot) },
          @{ $snapshot->{original} }[ $start .. $end - 1 ];
    }
    return \@lines;
}

sub prefixed {
    my ( $snapshot, $path ) = @_;
    my $title = "$path: desc";
    is( $snapshot->{lines}[0], $title, 'title uses the expected prefix' );
    is( $snapshot->{mode},     's',    'description is in Select mode' );
    ok( $snapshot->{snippet_active}, 'native snippet is active' );
    is_deeply( $snapshot->{selection}, ['desc'], 'only the description is selected' );
    is( $snapshot->{original}[0], '', 'Git supplied a blank title' );
    is_deeply(
        [ @{ without_stat($snapshot) }[ 1 .. $#{ $snapshot->{original} } ] ],
        [ @{ $snapshot->{original} }[ 1 .. $#{ $snapshot->{original} } ] ],
        'message body is preserved apart from the preview stat'
    );
}

sub unchanged {
    my ($snapshot) = @_;
    my $original = @{ $snapshot->{original} } ? $snapshot->{original} : [''];
    is_deeply( without_stat($snapshot), $original, 'message is unchanged apart from the preview stat' );
    is( $snapshot->{mode}, 'n', 'editor stays in Normal mode' );
    ok( !$snapshot->{snippet_active}, 'no snippet is active' );
}

sub one_staged_file {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "changed\n" );
    put( $self, 'two.txt', "unstaged\n" );
    git( $self, 'add', 'one.txt' );
    prefixed( edit( $self, 'commit' ), 'one.txt' );
}

sub editorconfig_width {
    my ($self) = @_;
    put( $self, '.editorconfig',
        "root = true\n\n[COMMIT_EDITMSG]\nmax_line_length = 72\ntrim_trailing_whitespace = true\n" );
    put( $self, 'one.txt', "one\n\nthree\n" );
    git( $self, 'add', 'one.txt' );
    git( $self, 'commit', '-qm', 'Initial title' );
    put( $self, 'one.txt', "changed\n\nthree\n" );
    git( $self, 'add', 'one.txt' );
    my $diff     = git( $self, 'diff', '--cached' );
    my $snapshot = edit( $self, 'commit' );
    is( $snapshot->{textwidth}, 80, 'commit messages keep an 80-column width despite EditorConfig' );
    local $self->{env}{TEST_SAVE} = 'Commit message';
    git( $self, 'commit' );
    like( read_file("$self->{repo}/.git/COMMIT_EDITMSG"),
        qr/\Q$diff\E/, 'saving preserves verbose diff whitespace' );
}

sub independent_of_patch_format {
    my ($self) = @_;
    seed($self);
    put( $self, 'directory/one.txt', "changed\n" );
    git( $self, 'add', 'directory/one.txt' );
    my $plain = edit( $self, 'commit', '--no-verbose' );
    prefixed( $plain, 'directory/one.txt' );
    is_deeply( stat_lines($plain), [], 'nonverbose commits do not gain a stat' );
    for my $args ( [ '-c', 'diff.noprefix=true', 'commit' ],
        [ '-c', 'diff.srcPrefix=old/', '-c', 'diff.dstPrefix=new/', 'commit' ] )
    {
        my $snapshot = edit( $self, @$args );
        prefixed( $snapshot, 'directory/one.txt' );
        like( join( "\n", @{ stat_lines($snapshot) } ), qr/1 file changed/, 'stat supports patch prefixes' );
        like( join( "\n", @{ stat_lines($snapshot) } ),
            qr/directory\/one\.txt/, 'stat preserves the directory path' );
    }
}

sub unstaged_verbose_diff {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "staged\n" );
    put( $self, 'two.txt', "unstaged\n" );
    git( $self, 'add', 'one.txt' );
    my $snapshot = edit( $self, 'commit', '-vv' );
    prefixed( $snapshot, 'one.txt' );
    my $stat = join( "\n", @{ stat_lines($snapshot) } );
    like( $stat, qr/one\.txt.*\|.*2.*\+-/, 'the stat describes the staged edit' );
    unlike( $stat, qr/two\.txt/, 'the stat excludes unstaged changes with -vv' );
}

sub preview_stat_is_once_and_not_committed {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "changed\n" );
    git( $self, 'add', 'one.txt' );
    $self->{env}{TEST_REPEAT_SETUP} = 1;
    my $snapshot = edit( $self, 'commit' );
    my $stat     = join( "\n", @{ stat_lines($snapshot) } );
    is( scalar( () = $stat =~ /1 file changed/g ), 1, 'repeated setup does not duplicate the stat' );
    $self->{env}{TEST_SAVE} = 'Committed message';
    git( $self, 'commit' );
    is(
        git( $self, 'log', '-1', '--format=%B' ),
        "Committed message\n\n",
        'the stat is not part of the commit message'
    );
}

sub status_stat_layout {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "changed\n" ) for qw(one.txt two.txt);
    git( $self, 'add', '.' );
    my $snapshot = edit( $self, 'commit' );
    my $stat     = stat_lines($snapshot);
    is(
        $stat->[0],
        "#\tstat:       2 files changed, 2 insertions(+), 2 deletions(-)",
        'summary follows the staged heading'
    );
    like( $stat->[1], qr/^#\tmodified:   one\.txt\s+\|\s+2 \+-$/, 'first status row includes its stat' );
    like( $stat->[2], qr/^#\tmodified:   two\.txt\s+\|\s+2 \+-$/, 'second status row includes its stat' );
    is( index( $stat->[1], '|' ), index( $stat->[2], '|' ), 'stat columns align' );
}

sub stat_paths {
    my ($self) = @_;
    seed($self);
    git( $self, 'mv', 'one.txt', 'zzz.txt' );
    my $unicode = "caf\x{e9}.txt";
    utf8::encode($unicode);
    my @paths = ( 'two.txt', 'space name.txt', 'quote"name.txt', $unicode, ( 'long-name-' x 12 ) . '.txt' );
    put( $self, $_, "changed\n" ) for @paths;
    git( $self, 'add', '.' );

    for my $quote (qw(true false)) {
        my $snapshot = edit( $self, '-c', "core.quotePath=$quote", 'commit' );
        my $stat     = stat_lines($snapshot);
        is( scalar @$stat, 7, 'all status rows remain visible' );
        like( $_, qr/\|\s+\d/, 'every status row receives its matching stat' ) for @$stat[ 1 .. $#$stat ];
        like(
            $stat->[-1],
            qr/renamed:.*zzz\.txt.*\|\s+0$/,
            'rename receives its own stat after status sorting'
        );
        like( join( "\n", @$stat ), qr/\Q$paths[-1]\E/, 'long status paths are not truncated' );
    }
}

sub binary_stat {
    my ($self) = @_;
    seed($self);
    put( $self, 'binary.bin', "old\0data" );
    git( $self, 'add', '.' );
    git( $self, 'commit', '-qm', 'Add binary' );
    put( $self, 'binary.bin', "new\0data" );
    git( $self, 'add', '.' );
    for my $args ( ['commit'], [ '-c', 'diff.noprefix=true', 'commit' ] ) {
        my $snapshot = edit( $self, @$args );
        like( join( "\n", @{ stat_lines($snapshot) } ),
            qr/binary\.bin.*\|.*Bin/, 'binary changes have a stat' );
    }
}

sub malformed_staged_list {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "changed\n" );
    git( $self, 'add', 'one.txt' );
    my $original = edit( $self, 'commit' )->{original};
    unchanged( edit( $self, 'commit', '--no-status' ) );
    ok( scalar( grep { $_ eq '# Changes to be committed:' } @$original ), 'Git supplies a staged-file list' );
    for my $kind (qw(no_header empty_list bad_entry)) {
        my @lines = @$original;
        @lines = grep { $_ ne '# Changes to be committed:' } @lines if $kind eq 'no_header';
        @lines = grep { !/^#\t/ } @lines                            if $kind eq 'empty_list';
        if ( $kind eq 'bad_entry' ) {
            s/^#\t.*/#\tunrecognized entry/ for @lines;
        }
        write_file( "$self->{repo}/.git/COMMIT_EDITMSG", join( "\n", @lines ) . "\n" );
        unlink $self->{env}{TEST_SNAPSHOT};
        my $result = run_command(
            [ "$self->{temporary}/editor", "$self->{repo}/.git/COMMIT_EDITMSG" ],
            { env => $self->{env}, cwd => $self->{repo}, timeout => 15 }
        );
        is( $result->{returncode}, 1, "$kind editor exits after the snapshot" );
        unlike( $result->{stderr}, qr/Error detected|E\d+:|E5108/, "$kind has no startup errors" );
        unchanged( JSON::PP->new->decode( read_file( $self->{env}{TEST_SNAPSHOT} ) ) );
    }
}

sub no_subprocess {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "changed\n" );
    git( $self, 'add', 'one.txt' );
    my $original = edit( $self, 'commit' )->{original};
    my $input    = "$self->{temporary}/message.json";
    my $script   = "$self->{temporary}/no-subprocess.lua";
    write_file( $input,  JSON::PP->new->encode($original) );
    write_file( $script, <<'LUA' );
vim.opt.runtimepath:prepend(vim.env.TEST_DOTFILES .. '/nvim')
vim.api.nvim_buf_set_name(0, 'COMMIT_EDITMSG')
vim.api.nvim_buf_set_lines(0, 0, -1, false,
    vim.json.decode(table.concat(vim.fn.readfile(vim.env.TEST_INPUT), '\n')))
local function unexpected() error('Commit title helper launched a subprocess') end
vim.system, vim.uv.spawn = unexpected, unexpected
vim.fn.system, vim.fn.systemlist, vim.fn.jobstart = unexpected, unexpected, unexpected
os.execute, io.popen = unexpected, unexpected
require('gitcommit').prefill_title()
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'one.txt: desc', 'Missing buffer-derived title')
vim.cmd.quit({ bang = true })
LUA
    my $result = run_command(
        [ $nvim, '--headless', '-n', '-i', 'NONE', '-u', 'NONE', '-l', $script ],
        { env => { %{ $self->{env} }, TEST_INPUT => $input }, timeout => 15 }
    );
    is( $result->{returncode}, 0, "helper uses the buffer without a subprocess: $result->{stderr}" );
}

sub lazy_loading {
    my ($self) = @_;
    seed($self);
    my $result = run_command( [ "$self->{temporary}/editor", "$self->{repo}/one.txt" ],
        { env => $self->{env}, timeout => 15 } );
    is( $result->{returncode}, 1, 'ordinary text editor exits after the snapshot' );
    unlike( $result->{stderr}, qr/Error detected|E\d+:|E5108/, 'ordinary text startup has no errors' );
    my $text = JSON::PP->new->decode( read_file( $self->{env}{TEST_SNAPSHOT} ) );
    ok( !$text->{commit_module_loaded}, 'ordinary text startup leaves the commit module unloaded' );
    put( $self, 'one.txt', "changed\n" );
    git( $self, 'add', 'one.txt' );
    my $commit = edit( $self, 'commit' );
    ok( $commit->{commit_module_loaded}, 'Git commit startup loads the commit module' );
    prefixed( $commit, 'one.txt' );
}

sub multiple_or_no_files {
    my ($self) = @_;
    seed($self);
    unchanged( edit( $self, 'commit', '--allow-empty' ) );
    put( $self, 'one.txt', "changed\n" );
    put( $self, 'two.txt', "changed\n" );
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'txt' );
}

sub shared_directory {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "new\n" ) for qw(nvim/init.vim nvim/lua/foo.lua nvim/lua/bar.lua);
    git( $self, 'add', 'nvim' );
    prefixed( edit( $self, 'commit' ), 'nvim' );
}

sub deepest_shared_directory {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "new\n" ) for qw(nvim/lua/foo.lua nvim/lua/snippets/bar.lua);
    git( $self, 'add', 'nvim' );
    prefixed( edit( $self, 'commit' ), 'nvim/lua' );
}

sub mostly_shared_directory {
    my ($self) = @_;
    seed($self);
    put( $self, 'README.md',              "new\n" );
    put( $self, "docs/screenshot-$_.png", "new\n" ) for 1 .. 14;
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'docs' );
}

sub directory_without_majority {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "new\n" )
      for qw(alpha/screenshot-1.png alpha/screenshot-2.png beta/screenshot-3.png beta/screenshot-4.png);
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'screenshot' );
}

sub shared_word {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "new\n" ) for qw(nvim/lua/gitcommit.lua tests/test-nvim-commit.t);
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'nvim' );
}

sub most_common_word {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "new\n" )
      for qw(alpha/repeat-repeat-repeat.lua beta/cache-writer.lua gamma/cache-reader.lua);
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'cache' );
}

sub underscores_stay_within_words {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "new\n" ) for qw(ci/test.sh tests/test_nvim_setup.t);
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'ci/test.sh' );
}

sub shared_underscore_chunk {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "new\n" ) for qw(alpha/cache_writer.lua beta/cache_writer.test.lua);
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'cache_writer' );
}

sub directory_component_boundaries {
    my ($self) = @_;
    seed($self);
    put( $self, $_, "new\n" ) for qw(nvim/one.lua nvim-other/two.lua);
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'nvim' );
    git( $self, 'reset', '--hard', 'HEAD' );
    put( $self, $_, "new\n" ) for qw(plugins/nvim/one.lua plugins/nvim-other/two.lua);
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'plugins' );
}

sub file_replaced_by_directory {
    my ($self) = @_;
    seed($self);
    put( $self, 'parent/shared', "old\n" );
    git( $self, 'add', '.' );
    git( $self, 'commit', '-qm', 'Add original file' );
    unlink "$self->{repo}/parent/shared" or die $!;
    put( $self, 'parent/shared/child.txt', "replacement\n" );
    git( $self, 'add', '-A' );
    prefixed( edit( $self, 'commit' ), 'parent' );
}

sub partial_commit {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "chosen\n" );
    put( $self, 'two.txt', "staged\n" );
    git( $self, 'add', 'two.txt' );
    my $snapshot = edit( $self, 'commit', '--only', '--', 'one.txt' );
    prefixed( $snapshot, 'one.txt' );
    my $stat = join( "\n", @{ stat_lines($snapshot) } );
    like( $stat, qr/one\.txt/, 'partial commit stat includes the selected file' );
    unlike( $stat, qr/two\.txt/, 'partial commit stat excludes the separately staged file' );
    is( git( $self, 'diff', '--cached', '--name-only' ),
        "two.txt\n", 'aborted partial commit preserves the original index' );
}

sub commit_all {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "changed\n" );
    prefixed( edit( $self, 'commit', '-a' ), 'one.txt' );
}

sub initial_commit {
    my ($self) = @_;
    put( $self, 'first.txt', "first\n" );
    git( $self, 'add', '.' );
    prefixed( edit( $self, 'commit' ), 'first.txt' );
}

sub existing_titles {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "changed\n" );
    git( $self, 'add', 'one.txt' );
    my $amend = edit( $self, 'commit', '--amend' );
    unchanged($amend);
    like(
        join( "\n", @{ stat_lines($amend) } ),
        qr/2 files changed/,
        'amend stat compares against the parent of the replaced commit'
    );
    is( $amend->{lines}[0], 'Initial title', 'amend title is preserved' );
    my $template = "$self->{temporary}/template";
    write_file( $template, "Template title\n\nTemplate body.\n" );
    my $new = edit( $self, 'commit', '--template', $template );
    unchanged($new);
    is( $new->{lines}[0], 'Template title', 'template title is preserved' );
    my $message = edit( $self, 'commit', '--edit', '-m', 'Provided title' );
    unchanged($message);
    is( $message->{lines}[0], 'Provided title', '-m title is preserved' );
    my $body = edit( $self, 'commit', '--edit', '--cleanup=verbatim', '-m', "\nBody-only message\n" );
    unchanged($body);
    is( $body->{original}[0], '',                  'verbatim -m keeps its initial blank line' );
    is( $body->{lines}[1],    'Body-only message', '-m body is preserved' );
}

sub rename_and_delete {
    my ($self) = @_;
    seed($self);
    git( $self, 'mv', 'one.txt', 'renamed.txt' );
    prefixed( edit( $self, 'commit' ), 'renamed.txt' );
    git( $self, 'reset', '--hard', 'HEAD' );
    git( $self, 'rm', 'one.txt' );
    prefixed( edit( $self, 'commit' ), 'one.txt' );
}

sub path_spelling {
    my ($self) = @_;
    seed($self);
    my $path = 'nested/with space/name.txt';
    put( $self, $path, "new\n" );
    git( $self, 'add', '--', $path );
    local $self->{repo} = "$self->{repo}/nested";
    prefixed( edit( $self, 'commit' ), 'nested/with space/name.txt' );
}

sub description_replacement {
    my ($self) = @_;
    seed($self);
    my $path = 'literal$prefix}.txt';
    put( $self, $path, "new\n" );
    git( $self, 'add', '--', $path );
    prefixed( edit( $self, 'commit' ), $path );
    local $self->{env}{TEST_REPLACEMENT} = 'Describe this change';
    my $snapshot = edit( $self, 'commit' );
    is(
        $snapshot->{lines}[0],
        "$path: Describe this change",
        'typing replaces desc and preserves the literal prefix'
    );
    is_deeply(
        [ @{ without_stat($snapshot) }[ 1 .. $#{ $snapshot->{original} } ] ],
        [ @{ $snapshot->{original} }[ 1 .. $#{ $snapshot->{original} } ] ],
        'typing leaves the message body untouched apart from the preview stat'
    );
}

sub linked_worktree {
    my ($self) = @_;
    seed($self);
    my $worktree = "$self->{temporary}/worktree";
    git( $self, 'worktree', 'add', '-qb', 'worktree', $worktree );
    local $self->{repo} = $worktree;
    put( $self, 'one.txt', "changed\n" );
    git( $self, 'add', 'one.txt' );
    prefixed( edit( $self, 'commit' ), 'one.txt' );
}

sub tag_message {
    my ($self) = @_;
    seed($self);
    put( $self, 'one.txt', "changed\n" );
    git( $self, 'add', 'one.txt' );
    unchanged( edit( $self, 'tag', '-a', 'example' ) );
}

run_cases(
    {
        one_staged_file                        => \&one_staged_file,
        editorconfig_width                     => \&editorconfig_width,
        independent_of_patch_format            => \&independent_of_patch_format,
        unstaged_verbose_diff                  => \&unstaged_verbose_diff,
        preview_stat_is_once_and_not_committed => \&preview_stat_is_once_and_not_committed,
        status_stat_layout                     => \&status_stat_layout,
        stat_paths                             => \&stat_paths,
        binary_stat                            => \&binary_stat,
        malformed_staged_list                  => \&malformed_staged_list,
        no_subprocess                          => \&no_subprocess,
        lazy_loading                           => \&lazy_loading,
        multiple_or_no_files                   => \&multiple_or_no_files,
        shared_directory                       => \&shared_directory,
        deepest_shared_directory               => \&deepest_shared_directory,
        mostly_shared_directory                => \&mostly_shared_directory,
        directory_without_majority             => \&directory_without_majority,
        shared_word                            => \&shared_word,
        most_common_word                       => \&most_common_word,
        underscores_stay_within_words          => \&underscores_stay_within_words,
        shared_underscore_chunk                => \&shared_underscore_chunk,
        directory_component_boundaries         => \&directory_component_boundaries,
        file_replaced_by_directory             => \&file_replaced_by_directory,
        partial_commit                         => \&partial_commit,
        commit_all                             => \&commit_all,
        initial_commit                         => \&initial_commit,
        existing_titles                        => \&existing_titles,
        rename_and_delete                      => \&rename_and_delete,
        path_spelling                          => \&path_spelling,
        description_replacement                => \&description_replacement,
        linked_worktree                        => \&linked_worktree,
        tag_message                            => \&tag_message,
    },
    \&setup
);
