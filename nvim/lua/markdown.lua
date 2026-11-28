local api = vim.api

local function setup()
	vim.bo.expandtab = true
	vim.bo.tabstop = 3
	vim.bo.softtabstop = -1
	vim.bo.shiftwidth = 0
	vim.cmd('inoreabbrev <buffer> -[ - [ ]')
	api.nvim_buf_create_user_command(0, 'Mdtick', "lua require('markdown').tick()", {})
	vim.keymap.set('n', '<Leader>x', '<Cmd>Mdtick<CR>', { buffer = true })
end

local function is_blank(line, quote_depth)
	if line:find('[^ \t>]') then return false end
	local _, depth = line:gsub('>', '')
	return depth <= quote_depth
end

local function tick()
	local line = api.nvim_get_current_line()
	local marker, checkbox, state = line:match('()[-+*.)][ \t]+()%[([ \txX])%]%f[%s%z]')
	if not marker then return end
	local cursor = api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local root = assert(vim.treesitter.get_parser(0, 'markdown')):parse()[1]:root()
	-- Spanning the marker and checkbox selects the list item.
	local item = root:named_descendant_for_range(row, marker - 1, row, checkbox + 1)
	if not item or item:type() ~= 'list_item' then return end

	local reopening = state:lower() == 'x'
	local updated = line:sub(1, checkbox) .. (reopening and ' ' or 'x') .. line:sub(checkbox + 2)
	local _, item_col = item:start()
	local prefix = line:sub(1, item_col)
	local _, quote_depth = prefix:gsub('>', '')

	local next_item = not reopening and item:next_named_sibling()
	local last_item = item
	local sibling = next_item
	-- Only look directly before siblings so blank lines inside an item stay with it.
	while sibling do
		local sibling_row = sibling:start()
		local previous_line = api.nvim_buf_get_lines(0, sibling_row - 1, sibling_row, false)[1]
		if is_blank(previous_line, quote_depth) then break end
		last_item = sibling
		sibling = sibling:next_named_sibling()
	end
	if last_item == item then
		api.nvim_set_current_line(updated)
		return
	end

	local lines = api.nvim_buf_get_lines(0, row, last_item:end_(), false)
	local last = #lines
	while is_blank(lines[last], quote_depth) do last = last - 1 end

	local next_row, next_col = next_item:start()
	local next_index = next_row - row + 1
	-- Keep a shared parent marker on the first item of the nested list.
	if prefix:find('[^ \t>]') then
		local next_line = lines[next_index]
		updated = next_line:sub(1, next_col) .. updated:sub(item_col + 1)
		lines[next_index] = prefix .. next_line:sub(next_col + 1)
		cursor[2] = next_col + math.max(cursor[2] - item_col, 0)
	end
	lines[1] = updated

	local replacement = vim.list_slice(lines, next_index, last)
	vim.list_extend(replacement, lines, 1, next_index - 1)
	api.nvim_buf_set_lines(0, row, row + last, false, replacement)
	cursor[1] = cursor[1] + last - next_index + 1
	api.nvim_win_set_cursor(0, cursor)
end

return { setup = setup, tick = tick }
