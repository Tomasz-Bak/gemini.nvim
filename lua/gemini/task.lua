local config = require('gemini.config')
local api = require('gemini.api')
local util = require('gemini.util')

local M = {}

local context = {
  bufnr = nil,
  model_response = nil,
  tmpfile = nil,
}

M.setup = function()
  local model = config.get_config({ 'task', 'model' })
  if not model or not model.model_id then
    return
  end

  vim.api.nvim_create_user_command('GeminiTask', M.run_task, {
    force = true,
    desc = 'Google Gemini',
    nargs = 1,
  })

  vim.api.nvim_create_user_command('GeminiApply', M.apply_patch, {
    force = true,
    desc = 'Apply patch',
  })
end

local get_prompt_text = function(bufnr, user_prompt)
  local get_prompt = config.get_config({ 'task', 'get_prompt' })
  if not get_prompt then
    vim.notify('prompt function is not found', vim.log.levels.WARN)
    return nil
  end
  return get_prompt(bufnr, user_prompt)
end

local function open_file_in_split(filepath, ft)
  local cur_win = vim.api.nvim_get_current_win()
  local bufnr = vim.fn.bufnr(filepath, true)
  if bufnr == 0 then
    vim.notify("Error: Could not find or create buffer for file: " .. filepath, vim.log.levels.ERROR, { title = 'Gemini' })
    return
  end
  vim.api.nvim_set_option_value('filetype', ft, {buf = bufnr})

  local win_id = vim.api.nvim_open_win(bufnr, false, {
    split = 'right',
    win = 0,
  })
  vim.api.nvim_set_current_win(win_id)

  vim.api.nvim_set_option_value('diff', true, { win = cur_win })
  vim.api.nvim_set_option_value('diff', true, { win = win_id })
  vim.api.nvim_set_option_value('scrollbind', true, { win = win_id })
  vim.api.nvim_set_option_value('cursorbind', true, { win = win_id })
end

local function diff_with_current_file(bufnr, new_content)
  local tmpfile = vim.fn.tempname()

  -- Write to the temp file
  local f = io.open(tmpfile, "w")
  if f then
    f:write(new_content)
    f:close()
  end


  local ft = vim.api.nvim_get_option_value('filetype', {buf = bufnr})
  open_file_in_split(vim.fn.fnameescape(tmpfile), ft)
  return tmpfile
end

M.run_task = function(ctx)
  local bufnr = vim.api.nvim_get_current_buf()
  local user_prompt = ctx.args
  local prompt = get_prompt_text(bufnr, user_prompt)

  local system_text = nil
  local get_system_text = config.get_config({ 'task', 'get_system_text' })
  if get_system_text then
    system_text = get_system_text()
  end

  vim.notify('Running Gemini Task...', vim.log.levels.INFO, { title = 'Gemini' })
  local generation_config = config.get_gemini_generation_config('task')
  local model_id = config.get_config({ 'task', 'model', 'model_id' })

  local tmpfile = vim.fn.tempname()
  local ft = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  open_file_in_split(vim.fn.fnameescape(tmpfile), ft)
  local tmp_bufnr = vim.api.nvim_get_current_buf()

  context.bufnr = bufnr
  context.tmpfile = tmpfile

  local full_thought = ""
  local full_text = ""

  api.gemini_generate_content_stream(prompt, model_id, generation_config, function(json_text)
    local ok, model_response = pcall(vim.json.decode, json_text)
    if not ok then return end

    local parts = util.table_get(model_response, { 'candidates', 1, 'content', 'parts' })
    if not parts then return end

    for _, part in ipairs(parts) do
      if part.thought then
        full_thought = full_thought .. part.text
      elseif part.text then
        full_text = full_text .. part.text
      end
    end

    vim.schedule(function()
      local output = {}
      if #full_thought > 0 then
        table.insert(output, "> [Thinking]")
        for _, line in ipairs(vim.split(full_thought, "\n")) do
          table.insert(output, "> " .. line)
        end
        table.insert(output, "")
      end
      for _, line in ipairs(vim.split(full_text, "\n")) do
        table.insert(output, line)
      end
      vim.api.nvim_buf_set_lines(tmp_bufnr, 0, -1, false, output)
    end)
  end, system_text, function()
    vim.schedule(function()
      vim.notify('Gemini Task finished. Review the full response.', vim.log.levels.INFO, { title = 'Gemini' })
    end)
  end)
end

local function close_split_by_filename(tmpfile)
  -- Get the buffer number for the temp file
  local bufnr = vim.fn.bufnr(tmpfile)
  if bufnr == -1 then
    vim.notify("No buffer found for file: " .. tmpfile, vim.log.levels.WARN, { title = 'Gemini' })
    return
  end

  -- Find the window displaying this buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_win_close(win, true)  -- force close the window
      vim.api.nvim_buf_delete(bufnr, { force = true, unload = true })
      return
    end
  end
  vim.notify("No window found showing the buffer for file: " .. tmpfile, vim.log.levels.WARN, { title = 'Gemini' })
end

M.apply_patch = function()
  if not context.bufnr or not context.tmpfile then
    vim.notify('No Gemini task to apply.', vim.log.levels.WARN)
    return
  end

  vim.notify('Applying changes from Gemini...', vim.log.levels.INFO, { title = 'Gemini' })

  local tmp_bufnr = vim.fn.bufnr(vim.fn.fnamemodify(context.tmpfile, ':p'))
  if tmp_bufnr == -1 then
    vim.notify('Could not find the temporary buffer for edited changes.', vim.log.levels.ERROR)
    return
  end

  local edited_lines_raw = vim.api.nvim_buf_get_lines(tmp_bufnr, 0, -1, false)
  local cleaned_lines = util.strip_code(edited_lines_raw)

  vim.api.nvim_buf_set_lines(context.bufnr, 0, -1, false, cleaned_lines)

  if context.tmpfile then
    close_split_by_filename(context.tmpfile)
  end

  context.bufnr = nil
  context.model_response = nil
  context.tmpfile = nil
end

return M
