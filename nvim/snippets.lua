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
	if vim.snippet.active({ direction = direction }) then
		vim.snippet.jump(direction)
	end
end

local function expand_or_jump_snippet()
	if vim.snippet.active() then
		jump_snippet(1)
		return
	end

	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local trigger = line:sub(1, col):match('[%w_]+$')
	local body = (snippets[vim.bo.filetype] or {})[trigger] or snippets.global[trigger]
	if not body then return end

	vim.api.nvim_buf_set_text(0, row - 1, col - #trigger, row - 1, col, {})
	vim.snippet.expand(body)
end

vim.keymap.set('i', '<M-j>', expand_or_jump_snippet)
vim.keymap.set('s', '<M-j>', function() jump_snippet(1) end)
vim.keymap.set({ 'i', 's' }, '<M-k>', function() jump_snippet(-1) end)
