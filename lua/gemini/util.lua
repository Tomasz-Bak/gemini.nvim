local M = {}

M.borderchars = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' }

M.open_window = function(content, options)
  local popup = require('plenary.popup')
  options.borderchars = M.borderchars
  local win_id, result = popup.create(content, options)
  local bufnr = vim.api.nvim_win_get_buf(win_id)
  local border = result.border
  vim.api.nvim_set_option_value('ft', 'markdown', { buf = bufnr })
  vim.api.nvim_set_option_value('wrap', true, { win = win_id })

  local close_popup = function()
    vim.api.nvim_win_close(win_id, true)
  end

  local keys = { '<C-q>', 'q' }
  for _, key in pairs(keys) do
    vim.api.nvim_buf_set_keymap(bufnr, 'n', key, '', {
      silent = true,
      callback = close_popup,
    })
  end
  return win_id, bufnr, border
end

M.treesitter_has_lang = function(bufnr)
  local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  local lang = vim.treesitter.language.get_lang(filetype)
  return lang ~= nil
end

M.find_node_by_type = function(node_type)
  local node = vim.treesitter.get_node()
  while node do
    local type = node:type()
    if string.find(type, node_type) then
      return node
    end

    local parent = node:parent()
    if parent == node then
      break
    end
    node = parent
  end
  return nil
end

M.debounce = function(callback, timeout)
  local timer = nil
  local f = function(...)
    local t = { ... }
    local handler = function()
      callback(unpack(t))
    end

    if timer ~= nil then
      timer:stop()
    end
    timer = vim.defer_fn(handler, timeout)
  end
  return f
end

M.table_get = function(t, id)
  if type(id) ~= 'table' then return M.table_get(t, { id }) end
  local success, res = true, t
  for _, i in ipairs(id) do
    success, res = pcall(function() return res[i] end)
    if not success or res == nil then return end
  end
  return res
end

M.is_blacklisted = function(blacklist, filetype)
  for _, ft in ipairs(blacklist) do
    if string.find(filetype, ft, 1, true) ~= nil then
      return true
    end
  end
  return false
end

M.strip_code = function(text)
  if not text or text == "" then
    return {}
  end

  local all_lines = vim.split(text, "\n")
  local result_lines = {}
  local in_code_block = false
  local found_any_block = false

  for _, line in ipairs(all_lines) do
    -- Detect the start or end of a code block
    if line:match("^%s*```") then
      in_code_block = not in_code_block
      found_any_block = true
    else
      -- Only collect lines that are inside a triple-backtick block
      if in_code_block then
        table.insert(result_lines, line)
      end
    end
  end

  -- Fallback: If no code blocks were found, return the original text split into lines.
  -- This handles cases where the model returns raw code without markdown formatting.
  if not found_any_block or #result_lines == 0 then
    return all_lines
  end

  return result_lines
end

return M
