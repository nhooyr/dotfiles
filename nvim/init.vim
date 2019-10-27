let s:vim_plug = '~/.local/share/nvim/site/autoload/plug.vim'
if empty(glob(s:vim_plug, 1))
  execute 'silent !curl -fLo' s:vim_plug '--create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
endif

call plug#begin(stdpath('data') . '/plugged')
Plug 'simnalamburt/vim-mundo'
Plug 'tpope/vim-surround'
call plug#end()

command! PU PlugUpgrade | PlugUpdate

noremap ; :
nnoremap <silent> <silent> q :quit<CR>
nnoremap <silent> <C-S> :source $MYVIMRC<CR>
nnoremap <silent> <silent> <leader>ec :edit $MYVIMRC<CR>
nnoremap <silent> k gk
nnoremap <silent> j gj
nnoremap <silent> Y y$
xnoremap <silent> Y "*y

cnoremap <silent> <C-N> <Down>
cnoremap <silent> <C-P> <Up>
cnoremap <silent> <C-F> <Right>
cnoremap <silent> <C-B> <Left>
cnoremap <silent> <C-A> <Home>
cnoremap <silent> <C-D> <Del>

cnoremap <silent> <M-f> <S-Right>
cnoremap <silent> <M-b> <S-Left>

cnoremap <silent> <M-d> <S-Right><C-w>
cnoremap <silent> <M-BS> <C-w>

nnoremap <silent> <C-E> 2<C-E>
nnoremap <silent> <C-Y> 2<C-Y>
nnoremap <silent> <Leader>h :let v:hlsearch = !v:hlsearch<CR>

nnoremap <silent> <C-k> <C-W>k
nnoremap <silent> <C-l> <C-W>l
nnoremap <silent> <C-j> <C-W>j
nnoremap <silent> <C-h> <C-W>h

nnoremap <silent> <Leader>r :set columns=85<CR>

set noshowmode
set noruler
set laststatus=0
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
  set tabstop=2
  set softtabstop=2
  set shiftwidth=2
endif
set shortmess+=aI

let g:mundo_verbose_graph = 0
let g:mundo_close_on_revert = 1
nnoremap <silent> <Leader>u :MundoToggle<CR>

" https://stackoverflow.com/questions/9850360/what-is-netrwhist
let g:netrw_dirhistmax = 0

" https://github.com/neovim/neovim/issues/8350#issuecomment-443707200
augroup vertical
  autocmd!
	autocmd WinNew * wincmd L
augroup END

" https://stackoverflow.com/questions/37804435/how-to-enable-line-numbers-for-the-vim-help-permanently
augroup help
	autocmd!
	autocmd FileType * setlocal number
augroup END
