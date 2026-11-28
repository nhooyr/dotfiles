local api = vim.api

local function last_content_line(lines, index, quote_depth)
	while not lines[index]:find('[^ \t>]') do
		local _, depth = lines[index]:gsub('>', '')
		if depth > quote_depth then break end
		index = index - 1
	end
	return index
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
	local next_item = not reopening and item:next_named_sibling()
	if not next_item then
		api.nvim_set_current_line(updated)
		return
	end

	local lines = api.nvim_buf_get_lines(0, row, item:parent():end_(), false)
	local next_row, next_col = next_item:start()
	local next_index = next_row - row + 1
	local _, item_col = item:start()
	local prefix = line:sub(1, item_col)
	-- Keep a shared parent marker on the first item of the nested list.
	if prefix:find('[^ \t>]') then
		local next_line = lines[next_index]
		updated = next_line:sub(1, next_col) .. updated:sub(item_col + 1)
		lines[next_index] = prefix .. next_line:sub(next_col + 1)
		cursor[2] = next_col + math.max(cursor[2] - item_col, 0)
	end
	lines[1] = updated

	local _, quote_depth = prefix:gsub('>', '')
	local item_end = last_content_line(lines, next_index - 1, quote_depth)
	local last = last_content_line(lines, #lines, quote_depth)
	local replacement = vim.list_slice(lines, next_index, last)
	vim.list_extend(replacement, lines, item_end + 1, next_index - 1)
	vim.list_extend(replacement, lines, 1, item_end)
	api.nvim_buf_set_lines(0, row, row + last, false, replacement)
	cursor[1] = cursor[1] + last - item_end
	api.nvim_win_set_cursor(0, cursor)
end

return { tick = tick }
