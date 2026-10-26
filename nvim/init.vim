set tabstop=4
set shiftwidth=0
set ignorecase
set smartcase
set mouse=
set clipboard=unnamedplus
set laststatus=3
set textwidth=120

set backup
set backupdir-=.
set undofile
set undolevels=99999
set undoreload=99999
packadd nvim.undotree
nnoremap <silent> <nowait> <Leader>u :Undotree<CR>

set notermguicolors
colorscheme default
highlight Search cterm=italic
highlight CurSearch cterm=italic
highlight Comment ctermfg=8 cterm=italic
highlight Constant ctermfg=5
highlight Type ctermfg=5
highlight PreProc ctermfg=6 cterm=italic
highlight Error cterm=italic,bold
let g:gitcommit_summary_length = &textwidth

set list
set listchars+=extends:>,precedes:<
highlight! link NonText Comment
highlight! link LineNr Comment

set dictionary=/usr/share/dict/words
set spell
set spelllang=en_ca,en_us
set spellcapcheck=
highlight clear SpellBad
highlight clear SpellCap
highlight clear SpellRare
highlight clear SpellLocal
nnoremap <silent> <nowait> <Leader>p :set spell!<CR>
command Mkspell execute 'mkspell! ' . fnameescape(stdpath('data') . '/site/spell/en.utf-8.add')

" https://github.com/neovim/neovim/issues/39337
let g:termfeatures = get(g:, 'termfeatures', {})
let g:termfeatures.osc52 = v:false

noremap ; :
noremap : ;
inoremap <silent> <nowait> <M-BS> <C-w>
cnoremap <nowait> <M-BS> <C-w>
function! s:update_myvimrc() abort
	if expand('%:p') ==# $MYVIMRC
		update
	endif
endfunction
nnoremap <silent> <nowait> <Leader>s :call <SID>update_myvimrc() \| source $MYVIMRC<CR>

nnoremap <silent> <nowait> <Leader>h :let v:hlsearch = !v:hlsearch<CR>
nnoremap <nowait> <Leader>r :%s##
" https://vim.fandom.com/wiki/Search_for_visually_selected_text
vnoremap // "zy/\V<C-R>=substitute(escape(@z,'/\'),'\n','\\n','g')<CR><CR>

nnoremap <silent> <nowait> q :quit<CR>
nnoremap <silent> <nowait> <C-q> :quitall!<CR>
inoremap <silent> <nowait> <C-q> <Esc>:quitall!<CR>
nnoremap <silent> <nowait> <C-s> :xit<CR>
inoremap <silent> <nowait> <C-s> <Esc>:xit<CR>
let s:orig_file = get(s:, 'orig_file', resolve(expand('%:p')))
function! s:exit_and_run() abort
	update
	if !empty($AQSNOW_FISH_RENDEZVOUS)
		if resolve(expand('%:p')) ==# s:orig_file && (line('$') > 1 || getline(1) != "")
			call writefile([@%], $AQSNOW_FISH_RENDEZVOUS)
		endif
	endif
	xit
endfunction
nnoremap <silent> <nowait> <M-CR> :call <SID>exit_and_run()<CR>
inoremap <silent> <nowait> <M-CR> <Esc>:call <SID>exit_and_run()<CR>

inoremap <nowait> <C-a> <C-o>^
inoremap <nowait> <C-d> <Del>
inoremap <nowait> <C-k> <C-o>D
cnoremap <nowait> <C-a> <Home>
cnoremap <nowait> <C-d> <Del>

vnoremap <silent> <nowait> > >gv
vnoremap <silent> <nowait> < <gv
nmap <silent> <nowait> <C-_> gcc
imap <silent> <nowait> <C-_> <C-o>gcc
vmap <silent> <nowait> <C-_> gc

set completeopt=menuone,noselect,popup
set complete+=U,kspell,i,d,f,o
inoremap <silent><expr> <C-Space> pumvisible() ? "\<C-n>" :
	   \ strpart(getline('.'), 0, col('.') - 1) =~# '\f*/\f*$'
	   \ ? "\<C-x>\<C-f>" : "\<C-n>"
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <C-e> pumvisible() ? "\<C-e>" : "\<C-o>$"
highlight PmenuMatch cterm=underline
highlight PmenuSel cterm=italic,underline,bold
highlight PmenuMatchSel cterm=italic,bold

command Mkdirp write ++p
nnoremap <silent> <nowait> <Leader>m :Mkdirp<CR>

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
	autocmd FocusLost * nested if !empty(getbufinfo({'bufmodified': 1})) | silent! wall | stopinsert | endif
	autocmd filetype gitcommit setlocal tabstop=4 textwidth=120
	autocmd filetype html,jsonc,fish setlocal expandtab
	autocmd BufRead,BufNewFile *.json setlocal filetype=jsonc
	autocmd BufReadPost * call <SID>restore_cursor()
augroup END
nnoremap <silent> <nowait> <Leader>w :keeppatterns %s/\s\+$//<CR>
nnoremap <silent> <nowait> <Leader>= :keeppatterns %s/^\s*+//<CR>
