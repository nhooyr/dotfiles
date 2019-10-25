let s:vim_plug = '~/.local/share/nvim/site/autoload/plug.vim'
if empty(glob(s:vim_plug, 1))
  execute 'silent !curl -fLo' s:vim_plug '--create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
endif

call plug#begin(stdpath('data') . '/plugged')
Plug 'wimstefan/Lightning'
Plug 'simnalamburt/vim-mundo'
Plug 'tpope/vim-surround'
call plug#end()

command! PU PlugUpgrade | PlugUpdate

noremap ; :
noremap : ;
nnoremap <silent> <C-S> :source $MYVIMRC<CR>
nnoremap k gk
nnoremap j gj
nnoremap Y y$
nnoremap <silent> q :quit<CR>
xnoremap Y "*y

" Enable once colorscheme ported from sublime text.
"set cursorline

cnoremap <C-N> <Down>
cnoremap <C-P> <Up>
cnoremap <C-F> <Right>
cnoremap <C-B> <Left>
cnoremap <C-A> <Home>
cnoremap <C-D> <Del>

cnoremap <M-f> <S-Right>
cnoremap <M-b> <S-Left>

cnoremap <M-d> <S-Right><C-w>
cnoremap <M-BS> <C-w>

nnoremap <C-E> 2<C-E>
nnoremap <C-Y> 2<C-Y>
nnoremap <silent> <Leader>h :let v:hlsearch = !v:hlsearch<CR>

nnoremap <C-k> <C-W>k
nnoremap <C-l> <C-W>l
nnoremap <C-j> <C-W>j
nnoremap <C-h> <C-W>h

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
colorscheme lightning
if has("vim_starting")
  set tabstop=2
  set softtabstop=2
  set shiftwidth=2
endif

let g:mundo_verbose_graph = 0
let g:mundo_close_on_revert = 1
nnoremap <silent> <Leader>u :MundoToggle<CR>

" https://stackoverflow.com/questions/9850360/what-is-netrwhist
let g:netrw_dirhistmax = 0
