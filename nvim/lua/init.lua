require('vim._core.ui2').enable({
  enable = true, -- Whether to enable or disable the UI.
  msg = { -- Options related to the message module.
	---@type string|table<string, 'cmd'|'msg'|'pager'> Default message target
	---or table mapping |ui-messages| kinds, triggers and IDs to a target.
	---Table keys are Lua patterns matching the start of the message ID. 'default'
	---mapping applies to any omitted kind: { default = 'cmd', progress = 'msg' }.
	targets = 'cmd',
	dialog = { -- Options related to dialog window.
	  height = 0.5, -- Maximum height.
	},
	msg = { -- Options related to msg window.
	  height = 0.5, -- Maximum height.
	},
	pager = { -- Options related to message window.
	  height = 0.999, -- Maximum height.
	},
  },
})
