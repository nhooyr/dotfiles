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
	local checkbox = line:find('%[[ \t]%]%f[%s%z]')
	if not checkbox then return end
	local row, col = unpack(api.nvim_win_get_cursor(0))
	local tree = assert(vim.treesitter.get_parser(0, 'markdown')):parse()[1]
	local item = tree:root():named_descendant_for_range(row - 1, checkbox, row - 1, checkbox + 1)
	while item and item:type() ~= 'list_item' do item = item:parent() end
	if not item then return end
	local marker_row, marker_end = item:named_child(0):end_()
	if marker_row ~= row - 1 or line:sub(marker_end + 1, checkbox - 1):find('[^ \t]') then return end

	local checked = line:sub(1, checkbox) .. 'x' .. line:sub(checkbox + 2)
	local next_item = item:next_named_sibling()
	if not next_item then
		api.nvim_set_current_line(checked)
		return
	end

	local list_end = item:parent():end_()
	local lines = api.nvim_buf_get_lines(0, row - 1, list_end, false)
	lines[1] = checked
	local next_row, next_col = next_item:start()
	local next_index = next_row - row + 2
	local _, item_col = item:start()
	local prefix = line:sub(1, item_col)
	-- Keep a shared parent marker on the first item of the nested list.
	if prefix:find('[^ \t>]') then
		local next_line = lines[next_index]
		lines[1] = next_line:sub(1, next_col) .. checked:sub(item_col + 1)
		lines[next_index] = prefix .. next_line:sub(next_col + 1)
		col = next_col + math.max(col - item_col, 0)
	end
	local _, quote_depth = prefix:gsub('>', '')
	local item_end = last_content_line(lines, next_index - 1, quote_depth)
	local last = last_content_line(lines, #lines, quote_depth)
	local moved = vim.list_slice(lines, next_index, last)
	vim.list_extend(moved, lines, item_end + 1, next_index - 1)
	vim.list_extend(moved, lines, 1, item_end)
	vim.list_extend(moved, lines, last + 1)
	api.nvim_buf_set_lines(0, row - 1, list_end, false, moved)
	api.nvim_win_set_cursor(0, { row + last - item_end, col })
end

return { tick = tick }
