set background=light
hi clear
" syntax reset resets to default colorscheme.
syntax reset
let g:colors_name = "elysian"

" Vim UI colors.
hi Normal       ctermfg=NONE   ctermbg=NONE cterm=NONE
hi CursorLine   ctermfg=NONE   ctermbg=12   cterm=NONE
hi CursorLineNr ctermfg=244    ctermbg=12   cterm=NONE
hi LineNr       ctermfg=244    ctermbg=NONE cterm=NONE
hi ErrorMsg     ctermfg=yellow ctermbg=NONE cterm=NONE
hi VertSplit    ctermfg=244    ctermbg=NONE cterm=NONE
hi MatchParen   ctermfg=NONE   ctermbg=225  cterm=NONE
hi NonText      ctermfg=244    ctermbg=NONE cterm=NONE
hi IncSearch    ctermfg=NONE   ctermbg=218  cterm=NONE
hi Search       ctermfg=NONE   ctermbg=153  cterm=NONE
hi StatusLine   ctermfg=NONE   ctermbg=12   cterm=NONE
hi StatusLineNC ctermfg=NONE   ctermbg=12   cterm=NONE
hi Visual       ctermfg=NONE   ctermbg=225  cterm=NONE
hi TabLine      ctermfg=NONE   ctermbg=NONE cterm=NONE
hi TabLineFill  ctermfg=NONE   ctermbg=NONE cterm=NONE
hi TabLineSel   ctermfg=NONE   ctermbg=218  cterm=NONE
hi SignColumn   ctermfg=NONE   ctermbg=NONE cterm=NONE
hi Folded       ctermfg=244    ctermbg=255  cterm=NONE
hi FoldColumn   ctermfg=244    ctermbg=NONE cterm=NONE

hi Directory    ctermfg=17     ctermbg=NONE cterm=NONE
hi SpecialKey   ctermfg=5      ctermbg=NONE cterm=underline
augroup elysian
  autocmd!
  " Ignore carriage returns.
  autocmd FileType * match Ignore /\r$/
augroup END


" Language colors.
hi Comment      ctermfg=244  ctermbg=NONE cterm=NONE
hi Constant     ctermfg=168  ctermbg=NONE cterm=NONE
hi String       ctermfg=2    ctermbg=NONE cterm=NONE
hi Identifier   ctermfg=61   ctermbg=NONE cterm=NONE
hi Statement    ctermfg=54   ctermbg=NONE cterm=NONE
hi Title        ctermfg=54   ctermbg=NONE cterm=NONE
hi PreProc      ctermfg=NONE ctermbg=NONE cterm=NONE
hi Type         ctermfg=NONE ctermbg=NONE cterm=NONE
hi Special      ctermfg=6    ctermbg=NONE cterm=NONE
hi Underlined   ctermfg=6    ctermbg=NONE cterm=NONE
hi Error        ctermfg=NONE ctermbg=NONE cterm=NONE
hi Todo         ctermfg=NONE ctermbg=NONE cterm=bold
" By default StorageClass links to Type which makes no sense.
hi link StorageClass Statement

" Git colors.
hi diffAdded   ctermfg=2     ctermbg=NONE  cterm=NONE
hi diffRemoved ctermfg=1     ctermbg=NONE  cterm=NONE
hi diffFile    ctermfg=54    ctermbg=NONE  cterm=underline
hi diffLine    ctermfg=61    ctermbg=NONE  cterm=underline
hi link gitcommitSummary Normal

" Diff mode colors.
hi DiffAdd    ctermfg=NONE  ctermbg=194  cterm=NONE
hi DiffText   ctermfg=NONE  ctermbg=12   cterm=underline
hi DiffChange ctermfg=NONE  ctermbg=12   cterm=NONE
hi DiffDelete ctermfg=NONE  ctermbg=217  cterm=NONE
hi link diffIndexLine diffFile

hi markdownItalic ctermfg=NONE ctermbg=NONE cterm=NONE
