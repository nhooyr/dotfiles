set number
set tabstop=4
set shiftwidth=0
set ignorecase
set smartcase
set laststatus=3
set title
set titlestring=%t%(\ %M%)%(\ \(%{expand('%:p:~:h')}\)%)%a\ -\ nvim
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
vnoremap j gj
vnoremap k gk
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
nnoremap <C-e> 2<C-e>
nnoremap <C-y> 2<C-y>

set backup
set backupdir-=.
set undofile
set undolevels=99999
set undoreload=99999
packadd nvim.undotree
nnoremap <Leader>u :Undotree<CR>

set notermguicolors
colorscheme default
highlight Comment ctermfg=8 cterm=italic
highlight LineNr ctermfg=8
highlight Constant ctermfg=5
highlight Type ctermfg=5
highlight PreProc ctermfg=6
highlight Error cterm=bold
highlight WinSeparator cterm=bold

set list
set listchars+=extends:>,precedes:<
highlight! link NonText Comment
highlight! link Folded Comment
highlight! link gitcommitOverflow Error

set dictionary=/usr/share/dict/words
set spell
set spelllang=en_ca,en_us
function! s:set_spell_highlight() abort
	let s:spell_visible = get(s:, 'spell_visible', 0)
	if s:spell_visible ==# 0
		highlight clear SpellBad
		highlight clear SpellCap
		highlight clear SpellRare
		highlight clear SpellLocal
	else
		highlight SpellBad cterm=underline
		highlight SpellCap cterm=underline
		highlight SpellRare cterm=underline
		highlight SpellLocal cterm=underline
	endif
endfunction
call s:set_spell_highlight()
" Toggle spell via the highlight groups to keep it active for 'complete' kspell
function! s:toggle_spell_visible() abort
	let s:spell_visible = !s:spell_visible
	call s:set_spell_highlight()
	echo 's:spell_visible =' s:spell_visible
endfunction
nnoremap <Leader>z :call <SID>toggle_spell_visible()<CR>
command Mkspell execute 'mkspell! ' . fnameescape(stdpath('data') . '/site/spell/en.utf-8.add')

" https://github.com/neovim/neovim/issues/39337
let g:termfeatures = get(g:, 'termfeatures', {})
let g:termfeatures.osc52 = v:false

noremap ; :
noremap : ;
noremap 0 ^
noremap ^ 0
inoremap <M-BS> <C-w>
cnoremap <M-BS> <C-w>
cnoremap <M-v> <C-r>"
cnoremap <M-f> \V
nnoremap <Leader>s :if expand('%:p') ==# $MYVIMRC \| update \| endif \| source $MYVIMRC<CR>
			\:echo 'source' $MYVIMRC<CR>
nnoremap <Leader>v :e $MYVIMRC<CR>
let g:netrw_banner = 0
let g:netrw_list_hide = '^\.\.\?\/$'
nnoremap <silent> - :execute 'edit' fnameescape(expand('%:p:h'))<CR>

nnoremap <Leader>h :let v:hlsearch = !v:hlsearch<CR>:echo 'v:hlsearch =' v:hlsearch<CR>
nnoremap <Leader>r :%s###g<Left><Left>
nnoremap <M-r> cgn
" https://vim.fandom.com/wiki/Search_for_visually_selected_text
vnoremap / "zy/\V<C-R>=substitute(escape(@z,'/\'),'\n','\\n','g')<CR><CR>
vnoremap g/ /
vnoremap <silent> <Leader>n :s/^/\=line('.')-line("'<")+1.'. '/<CR>:noh<CR>
vmap <Leader>r /<Leader>r
vnoremap <M-r> :s###g<Left><Left>

nnoremap q :quit<CR>
nnoremap <M-q> q
nnoremap <C-q> :qall!<CR>
inoremap <C-q> <Esc>:qall!<CR>
nnoremap <M-s> :write<CR>
inoremap <M-s> <Esc>:write<CR>
nnoremap <C-s> :xit<CR>
inoremap <C-s> <Esc>:xit<CR>

let s:orig_file = get(s:, 'orig_file', resolve(expand('%:p')))
function! s:quit_and_run() abort
	if mode() ==# 'i'
		execute "normal! i" . copilot#Accept('')
	endif
	wall
	if !empty($AQSNOW_FISH_RENDEZVOUS)
		if resolve(expand('%:p')) ==# s:orig_file && (line('$') > 1 || getline(1) != "")
			call writefile(['exec'], $AQSNOW_FISH_RENDEZVOUS)
		endif
	endif
	qall
endfunction
nnoremap <M-CR> :call <SID>quit_and_run()<CR>
inoremap <M-CR> <Cmd>call <SID>quit_and_run()<CR>
function! s:fzf_file_widget() abort
	wall
	if !empty($AQSNOW_FISH_RENDEZVOUS)
		call writefile(['<M-v>'], $AQSNOW_FISH_RENDEZVOUS)
	endif
	qall
endfunction
nnoremap <M-v> :call <SID>fzf_file_widget()<CR>
inoremap <M-v> <Esc>:call <SID>fzf_file_widget()<CR>

inoremap <C-a> <C-o>^
inoremap <C-d> <Del>
inoremap <C-k> <C-\><C-o>D
cnoremap <C-a> <Home>
cnoremap <C-d> <Del>

vnoremap > >gv
vnoremap < <gv
nmap <C-_> gcc
imap <C-_> <C-o>gcc
vmap <C-_> gc

nnoremap ]p ]p=`]
nnoremap ]P ]P=`]
nnoremap ]<M-p> "+]p=`]
nnoremap ]<M-P> "+]P=`]

nnoremap c "_c
nnoremap C "_C
vnoremap c "_c
nnoremap s "_s
vnoremap s "_s
nnoremap S "_S
vnoremap S "_S
nnoremap <BS><BS> "_dd
nnoremap <BS> "_d
vnoremap <BS> "_d
nnoremap gp `[v`]
nnoremap <Leader>p "+p
nnoremap <Leader>P "+P
inoremap <M-p> <C-o>"+P
nnoremap Y "+y
nnoremap YY m`^"+y$``
vnoremap Y "+y
vnoremap C "+c
nnoremap D "+d
nnoremap DD m`^"+y$``"_dd
vnoremap D "+d
nnoremap <silent> <Leader>d :t.<CR>

set completeopt=menuone,noselect,popup
set complete+=U,kspell,i,d,f,o
set pumheight=8

inoremap <expr> <C-Space> pumvisible() ? "\<C-n>" :
	   \ strpart(getline('.'), 0, col('.') - 1) =~# '\f*/\f*$'
	   \ ? "\<C-x>\<C-f>" : "\<C-n>"
if !exists('g:loaded_copilot')
	inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
endif
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <C-e> pumvisible() ? "\<C-e>" : "\<C-o>$"
highlight PmenuMatch cterm=underline
highlight PmenuSel ctermfg=4
highlight PmenuMatchSel cterm=underline,bold
highlight! link PmenuSbar Pmenu
highlight! link PmenuThumb Pmenu
" Only time we use a non-base16 color. Keeps copilot suggestions visible in comments which are cterm=8.
highlight CopilotSuggestion ctermfg=244
let g:copilot_filetypes = {
			\ '*': v:true,
			\ }

command -bar -bang -nargs=0 Mkdirp write<bang> ++p
nnoremap <Leader>m :Mkdirp<CR>

command DiffOrig vert new | set buftype=nofile | read ++edit # | 0d_ |
			   \ diffthis | wincmd p | diffthis

nnoremap <Leader>w :keeppatterns %s/\s\+$//<CR>
nnoremap <Leader>- :keeppatterns %s/^\s*[+-]//<CR>
vnoremap <Leader>- :keeppatterns s/^\s*[+-]//<CR>
nnoremap <M-n> :next<CR>
nnoremap <M-p> :prev<CR>
nnoremap Z zz

function! s:vidir_mcr() abort
	write !sh
	set nomodified
endfunction

function! s:vidir() abort
	enew
	silent read !ls -1
	normal ggS# :w !sh
	nnoremap <buffer> <M-CR> :call <SID>vidir_mcr()<CR>
	inoremap <buffer> <M-CR> <Cmd>call <SID>vidir_mcr()<CR>
	silent 2,$s/.*/mv -v '\0' '\0'
	set nomodified
	set buftype=nofile
	set filetype=sh
endfunction
command Vidir call s:vidir()
command -bar -range=% Reverse <line1>,<line2>global/^/m<line1>-1

" For BufReadPost restore_cursor.
filetype plugin indent on
augroup aqsnow
	autocmd!
	autocmd FocusLost,BufLeave * nested if !empty(getbufinfo({'bufmodified': 1})) | silent! wall | endif
	autocmd filetype gitcommit setlocal noet ts=4 sw=0 tw=80
	autocmd filetype gitcommit let g:gitcommit_summary_length = &textwidth
	autocmd filetype html,jsonc,css setlocal et ts=2 sw=0
	autocmd filetype markdown setlocal et ts=3 sw=0
	autocmd filetype fish setlocal et ts=4 sw=0
	autocmd BufRead,BufNewFile *.json setlocal filetype=jsonc
	autocmd BufReadPost * call <SID>restore_cursor()
	autocmd filetype fish setlocal formatprg=fish_indent
	autocmd filetype sh let &l:formatprg='shfmt -s'
	autocmd BufWritePost $MYVIMRC autocmd aqsnow SafeState * ++once source $MYVIMRC
	autocmd filetype gitcommit nnoremap <buffer> ]c /^@@<CR>zz
	autocmd filetype gitcommit nnoremap <buffer> [c ?^@@<CR>zz
	autocmd filetype netrw nnoremap <buffer> <nowait> q :quit<CR>
augroup END

function! s:restore_cursor() abort
	" Commit messages, rebase todos, and diffs start at the top.
	if &filetype =~# 'commit' || &filetype ==# 'gitrebase' || &diff
		return
	endif
	if line("'\"") > 0
		if line("'\"") <= line("$")
			normal! g`"
		else
			keepjumps normal! G
		endif
	endif
endfunction
