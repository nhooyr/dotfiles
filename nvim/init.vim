function! s:plugins() abort
  let s:vim_plug = '~/.local/share/nvim/site/autoload/plug.vim'
  if empty(glob(s:vim_plug, 1))
    execute 'silent !curl -fLo' s:vim_plug '--create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
    augroup vim-plug
      autocmd!
      autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
    augroup END
  endif

  call plug#begin(stdpath('data') . '/plugged')
  Plug 'peitalin/vim-jsx-typescript'
  " Default syntax does not work well.
  Plug 'leafgarland/typescript-vim'

  Plug 'simnalamburt/vim-mundo'
  Plug 'tpope/vim-surround'
  Plug 'machakann/vim-highlightedyank'
  Plug 'tpope/vim-unimpaired'

  Plug 'prabirshrestha/asyncomplete.vim'
  Plug 'prabirshrestha/async.vim'
  Plug 'prabirshrestha/vim-lsp'
  Plug 'prabirshrestha/asyncomplete-lsp.vim'
  Plug 'mattn/vim-lsp-settings'

  Plug 'tpope/vim-endwise'
  Plug 'jiangmiao/auto-pairs'
  Plug 'alvan/vim-closetag'
  call plug#end()

  command! PU PlugUpgrade | PlugUpdate
  command! PC PlugClean
endfunction

call s:plugins()

function! s:settings() abort
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
  set autochdir

  " Have seen bizarre behaviour with this.
  set guicursor=

  set complete-=t
endfunction
call s:settings()

function! s:binds() abort
  command! S :source $MYVIMRC

  noremap ; :
  nnoremap <silent> <nowait> q :quit<CR>
  nnoremap <silent> <leader>ec :e $MYVIMRC<CR>
  nnoremap <silent> k gk
  nnoremap <silent> j gj
  " https://vim.fandom.com/wiki/Format_pasted_text_automatically
  nnoremap <silent> p :normal! p=`]<CR>
  nnoremap <silent> P :normal! P=`]<CR>

  nnoremap <silent> Y y$

  nnoremap <silent> 0 ^
  nnoremap <silent> ^ 0

  " Always use black hole register for deletes.
  "
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
  " noremap! <C-f> <Right>
  noremap! <C-b> <Left>
  noremap! <C-e> <End>
  cnoremap <C-a> <Home>
  inoremap <C-a> <C-o>^
  noremap! <C-d> <Del>
  cnoremap <C-k> <C-c>:
  inoremap <C-k> <Esc>"_ddO

  cnoremap <M-f> <S-Right>
  cnoremap <M-b> <S-Left>
  " This one does not work well because C-w uses iskeyword but S-Right does not
  cnoremap <M-d> <S-Right><C-w>
  cnoremap <M-BS> <C-w>

  inoremap <M-f> <C-o>w
  inoremap <M-b> <C-o>b
  inoremap <M-d> <C-o>dw
  inoremap <M-BS> <C-w>

  nnoremap <silent> <C-q> :quitall!<CR>
  inoremap <C-q> <Esc>:quitall!<CR>
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

  noremap <silent> <C-z> zz
  noremap! <silent> <C-z> <ESC>zz

  " https://stackoverflow.com/a/9464929/4283659
  nnoremap <silent> <Leader>s :echo map(synstack(line('.'), col('.')), 'synIDattr(v:val, "name")')<CR>

  " Revert to last write.
  nnoremap <silent> <Leader>rv :earlier 1f<CR>
endfunction
call s:binds()

function! s:netrw() abort
  " https://stackoverflow.com/questions/9850360/what-is-netrwhist
  let g:netrw_dirhistmax = 0
  let g:netrw_banner = 0
  " Hides ./ and ../
  let g:netrw_list_hide = '^\.\.\=/$'
  nnoremap <silent> - :Ex<CR>
endfunction
call s:netrw()

function! s:plugin_settings() abort
  let g:mundo_close_on_revert = 1
  nnoremap <silent> <Leader>u :MundoToggle<CR>

  let g:highlightedyank_highlight_duration = 150

  let g:closetag_filenames = '*.html,*.xhtml,*.phtml,*.tsx,*.jsx'

  let g:AutoPairsShortcutBackInsert = ''
endfunction
call s:plugin_settings()

augroup nhooyr
  autocmd!
  autocmd FileType gitcommit startinsert
  " q should always quit.
  " In particular this was added for man.vim which uses close instead of quit
  " and so we cannot quit if there is only a man window left.
  autocmd FileType * nnoremap <buffer> <nowait> <silent> q :quit<CR>
  " endwise has an obnoxious keybinding that interferes with my C-x.
  autocmd FileType * silent! iunmap <C-x><CR>
augroup END

function! s:quick() abort
  function! s:exit_quick() abort
    if $QUICK_PATH != ""
      call system("touch " . $QUICK_PATH)
    endif
    quit!
  endfunction

  nnoremap <silent> <M-v> :call <SID>exit_quick()<CR>
  inoremap <silent> <M-v> <ESC>:call <SID>exit_quick()<CR>
endfunction
call s:quick()

function! s:lsp() abort
  let g:asyncomplete_auto_popup = 0
  let g:lsp_diagnostics_enabled = 0
  imap <c-space> <Plug>(asyncomplete_force_refresh)
endfunction
call s:lsp()
