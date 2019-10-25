set background=light
hi clear
" syntax reset resets to default colorscheme.
syntax reset
let g:colors_name = "elysian"

" Vim UI colors.
hi CursorLine   ctermfg=NONE  ctermbg=12   cterm=NONE
hi CursorLineNr ctermfg=244   ctermbg=12   cterm=NONE
hi LineNr       ctermfg=244   ctermbg=NONE cterm=NONE
hi ErrorMsg     ctermfg=9     ctermbg=NONE cterm=NONE
hi VertSplit    ctermfg=244   ctermbg=NONE cterm=NONE
hi MatchParen   ctermfg=NONE  ctermbg=225  cterm=NONE
hi ModeMsg      ctermfg=2     ctermbg=NONE cterm=NONE
hi NonText      ctermfg=white ctermbg=NONE cterm=NONE
hi IncSearch    ctermfg=NONE  ctermbg=218  cterm=bold
hi Search       ctermfg=NONE  ctermbg=194  cterm=NONE
hi StatusLine   ctermfg=black ctermbg=NONE cterm=NONE
hi StatusLineNC ctermfg=black ctermbg=NONE cterm=NONE
hi Visual       ctermfg=NONE  ctermbg=225  cterm=NONE

" Language colors.
hi Normal       ctermfg=232   ctermbg=NONE cterm=NONE
hi Comment      ctermfg=244   ctermbg=NONE cterm=NONE
hi Constant     ctermfg=168   ctermbg=NONE cterm=NONE
hi String       ctermfg=2     ctermbg=NONE cterm=NONE
hi Identifier   ctermfg=61    ctermbg=NONE cterm=NONE
hi Statement    ctermfg=54    ctermbg=NONE cterm=NONE
hi PreProc      ctermfg=NONE  ctermbg=NONE cterm=NONE
hi Type         ctermfg=NONE  ctermbg=NONE cterm=NONE
hi Special      ctermfg=6     ctermbg=NONE cterm=NONE
hi Underlined   ctermfg=6     ctermbg=NONE cterm=NONE
hi Error        ctermfg=white ctermbg=9    cterm=NONE
hi Todo         ctermfg=NONE  ctermbg=NONE cterm=bold

" Git colors.
hi diffAdded           ctermfg=1    ctermbg=NONE cterm=NONE
hi diffRemoved         ctermfg=2    ctermbg=NONE cterm=NONE
hi gitKeyword          ctermfg=NONE ctermbg=NONE cterm=bold
hi gitIdentityKeyword  ctermfg=NONE ctermbg=NONE cterm=bold
