local M = {}

local function cmd(lines)
  vim.cmd(table.concat(lines, "\n"))
end

local function normalize_color(value)
  if type(value) ~= "string" then
    return value
  end

  if value == "fg" or value == "bg" then
    return value
  end

  if value:match("^#%x%x%x%x%x%x$") then
    return tonumber(value:sub(2), 16)
  end

  return value
end

local function normalize_highlight(spec)
  local normalized = {}

  for key, value in pairs(spec) do
    if key == "fg" or key == "bg" or key == "sp" then
      normalized[key] = normalize_color(value)
    else
      normalized[key] = value
    end
  end

  return normalized
end

function M.apply_theme()
  local theme = require("todotxt").get_config().theme

  for group, spec in pairs(theme) do
    vim.api.nvim_set_hl(0, group, normalize_highlight(spec))
  end
end

local syntax_commands = {
  "syntax case match",
  "syntax clear",
  [[syntax match todotxtPriority /^\s*(\([A-Y]\))\ze\s/ containedin=ALLBUT,todotxtDoneLine]],
  [[syntax match todotxtCreationDate /\%(^\s*(\([A-Y]\))\s\+\)\@<=\d\{4}-\d\d-\d\d\>/ containedin=ALLBUT,todotxtDoneLine]],
  [[syntax match todotxtCreationDate /\%(^\s*\)\@<=\d\{4}-\d\d-\d\d\>/ containedin=ALLBUT,todotxtDoneLine]],
  [[syntax match todotxtProject /\(^\|\s\)\zs+\S\+/ containedin=ALLBUT,todotxtDoneLine]],
  [[syntax match todotxtContext /\(^\|\s\)\zs@\S\+/ containedin=ALLBUT,todotxtDoneLine]],
  [[syntax match todotxtDue /\(^\|\s\)\zsdue:\d\{4}-\d\d-\d\d\>/ contains=todotxtDueKey,todotxtDueDate containedin=ALLBUT,todotxtDoneLine]],
  [[syntax match todotxtDueKey /\<due:\ze\d\{4}-\d\d-\d\d\>/ contained]],
  [[syntax match todotxtDueDate /\%(\<due:\)\@<=\d\{4}-\d\d-\d\d\>/ contained]],
  [[syntax match todotxtMeta /\(^\|\s\)\zs\%(due:\)\@![^[:space:]:]\+:[^[:space:]:]\+\ze\%(\s\|$\)/ contains=todotxtMetaKey,todotxtMetaValue,todotxtMetaDate containedin=ALLBUT,todotxtDoneLine]],
  [[syntax match todotxtMetaKey /[^[:space:]:]\+\ze:[^[:space:]:]\+/ contained]],
  [[syntax match todotxtMetaValue /\%([^[:space:]:]\+:\)\@<=[^[:space:]:]\+/ contained contains=todotxtMetaDate]],
  [[syntax match todotxtMetaDate /\%([^[:space:]:]\+:\)\@<=\d\{4}-\d\d-\d\d\>/ contained]],
  [[syntax match todotxtDoneLine /^\s*x \d\{4}-\d\d-\d\d.*$/ contains=NONE]],
}

function M.setup()
  cmd(syntax_commands)
  M.apply_theme()
  vim.b.current_syntax = "todotxt"
end

return M
