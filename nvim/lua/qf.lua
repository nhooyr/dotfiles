return function()
	local lines = vim.fn.getline(1, '$')
	for i, text in ipairs(lines) do lines[i] = text:gsub('^([^|]*|[%d-]+) col ', '%1:') end
	vim.bo.modifiable = true
	vim.fn.setline(1, lines)
	vim.bo.modifiable = false
	vim.bo.modified = false
end
