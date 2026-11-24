let s:config_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let &packlockfile = s:config_dir . '/nvim-pack-lock.json'
lua << EOF
vim.pack.add({
    { src = 'https://github.com/nhooyr/copilot.vim.git', version = 'fix-partial-accept-preview' },
    'https://github.com/justinmk/vim-dirvish.git',
}, { confirm = false })
EOF
