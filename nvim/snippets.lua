local snippets = {
	global = {
		fx = "Fiat Lux$0",
		todo = "TODO: ${1:desc}$0",
	},
	go = {
		ife = "if err != nil {\n\t${1:return err}\n}\n$0",
	},
}

local function jump_snippet(direction)
	if vim.snippet.active() then
		vim.snippet.jump(direction)
		vim.api.nvim_clear_autocmds({ group = 'nvim.snippet', event = 'ModeChanged', buffer = 0 })
	end
end

local function expand_or_jump_snippet()
	local normal = vim.fn.mode() == 'n'
	if vim.snippet.active() then
		if normal then return '<M-l>' end
		jump_snippet(1)
		return
	end

	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local tail = line:sub(col + 1):match('^[%w_]+')
	if normal then
		if not tail then return '' end
		col = col + #tail
	end
	local trigger = line:sub(1, col):match('[%w_]+$')
	local body = (snippets[vim.bo.filetype] or {})[trigger] or snippets.global[trigger]
	if not body then return '' end
	if normal then return (#tail > 1 and (#tail - 1) .. 'l' or '') .. 'a<M-j>' end

	vim.api.nvim_buf_set_text(0, row - 1, col - #trigger, row - 1, col, {})
	vim.snippet.expand(body)
	-- Keep the session when returning to Normal mode.
	vim.api.nvim_clear_autocmds({ group = 'nvim.snippet', event = 'ModeChanged', buffer = 0 })
end

vim.keymap.set('i', '<M-j>', expand_or_jump_snippet)
vim.keymap.set('n', '<M-j>', expand_or_jump_snippet, { expr = true, remap = true })
vim.keymap.set('s', '<M-j>', '<M-l>', { remap = true })
vim.keymap.set({ 'n', 'i', 's' }, '<M-k>', function() vim.snippet.stop() end)

for key, direction in pairs({ ['<M-l>'] = 1, ['<M-h>'] = -1 }) do
	vim.keymap.set({ 'n', 'i', 's' }, key, function()
		jump_snippet(direction)
	end)
end
