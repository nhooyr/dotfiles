set background=light
hi clear
" syntax reset resets to default colorscheme.
syntax reset
let g:colors_name = "elysian"

" Vim UI colors.
hi Normal       ctermfg=NONE   ctermbg=NONE cterm=NONE
hi CursorLine   ctermfg=NONE   ctermbg=NONE cterm=NONE
hi CursorLineNr ctermfg=252    ctermbg=NONE cterm=NONE
hi LineNr       ctermfg=244    ctermbg=NONE cterm=NONE
hi ErrorMsg     ctermfg=yellow ctermbg=NONE cterm=NONE
hi VertSplit    ctermfg=234    ctermbg=NONE cterm=NONE
hi MatchParen   ctermfg=0      ctermbg=225  cterm=NONE
hi NonText      ctermfg=234    ctermbg=NONE cterm=NONE
hi IncSearch    ctermfg=0      ctermbg=218  cterm=NONE
hi Search       ctermfg=0      ctermbg=153  cterm=NONE
hi StatusLine   ctermfg=0      ctermbg=146  cterm=NONE
hi StatusLineNC ctermfg=NONE   ctermbg=234  cterm=NONE
hi Visual       ctermfg=0      ctermbg=225  cterm=NONE
hi TabLine      ctermfg=NONE   ctermbg=234  cterm=NONE
hi TabLineFill  ctermfg=NONE   ctermbg=234  cterm=NONE
hi TabLineSel   ctermfg=0      ctermbg=218  cterm=NONE
hi SignColumn   ctermfg=NONE   ctermbg=NONE cterm=NONE
hi Folded       ctermfg=249    ctermbg=NONE cterm=italic

hi NormalFloat  ctermfg=NONE   ctermbg=234 cterm=NONE

hi Directory  ctermfg=18  ctermbg=NONE cterm=NONE
hi SpecialKey ctermfg=5   ctermbg=NONE cterm=underline
hi TermCursor ctermfg=246 ctermbg=NONE cterm=reverse

hi SpellBad   ctermfg=yellow ctermbg=NONE cterm=italic,underline
hi SpellCap   ctermfg=blue   ctermbg=NONE cterm=italic,underline
hi SpellLocal ctermfg=blue   ctermbg=NONE cterm=italic,underline
hi SpellRare  ctermfg=blue   ctermbg=NONE cterm=italic,underline

" Language colors.
hi Comment    ctermfg=249    ctermbg=NONE cterm=italic
hi Constant   ctermfg=168    ctermbg=NONE cterm=NONE
hi String     ctermfg=2      ctermbg=NONE cterm=NONE
hi Identifier ctermfg=61     ctermbg=NONE cterm=NONE
hi Statement  ctermfg=5      ctermbg=NONE cterm=NONE
hi Operator   ctermfg=NONE   ctermbg=NONE cterm=NONE
hi Title      ctermfg=5      ctermbg=NONE cterm=NONE
hi PreProc    ctermfg=NONE   ctermbg=NONE cterm=NONE
hi Type       ctermfg=NONE   ctermbg=NONE cterm=NONE
hi Special    ctermfg=6      ctermbg=NONE cterm=NONE
hi Underlined ctermfg=6      ctermbg=NONE cterm=NONE
hi Error      ctermfg=yellow ctermbg=NONE cterm=bold,underline
hi Todo       ctermfg=white  ctermbg=NONE cterm=bold
" By default StorageClass links to Type which makes no sense.
hi link StorageClass Statement

" Git colors.
hi diffAdded   ctermfg=2   ctermbg=NONE  cterm=NONE
hi diffRemoved ctermfg=1   ctermbg=NONE  cterm=NONE
hi diffFile    ctermfg=5   ctermbg=NONE  cterm=underline
hi diffLine    ctermfg=5   ctermbg=NONE  cterm=underline
hi link gitcommitSummary Normal

" Diff mode colors.
hi DiffAdd    ctermfg=0  ctermbg=194  cterm=NONE
hi DiffText   ctermfg=0  ctermbg=12   cterm=underline
hi DiffChange ctermfg=0  ctermbg=12   cterm=NONE
hi DiffDelete ctermfg=0  ctermbg=217  cterm=NONE
hi link diffIndexLine diffFile

hi link markdownItalic NONE

hi link qfFileName Identifier

hi link zshVariable Identifier

augroup elysian
  autocmd!
  " Ignore carriage returns.
  autocmd FileType * match Ignore /\r$/

  autocmd FileType dirvish hi link DirvishArg Normal
augroup END
