local snippets = {
	global = {
		fx = "Fiat Lux$0",
		imps = "imps: ${1:Chat}$0",
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

local function expand_or_jump_snippet(expand_only)
	if not expand_only and vim.snippet.active() then
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

local function complete(findstart, base)
	if findstart == 1 then return vim.fn.getline('.'):sub(1, vim.fn.col('.') - 1):find('[%w_]*$') - 1 end
	local matches = {}
	for trigger, body in pairs(vim.tbl_extend('force', snippets.global, snippets[vim.bo.filetype] or {})) do
		if trigger:sub(1, #base) == base then
			matches[#matches + 1] = { word = trigger, menu = '[snip]', info = body, user_data = 'snip', dup = 1 }
		end
	end
	table.sort(matches, function(a, b) return a.word < b.word end)
	return matches
end

return { expand_or_jump = expand_or_jump_snippet, jump = jump_snippet, complete = complete }
