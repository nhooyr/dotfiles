if &shell =~# 'fish$'
    set shell=sh
endif

let s:vim_plug = '~/.local/share/nvim/site/autoload/plug.vim'
if empty(glob(s:vim_plug, 1))
  execute 'silent !curl -fLo' s:vim_plug '--create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
	augroup vim-plug
		autocmd!
		autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
	augroup END
endif

call plug#begin(stdpath('data') . '/plugged')
Plug 'simnalamburt/vim-mundo'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-fugitive'
Plug 'machakann/vim-highlightedyank'
Plug 'justinmk/vim-dirvish'
Plug '/usr/local/opt/fzf'
Plug 'junegunn/fzf.vim'
call plug#end()

command! Pu PlugUpgrade | PlugUpdate
command! Pc PlugClean

command! S :source $MYVIMRC

noremap ; :
nnoremap <silent> q :quit!<CR>
nnoremap <silent> Q q
nnoremap <silent> <leader>ec :e $MYVIMRC<CR>
nnoremap <silent> <leader>f :file<CR>
nnoremap <silent> k gk
nnoremap <silent> j gj
nnoremap <silent> p ]p
nnoremap <silent> P ]P
nnoremap <silent> Y y$
xnoremap <silent> Y "*y

nnoremap <silent> 0 ^
nnoremap <silent> ^ 0

" Always use black hole register for deletes.
" Below we set clipboard to unnamed to always use clipboard
" for yanks.
nnoremap <silent> <BS> "_d
nnoremap <silent> <BS><BS> "_dd
vnoremap <silent> <BS> "_d
nnoremap <silent> x "_x
vnoremap <silent> x "_x
nnoremap <silent> c "_c
vnoremap <silent> c "_c
nnoremap <silent> C "_C
vnoremap <silent> C "_C
nnoremap <silent> s "_s
vnoremap <silent> s "_s
nnoremap <silent> S "_S
vnoremap <silent> S "_S

vnoremap <silent> > >gv
vnoremap <silent> < <gv

" Emacs style insert and commadn line keybindings
" https://github.com/maxbrunsfeld/vim-emacs-bindings/blob/master/plugin/emacs-bindings.vim
cnoremap <C-N> <Down>
cnoremap <C-P> <Up>
cnoremap <C-F> <Right>
cnoremap <C-B> <Left>
cnoremap <C-A> <Home>
cnoremap <C-D> <Del>
cnoremap <C-H> <BS>
cnoremap <C-k> <C-c>:
cnoremap <M-f> <S-Right>
cnoremap <M-b> <S-Left>
" This one does not work well because C-w uses iskeyword but S-Right does not
"cnoremap <M-d> <S-Right><C-w>
cnoremap <M-BS> <C-w>
inoremap <C-N> <Down>
inoremap <C-P> <Up>
inoremap <C-F> <Right>
inoremap <C-B> <Left>
inoremap <C-A> <Home>
inoremap <C-E> <End>
inoremap <C-D> <Del>
inoremap <C-H> <BS>
inoremap <C-k> <Esc>"_ddO
inoremap <M-f> <C-o>w
inoremap <M-b> <C-o>b
inoremap <M-d> <C-o>dw
inoremap <M-BS> <C-w>

nnoremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>
nnoremap <C-x> :x<CR>
inoremap <C-x> <Esc>:x<CR>

nnoremap <silent> <C-E> 2<C-E>
nnoremap <silent> <C-Y> 2<C-Y>
nnoremap <silent> <Leader>h :let v:hlsearch = !v:hlsearch<CR>

nnoremap <silent> <C-k> <C-W>k
nnoremap <silent> <C-l> <C-W>l
nnoremap <silent> <C-j> <C-W>j
nnoremap <silent> <C-h> <C-W>h

nnoremap <silent> <Leader>r :set columns=85<CR>

set clipboard=unnamed
set noshowmode
set noruler
"set laststatus=0
set cursorline
set noshowcmd
set splitright
set splitbelow
set wildignorecase
set ignorecase
set smartcase
set undofile
set undolevels=1000
set number
set inccommand=nosplit
set gdefault
colorscheme elysian
augroup elysian
  autocmd!
  autocmd BufWritePost elysian.vim colorscheme elysian
augroup END
if has("vim_starting")
  set tabstop=4
  set softtabstop=4
  set shiftwidth=4
endif
set shortmess+=aI

let g:mundo_verbose_graph = 0
let g:mundo_close_on_revert = 1
nnoremap <silent> <Leader>u :MundoToggle<CR>

" https://stackoverflow.com/questions/9850360/what-is-netrwhist
let g:netrw_dirhistmax = 0

augroup nhooyr
	autocmd!
	" https://stackoverflow.com/questions/37804435/how-to-enable-line-numbers-for-the-vim-help-permanently
	autocmd FileType * setlocal number
	" https://github.com/neovim/neovim/issues/8350#issuecomment-443707200
	autocmd WinNew * wincmd L
	autocmd FileType gitcommit startinsert
	" q should always quit.
	" In particular this was added for man.vim which uses lclose instead of quit
	" and so we cannot quit if there is only a man window left.
	autocmd FileType * nnoremap <buffer> <silent> q :quit!<CR>
augroup END

" https://github.com/neovim/neovim/issues/10748
let g:man_hardwrap=1

let g:clipboard = {
			\   'name': 'pbcopy',
			\   'copy': {
			\      '+': 'pbcopy',
			\      '*': 'pbcopy',
			\    },
			\   'paste': {
			\      '+': 'pbpaste',
			\      '*': 'pbpaste',
			\   },
			\   'cache_enabled': 1,
			\ }

let g:highlightedyank_highlight_duration = 150

autocmd! FileType fzf set laststatus=0 noshowmode noruler
  \| autocmd BufLeave <buffer> set laststatus=2 showmode ruler
