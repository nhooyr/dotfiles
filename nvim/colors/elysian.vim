set background=light
hi clear
" syntax reset resets to default colorscheme.
syntax reset
let g:colors_name = "elysian"

" Vim UI colors.
hi CursorLine   ctermfg=NONE   ctermbg=12   cterm=NONE
hi CursorLineNr ctermfg=244    ctermbg=12   cterm=NONE
hi LineNr       ctermfg=244    ctermbg=NONE cterm=NONE
hi ErrorMsg     ctermfg=yellow ctermbg=NONE cterm=bold
hi VertSplit    ctermfg=244    ctermbg=NONE cterm=NONE
hi MatchParen   ctermfg=NONE   ctermbg=225  cterm=NONE
" hi ModeMsg      ctermfg=white  ctermbg=NONE cterm=NONE
hi NonText      ctermfg=white  ctermbg=NONE cterm=NONE
hi IncSearch    ctermfg=NONE   ctermbg=218  cterm=bold
hi Search       ctermfg=NONE   ctermbg=153  cterm=NONE
hi StatusLine   ctermfg=black  ctermbg=194  cterm=bold
hi StatusLineNC ctermfg=NONE   ctermbg=255 cterm=NONE
hi Visual       ctermfg=NONE   ctermbg=225  cterm=NONE
hi TabLine      ctermfg=NONE   ctermbg=NONE cterm=NONE
hi TabLineFill  ctermfg=NONE   ctermbg=NONE cterm=NONE
hi TabLineSel   ctermfg=NONE   ctermbg=218  cterm=bold
hi SignColumn   ctermfg=NONE   ctermbg=NONE cterm=NONE
hi Folded       ctermfg=244    ctermbg=255  cterm=NONE

hi Directory    ctermfg=4  ctermbg=NONE cterm=NONE

" Language colors.
hi Normal       ctermfg=NONE  ctermbg=NONE cterm=NONE
hi Comment      ctermfg=244  ctermbg=NONE cterm=NONE
hi Constant     ctermfg=168  ctermbg=NONE cterm=NONE
hi String       ctermfg=2    ctermbg=NONE cterm=NONE
hi Identifier   ctermfg=61   ctermbg=NONE cterm=NONE
hi Statement    ctermfg=54   ctermbg=NONE cterm=NONE
hi PreProc      ctermfg=NONE ctermbg=NONE cterm=NONE
hi Type         ctermfg=NONE ctermbg=NONE cterm=NONE
hi Special      ctermfg=6    ctermbg=NONE cterm=NONE
hi Underlined   ctermfg=6    ctermbg=NONE cterm=NONE
hi Error        ctermfg=NONE ctermbg=NONE cterm=NONE
hi Todo         ctermfg=NONE ctermbg=NONE cterm=bold

" Git colors.
hi DiffAdd            ctermfg=2    ctermbg=NONE cterm=NONE
hi DiffChange         ctermfg=5    ctermbg=NONE cterm=NONE
hi DiffDelete         ctermfg=1    ctermbg=NONE cterm=NONE
hi link diffAdded DiffAdd
hi link diffRemoved DiffDelete
hi gitKeyword         ctermfg=NONE ctermbg=NONE cterm=bold
hi gitIdentityKeyword ctermfg=NONE ctermbg=NONE cterm=bold

hi ExtraWhitespace ctermfg=NONE ctermbg=yellow cterm=NONE
