function! nhooyr_coc#init() abort
  inoremap <silent> <expr> <C-Space> coc#refresh()
  imap <silent> <C-j> <Plug>(coc-snippets-expand-jump)
  nmap <silent> gy <Plug>(coc-type-definition)
  nmap <silent> gi <Plug>(coc-implementation)
  nmap <silent> gr <Plug>(coc-references)
  nmap <leader>rn <Plug>(coc-rename)

  augroup nhooyr_coc
    autocmd!
    autocmd FileType typescript,json,go,vim setlocal formatexpr=CocAction('formatSelected')
    autocmd FileType typescript,json,go,vim nmap <silent> <buffer> <C-]> <Plug>(coc-definition)
    autocmd FileType typescript,json,go,vim nnoremap <silent> <buffer> K :call CocAction('doHover')<CR>
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

  command! -nargs=? Fold :call CocAction('fold', <f-args>)
endfunction
