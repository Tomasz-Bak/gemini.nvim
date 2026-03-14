local config = require('gemini.config')
local util = require('gemini.util')
local api = require('gemini.api')

local M = {}

M.setup = function()
  local model = config.get_config({ 'chat', 'model' })
  if not model or not model.model_id then
    return
  end

  vim.api.nvim_create_user_command('GeminiChat', M.start_chat, {
    force = true,
    desc = 'Google Gemini',
    nargs = 1,
  })

  vim.api.nvim_create_user_command('Gemini', function()
    M.open_chat_gui()
  end, {
    force = true,
    desc = 'Open Gemini Chat Sidebar',
  })
end

local context = {
  chat_winnr = nil,
  chat_number = 0,
  gui = {
    out_buf = nil,
    in_buf = nil,
    out_win = nil,
    in_win = nil,
  }
}

M.open_chat_gui = function()
  -- Create Sidebar (Right split)
  vim.cmd('rightbelow vsplit')
  vim.cmd('vertical resize 50')
  local out_win = vim.api.nvim_get_current_win()
  local out_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('ft', 'markdown', { buf = out_buf })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = out_buf })
  vim.api.nvim_win_set_buf(out_win, out_buf)
  vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, { "# Gemini Chat Output", "" })

  -- Create Input Area (Bottom of sidebar)
  vim.cmd('belowright split')
  vim.cmd('resize 5')
  local in_win = vim.api.nvim_get_current_win()
  local in_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('ft', 'markdown', { buf = in_buf })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = in_buf })
  vim.api.nvim_win_set_buf(in_win, in_buf)

  context.gui = {
    out_buf = out_buf,
    in_buf = in_buf,
    out_win = out_win,
    in_win = in_win,
  }

  -- Keymap for sending message
  vim.keymap.set('n', '<CR>', function() M.send_gui_message() end, { buffer = in_buf, silent = true })
  vim.api.nvim_buf_set_lines(in_buf, 0, -1, false, { "" })
  vim.api.nvim_set_current_win(in_win)
  vim.cmd('startinsert')
end

M.send_gui_message = function()
  local lines = vim.api.nvim_buf_get_lines(context.gui.in_buf, 0, -1, false)
  local user_text = table.concat(lines, "\n")
  if #user_text == 0 then return end

  -- Clear input
  vim.api.nvim_buf_set_lines(context.gui.in_buf, 0, -1, false, { "" })

  -- Append User text to output
  local out_buf = context.gui.out_buf
  local current_lines = vim.api.nvim_buf_get_lines(out_buf, 0, -1, false)
  table.insert(current_lines, "### User")
  table.insert(current_lines, user_text)
  table.insert(current_lines, "")
  table.insert(current_lines, "### Gemini")
  local response_start_idx = #current_lines
  vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, current_lines)

  local generation_config = config.get_gemini_generation_config('chat')
  local model_id = config.get_config({ 'chat', 'model', 'model_id' })
  
  local full_thought = ""
  local full_text = ""

  api.gemini_generate_content_stream(user_text, model_id, generation_config, function(json_text)
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
      
      vim.api.nvim_buf_set_lines(out_buf, response_start_idx, -1, false, output)
      -- Auto-scroll
      vim.api.nvim_win_set_cursor(context.gui.out_win, { vim.api.nvim_buf_line_count(out_buf), 0 })
    end)
  end)
end

local function get_bufnr(user_text)
  local conf = config.get_config({ 'chat' })
  if not conf then
    vim.api.nvim_command('tabnew')
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_option_value('ft', 'markdown', { buf = bufnr })
    return bufnr
  end

  local bufnr = nil
  if not context.chat_winnr or not vim.api.nvim_win_is_valid(context.chat_winnr) or conf.window.position == 'new_tab' then
    if conf.window.position == 'tab' or conf.window.position == 'new_tab' then
      vim.api.nvim_command('tabnew')
    elseif conf.window.position == 'left' then
      vim.api.nvim_command('vertical topleft split new')
      vim.api.nvim_win_set_width(0, conf.window.width or 80)
    elseif conf.window.position == 'right' then
      vim.api.nvim_command('rightbelow vnew')
      vim.api.nvim_win_set_width(0, conf.window.width or 80)
    end
    context.chat_winnr = vim.api.nvim_tabpage_get_win(0)
    bufnr = vim.api.nvim_win_get_buf(0)
  end
  vim.api.nvim_set_current_win(context.chat_winnr)
  bufnr = bufnr or vim.api.nvim_win_get_buf(0)
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })
  vim.api.nvim_set_option_value('ft', 'markdown', { buf = bufnr })
  vim.api.nvim_buf_set_name(bufnr, 'Chat' .. context.chat_number .. ': ' .. user_text)

  return vim.api.nvim_win_get_buf(0)
end

M.start_chat = function(cxt)
  local user_text = cxt.args
  context.chat_number = context.chat_number + 1
  local bufnr = get_bufnr(user_text)
  local lines = { 'Generating response...' }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local generation_config = config.get_gemini_generation_config('chat')
  local text = ''
  local model_id = config.get_config({ 'chat', 'model', 'model_id' })
  api.gemini_generate_content_stream(user_text, model_id, generation_config, function(json_text)
    local model_response = vim.json.decode(json_text)
    model_response = util.table_get(model_response, { 'candidates', 1, 'content', 'parts', 1, 'text' })
    if not model_response then
      return
    end

    text = text .. model_response
    vim.schedule(function()
      lines = vim.split(text, '\n')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end)
  end)
end

return M
