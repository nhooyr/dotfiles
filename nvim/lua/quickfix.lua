local fn = vim.fn
local kinds = { e = 'error', w = 'warning', i = 'info', n = 'note' }

local function toggle_location_list()
	local list = fn.getloclist(0, { winid = 0, id = 0 })
	vim.cmd(list.winid ~= 0 and 'lclose' or list.id ~= 0 and 'lopen' or 'Lvim')
end

local function range(first, last)
	return last > 0 and last ~= first and first .. '-' .. last or tostring(first)
end

local function directory(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local list = fn.getqflist({ context = 0, qfbufnr = 0 })
	if list.qfbufnr ~= buf then
		local win = fn.bufwinid(buf)
		if win == -1 then return nil end
		list = fn.getloclist(win, { context = 0 })
	end
	if type(list.context) == 'table' and type(list.context.cwd) == 'string' then
		return list.context.cwd
	end
end

local function title()
	local text = vim.w.quickfix_title
	if not text then return '' end
	text = text:gsub('^:vgrep(%s)', ':grep%1'):gsub('^Find([gf]?%s)', ':Find%1')
	local shorten = require('dirali').shorten
	text = text:gsub([[(['"])(.-)%1]], function(quote, path)
		return quote .. shorten(path) .. quote
	end)
	local cwd = directory()
	return (cwd and shorten(cwd) .. ' && ' or '') .. text:gsub([[/[^%s'"]+]], shorten)
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
				name = item.bufnr == 0 and '' or fn.bufname(item.bufnr)
				if help then name = fn.fnamemodify(name, ':t')
				elseif name:sub(1, 1) == '/' then name = fn.fnamemodify(name, ':.') end
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

return { fmt = fmt, title = title, directory = directory, toggle_location_list = toggle_location_list }
