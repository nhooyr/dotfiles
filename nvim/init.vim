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
Plug 'machakann/vim-highlightedyank'

Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'josa42/coc-go', {'do': 'yarn install --frozen-lockfile'}
Plug 'neoclide/coc-tsserver', {'do': 'yarn install --frozen-lockfile'}
Plug 'iamcco/coc-vimlsp', {'do': 'yarn install --frozen-lockfile'}
Plug 'neoclide/coc-snippets', {'do': 'yarn install --frozen-lockfile'}
Plug 'weirongxu/coc-calc', {'do': 'yarn install --frozen-lockfile'}
Plug 'clangd/coc-clangd', {'do': 'yarn install --frozen-lockfile'}
Plug 'voldikss/coc-cmake', {'do': 'yarn install --frozen-lockfile'}
Plug 'neoclide/coc-json', {'do': 'yarn install --frozen-lockfile'}
Plug 'neoclide/coc-yaml', {'do': 'yarn install --frozen-lockfile'}
Plug 'neoclide/coc-css', {'do': 'yarn install --frozen-lockfile'}
Plug 'neoclide/coc-html', {'do': 'yarn install --frozen-lockfile'}
Plug 'neoclide/coc-rls', {'do': 'yarn install --frozen-lockfile'}
Plug 'iamcco/coc-svg', {'do': 'yarn install --frozen-lockfile'}

Plug 'tpope/vim-endwise'
Plug 'jiangmiao/auto-pairs'
call plug#end()

command! Pu PlugUpgrade | PlugUpdate
command! Pc PlugClean

command! S :source $MYVIMRC

noremap ; :
nnoremap <silent> <nowait> q :quit<CR>
nnoremap <silent> <leader>ec :e $MYVIMRC<CR>
nnoremap <silent> k gk
nnoremap <silent> j gj
nnoremap <silent> p ]p
nnoremap <silent> P ]P
nnoremap <silent> Y y$

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
noremap <silent> S "_S

vnoremap <silent> > >gv
vnoremap <silent> < <gv

" Emacs style insert and command line keybindings
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
cnoremap <M-d> <S-Right><C-w>
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

nnoremap <silent> <C-q> :quit<CR>
inoremap <C-q> <Esc>:quit<CR>
nnoremap <silent> <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>
nnoremap <silent> <C-x> :x<CR>
inoremap <C-x> <Esc>:x<CR>

nnoremap <silent> <C-E> 2<C-E>
nnoremap <silent> <C-Y> 2<C-Y>
nnoremap <silent> <Leader>h :let v:hlsearch = !v:hlsearch<CR>

nnoremap <silent> <C-k> <C-W>k
nnoremap <silent> <C-l> <C-W>l
nnoremap <silent> <C-j> <C-W>j
nnoremap <silent> <C-h> <C-W>h

set clipboard=unnamed
set noshowmode
set signcolumn=no
set cursorline
set noshowcmd
set splitright
set splitbelow
set wildignorecase
set ignorecase
set smartcase
set undofile
set undolevels=10000
set inccommand=nosplit
set gdefault
let $COLOR = stdpath('config') . '/colors/elysian.vim'
colorscheme elysian
augroup elysian
  autocmd!
  autocmd BufWritePost elysian.vim colorscheme elysian
  autocmd BufWritePost $MYVIMRC source $MYVIMRC
augroup END
if has('vim_starting')
  set tabstop=2
  set softtabstop=2
  set shiftwidth=2
  set expandtab
endif
set shortmess+=aIAc
set mouse=a
set rulerformat=%=%l
set updatetime=100
set laststatus=1

let g:mundo_close_on_revert = 1
nnoremap <silent> <Leader>u :MundoToggle<CR>

augroup nhooyr
  autocmd!
  autocmd FileType gitcommit startinsert
  " q should always quit.
  " In particular this was added for man.vim which uses close instead of quit
  " and so we cannot quit if there is only a man window left.
  autocmd FileType * nnoremap <buffer> <nowait> <silent> q :quit<CR>
  autocmd FileType * iunmap <C-x><CR>
augroup END

let g:highlightedyank_highlight_duration = 150

" https://stackoverflow.com/questions/9850360/what-is-netrwhist
let g:netrw_dirhistmax = 0
let g:netrw_banner = 0
" Hides ./ and ../
let g:netrw_list_hide = '^\.\.\=/$'
nnoremap <silent> - :Ex<CR>

" https://stackoverflow.com/a/9464929/4283659
nnoremap <silent> <Leader>s :echo map(synstack(line('.'), col('.')), 'synIDattr(v:val, "name")')<CR>

" Revert to last write.
nnoremap <silent> <Leader>rv :earlier 1f<CR>

call nhooyr_coc#init()
