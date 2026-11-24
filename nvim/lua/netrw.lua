local function edit_parent()
	local path
	if vim.bo.filetype == 'netrw' then path = vim.b.netrw_curdir else path = vim.fn.expand('%:p') end
	local parent = path:match('^/+$') and '/' or vim.fn.fnamemodify(path:gsub('/+$', ''), ':h')
	vim.cmd('edit ' .. vim.fn.fnameescape(parent))
end

local function setup()
	vim.keymap.set('n', 'q', '<Cmd>quit<CR>', { buffer = true, nowait = true })
	if vim.b.netrw_curdir and vim.b.netrw_curdir:match('^/') then
		vim.keymap.set('n', '-', "<Cmd>lua require('netrw').edit_parent()<CR>", { buffer = true, nowait = true })
	end
end

return { setup = setup, edit_parent = edit_parent }
