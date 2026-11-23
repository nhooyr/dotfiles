local fn = vim.fn

local function fmt()
	local lines, names = fn.getline(1, '$'), {}
	local items = fn.getwininfo(fn.win_getid())[1].loclist == 1 and fn.getloclist(0) or fn.getqflist()
	for i, text in ipairs(lines) do
		local item = items[i]
		local name = item.module
		if name == '' and item.bufnr ~= 0 then
			local key = item.bufnr * 2 + (item.type == '\1' and 1 or 0)
			names[key] = names[key] or fn.fnamemodify(fn.bufname(item.bufnr), item.type == '\1' and ':t' or ':.')
			name = names[key]
		end
		local boundary = #name + 1
		if text:sub(1, boundary) == name .. '|' then
			lines[i] = text:sub(1, boundary) .. text:sub(boundary + 1):gsub('^([%d-]+) col ', '%1:')
		end
	end
	vim.bo.modifiable = true
	fn.setline(1, lines)
	vim.bo.modifiable = false
	vim.bo.modified = false
end

return { fmt = fmt }
