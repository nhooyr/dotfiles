set number
set tabstop=4
set shiftwidth=0
set ignorecase
set smartcase
set laststatus=3
set title
set titlestring=%{v:lua.require'dirali'.filename()}%(\ %M%)%a\ -\ nvim
let &statusline = substitute(&statusline, '%f', "%{v:lua.require'dirali'.filename()}", '')
" File-watcher activity should not flash a busy symbol beside the Git prompt.
let &statusline = substitute(&statusline, "%{ &busy > 0 ? '[^']*' : '' }", '', 'g')
" Remove our previous VCS field before rebuilding the status line.
if exists('s:vcs_statusline')
	let &statusline = substitute(&statusline, '\V' . s:vcs_statusline, '', 'g')
endif
let s:vcs_statusline = "%{get(b:,'vcs_prompt','')} "
let &statusline = substitute(&statusline, '%=', '%=' . s:vcs_statusline, '')
set textwidth=110
set foldmethod=indent
set foldlevel=999
set foldlevelstart=999
set shortmess+=I
set splitbelow
set splitright
set formatoptions-=t
nnoremap j gj
nnoremap k gk
xnoremap j gj
xnoremap k gk
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
nnoremap <C-e> <Cmd>execute 'normal!' (v:count1 * 2).'<C-e>'<CR>
nnoremap <C-y> <Cmd>execute 'normal!' (v:count1 * 2).'<C-y>'<CR>

set backup
set backupdir-=.
set undofile
set undolevels=99999
set undoreload=99999
command! Undotree packadd nvim.undotree | lua require('undotree').open()
nnoremap <Leader>u <Cmd>Undotree<CR>
nnoremap <M-u> <Cmd>execute 'earlier' v:count1.'f'<CR>

set notermguicolors
colorscheme default
nnoremap <Leader>i <Cmd>Inspect<CR>
highlight Comment ctermfg=8 cterm=italic
highlight Search ctermfg=0 ctermbg=3
highlight! link CurSearch Search
highlight! link Visual Search
highlight LineNr ctermfg=8
highlight Constant ctermfg=5
highlight Type ctermfg=5
highlight PreProc ctermfg=6
highlight Error ctermfg=1 ctermbg=none cterm=underline
highlight WarningMsg ctermfg=6
highlight! link DiagnosticWarn WarningMsg
highlight RedrawDebugClear ctermbg=6
highlight WinSeparator cterm=bold
highlight link gitcommitOverflow Error
highlight link json5Key Statement

function s:set_mode_highlight(check_record) abort
	let mode = mode(1)
	if a:check_record && reg_recording() !=# ''
		highlight ModeMsg ctermfg=4
	elseif mode =~# "^[vVsS\<C-v>\<C-s>]"
		highlight ModeMsg ctermfg=5
	elseif mode =~# '^R\|^ni[RV]'
		highlight ModeMsg ctermfg=6
	else
		highlight ModeMsg ctermfg=2
	endif
endfunction
call s:set_mode_highlight(v:true)

set list
set listchars+=extends:>,precedes:<
highlight! link NonText Comment
highlight! link Folded Comment

set dictionary=/usr/share/dict/words
set spelllang=en_ca,en_us
function s:set_spell_highlight() abort
	let s:spell_visible = get(s:, 'spell_visible', 0)
	if s:spell_visible ==# 0
		highlight clear SpellBad
		highlight clear SpellCap
		highlight clear SpellRare
		highlight clear SpellLocal
	else
		set spell
		highlight SpellBad cterm=underline
		highlight SpellCap cterm=underline
		highlight SpellRare cterm=underline
		highlight SpellLocal cterm=underline
	endif
endfunction
call s:set_spell_highlight()
" Toggle spell via the highlight groups to keep it active for 'complete' kspell
function s:toggle_spell_visible() abort
	let s:spell_visible = !s:spell_visible
	call s:set_spell_highlight()
	echo 's:spell_visible =' s:spell_visible
endfunction
nnoremap <Leader>z <Cmd>call <SID>toggle_spell_visible()<CR>
command Mkspell execute 'mkspell! ' . fnameescape(stdpath('data') . '/site/spell/en.utf-8.add')

" https://github.com/neovim/neovim/issues/39337
let g:termfeatures = get(g:, 'termfeatures', {})
let g:termfeatures.osc52 = v:false

noremap ; :
noremap : ;
noremap 0 ^
noremap ^ 0
sunmap ;
sunmap :
sunmap 0
sunmap ^
inoremap <M-BS> <C-w>
cnoremap <M-BS> <C-w>
cnoremap <M-v> <C-r>"
cnoremap <M-f> \V
nnoremap <Leader>s <Cmd>if <SID>is_config_file(expand('%:p')) \| silent update \| endif
				\ \| execute 'source' fnameescape($MYVIMRC) \| echo 'source' $MYVIMRC<CR>
nnoremap <Leader>c <Cmd>e $dotfiles/fish/config.fish<CR>
nnoremap <Leader>v <Cmd>e $MYVIMRC<CR>
nnoremap <Leader>t <Cmd>e $dotfiles/nvim/lua/snips.lua<CR>
let g:netrw_banner = 0
let g:netrw_list_hide = '^\.\.\?\/$'
let g:netrw_keepdir = 0
set autochdir
function s:edit_parent() abort
	let path = &filetype ==# 'netrw' ? b:netrw_curdir : expand('%:p')
	let parent = path =~# '^/\+$' ? '/' : fnamemodify(substitute(path, '/\+$', '', ''), ':h')
	execute 'edit' fnameescape(parent)
endfunction
nnoremap - <Cmd>call <SID>edit_parent()<CR>

nnoremap <Leader>h <Cmd>let v:hlsearch = !v:hlsearch \| echo 'v:hlsearch =' v:hlsearch<CR>
nnoremap <Leader>r :%s###g<Left><Left>
nnoremap <M-r> cgn
" https://vim.fandom.com/wiki/Search_for_visually_selected_text
xnoremap <Leader>/ "zy/\V<C-R>=substitute(escape(@z,'/\'),'\n','\\n','g')<CR><CR>
xnoremap <silent> <Leader>n :s/^/\=line('.')-line("'<")+1.'. '/<CR>:noh<CR>
xmap <Leader>r <Leader>/<Leader>r
xnoremap <M-r> :s###g<Left><Left>

nnoremap q <Cmd>quit<CR>
nnoremap <M-q> q
nnoremap <C-q> <Cmd>qall!<CR>
inoremap <C-q> <Esc>:qall!<CR>
nnoremap <M-s> <Cmd>write<CR>
inoremap <M-s> <Esc>:write<CR>
nnoremap <C-s> <Cmd>xit<CR>
inoremap <C-s> <Esc>:xit<CR>

let s:orig_file = get(s:, 'orig_file', resolve(expand('%:p')))
function s:quit_and_run() abort
	if mode() ==# 'i'
		execute 'normal! i' . copilot#Accept('')
	endif
	wall
	if !empty($AQSNOW_FISH_RENDEZVOUS)
		if resolve(expand('%:p')) ==# s:orig_file && (line('$') > 1 || getline(1) != '')
			call writefile(['exec'], $AQSNOW_FISH_RENDEZVOUS)
		endif
	endif
	qall
endfunction
nnoremap <M-CR> <Cmd>call <SID>quit_and_run()<CR>
inoremap <M-CR> <Cmd>call <SID>quit_and_run()<CR>
snoremap <M-CR> <Esc><Cmd>call <SID>quit_and_run()<CR>
function s:fzf_path_widget() abort
	wall
	if !empty($AQSNOW_FISH_RENDEZVOUS)
		call writefile(['<M-v>'], $AQSNOW_FISH_RENDEZVOUS)
	endif
	qall
endfunction
nnoremap <M-v> <Cmd>call <SID>fzf_path_widget()<CR>
inoremap <M-v> <Esc>:call <SID>fzf_path_widget()<CR>

inoremap <C-a> <C-o>^
inoremap <C-d> <Del>
inoremap <C-k> <C-\><C-o>D
cnoremap <C-a> <Home>
cnoremap <C-d> <Del>

xnoremap > >gv
xnoremap < <gv
nmap <C-_> gcc
imap <C-_> <C-o>gcc
xmap <C-_> gc

nnoremap ]p ]p=`]
nnoremap ]P ]P=`]
nnoremap ]<M-p> "+]p=`]
nnoremap ]<M-P> "+]P=`]

nnoremap x "_x
nnoremap X "_X
nnoremap c "_c
xnoremap c "_c
nnoremap C "_C
xnoremap C "_C
nnoremap s "_s
xnoremap s "_s
nnoremap S "_S
xnoremap S "_S
nnoremap <BS><BS> "_dd
nnoremap <BS> "_d
xnoremap <BS> "_d
nnoremap gp `[v`]
nnoremap <Leader>p "+p
nnoremap <Leader>P "+P
inoremap <M-p> <C-o>"+P
nnoremap <M-y> "+y
nnoremap <M-y><M-y> m`^"+y$``
xnoremap <M-y> "+y
nnoremap <M-c> "+c
nnoremap <M-c><M-c> m`^"+y$``"_cc
xnoremap <M-c><M-c> "+c
nnoremap <M-d> "+d
nnoremap <M-d><M-d> m`^"+y$``"_dd
xnoremap <M-d> "+d
nnoremap <Leader>d <Cmd>execute '.,.+'.(v:count1-1).'t.'<CR>

set completeopt=menuone,noselect,popup
set complete+=U,kspell,i,d,f,o
set complete^=Fv:lua.require'snips'.complete
set pumheight=8

inoremap <C-n> <Cmd>set spell<CR><C-n>
inoremap <C-p> <Cmd>set spell<CR><C-p>
inoremap <expr> <C-Space> pumvisible() ? '<C-n>' :
	   \ strpart(getline('.'), 0, col('.') - 1) =~# '\f*/\f*$'
	   \ ? '<C-x><C-f>' : '<Cmd>set spell<CR><C-n>'
if !exists('g:loaded_copilot')
	inoremap <expr> <Tab> pumvisible() ? '<C-n>' : '<Tab>'
endif
inoremap <expr> <S-Tab> pumvisible() ? '<C-p>' : '<S-Tab>'
inoremap <expr> <C-e> pumvisible() ? '<C-e>' : '<C-o>$'
highlight PmenuMatch cterm=underline
highlight PmenuSel ctermfg=3 ctermbg=0 cterm=none
highlight PmenuMatchSel cterm=none
highlight PmenuThumb ctermbg=8
highlight! link NormalFloat LineNr
" Only time we use a non-base16 color. Keeps copilot suggestions visible in comments which are cterm=8.
highlight CopilotSuggestion ctermfg=244
let g:copilot_filetypes = {
			\ '*': v:true,
			\ }

command -bar -bang -nargs=0 Mkdirp write<bang> ++p
nnoremap <Leader>m <Cmd>Mkdirp<CR>

command DiffOrig vert new | set buftype=nofile | read ++edit # | 0d_ |
			   \ diffthis | wincmd p | diffthis

nnoremap <Leader>w <Cmd>%s/\s\+$//<CR>
nnoremap <Leader>- <Cmd>%s/^\s*[+-]//<CR>
xnoremap <Leader>- :s/^\s*[+-]//<CR>
nnoremap <M-w> /^\s\+
nnoremap <M-n> <Cmd>execute v:count1.'next'<CR>
nnoremap <M-p> <Cmd>execute v:count1.'prev'<CR>
nnoremap Z zz

function s:vidir_mcr() abort
	execute 'write !cd -- ' . shellescape(b:vidir_dir, 1) . ' && sh'
	if v:shell_error == 0
		setlocal nomodified
	endif
endfunction

function s:vidir() abort
	let directory = getcwd()
	for buffer in getbufinfo()
		if get(buffer.variables, 'vidir_dir', '') ==# directory
			execute 'buffer' buffer.bufnr
			return
		endif
	endfor
	enew
	let b:vidir_dir = directory
	call nvim_buf_set_name(0, 'vidir://' . luaeval("require('dirali').shorten(_A)", directory))
	call setline(1, ['#!/bin/sh', 'set -eu'])
	silent $read !LC_COLLATE=C gls -1A -v --group-directories-first -r
	autocmd BufWriteCmd <buffer> call <SID>vidir_mcr()
	nnoremap <buffer> <M-CR> <Cmd>call <SID>vidir_mcr()<CR>
	inoremap <buffer> <M-CR> <Cmd>call <SID>vidir_mcr()<CR>
	" Quote for the sh command list, regardless of the interactive shell.
	let shell = &shell
	try
		set shell=sh
		if line('$') > 2
			silent 3,$s/.*/\='mv -v -- ' . shellescape(submatch(0)) . ' ' . shellescape(submatch(0))/
		endif
	finally
		let &shell = shell
	endtry
	setlocal nomodified buftype=acwrite filetype=sh
endfunction
command Vidir call s:vidir()
command -bar -range=% Reverse <line1>,<line2>global/^/m<line1>-1

let s:vgrep = shellescape(fnamemodify(resolve(expand('<sfile>:p')), ':h:h') . '/bin/vgrep')
let s:grep_repositories = get(s:, 'grep_repositories', {})
let s:grep_pending = {}
let s:grep_generation = get(s:, 'grep_generation', 0) + 1
function s:cache_grep_repository(generation, directory, in_git) abort
	if a:generation != s:grep_generation
		return
	endif
	let s:grep_repositories[a:directory] = a:in_git
	call remove(s:grep_pending, a:directory)
endfunction
function s:update_grepprg() abort
	let directory = getcwd()
	if !has_key(s:grep_repositories, directory) && !has_key(s:grep_pending, directory)
		let s:grep_pending[directory] = 1
		" Defer until sourcing finishes so the current gitstatus module handles it.
		call luaeval("vim.schedule(function() require('gitstatus').worktree(_A.directory, function(in_git) vim.fn[_A.callback](_A.generation, _A.directory, in_git) end) end)",
				\ {'directory': directory, 'generation': s:grep_generation, 'callback': expand('<SID>') . 'cache_grep_repository'})
	endif
	" Apply a ready result on entry, never from an asynchronous search callback:
	" changing grepformat during :grep could misparse the command already running.
	if get(s:grep_repositories, directory, v:false)
		let &grepprg = s:vgrep . ' --git'
		set grepformat=%f:%l:%c:%m
	else
		let &grepprg = s:vgrep
		set grepformat=%f:%l:%m
	endif
endfunction
call s:update_grepprg()
nnoremap <Leader>g :silent grep '' .<Left><Left><Left>
nnoremap <Leader>q <Cmd>execute getqflist({'winid': 0}).winid ? 'cclose' : 'copen'<CR>
nnoremap <Leader>[ <Cmd>execute 'colder' v:count1<CR>
nnoremap <Leader>] <Cmd>execute 'cnewer' v:count1<CR>
let &quickfixtextfunc = "v:lua.require'qf'.fmt"
highlight link qfLineNr Type
highlight QuickFixLine ctermfg=0 ctermbg=3

let s:config_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')
silent doautocmd <nomodeline> User AqsnowGitStatusStop
lua for _, name in ipairs({'dirali', 'gitcommit', 'gitstatus', 'qf', 'snips'}) do package.loaded[name] = nil end
inoremap <M-j> <Cmd>lua require('snips').expand_or_jump()<CR>
snoremap <M-j> <Cmd>lua require('snips').jump(1)<CR>
inoremap <M-k> <Cmd>lua require('snips').jump(-1)<CR>
snoremap <M-k> <Cmd>lua require('snips').jump(-1)<CR>

function s:is_config_file(path) abort
	return index([resolve($MYVIMRC),
				\ s:config_dir . '/lua/snips.lua',
				\ s:config_dir . '/lua/qf.lua',
				\ s:config_dir . '/lua/dirali.lua',
				\ s:config_dir . '/lua/gitcommit.lua',
				\ s:config_dir . '/lua/gitstatus.lua'], resolve(a:path)) >= 0
endfunction

" For BufReadPost's restore_cursor.
filetype on
augroup aqsnow
	autocmd!
	autocmd ModeChanged,RecordingEnter * call <SID>set_mode_highlight(v:true)
	autocmd RecordingEnter * redraw!
	autocmd RecordingLeave * call <SID>set_mode_highlight(v:false)
	autocmd DirChanged * call <SID>update_grepprg()
	autocmd CmdlineEnter : call <SID>update_grepprg()
	autocmd QuickFixCmdPost grep ++nested copen
	autocmd CompleteDone * lua if vim.v.completed_item.user_data == 'snip' then
			\ require('snips').expand() end
	autocmd FocusLost,BufLeave * nested if !empty(getbufinfo({'bufmodified': 1})) | doautoall <nomodeline> aqsnow User AqsnowAutosave | endif
	" New files wait for an explicit save.
	autocmd User AqsnowAutosave nested if &modified && filereadable(expand('%:p')) | silent! update | endif
	autocmd BufWritePre,FileWritePre * if expand('<afile>') !~# '://' | call mkdir(expand('<afile>:p:h'), 'p') | endif
	autocmd filetype gitcommit setlocal noet ts=4 sw=0 tw=80
	autocmd filetype gitcommit let g:gitcommit_summary_length = &textwidth
	autocmd filetype gitcommit lua require('gitcommit').prefill_title()
	autocmd filetype html,jsonc,css setlocal et ts=2 sw=0
	autocmd filetype markdown setlocal et ts=3 sw=0
	autocmd filetype fish setlocal et ts=4 sw=0
	autocmd filetype gitconfig let &l:commentstring='# %s'
	autocmd BufRead,BufNewFile gitconfig,*.gitconfig setfiletype gitconfig
	autocmd BufRead,BufNewFile *.json setlocal filetype=json5
	autocmd BufReadPost * call <SID>restore_cursor()
	autocmd BufEnter,WinEnter * if &autochdir && exists('b:vidir_dir') | call nvim_set_current_dir(b:vidir_dir) | endif
	autocmd filetype fish setlocal formatprg=fish_indent
	autocmd filetype sh let &l:formatprg='shfmt -s'
	autocmd BufWritePost * if <SID>is_config_file(expand('<afile>:p')) | execute 'autocmd aqsnow SafeState * ++once execute "source" fnameescape($MYVIMRC)' | endif
	autocmd filetype gitcommit nnoremap <buffer> ]c /^diff --<CR>
	autocmd filetype gitcommit nnoremap <buffer> [c ?^diff --<CR>
	autocmd filetype gitcommit,diff nnoremap <buffer> ]h /^@@<CR>
	autocmd filetype gitcommit,diff nnoremap <buffer> [h ?^@@<CR>
	autocmd filetype netrw nnoremap <buffer> <nowait> q <Cmd>quit<CR>
	autocmd filetype netrw if exists('b:netrw_curdir') && b:netrw_curdir =~# '^/' | nnoremap <buffer> <nowait> - <Cmd>call <SID>edit_parent()<CR> | endif
	autocmd VimEnter * lua require('gitstatus').start()
	autocmd BufEnter,BufFilePost,DirChanged * lua require('gitstatus').refresh()
	autocmd FocusGained * lua require('gitstatus').focus()
	autocmd BufWritePost,FileWritePost * lua require('gitstatus').written(tonumber(vim.fn.expand('<abuf>')))
	autocmd User AqsnowGitStatusStop lua require('gitstatus').stop()
	autocmd VimLeavePre * lua require('gitstatus').stop()
augroup END
if v:vim_did_enter
	lua require('gitstatus').start()
endif

function s:restore_cursor() abort
	" Commit messages, rebase todos, and diffs start at the top.
	if &filetype =~# 'commit' || &filetype ==# 'gitrebase' || &diff
		return
	endif
	if line("'\"") > 0
		if line("'\"") <= line('$')
			normal! g`"
		else
			keepjumps normal! G
		endif
	endif
endfunction
