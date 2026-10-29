set number
set tabstop=4
set shiftwidth=0
set ignorecase
set smartcase
set mouse=
vnoremap <C-c> "+y
nnoremap gp `[v`]
set laststatus=3
set textwidth=120
set foldmethod=indent
set foldlevel=999
set foldlevelstart=999
set shortmess+=I

set backup
set backupdir-=.
set undofile
set undolevels=99999
set undoreload=99999
packadd nvim.undotree
nnoremap <Leader>u :Undotree<CR>

set notermguicolors
colorscheme default
highlight MatchParen ctermfg=6
highlight Comment ctermfg=8 cterm=italic
highlight Constant ctermfg=5
highlight Type ctermfg=5
highlight PreProc ctermfg=6 cterm=italic
highlight Error cterm=italic,bold
highlight WinSeparator cterm=bold
let g:gitcommit_summary_length = &textwidth

set list
set listchars+=extends:>,precedes:<
highlight! link NonText Comment
highlight! link LineNr Comment
highlight! link Folded Comment

set dictionary=/usr/share/dict/words
set spelllang=en_ca,en_us
function! s:toggle_spell() abort
	set spell!
	if &spell ==# 1
		highlight SpellBad cterm=underline
		highlight SpellCap cterm=underline
		highlight SpellRare cterm=underline
		highlight SpellLocal cterm=underline
	else
		highlight clear SpellBad
		highlight clear SpellCap
		highlight clear SpellRare
		highlight clear SpellLocal
	endif
endfunction
if &spell ==# 0
	set spell
	call s:toggle_spell()
endif
nnoremap <Leader>z :call <SID>toggle_spell()<CR>
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
nnoremap <Leader>s :if expand('%:p') ==# $MYVIMRC \| update \| endif \| source $MYVIMRC<CR>
let g:netrw_banner = 0
let g:netrw_list_hide = '^\.\.\?\/$'
nnoremap - :edit %:p:h<CR>

nnoremap <Leader>h :let v:hlsearch = !v:hlsearch<CR>
nnoremap <Leader>r :%s###g<Left><Left>
" https://vim.fandom.com/wiki/Search_for_visually_selected_text
vnoremap // "zy/\V<C-R>=substitute(escape(@z,'/\'),'\n','\\n','g')<CR><CR>
vmap <Leader>r //<Leader>r

nnoremap <M-q> q
nnoremap q :quit<CR>
nnoremap <C-s> :xit<CR>
inoremap <C-s> <Esc>:xit<CR>
nnoremap <M-w> :wall<CR>
inoremap <M-w> <Esc>:wall<CR>
nnoremap <C-q> :qall!<CR>
inoremap <C-q> <Esc>:qall!<CR>

let s:orig_file = get(s:, 'orig_file', resolve(expand('%:p')))
function! s:quit_and_run() abort
	wall
	if !empty($AQSNOW_FISH_RENDEZVOUS)
		if resolve(expand('%:p')) ==# s:orig_file && (line('$') > 1 || getline(1) != "")
			call writefile(['true'], $AQSNOW_FISH_RENDEZVOUS)
		endif
	endif
	qall
endfunction
nnoremap <M-CR> :call <SID>quit_and_run()<CR>
inoremap <M-CR> <Esc>:call <SID>quit_and_run()<CR>
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

nnoremap c "_c
vnoremap c "_c
nnoremap C "_C
vnoremap C "_C
nnoremap <BS><BS> "_dd
nnoremap <BS> "_d
vnoremap <BS> "_d
nnoremap <silent> <Leader>d :t.<CR>
nnoremap <silent> <M-d> :t.<CR>

set completeopt=menuone,noselect,popup
set complete+=U,kspell,i,d,f,o
inoremap <expr> <C-Space> pumvisible() ? "\<C-n>" :
	   \ strpart(getline('.'), 0, col('.') - 1) =~# '\f*/\f*$'
	   \ ? "\<C-x>\<C-f>" : "\<C-n>"
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <C-e> pumvisible() ? "\<C-e>" : "\<C-o>$"
highlight PmenuMatch cterm=underline
highlight PmenuSel cterm=italic,underline,bold
highlight PmenuMatchSel cterm=italic,bold

command -bar -bang -nargs=0 Mkdirp write<bang> ++p
nnoremap <Leader>m :Mkdirp<CR>

command DiffOrig vert new | set buftype=nofile | read ++edit # | 0d_ |
			   \ diffthis | wincmd p | diffthis

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

" For BufReadPost restore_cursor.
filetype plugin indent on
augroup aqsnow
	autocmd!
	autocmd FocusLost * nested if !empty(getbufinfo({'bufmodified': 1})) | silent! wall | endif
	autocmd filetype gitcommit setlocal tabstop=4 textwidth=120
	autocmd filetype html,jsonc,fish setlocal expandtab
	autocmd BufRead,BufNewFile *.json setlocal filetype=jsonc
	autocmd BufReadPost * call <SID>restore_cursor()
	autocmd filetype fish setlocal formatprg=fish_indent
	autocmd filetype sh let &l:formatprg='shfmt -s'
	autocmd BufWritePost $MYVIMRC autocmd aqsnow SafeState * ++once source $MYVIMRC
	autocmd filetype gitcommit nnoremap <buffer> ]c /^@@<CR>
	autocmd filetype gitcommit nnoremap <buffer> [c ?^@@<CR>
	autocmd filetype netrw nnoremap <buffer> <nowait> q :quit<CR>
augroup END
nnoremap <Leader>w :keeppatterns %s/\s\+$//<CR>
nnoremap <Leader>= :keeppatterns %s/^\s*[+-]//<CR>
nnoremap <Leader>n :next<CR>
nnoremap <Leader>p :prev<CR>
nnoremap <M-n> *
nnoremap <M-p> #
