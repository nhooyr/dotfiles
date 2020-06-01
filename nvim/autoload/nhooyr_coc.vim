" https://github.com/neoclide/coc.nvim#example-vim-configuration
function! nhooyr_coc#init() abort
  " This was changed from C-n due to some bizarre behaviour
  " with completing the closing tag in an html file.
  inoremap <silent><expr> <TAB>
        \ pumvisible() ? "\<Down>" :
        \ <SID>check_back_space() ? "\<TAB>" :
        \ coc#refresh()
  inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

  function! s:check_back_space() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~# '\s'
  endfunction

  " Use <c-space> to trigger completion.
  inoremap <silent> <expr> <c-space> coc#refresh()

  nmap <silent> gy <Plug>(coc-type-definition)
  nmap <silent> gi <Plug>(coc-implementation)
  nmap <silent> gr <Plug>(coc-references)

  nnoremap <silent> K :call <SID>show_documentation()<CR>

  function! s:show_documentation()
    if (index(['vim','help'], &filetype) >= 0)
      execute 'h '.expand('<cword>')
    else
      call CocAction('doHover')
    endif
  endfunction

  autocmd CursorHold * silent call CocActionAsync('highlight')

  nmap <leader>rn <Plug>(coc-rename)
  xmap <silent> <leader>f  <Plug>(coc-format-selected)
  nmap <silent> <leader>f  <Plug>(coc-format-selected)

  augroup nhooyr_coc
    autocmd!
    autocmd FileType typescript,json,go,vim setl formatexpr=CocAction('formatSelected')
    autocmd FileType typescript,json,go,vim nmap <silent> <buffer> <C-]> <Plug>(coc-definition)
  augroup end

  xmap if <Plug>(coc-funcobj-i)
  omap if <Plug>(coc-funcobj-i)
  xmap af <Plug>(coc-funcobj-a)
  omap af <Plug>(coc-funcobj-a)
  xmap ic <Plug>(coc-classobj-i)
  omap ic <Plug>(coc-classobj-i)
  xmap ac <Plug>(coc-classobj-a)
  omap ac <Plug>(coc-classobj-a)

  nmap <silent> <space>s <Plug>(coc-range-select)
  xmap <silent> <space>s <Plug>(coc-range-select)

  command! -nargs=0 Format :call CocAction('format')
  command! -nargs=? Fold :call     CocAction('fold', <f-args>)

  imap <C-j> <Plug>(coc-snippets-expand-jump)
endfunction
