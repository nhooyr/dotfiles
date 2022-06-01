" TODO: prune
" TODO: teach vim about zsh bookmarks somehow
" https://threkk.medium.com/how-to-use-bookmarks-in-bash-zsh-6b8074e40774
" get rid of zsh bookmarks and only use CDPATH in both vim and zsh!
" put bookmarks in directory inside bookmarks directory for never any ambiguity.
" e.g. scratch would be eqd/scratch instead of ~scratch. so easy!
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
  Plug 'neovim/nvim-lspconfig'
  Plug 'PeterRincker/vim-argumentative'
  Plug 'simnalamburt/vim-mundo'

  Plug 'tpope/vim-surround'
  Plug 'tpope/vim-commentary'

  Plug 'Shougo/neosnippet.vim'
  Plug 'Shougo/neosnippet-snippets'

  Plug 'junegunn/fzf'

  Plug 'gcmt/taboo.vim'
  Plug 'justinmk/vim-dirvish'

  Plug 'mattn/emmet-vim'

  Plug expand('~/src/terrastruct/d2-vim')
  " Plug 'terrastruct/dia-vim'
  call plug#end()

  command! -bar PU PlugUpgrade | PlugUpdate
  command! -bar PC PlugClean
endfunction
call s:plugins()

function! s:plugin_settings() abort
  set sessionoptions+=globals,terminal

  let g:dia_block_string_syntaxes = {'zsh': ['zsh'], 'rust': ['rust'], 'typescript': ['typescript', 'ts']}

  augroup nhooyr_dia_go
    autocmd!
    " autocmd Syntax go unlet b:current_syntax | syn include @goRawStringD2 syntax/dia.vim | let b:current_syntax = 'go'
    " autocmd Syntax go unlet b:current_syntax | syn include @goRawStringJSON syntax/json.vim | let b:current_syntax = 'go'
    " autocmd Syntax go syn region goRawStringD2 matchgroup=goRawString start=/\/\/raw:embed d2\n.\{-}`/ end=/`/ contains=@goRawStringD2
    " autocmd Syntax go syn region goRawStringJSON matchgroup=goRawString start=/\/\/raw:embed json\n.\{-}`/ end=/`/ contains=@goRawStringJSON
  augroup END

  let g:mundo_close_on_revert = 1
  let g:mundo_verbose_graph = 0
  let g:mundo_header = 0
  nnoremap <silent> <Leader>u :MundoToggle<CR>

  let g:surround_no_insert_mappings = 1

  let g:neosnippet#snippets_directory = stdpath('config').'/after/snippets'
  imap <silent> <M-i> <Plug>(neosnippet_expand)
  imap <silent> <C-j> <Plug>(neosnippet_jump)

  let g:user_emmet_leader_key = "<C-y>"
  let g:user_emmet_mode="i"

  " let g:go_gopls_enabled = 0
  " let g:go_echo_go_info = 0
  " let g:go_template_autocreate = 0
  " let g:go_fmt_autosave = 0

  " let g:delimitMate_expand_cr = 1

  nmap <C-_> gcc
  vmap <C-_> gc
  nmap <M-c> gcgc`]
  imap <C-_> <C-o>gcc

  inoremap <silent> <M-CR> <CR><M-O>

  " augroup nhooyr_plugins
  "   autocmd!
  "   " https://github.com/fatih/vim-go/blob/bd56f5690807d4a92652fe7a4d10dc08f260564e/ftdetect/gofiletype.vim#L10
  "   autocmd BufRead,BufNewFile *.gohtml set filetype=gohtmltmpl
  " augroup END

  " To avoid conflict with my insert mode <C-x> keybind.
  " From vim-endwise.
  " https://github.com/tpope/vim-endwise/blob/97180a73ad26e1dcc1eebe8de201f7189eb08344/plugin/endwise.vim#L129
  " Have endwise disabled due to delimitMate for now.
  augroup nhooyr_endwise_unmap
    autocmd!
    " autocmd VimEnter * iunmap <C-x><CR>
  augroup END

  let g:taboo_tab_format = " %f%m[%N] "
  let g:taboo_renamed_tab_format = " %l%m[%N] "
endfunction
call s:plugin_settings()

function! s:settings() abort
  set nomodeline
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

  if has("vim_starting")
    set tabstop=2
    let &shiftwidth=&tabstop
    set expandtab

    set foldmethod=indent
  endif
  set foldlevelstart=20
  set textwidth=90

  set formatoptions+=ro
  set formatoptions-=t

  " https://vim.fandom.com/wiki/Search_only_in_unfolded_text
  set foldopen=
  " https://github.com/neovim/neovim/issues/2067#issuecomment-398283872
  let &fillchars="eob: ,diff: "

  set diffopt+=foldcolumn:0,algorithm:histogram

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
  " netrw needs an explicit nu here for line numbers otherwise they don't always come up
  " even with FileType and BufWinEnter set.
  " let g:netrw_bufsettings = 'noma nomod nonu nowrap ro nobl nu'

  augroup nhooyr_settings
    autocmd!
    autocmd TextYankPost * silent! lua require'vim.highlight'.on_yank(nil, 150)

    " https://superuser.com/a/1090762
    autocmd CursorHold * if getcmdwintype() == '' | checktime | endif

    autocmd BufWinEnter,FileType * setlocal foldmethod=indent
    autocmd BufEnter,FileType * setlocal nonumber
    autocmd BufEnter,FileType * setlocal cursorline
    autocmd BufLeave * setlocal nocursorline
    autocmd FileType diff let &commentstring="# %s"
    autocmd FileType c let &commentstring="// %s"
    autocmd FileType make let &tabstop=&shiftwidth
    autocmd FileType help setlocal fo-=t
    autocmd FileType go setlocal noexpandtab
  augroup END

  set breakindent
  set breakindentopt=shift:2
  set showbreak=>>

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

  let g:is_posix = 1

  augroup nhooyr_autocd
    autocmd!
    " autocmd FileType * silent! Lcd
    " autocmd BufEnter * silent! Lcd
  augroup END
  function! s:lcd() abort
    if &buftype ==# "terminal"
      let l:term_dir = matchlist(@%, 'term://\(\~.*\)//.*')[1]
      execute 'lcd '.expand(l:term_dir)
    else
      lcd %:p:h
    endif
    pwd
  endfunction
  command! -bar Lcd call s:lcd()

  function! s:rdiff(args) abort
    enew
    setlocal noreadonly
    silent execute 'read !git diff '.a:args
    normal gg"_dd
    setlocal filetype=diff
    setlocal noswapfile buftype=nofile bufhidden=hide
    setlocal nomodified readonly nomodifiable
    execute 'file git-diff-'.bufnr()
  endfunction
  command! -bar -nargs=* Rdiff call s:rdiff(<q-args>)

  function! s:make_session(name) abort
    let l:sessions_file = stdpath('data').'/sessions/'.a:name.'.vim'
    silent !mkdir -p $XDG_DATA_HOME/nvim/sessions
    execute 'silent mksession! '.l:sessions_file
  endfunction
  command! -bar -nargs=1 MakeSession call <SID>make_session(<q-args>)

  function! s:save_this_session() abort
    if $NVIM_SESSION != ''
      call s:make_session($NVIM_SESSION)
    elseif v:this_session != ''
      execute 'mksession! ' . v:this_session
    endif
  endfunction

  augroup nhooyr_session
    autocmd!
    execute 'autocmd BufRead '.fnameescape(stdpath('data')).'/sessions/*.vim silent source %'
    autocmd VimLeave * call <SID>save_this_session()
  augroup END

  function! s:bclean_delete_cmd(force, buf) abort
    return 'bwipeout'.a:force.' '.a:buf.bufnr.' "'.a:buf.name
  endfunction

  function! s:bclean(bang, force) abort
    let l:force = ''
    if a:force !=# ''
      let l:force = '!'
    endif
    " Find all hidden or listed and unloaded buffers.
    let l:buffers = filter(getbufinfo(), 'v:val.hidden || (v:val.listed && !v:val.loaded)')
    for l:buf in l:buffers
      let l:delete_cmd = s:bclean_delete_cmd(l:force, l:buf)
      if a:bang ==# '!'
        try
          silent execute l:delete_cmd
        catch
          let l:delete_cmd = s:bclean_delete_cmd('!', l:buf)
        endtry
      endif
      echom l:delete_cmd
    endfor
  endfunction
  " Bclean or Bclean! or Bclean!!
  command! -bar -bang -nargs=? Bclean call s:bclean('<bang>', <q-args>)

  function! s:tab_leave() abort
    if len(g:nhooyr_tab_history) > 1
      let g:nhooyr_tab_history = [g:nhooyr_tab_history[1]]
    endif
    call add(g:nhooyr_tab_history, tabpagenr())
  endfunction
  function! s:tab_closed() abort
    if len(g:nhooyr_tab_history) < 2
      let g:nhooyr_tab_history = []
      return
    endif
    if g:nhooyr_tab_history[0] > g:nhooyr_tab_history[1]
      let g:nhooyr_tab_history[0] -= 1
    endif
    execute 'tabn '.g:nhooyr_tab_history[0]
    let g:nhooyr_tab_history = []
  endfunction
  if !exists('g:nhooyr_tab_history')
    let g:nhooyr_tab_history = []
  endif
  augroup nhooyr_tab_history
    autocmd!
    autocmd! TabLeave * call s:tab_leave()
    autocmd! TabClosed * call s:tab_closed()

    autocmd! WinClosed * wincmd p
  augroup END
  nnoremap <silent> <Leader>t :execute 'tabn '.g:nhooyr_tab_history[1]<CR>
endfunction
call s:settings()

function! s:maps() abort
  nnoremap <silent> t zt
  nnoremap <silent> s zz
  nnoremap <silent> <M-b> zb

  command! -bar SpellCleanAdd runtime spell/cleanadd.vim

  nnoremap <silent> 's :split<CR>
  nnoremap <silent> 'v :vsplit<CR>
  nnoremap <silent> 't :tabnew<CR>

  nnoremap <silent> <Leader>er :source $MYVIMRC<CR>
  nnoremap <silent> <Leader>s :setlocal spell! spelllang=en_ca<CR>
  nnoremap <silent> <Leader>c :Lcd<CR>
  nnoremap <silent> <Leader>g :Gcd<CR>
  nnoremap <silent> 'f :let @+ = expand('%:p')<CR>
  nnoremap <silent> 'h :let @+ = expand('%:p:h')<CR>

  nnoremap <silent> <Leader>ll :set list!<CR>

  " Strip leading whitespace.
  nnoremap <silent> <Leader>ls :%s/\s\+$// \| nohlsearch<CR>

  noremap ; :
  noremap : ;
  nnoremap <silent> <nowait> q :quit<CR>
  nnoremap <silent> Qm q
  nnoremap <silent> Q: q:
  nnoremap <silent> Q/ q/
  nnoremap <silent> Q? q?
  nnoremap <silent> <M-q> @@
  nnoremap <silent> <leader>es :e $MYVIMRC<CR>
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
  " nnoremap <silent> s "_s
  " vnoremap <silent> s "_s
  " nnoremap <silent> S "_S
  " noremap <silent> S "_S

  vnoremap <silent> > >gv
  vnoremap <silent> < <gv

  " Emacs style insert and command line keybindings
  " https://github.com/maxbrunsfeld/vim-emacs-bindings/blob/master/plugin/emacs-bindings.vim
  inoremap <C-f> <Right>
  noremap! <C-b> <Left>
  noremap! <C-e> <End>
  inoremap <nowait> <C-g> <C-e>
  cnoremap <C-a> <Home>
  cnoremap <C-X><C-A> <C-A>
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
  " inoremap <M-d> <C-\><C-o>dw

  nnoremap <silent> <C-s> :silent w<CR>
  inoremap <silent> <C-s> <Esc>:silent w<CR>
  cnoremap <silent> <C-s> <C-c>:silent w<CR>
  nnoremap <silent> <C-q> :silent quit!<CR>
  inoremap <silent> <C-q> <Esc>:silent quit!<CR>
  cnoremap <silent> <C-q> <C-c>:silent quit!<CR>
  " tnoremap <silent> <C-q> <C-\><C-n>:silent quit!<CR>

  nnoremap <silent> <Leader>h :let v:hlsearch = !v:hlsearch<CR>

  nnoremap <silent> <M-]> :tabnext<CR>
  nnoremap <silent> <M-[> :tabprev<CR>
  inoremap <silent> <M-]> <ESC>:tabnext<CR>
  inoremap <silent> <M-[> <ESC>:tabprev<CR>
  tnoremap <silent> <M-]> <C-\><C-n>:tabnext<CR>
  tnoremap <silent> <M-[> <C-\><C-n>:tabprev<CR>

  nnoremap <silent> <C-k> <C-W>k
  nnoremap <silent> <C-l> <C-W>l
  nnoremap <silent> <C-j> <C-W>j
  nnoremap <silent> <C-h> <C-W>h
  tnoremap <silent> <C-k> <C-\><C-n><C-W>k
  tnoremap <silent> <C-l> <C-\><C-n><C-W>l
  tnoremap <silent> <C-j> <C-\><C-n><C-W>j
  tnoremap <silent> <C-h> <C-\><C-n><C-W>h
  nnoremap <silent> 'd :enew <BAR> silent bwipeout!#<CR>
  nnoremap <silent> 'q :enew <BAR> silent bwipeout!# <BAR> :close<CR>
  nnoremap <silent> <M-q> :buf#<Bar>bwipeout!#<Bar>startinsert<CR>
  inoremap <silent> <M-q> <Esc>:buf#<Bar>bwipeout!#<Bar>startinsert<CR>
  nnoremap <silent> <M-x> :silent write<Bar>buf#<Bar>bwipeout#<Bar>startinsert<CR>
  inoremap <silent> <M-x> <Esc>:silent write<Bar>buf#<Bar>bwipeout#<Bar>startinsert<CR>
  " TODO: Sort all mode mappings to easily see what's available and taken.
  "       Add comments for default binds.
  " TODO: Add map for digraph C-k and then re-enable these.
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
  nnoremap <silent> ]l :lnext<CR>
  nnoremap <silent> [l :lprev<CR>
  function! s:toggle_quickfix() abort
    if empty(filter(getwininfo(), 'v:val.quickfix'))
      copen
    else
      cclose
    endif
  endfunction
  function! s:toggle_loclist() abort
    if empty(filter(getwininfo(), 'v:val.loclist'))
      lopen
    else
      lclose
    endif
  endfunction
  nnoremap <silent> <Leader>qq :call <SID>toggle_quickfix()<CR>
  nnoremap <silent> <Leader>ql :call <SID>toggle_loclist()<CR>
  nnoremap <silent> ]t :tabn<CR>
  nnoremap <silent> [t :tabp<CR>

  " nnoremap <silent> z] zo]z
  " nnoremap <silent> z[ zo[z

  nnoremap <Leader>r :%s##
  vnoremap <Leader>r :s##
  " https://vim.fandom.com/wiki/Search_for_visually_selected_text
  vnoremap // y/\V<C-R>=escape(@",'/\')<CR><CR>

  " TODO: fix these and see [(, [{, ]), ]}
  nnoremap <silent> ]] ][
  nnoremap <silent> [[ []
  " noremap <silent> [[ ?{<CR>w99[{
  " noremap <silent> ][ /}<CR>b99]}
  " noremap <silent> ]] j0[[%/{<CR>
  " noremap <silent> [] k$][%?}<CR>

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
    autocmd FileType qf nnoremap <buffer> <silent> <M-CR> <CR>:cclose<Bar>lclose<CR>

    " autocmd FileType diff nnoremap <buffer> <silent> <Leader>c :%s/^# //<Bar>nohlsearch<CR><C-o>
    " autocmd FileType diff nnoremap <buffer> <silent> <M-p>     :call  <SID>diff_next("?")<CR>
    " autocmd FileType diff nnoremap <buffer> <silent> <M-n>     :call  <SID>diff_next("/")<CR>

    " https://stackoverflow.com/questions/39009792/vimgrep-pattern-and-immediately-open-quickfix-in-split-mode
    autocmd QuickFixCmdPost [^l]* cwindow
    autocmd QuickFixCmdPost l*    lwindow

    " q should always close.
    autocmd FileType * nnoremap <buffer> <nowait> <silent> q :close<CR>
    " C-x should always do :x.
    autocmd FileType * nnoremap <buffer> <nowait> <silent> <C-x> :silent x<CR>
    autocmd FileType * inoremap <buffer> <nowait> <silent> <C-x> <Esc>:silent x<CR>
    " autocmd FileType * cnoremap <buffer> <nowait> <silent> <C-x> <C-c>:silent x<CR>
  augroup END

  if executable("rg")
    let &grepprg="rg -S --vimgrep"
    command! -bar -nargs=+ Rg silent grep! <args>
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

  function! s:lvimgrep(pattern) abort
    call feedkeys("/".a:pattern."/\<CR>")
    call feedkeys(":lvimgrep /".a:pattern."/j %\<CR>")
  endfunction
  command! -bar -nargs=+ Search call <SID>lvimgrep(<q-args>)

  " Life saver alignment mapping.
  " https://unix.stackexchange.com/a/179319
  " TODO: turn into command that accepts something to align on.
  vnoremap <silent> <C-l> :!column -t \| sed 's/\( *\) /\1/g'<CR>

  function! s:note() abort
    execute 'edit $HOME/src/nhooyr/notes/'.strftime("%Y/%m/%d").'.txt'
  endfunction
  nnoremap <silent> <M-n> :call <SID>note()<CR>

  function! s:find(pat) abort
    cgetexpr system('find . -path '.shellescape(a:pat)
          \.' | xargs file | sed "s/:/:1:/"')
  endfunction
  command! -bar -nargs=1 Find call <SID>find(<q-args>)

  function! s:ggrep(pat) abort
    call s:gcd()
    execute 'Lgrep '.a:pat
    silent! Lcd
  endfunction
  command! -bar -nargs=1 Lgrep silent lgrep! <args>
  command! -bar -nargs=1 Ggrep call <SID>ggrep(<q-args>)

  function! s:gcd() abort
    silent! Lcd
    if match(getcwd(), '/.git$') != -1
      lcd ..
      return
    endif
    let l:git_dir = system('git rev-parse --show-toplevel')
    execute 'lcd '.l:git_dir
    pwd
  endfunction
  command! -bar Gcd call s:gcd()
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
    if &buftype ==# "terminal"
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
      echom 'please run in terminal and review diff (there were deletions)'
      return
    endif
    " No deletions so no approval needed.
    echom 'gcn ' . strftime("%I:%M:%S%p")
    call jobstart("zsh -ic gcn &!")
  endfunction

  command! -bar -nargs=1 TermFile file %;\#<args>
  function! s:term(cmd) abort
    execute 'term '.a:cmd
    let l:tabname = g:TabooTabName(tabpagenr())
    if empty(l:tabname)
      let l:tabname = "scratch"
    endif
    execute 'TermFile '.l:tabname
  endfunction
  command! -bar -nargs=? Term call s:term(<q-args>)
  nnoremap <silent> <M-t> :call <SID>term('')<CR>
  " Will not work with embedded vi's unfortunately.
  " tnoremap <silent> <ESC> <C-\><C-n>
  tnoremap <silent> <M-l> <C-l>
  nnoremap <silent> <M-l> i<C-l><C-\><C-n>

  " function! s:quickPathsSink(path) abort
  "   let l:system("zsh -c 'source ~/.zshrc && eval \"echo $1\"' -- ".shellescape('~notes'))
  " endfunction
  " TODO: some day expand bookmark after and not use fzf#wrap.
  command! -bar QuickPaths call fzf#run(fzf#wrap({'source': 'source ~/.zshrc && processed_quick_paths | expand_bookmarks'}))
  nnoremap <silent> <M-v> :QuickPaths<CR>
  inoremap <silent> <M-v> <ESC>:QuickPaths<CR>

  nnoremap <silent> <M-r> :call <SID>gcn()<CR>
  inoremap <silent> <M-r> <ESC>:call <SID>gcn()<CR>

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

  let g:fzf_preview_window = []
endfunction
call s:fzf()

function! s:lsp() abort
  if !exists("g:nhooyr_lsp")
    let g:nhooyr_lsp = 1
    lua << EOF
    local lsp_loaded, lsp = pcall(require, "lspconfig")
    if not lsp_loaded then
      return
    end

    -- Disable diagnostics globally.
    vim.lsp.handlers["textDocument/publishDiagnostics"] = function() end

    lsp.gopls.setup{}
    lsp.tsserver.setup{}
    lsp.clangd.setup{}
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
    nnoremap <silent> <buffer> gp    <cmd>lua vim.lsp.buf.type_definition()<CR>
    nnoremap <silent> <buffer> gr    <cmd>lua vim.lsp.buf.references()<CR>
    nnoremap <silent> <buffer> gs    <cmd>lua vim.lsp.buf.document_symbol()<CR>
    nnoremap <silent> <buffer> gw    <cmd>lua vim.lsp.buf.workspace_symbol()<CR>
    nnoremap <silent> <buffer> ge    <cmd>lua vim.lsp.buf.rename()<CR>

    setlocal omnifunc=v:lua.vim.lsp.omnifunc
  endfunction

  augroup nhooyr_lsp
    autocmd!
    autocmd FileType go,lua,javascript*,typescript*,c,cpp call s:b_lsp()
  augroup END
endfunction
call s:lsp()
