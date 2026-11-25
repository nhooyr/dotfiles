local snippets = {
	global = {
		fx = 'Fiat Lux$0',
		chat = 'chat: ${1:Improvements}$0',
		todo = 'TODO: ${1:desc}$0',

		fmt = 'format$0',
		Fmt = 'Format$0',
		fmts = 'formatting$0',
		Fmts = 'Formatting$0',
		imp = 'improve$0',
		Imp = 'Improve$0',
		imps = 'improvements$0',
		Imps = 'Improvements$0',
		garg = 'gargantuan$0',
		Garg = 'Gargantuan$0',
		up = 'update$0',
		Up = 'Update$0',
		ups = 'updates$0',
		Ups = 'Updates$0',

		play = 'hello world: ${1:One} ${2:Two} ${3:Three} $1$0',
	},
	go = {
		ife = 'if err != nil {\n\t${1:return err}\n}\n$0',
	},
}

local function jump_snippet(direction)
	if vim.snippet.active({ direction = direction }) then
		vim.snippet.jump(direction)
	end
end

local function expand_snippet()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local trigger = line:sub(1, col):match('[%w_]+$')
	local body = (snippets[vim.bo.filetype] or {})[trigger] or snippets.global[trigger]
	if not body then return end

	vim.api.nvim_buf_set_text(0, row - 1, col - #trigger, row - 1, col, {})
	vim.snippet.expand(body)
end

local function expand_or_jump_snippet()
	if vim.snippet.active() then
		jump_snippet(1)
	else
		expand_snippet()
	end
end

local function complete(findstart, base)
	if findstart == 1 then return vim.fn.getline('.'):sub(1, vim.fn.col('.') - 1):find('[%w_]*$') - 1 end
	local matches = {}
	for trigger, body in pairs(vim.tbl_extend('force', snippets.global, snippets[vim.bo.filetype] or {})) do
		if trigger:sub(1, #base) == base then
			local info = ' ' .. body:gsub('\n', '\n ')
			matches[#matches + 1] = { word = trigger, menu = '[snippets.lua]', info = info, user_data = 'snip', dup = 1 }
		end
	end
	table.sort(matches, function(a, b) return a.word < b.word end)
	return matches
end

vim.api.nvim_create_autocmd('CompleteDone', {
	group = vim.api.nvim_create_augroup('aqsnow.snippets', { clear = true }),
	callback = function()
		if vim.v.completed_item.user_data == 'snip' then require('snippets').expand() end
	end,
})

return {
	expand = expand_snippet,
	expand_or_jump = expand_or_jump_snippet,
	jump = jump_snippet,
	complete = complete,
}
