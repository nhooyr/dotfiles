local api = vim.api

local function is_blank(line, quote_depth)
	if line:find('[^ \t>]') then return false end
	local _, depth = line:gsub('>', '')
	return depth <= quote_depth
end

local function tick()
	local line = api.nvim_get_current_line()
	local marker, checkbox = line:match('()[-+*.)][ \t]+()%[[ \t]%]%f[%s%z]')
	if not marker then return end
	local cursor = api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local root = assert(vim.treesitter.get_parser(0, 'markdown')):parse()[1]:root()
	-- Spanning the marker and checkbox selects the list item.
	local item = root:named_descendant_for_range(row, marker - 1, row, checkbox + 1)
	if not item or item:type() ~= 'list_item' then return end

	local checked = line:sub(1, checkbox) .. 'x' .. line:sub(checkbox + 2)
	local _, item_col = item:start()
	local prefix = line:sub(1, item_col)
	local _, quote_depth = prefix:gsub('>', '')
	local list_end = item:parent():end_()
	local next_item = item:next_named_sibling()
	local lines = next_item and api.nvim_buf_get_lines(0, row, list_end, false)
	local following = next_item
	-- Only look directly before siblings so blank lines inside an item stay with it.
	while following and not is_blank(lines[following:start() - row], quote_depth) do
		following = following:next_named_sibling()
	end
	if following == next_item then
		api.nvim_set_current_line(checked)
		return
	end

	local last = (following and following:start() or list_end) - row
	while is_blank(lines[last], quote_depth) do last = last - 1 end

	local next_row, next_col = next_item:start()
	local next_index = next_row - row + 1
	-- Keep a shared parent marker on the first item of the nested list.
	if prefix:find('[^ \t>]') then
		local next_line = lines[next_index]
		checked = next_line:sub(1, next_col) .. checked:sub(item_col + 1)
		lines[next_index] = prefix .. next_line:sub(next_col + 1)
		cursor[2] = next_col + math.max(cursor[2] - item_col, 0)
	end
	lines[1] = checked

	local replacement = vim.list_slice(lines, next_index, last)
	vim.list_extend(replacement, lines, 1, next_index - 1)
	api.nvim_buf_set_lines(0, row, row + last, false, replacement)
	cursor[1] = cursor[1] + last - next_index + 1
	api.nvim_win_set_cursor(0, cursor)
end

return { tick = tick }
