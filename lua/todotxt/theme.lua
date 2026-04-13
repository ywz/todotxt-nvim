local M = {}

local default_theme = {
	todotxtDoneLine = { fg = "#6c7b8b", strikethrough = true },
	todotxtLowPriorityLine = { fg = "#C4C6CD" },
	todotxtCreationDate = { fg = "#9b9ea4" },
	todotxtPriority = { fg = "#d02090", bold = true },
	todotxtProject = { fg = "#A6DBFF", bold = false },
	todotxtContext = { fg = "#8cf8f7", bold = true },
	todotxtDue = { fg = "#FCE094" },
	todotxtDueKey = { fg = "#FCE094" },
	todotxtDueDate = { fg = "#FCE094" },
	todotxtTodayDue = { fg = "#FFCAFF", bold = true },
	todotxtMeta = { fg = "#C4C6CD" },
	todotxtMetaKey = { fg = "#b4f6c0", bold = true },
	todotxtMetaValue = { fg = "#b4f6c0" },
	todotxtMetaDate = { fg = "#b4f6c0" },
	todotxtOverdueDue = { fg = "#FFC0B9", bg = "#590008", bold = true },
	todotxtCalendarToday = { fg = "#14161B", bg = "#A6DBFF", bold = true },
	todotxtCalendarSelected = { fg = "#14161B", bg = "#FCE094", bold = true },
}

function M.get_default_theme()
	return vim.deepcopy(default_theme)
end

return M
