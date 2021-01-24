function! s:plugins() abort
  let s:vim_plug = "~/.local/share/nvim/site/autoload/plug.vim"
  if empty(glob(s:vim_plug, 1))
    execute "silent !curl -fLo" s:vim_plug "--create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
    augroup nhooyr_plug_install
      autocmd!
      autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
    augroup END
  endif

  call plug#begin(stdpath("data") . "/plugged")
  Plug 'peitalin/vim-jsx-typescript'
  " Default syntax does not work well with tsx.
  Plug 'leafgarland/typescript-vim'
  Plug 'fatih/vim-go'

  Plug 'tpope/vim-surround'
  " Plug 'tpope/vim-endwise'
  Plug 'tpope/vim-commentary'
  " Plug 'Raimondi/delimitMate'
  " Plug 'tmsvg/pear-tree'

  Plug 'Shougo/neosnippet.vim'
  Plug 'Shougo/neosnippet-snippets'
  Plug 'neovim/nvim-lsp'

  Plug 'simnalamburt/vim-mundo'
  Plug 'nhooyr/emmet-vim' " Plug 'mattn/emmet-vim'
  Plug 'PeterRincker/vim-argumentative'
  Plug 'godlygeek/tabular'
  Plug 'chrisbra/Recover.vim'
  call plug#end()

  command! PU PlugUpgrade | PlugUpdate
  command! PC PlugClean
endfunction
call s:plugins()

function! s:plugin_settings() abort
  let g:mundo_close_on_revert = 1
  let g:mundo_verbose_graph = 0
  let g:mundo_header = 0
  nnoremap <silent> <Leader>u :MundoToggle<CR>

  let g:surround_no_insert_mappings = 1

  map! <silent> <C-k> <Plug>(neosnippet_expand)
  map! <silent> <C-j> <Plug>(neosnippet_jump)
  imap <silent><expr> <C-l> '- '.strftime("%I:%M:%S%p").': '
  nmap <silent> <M-o> o<C-o>"_d0<C-l>

  let g:user_emmet_leader_key = "<C-y>"
  let g:user_emmet_mode="i"

  let g:go_gopls_enabled = 0
  let g:go_echo_go_info = 0
  let g:go_template_autocreate = 0
  let g:go_fmt_autosave = 0

  let g:delimitMate_expand_cr = 1

  nmap <C-_> gcc
  vmap <C-_> gc
  nmap <M-c> gcgc`]
  imap <C-_> <C-o>gcc

  inoremap <silent> <M-CR> <CR><M-O>

  augroup nhooyr_plugins
    autocmd!
    autocmd FileType markdown noremap <buffer> <silent> <C-t> :Tabularize /\|<CR>
    " https://github.com/fatih/vim-go/blob/bd56f5690807d4a92652fe7a4d10dc08f260564e/ftdetect/gofiletype.vim#L10
    autocmd BufRead,BufNewFile *.gohtml set filetype=gohtmltmpl
  augroup END

  " To avoid conflict with my insert mode <C-x> keybind.
  " From vim-endwise.
  " https://github.com/tpope/vim-endwise/blob/97180a73ad26e1dcc1eebe8de201f7189eb08344/plugin/endwise.vim#L129
  " Have endwise disabled due to delimitMate for now.
  augroup nhooyr_endwise_unmap
    autocmd!
    " autocmd VimEnter * iunmap <C-x><CR>
  augroup END
endfunction
call s:plugin_settings()

function! s:settings() abort
  " set autochdir
  set backup
  set backupdir=~/.local/share/nvim/backup//
  call mkdir(&backupdir, "p")

  set clipboard=unnamed
  set noshowmode
  set signcolumn=no
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
  colorscheme elysian
  set shortmess+=Ic
  " 1. I often open the same file in multiple vim instances so I don't
  "    care for the swap file warning.
  "    And can use :recover for when I know the OS crashed.
  " 2. Nevermind, disabled this as vim's smart enough to not bother me
  "    if there are no changes.
  " 3. Nevermind that nevermind, I often see the warning when using <C-]>
  "    and neovim doesn't recognize then files are the same.
  set shortmess+=A
  set mouse=a
  set noruler
  set updatetime=100
  set laststatus=2

  set title
  set titlestring=%t

  let &listchars.=',space:|'

  " Neovim's TUI cursor bugs out often enough.
  set guicursor=

  " It gets really confusing when line numbers are disabled as you can't tell what's a
  " continuation and usually I don't care for text beyond 120 char as it's probably a
  " link.
  set nowrap

  if has("vim_starting")
    set tabstop=2
    let &shiftwidth=&tabstop
    set expandtab

    set foldmethod=indent
    set foldnestmax=1
    set foldlevel=1
  endif
  set textwidth=90

  set formatoptions+=cro

  " https://vim.fandom.com/wiki/Search_only_in_unfolded_text
  set foldopen=
  " https://github.com/neovim/neovim/issues/2067#issuecomment-398283872
  let &fillchars="eob: ,diff: "

  set diffopt+=foldcolumn:0,algorithm:histogram

  let g:markdown_fenced_languages = ["bash=sh", "go"]


  " Too slow for now, maybe use jobstart later in future but iris.
  " let s:status_filename = ""
  " let s:status_f = ""
  " function! NhooyrStatus() abort
  "   let l:status_filename = expand("%:p")
  "   if l:status_filename !=# s:status_filename
  "     let s:status_filename = l:status_filename
  "     let s:status_f = system("zsh -c 'source ~/src/nhooyr/dotfiles/zsh/zshrc && " .
  "           \ "echo -n " . s:status_filename . " | replace_bookmarks'")
  "   endif

  "   return " " . s:status_f . " %m"
  " endfunction
  " let &statusline="%!NhooyrStatus()"
  " %p shows percentage of *current* line but %P shows percentage of last line visible.
  let &statusline=" %F %m %= %l    %P "

  " Fuck netrw.
  let g:loaded_netrw       = 1
  let g:loaded_netrwPlugin = 1

  augroup nhooyr_settings
    autocmd!
    autocmd TextYankPost * silent! lua require'vim.highlight'.on_yank(nil, 150)

    " https://github.com/neovim/neovim/issues/1936#issuecomment-309311829
    autocmd FocusGained * checktime
    autocmd FocusLost * wshada

    " zsh.txt is not a zshell script...
    " See runtime/scripts.vim
    autocmd BufWinEnter *.txt set ft=text

    " autocmd BufWinEnter * setlocal number
    autocmd FileType diff let &commentstring="# %s"
    autocmd FileType c let &commentstring="// %s"
    autocmd FileType make let &tabstop=&shiftwidth
  augroup END

  function! s:mkdirp(file, buf) abort
    if !empty(getbufvar(a:buf, "&buftype"))
      return
    endif

    let l:dir = fnamemodify(a:file, ":h")
    if !isdirectory(dir)
      call mkdir(dir, "p")
    endif
  endfunction
  augroup nhooyr_mkdirp
    autocmd!
    autocmd BufWritePre * call s:mkdirp(expand("<afile>"), +expand("<abuf>"))
  augroup END
endfunction
call s:settings()

function! s:maps() abort
  nnoremap <silent> <Leader>s :source $MYVIMRC<CR>
  nnoremap <silent> <Leader>cd :cd %:h<CR>

  nnoremap <silent> <Leader>ll :set list!<CR>

  " Strip leading whitespace.
  nnoremap <silent> <Leader>ls :%s/\s\+$// \| nohlsearch<CR>

  noremap ; :
  noremap , ;
  nnoremap <silent> <nowait> q :quit<CR>
  nnoremap <silent> Q q
  nnoremap <silent> <M-q> @@
  nnoremap <silent> <leader>ee :e $MYVIMRC<CR>
  nnoremap <silent> <leader>ec :e ~/.config/nvim/colors/elysian.vim<CR>
  nnoremap <silent> k gk
  nnoremap <silent> j gj
  " https://vim.fandom.com/wiki/Format_pasted_text_automatically
  nnoremap <silent> p ]p
  nnoremap <silent> P ]P
  nnoremap <silent> ]p p=`]
  nnoremap <silent> ]P P=`]

  nnoremap <silent> Y y$

  noremap <silent> 0 ^
  noremap <silent> ^ 0

  " Always use black hole register for deletes.
  "
  " Below we set clipboard to unnamed to always use clipboard
  " for yanks.
  nmap <silent> <BS> "_d
  nnoremap <silent> <BS><BS> "_dd
  vmap <silent> <BS> "_d
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

  cnoremap <M-f> <S-Right>
  cnoremap <M-b> <S-Left>
  " This one does not work well because C-w uses iskeyword but S-Right does not
  cnoremap <M-d> <S-Right><C-w>
  cnoremap <M-BS> <C-w>
  cnoremap <M-n> <Down>
  cnoremap <M-p> <Up>

  inoremap <M-f> <C-\><C-o>w
  inoremap <M-b> <C-\><C-o>b
  inoremap <M-d> <C-\><C-o>dw

  nnoremap <silent> <C-s> :silent w<CR>
  inoremap <silent> <C-s> <Esc>:silent w<CR>
  cnoremap <silent> <C-s> <C-c>:silent w<CR>
  nnoremap <silent> <C-x> :silent x<CR>
  inoremap <silent> <C-x> <Esc>:silent x<CR>
  cnoremap <silent> <C-x> <C-c>:silent x<CR>
  nnoremap <silent> <C-q> :silent quit!<CR>
  inoremap <silent> <C-q> <Esc>:silent quit!<CR>
  cnoremap <silent> <C-q> <C-c>:silent quit!<CR>

  " nnoremap <silent> <C-e> 2<C-e>
  " nnoremap <silent> <C-y> 2<C-y>
  nnoremap <silent> <Leader>h :let v:hlsearch = !v:hlsearch<CR>

  nnoremap <silent> <C-k> <C-W>k
  nnoremap <silent> <C-l> <C-W>l
  nnoremap <silent> <C-j> <C-W>j
  nnoremap <silent> <C-h> <C-W>h
  " inoremap <silent> <C-k> <Esc><C-W>k
  " inoremap <silent> <C-l> <Esc><C-W>l
  " inoremap <silent> <C-j> <Esc><C-W>j
  " inoremap <silent> <C-h> <Esc><C-W>h

  noremap <silent> <C-z> zz
  " For some reason in markdown files this causes C-f to be inserted as a literal.
  inoremap <silent> <C-z> <C-o>zz<C-f>

  " highlight group syntax
  " ^ since I keep forgetting the mapping and then can't find it in here lol.
  " https://stackoverflow.com/a/9464929/4283659
  nnoremap <silent> <Leader>p :echo map(synstack(line("."), col(".")), "synIDattr(v:val, 'name')")<CR>

  inoremap <silent> <M-BS> <C-w>

  " We use mkview to preserve cursor position.
  nnoremap <silent> <Leader>d :mkview<CR>"ayy"ap:loadview<CR>j

  nnoremap <silent> ]q :cnext<CR>
  nnoremap <silent> [q :cprev<CR>
  nnoremap <silent> <Leader>q :cclose<CR>
  nnoremap <silent> ]t :tabn<CR>
  nnoremap <silent> [t :tabp<CR>

  nnoremap <silent> z] zo]z
  nnoremap <silent> z[ zo[z

  nnoremap <Leader>r :%s##
  vnoremap <Leader>r :s##

  function! s:diff_next(direction) abort
    " Jumps to the next comment block.
    " Regex is ^[^#].*\n\zs\%(# .*\n\)\+
    " Meaning find the next line starting without # with a bunch starting with # and start
    " the match at before first #.
    silent! execute a:direction . '^[^#].*\n\zs\%(# .*\n\)\+'
    nohlsearch
  endfunction

  augroup nhooyr_maps
    autocmd!

    autocmd FileType qf setlocal statusline=%f
    autocmd FileType qf nnoremap <buffer> <silent> <M-CR> <CR>:cclose<CR>:lclose<CR>

    autocmd FileType diff nnoremap <buffer> <silent> <Leader>c :%s/^# //<CR>:nohlsearch<CR><C-o>
    autocmd FileType diff nnoremap <buffer> <silent> <M-p> :call <SID>diff_next("?")<CR>
    autocmd FileType diff nnoremap <buffer> <silent> <M-n> :call <SID>diff_next("/")<CR>

    " https://stackoverflow.com/questions/39009792/vimgrep-pattern-and-immediately-open-quickfix-in-split-mode
    autocmd QuickFixCmdPost [^l]* cwindow
    autocmd QuickFixCmdPost l*    lwindow

    " q should always quit.
    autocmd FileType * nnoremap <buffer> <nowait> <silent> q :quit<CR>
  augroup END

  if executable("rg")
    let &grepprg="rg -S --vimgrep"
    command! -nargs=+ Rg silent grep! <args>
  endif

  " https://stackoverflow.com/a/4313335/4283659
  nnoremap gp `[v`]

  " Don't like the cursor movement.
  " inoremap (; (<CR>)<Esc>O
  " inoremap {; {<CR>}<Esc>O
  " inoremap [; [<CR>]<Esc>O
  " inoremap "; ""<Left>
  " inoremap '; ''<Left>
  " inoremap `; ``<Left>
endfunction
call s:maps()

function! s:restore() abort
  augroup nhooyr_restore
    autocmd!
    autocmd BufWinEnter * call s:restore_cursor()
  augroup END

  function! s:restore_cursor() abort
    if &diff
      return
    endif
    if $EDITOR_LINE !=# ""
      execute 'normal! ' . $EDITOR_LINE.'G^zz'
      unlet $EDITOR_LINE
      return
    endif
    let path = expand("%:p:S")
    if path =~ "/.git"
      return
    endif
    if line("'\"") > 0 && line("'\"") <= line("$")
      normal! g'"zz
    endif
  endfunction
endfunction
call s:restore()

function! s:fzf() abort
  function! s:gcn() abort
    silent! write
    call system("zsh -ic \"cd ~notes && git add -A && git diff --cached --stat | grep -q " .
          \ "'deletions\\\?(-)'\"")
    if v:shell_error == 0
      " Needs approval.
      call s:exit_fzf("gcn")
      return
    endif
    " No deletions so no approval needed.
    echom 'gcn ' . strftime("%I:%M:%S%p")
    call jobstart("zsh -ic gcn &!")
  endfunction

  " This isn't used for just fzf anymore, see gcn usage.
  function! s:exit_fzf(type) abort
    if !empty($NVIM_FZF_TYPE)
      call system("echo " . a:type . " > " . $NVIM_FZF_TYPE)
    endif
    " Makes it far more efficient to switch between notes and files quickly after making
    " small editions. To also save I mean to avoid the extra keystroke.
    " Also more efficient than :write and :quit as :exit only writes if changes have been
    " made!
    exit
  endfunction

  nnoremap <silent> <M-v> :call <SID>exit_fzf("paths")<CR>
  inoremap <silent> <M-v> <ESC>:call <SID>exit_fzf("paths")<CR>

  nnoremap <silent> <M-r> :call <SID>gcn()<CR>
  inoremap <silent> <M-r> <ESC>:call <SID>gcn()<CR>

  nnoremap <silent> <M-g> :call <SID>exit_fzf("last-file")<CR>
  inoremap <silent> <M-g> <ESC>:call <SID>exit_fzf("last-file")<CR>

  nnoremap <silent> <M-a> :call <SID>exit_fzf("paths-all")<CR>
  inoremap <silent> <M-a> <ESC>:call <SID>exit_fzf("paths-all")<CR>

  nnoremap <silent> <M-t> :call <SID>exit_fzf("rg")<CR>
  inoremap <silent> <M-t> <ESC>:call <SID>exit_fzf("rg")<CR>

  " Adds all accessed files into my shell history.
  function! s:update_history() abort
    if &buftype !=# ""
      return
    endif
    if expand("%") ==# "[Plugins]"
      return
    endif
    let path = expand("%:p:S")
    if empty(path)
      return
    endif
    if path =~ "/.git"
      return
    endif
    call jobstart(["zsh", "-ic", 'print -rs e "$(normalize '.expand('%:p:S').')"'])
  endfunction

  augroup nhooyr_fzf
    autocmd!
    autocmd BufWinEnter,BufFilePost * call s:update_history()
  augroup END
endfunction
call s:fzf()

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
  set pumheight=10
  set dictionary+=/usr/share/dict/words

  inoremap <C-Space> <C-x><C-o>
  inoremap <M-l> <C-x><C-f>
  inoremap <M-k> <C-x><C-k>

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

  augroup nhooyr_lsp
    autocmd!
    autocmd FileType go,vim,lua,javascript,typescript*,c,cpp call s:b_lsp()
  augroup END
endfunction
call s:lsp()
