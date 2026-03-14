local uv = vim.loop or vim.uv

local M = {}

local API = "https://generativelanguage.googleapis.com/v1beta/models/";

M.MODELS = {
  GEMINI_3_1_PRO_PREVIEW = 'gemini-3.1-pro-preview',
  GEMINI_3_1_FLASH_LITE_PREVIEW = 'gemini-3.1-flash-lite-preview',
  GEMINI_3_PRO_PREVIEW = 'gemini-3-pro-preview',
  GEMINI_3_FLASH_PREVIEW = 'gemini-3-flash-preview',
  GEMINI_2_5_PRO = 'gemini-2.5-pro',
  GEMINI_2_5_FLASH = 'gemini-2.5-flash',
  GEMINI_2_5_FLASH_LITE = 'gemini-2.5-flash-lite',
  GEMINI_2_0_FLASH = 'gemini-2.0-flash',
  GEMINI_2_0_FLASH_LITE = 'gemini-2.0-flash-lite',
  GEMINI_PRO_LATEST = 'gemini-pro-latest',
  GEMINI_FLASH_LATEST = 'gemini-flash-latest',
  GEMINI_FLASH_LITE_LATEST = 'gemini-flash-lite-latest',
  GEMMA_3_27B = 'gemma-3-27b-it',
  GEMMA_3_12B = 'gemma-3-12b-it',
  GEMMA_3_4B = 'gemma-3-4b-it',
  GEMMA_3_1B = 'gemma-3-1b-it',
  DEEP_RESEARCH_PRO_PREVIEW = 'deep-research-pro-preview-12-2025',
}

M.gemini_generate_content = function(user_text, system_text, model_name, generation_config, callback)
  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    vim.notify("GEMINI_API_KEY not found in environment", vim.log.levels.ERROR)
    return ''
  end

  local api = API .. model_name .. ':generateContent?key=' .. api_key
  local contents = {
    {
      parts = {
        {
          text = user_text
        }
      }
    }
  }
  local data = {
    contents = contents,
    generationConfig = generation_config,
  }
  if system_text then
    data.systemInstruction = {
      parts = {
        {
          text = system_text,
        }
      }
    }
  end

  local json_text = vim.json.encode(data)
  local cmd = { 'curl', '-X', 'POST', api, '-H', 'Content-Type: application/json', '--data-binary', '@-' }
  local opts = { stdin = json_text }
  if callback then
    return vim.system(cmd, opts, callback)
  else
    return vim.system(cmd, opts)
  end
end

M.gemini_generate_content_stream = function(user_text, model_name, generation_config, callback, system_text, on_finish)
  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    vim.notify("GEMINI_API_KEY not found in environment", vim.log.levels.ERROR)
    return
  end

  if not callback then
    return
  end
  print("-- calling gemini stream api --")

  local api = API .. model_name .. ':streamGenerateContent?alt=sse&key=' .. api_key
  local data = {
    contents = {
      {
        parts = {
          {
            text = user_text
          }
        }
      }
    },
    generationConfig = generation_config,
  }
  if system_text then
    data.systemInstruction = {
      parts = {
        {
          text = system_text,
        }
      }
    }
  end
  local json_text = vim.json.encode(data)

  local stdin = uv.new_pipe()
  local stdout = uv.new_pipe()
  local stderr = uv.new_pipe()
  local options = {
    stdio = { stdin, stdout, stderr },
    args = { api, '-X', 'POST', '-s', '-H', 'Content-Type: application/json', '-d', json_text }
  }

  uv.spawn('curl', options, function(code, signal)
    if on_finish then
      on_finish(code, signal)
    end
  end)

  -- Capture stderr for debugging
  uv.read_start(stderr, function(err, data)
    if not err and data then
      vim.schedule(function()
        vim.notify("Gemini API Error (stderr): " .. data, vim.log.levels.ERROR)
      end)
    end
  end)

  local streamed_data = ''
  uv.read_start(stdout, function(err, data)
    if not err and data then
      streamed_data = streamed_data .. data

      -- SSE logic: split by newline, handle data: prefix
      while true do
        local start_index = string.find(streamed_data, 'data:')
        if not start_index then 
          -- If we have data but no "data:" prefix, it might be a raw JSON error
          if #streamed_data > 0 and not string.find(streamed_data, "^{") then
            break 
          end
        end
        
        local end_index = string.find(streamed_data, '\n', start_index)
        if not end_index then break end

        local json_text = string.sub(streamed_data, (start_index or 0) + 5, end_index - 1)
        -- Basic validation before callback
        if json_text:match("^%s*{") then
          callback(json_text)
        end
        streamed_data = string.sub(streamed_data, end_index + 1)
      end
    end
  end)
end

return M
