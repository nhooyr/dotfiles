local fn = vim.fn
local kinds = { e = 'error', w = 'warning', i = 'info', n = 'note' }

local function range(first, last)
	return last > 0 and last ~= first and first .. '-' .. last or tostring(first)
end

local function title()
	local text = vim.w.quickfix_title
	if not text then return '' end
	local shorten = require('dirali').shorten
	text = text:gsub([[(['"])(.-)%1]], function(quote, path)
		return quote .. shorten(path) .. quote
	end)
	return ' ' .. text:gsub([[/[^%s'"]+]], shorten)
end

local function fmt(info)
	local request = { id = info.id, items = 0 }
	local items = (info.quickfix == 1 and fn.getqflist(request)
		or fn.getloclist(info.winid, request)).items
	local names, help_names, lines = {}, {}, {}
	for i = info.start_idx, info.end_idx do
		local item = items[i]
		if item.lnum <= 0 then
			lines[#lines + 1] = ''
		else
			local help = item.type == '\1'
			local cache = help and help_names or names
			local name = item.module ~= '' and item.module or cache[item.bufnr]
			if not name then
				name = item.bufnr == 0 and '' or vim.api.nvim_buf_get_name(item.bufnr)
				if help then name = fn.fnamemodify(name, ':t')
				elseif name:sub(1, 1) == '/' then name = require('dirali').shorten(name) end
				cache[item.bufnr] = name
			end
			local position = range(item.lnum, item.end_lnum)
			local kind = help and '' or (kinds[item.type:lower()] or item.type)
			if item.nr > 0 then
				if kind == '' and not help then kind = 'error' end
				kind = kind .. (' %3d'):format(item.nr)
			end
			if kind ~= '' then position = position .. ' ' .. kind end
			local text = item.text:gsub('^[ \t]*', ''):gsub('\n%s*', ' ')
			lines[#lines + 1] = name .. '|' .. position .. '| ' .. text
		end
	end
	return lines
end

return { fmt = fmt, title = title }
