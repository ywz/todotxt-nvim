local M = {}

local theme = require("todotxt.theme")

local default_config = {
  theme = theme.get_default_theme(),
}

local config = vim.deepcopy(default_config)

local function refresh_open_todotxt_buffers()
  local ok, ftplugin = pcall(require, "todotxt.ftplugin")
  if not ok then
    return
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "todotxt" then
      vim.api.nvim_buf_call(buf, function()
        ftplugin.setup()
      end)
    end
  end
end

function M.get_config()
  return config
end

function M.get_default_config()
  return vim.deepcopy(default_config)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})

  vim.filetype.add({
    extension = {
      todotxt = "todotxt",
    },
    filename = {
      ["todo.txt"] = "todotxt",
      ["done.txt"] = "todotxt",
    },
    pattern = {
      [".*%.todo%.txt"] = { "todotxt", { priority = 100 } },
      [".*%.done%.txt"] = { "todotxt", { priority = 100 } },
    },
  })

  refresh_open_todotxt_buffers()
end

return M
