function! s:plugins() abort
  let s:vim_plug = "~/.local/share/nvim/site/autoload/plug.vim"
  if empty(glob(s:vim_plug, 1))
    execute "silent !curl -fLo" s:vim_plug "--create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
    augroup vim-plug
      autocmd!
      autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
    augroup END
  endif

  call plug#begin(stdpath("data") . "/plugged")
  Plug 'peitalin/vim-jsx-typescript'
  " Default syntax does not work well.
  Plug 'leafgarland/typescript-vim'
  Plug 'fatih/vim-go'

  Plug 'simnalamburt/vim-mundo'
  Plug 'machakann/vim-highlightedyank'
  Plug 'ntpeters/vim-better-whitespace'

  Plug 'tpope/vim-unimpaired'
  Plug 'tpope/vim-surround'
  Plug 'tpope/vim-endwise'
  Plug 'tpope/vim-sleuth'
  Plug 'tpope/vim-fugitive'
  Plug 'tomtom/tcomment_vim'

  Plug 'Shougo/neosnippet.vim'
  Plug 'Shougo/neosnippet-snippets'
  Plug 'neovim/nvim-lsp'

  Plug 'mattn/emmet-vim'
  Plug 'PeterRincker/vim-argumentative'
  call plug#end()

  command! PU PlugUpgrade | PlugUpdate
  command! PC PlugClean
endfunction
call s:plugins()

function! s:settings() abort
  set clipboard=unnamed
  set noshowmode
  set signcolumn=no
  " set cursorline
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
  let $COLOR = stdpath("config") . "/colors/elysian.vim"
  colorscheme elysian
  if has("vim_starting")
    set tabstop=2
    let &shiftwidth=&tabstop
    set expandtab
  endif
  set shortmess+=aIAc
  set mouse=a
  set noruler
  set updatetime=100
  set laststatus=1
  " set autochdir

  " Neovim's TUI cursor bugs out often enough.
  set guicursor=

  set foldmethod=indent
  set foldnestmax=1
  if has("vim_starting")
    set foldlevel=1
  endif
  set textwidth=100

  set formatoptions+=cro

  " https://vim.fandom.com/wiki/Search_only_in_unfolded_text
  set foldopen=
  " https://github.com/neovim/neovim/issues/2067#issuecomment-398283872
  let &fillchars="eob: ,diff: "

  set statusline=[%f]

  set diffopt+=foldcolumn:0,algorithm:histogram
endfunction
call s:settings()

function! s:binds() abort
  command! S :source $MYVIMRC

  noremap ; :
  noremap , ;
  nnoremap <silent> <nowait> q :quit<CR>
  nnoremap <nowait> Q q
  nnoremap <silent> <leader>ee :e $MYVIMRC<CR>
  nnoremap <silent> <leader>ec :e $COLOR<CR>
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
  noremap! <C-f> <Right>
  noremap! <C-b> <Left>
  noremap! <C-e> <End>
  inoremap <nowait> <C-g> <C-e>
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
  inoremap <silent> <C-q> <Esc>:quitall!<CR>
  cnoremap <silent> <C-q> <C-c>:quitall!<CR>

  nnoremap <silent> <C-e> 2<C-e>
  nnoremap <silent> <C-y> 2<C-y>
  nnoremap <silent> <Leader>h :let v:hlsearch = !v:hlsearch<CR>

  nnoremap <silent> <C-k> <C-W>k
  nnoremap <silent> <C-l> <C-W>l
  nnoremap <silent> <C-j> <C-W>j
  nnoremap <silent> <C-h> <C-W>h

  noremap <silent> <C-z> zz
  inoremap <silent> <C-z> <C-o>zz

  " https://stackoverflow.com/a/9464929/4283659
  nnoremap <silent> <Leader>l :echo map(synstack(line("."), col(".")), "synIDattr(v:val, 'name')")<CR>

  " Revert to last write.
  nnoremap <silent> <Leader>rv :earlier 1f<CR>
  " Adapted from https://www.reddit.com/r/vim/comments/7gqowu/hungrysmart_backspace_support/
  function! s:backspace() abort
    if getline(line(".")) =~ '\S'
      " Fallback to default behaviour.
      call feedkeys("\<BS>", "n")
      return
    endif

    " Remove all text on the current line as it's just whitespace.
    if col(".") > 1
      call feedkeys("\<BS>", "n")
    endif
    call feedkeys("\<BS>", "n")

    if getline(line(".")-1) !~ '\S'
      " Reindent current line if empty.
      call feedkeys("\<C-o>cc", "n")
    endif
  endfunction

  inoremap <silent> <BS> <C-O>:call <SID>backspace()<CR>

  nnoremap <silent> <Leader>w :StripWhitespace<CR>

  nnoremap <silent> <Leader>sc :colorscheme elysian<CR>
  nnoremap <silent> <Leader>ss :source $MYVIMRC<CR>

  nnoremap <silent> <Leader>d "ayy"ap
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

  let g:surround_no_insert_mappings = 1

  map! <silent> <C-j> <Plug>(neosnippet_expand_or_jump)

  let g:user_emmet_leader_key = "<M-e>"
  let g:user_emmet_mode="i"

  let g:go_gopls_enabled = 0
  let g:go_echo_go_info = 0
  let g:go_template_autocreate = 0

  nmap <M-c> gcc

  augroup nhooyr_plugins
    autocmd!
    autocmd FileType git DisableWhitespace
  augroup END
endfunction
call s:plugin_settings()

augroup nhooyr
  autocmd!
  " q should always quit.
  " In particular this was added for man.vim which uses close instead of quit
  " and so we cannot quit if there is only a man window left.
  autocmd FileType * nnoremap <buffer> <nowait> <silent> q :quit<CR>
  " https://github.com/neovim/neovim/issues/1936#issuecomment-309311829
  autocmd FocusGained * checktime
  autocmd FocusLost * wshada

  autocmd BufWinEnter * call s:restore_cursor()

  " Autosave from https://github.com/907th/vim-auto-save#events.
  autocmd TextChanged * silent! write
  autocmd InsertLeave * silent! write

  autocmd FileType qf setlocal statusline=%f
augroup END

function! s:restore_cursor() abort
  if &filetype ==# "gitcommit"
    return
  endif
  if line("'\"") <= line("$")
    normal! g'"zz
  endif
endfunction

function! s:quick() abort
  function! s:exit_quick() abort
    if !empty($QUICK_PATH)
      call system("touch " . $QUICK_PATH)
    endif
    quit!
  endfunction

  nnoremap <silent> <M-v> :call <SID>exit_quick()<CR>
  inoremap <silent> <M-v> <ESC>:call <SID>exit_quick()<CR>
endfunction
call s:quick()

function! s:lsp() abort
  if !exists("g:nhooyr_lsp")
    let g:nhooyr_lsp = 1
    lua << EOF
    local lsp_loaded, lsp = pcall(require, "nvim_lsp")
    if not lsp_loaded then
      return
    end

    -- Disable diagnostics globally.
    vim.lsp.callbacks["textDocument/publishDiagnostics"] = function() end

    lsp.gopls.setup{}
    lsp.tsserver.setup{}
    lsp.vimls.setup{}
    lsp.clangd.setup{}
    lsp.sumneko_lua.setup{}
EOF
  endif

  " https://github.com/vim/vim/issues/3412#issuecomment-642821562
  set complete=.
  set completeopt=menuone,noselect
  set pumheight=5

  inoremap <C-Space> <C-x><C-o>
  inoremap <C-l> <C-x><C-f>

  function! s:b_lsp() abort
    nnoremap <silent> <buffer> gd    <cmd>lua vim.lsp.buf.declaration()<CR>
    nnoremap <silent> <buffer> <C-]> <cmd>lua vim.lsp.buf.definition()<CR>
    nnoremap <silent> <buffer> K     <cmd>lua vim.lsp.buf.hover()<CR>
    nnoremap <silent> <buffer> gi    <cmd>lua vim.lsp.buf.implementation()<CR>
    nnoremap <silent> <buffer> gh    <cmd>lua vim.lsp.buf.signature_help()<CR>
    nnoremap <silent> <buffer> gt    <cmd>lua vim.lsp.buf.type_definition()<CR>
    nnoremap <silent> <buffer> gr    <cmd>lua vim.lsp.buf.references()<CR>
    nnoremap <silent> <buffer> gs    <cmd>lua vim.lsp.buf.document_symbol()<CR>
    nnoremap <silent> <buffer> gw    <cmd>lua vim.lsp.buf.workspace_symbol()<CR>
    nnoremap <silent> <buffer> ge    <cmd>lua vim.lsp.buf.rename()<CR>

    setlocal omnifunc=v:lua.vim.lsp.omnifunc
  endfunction

  augroup lsp
    autocmd!
    autocmd FileType go,vim,lua,typescript*,c,cpp call s:b_lsp()
  augroup END
endfunction
call s:lsp()
