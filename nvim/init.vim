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

set notermguicolors
colorscheme default
highlight Comment ctermfg=8 cterm=italic
highlight Constant ctermfg=5
highlight Type ctermfg=5
highlight PreProc ctermfg=6 cterm=italic
let g:gitcommit_summary_length = &textwidth

set list
set listchars+=extends:>,precedes:<
highlight! link NonText Comment

set dictionary=/usr/share/dict/words
set spell
set spelllang=en_ca,en_us
set spellcapcheck=
nnoremap <silent> <nowait> <Leader>p :set spell!<CR>
command Mkspell execute 'mkspell! ' . fnameescape(stdpath('data') . '/site/spell/en.utf-8.add')

" https://github.com/neovim/neovim/issues/39337
let g:termfeatures = get(g:, 'termfeatures', {})
let g:termfeatures.osc52 = v:false

noremap ; :
noremap : ;
inoremap <silent> <nowait> <M-BS> <C-w>
cnoremap <nowait> <M-BS> <C-w>
nnoremap <silent> <nowait> <Leader>s :source $MYVIMRC<CR>

nnoremap <silent> <nowait> <Leader>h :let v:hlsearch = !v:hlsearch<CR>
nnoremap <nowait> <Leader>r :%s##
" https://vim.fandom.com/wiki/Search_for_visually_selected_text
vnoremap // "zy/\V<C-R>=escape(@z,'/\')<CR><CR>

nnoremap <silent> <nowait> q :quit<CR>
nnoremap <silent> <nowait> <C-q> :quitall!<CR>
inoremap <silent> <nowait> <C-q> <Esc>:quitall!<CR>
nnoremap <silent> <nowait> <C-s> :xit<CR>
inoremap <silent> <nowait> <C-s> <Esc>:xit<CR>
nnoremap <silent> <nowait> <M-CR> :if $AQSNOW_FISH_RENDEZVOUS != "" \| call writefile([@%], $AQSNOW_FISH_RENDEZVOUS) \| endif \| xit<CR>
inoremap <silent> <nowait> <M-CR> <Esc>:if $AQSNOW_FISH_RENDEZVOUS != "" \| call writefile([@%], $AQSNOW_FISH_RENDEZVOUS) \| endif \| xit<CR>

inoremap <nowait> <C-a> <C-o>^
inoremap <nowait> <C-d> <Del>
inoremap <nowait> <C-k> <C-o>dd
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
highlight PmenuSel cterm=bold,italic,underline
highlight PmenuMatchSel cterm=bold,italic

command DiffOrig vert new | set buftype=nofile | read ++edit # | 0d_
			   \ | diffthis | wincmd p | diffthis

augroup aqsnow
	autocmd!
	autocmd FocusLost * nested if !empty(getbufinfo({'bufmodified': 1})) | silent! wall | stopinsert | endif
	autocmd filetype gitcommit setlocal tabstop=4 textwidth=120
	autocmd filetype html,jsonc,fish setlocal expandtab
	autocmd BufRead,BufNewFile *.json setlocal filetype=jsonc
augroup END
nnoremap <silent> <nowait> <Leader>ls :%s/\s\+$// \| nohlsearch<CR>
