-- JSON/JSONC 解码与键位置解析，供各 provider 和 statuscolumn 共用

local M = {}

---@param source string
---@return string
local function sanitize_jsonc(source)
  local output = {}
  local index = 1
  local in_string = false

  while index <= #source do
    local char = source:sub(index, index)
    local next_char = source:sub(index + 1, index + 1)

    if in_string then
      output[#output + 1] = char
      if char == '\\' and index < #source then
        output[#output + 1] = next_char
        index = index + 2
      else
        if char == '"' then in_string = false end
        index = index + 1
      end
    elseif char == '"' then
      in_string = true
      output[#output + 1] = char
      index = index + 1
    elseif char == '/' and next_char == '/' then
      output[#output + 1] = ' '
      output[#output + 1] = ' '
      index = index + 2
      while index <= #source and source:sub(index, index) ~= '\n' do
        output[#output + 1] = ' '
        index = index + 1
      end
    elseif char == '/' and next_char == '*' then
      output[#output + 1] = ' '
      output[#output + 1] = ' '
      index = index + 2
      while index <= #source do
        char = source:sub(index, index)
        next_char = source:sub(index + 1, index + 1)
        if char == '*' and next_char == '/' then
          output[#output + 1] = ' '
          output[#output + 1] = ' '
          index = index + 2
          break
        end
        output[#output + 1] = char == '\n' and '\n' or ' '
        index = index + 1
      end
    else
      output[#output + 1] = char
      index = index + 1
    end
  end

  local uncommented = table.concat(output)
  local cleaned = {}
  index = 1
  in_string = false

  while index <= #uncommented do
    local char = uncommented:sub(index, index)
    if in_string then
      cleaned[#cleaned + 1] = char
      if char == '\\' and index < #uncommented then
        cleaned[#cleaned + 1] = uncommented:sub(index + 1, index + 1)
        index = index + 2
      else
        if char == '"' then in_string = false end
        index = index + 1
      end
    elseif char == '"' then
      in_string = true
      cleaned[#cleaned + 1] = char
      index = index + 1
    elseif char == ',' then
      local lookahead = index + 1
      while uncommented:sub(lookahead, lookahead):match('%s') do
        lookahead = lookahead + 1
      end
      local target = uncommented:sub(lookahead, lookahead)
      cleaned[#cleaned + 1] = (target == '}' or target == ']') and ' ' or char
      index = index + 1
    else
      cleaned[#cleaned + 1] = char
      index = index + 1
    end
  end

  return table.concat(cleaned)
end

---@param source string
---@return table?
function M.decode(source)
  local ok, data = pcall(vim.json.decode, sanitize_jsonc(source))
  return ok and type(data) == 'table' and data or nil
end

---@class VVTaskPanelJsonToken
---@field kind 'string' | 'punct'
---@field value string
---@field line integer

---@param raw string
---@return string?
local function decode_string(raw)
  local ok, value = pcall(vim.json.decode, raw)
  return ok and type(value) == 'string' and value or nil
end

---@param source string
---@return VVTaskPanelJsonToken[]
local function tokenize(source)
  local tokens = {}
  local index = 1
  local line = 1

  while index <= #source do
    local char = source:sub(index, index)
    if char == '\n' then
      line = line + 1
      index = index + 1
    elseif char:match('%s') then
      index = index + 1
    elseif char == '/' and source:sub(index + 1, index + 1) == '/' then
      index = index + 2
      while index <= #source and source:sub(index, index) ~= '\n' do
        index = index + 1
      end
    elseif char == '/' and source:sub(index + 1, index + 1) == '*' then
      index = index + 2

      while index <= #source do
        local current = source:sub(index, index)
        if current == '\n' then line = line + 1 end
        if current == '*' and source:sub(index + 1, index + 1) == '/' then
          index = index + 2
          break
        end
        index = index + 1
      end
    elseif char == '"' then
      local start = index
      local token_line = line
      index = index + 1

      while index <= #source do
        local current = source:sub(index, index)
        if current == '\\' then
          index = index + 2
        elseif current == '"' then
          index = index + 1
          break
        else
          if current == '\n' then line = line + 1 end
          index = index + 1
        end
      end

      local raw = source:sub(start, index - 1)
      local value = decode_string(raw)
      if value then
        tokens[#tokens + 1] = { kind = 'string', value = value, line = token_line }
      end
    elseif char:find('[%{%}%[%]:,]') then
      tokens[#tokens + 1] = { kind = 'punct', value = char, line = line }
      index = index + 1
    else
      index = index + 1
    end
  end

  return tokens
end

---@param tokens VVTaskPanelJsonToken[]
---@param section_key string
---@return integer?
local function section_start(tokens, section_key)
  local stack = {}

  for index, token in ipairs(tokens) do
    if token.kind == 'string'
      and token.value == section_key
      and #stack == 1
      and stack[1] == '{'
      and tokens[index + 1]
      and tokens[index + 1].value == ':'
      and tokens[index + 2]
      and tokens[index + 2].value == '{'
    then
      return index + 2
    end

    if token.value == '{' or token.value == '[' then
      stack[#stack + 1] = token.value
    elseif token.value == '}' or token.value == ']' then
      stack[#stack] = nil
    end
  end
end

---@param source string
---@param section_key string
---@return table<string, integer>
function M.key_lines(source, section_key)
  local tokens = tokenize(source)
  local start = section_start(tokens, section_key)
  if not start then return {} end

  local lines = {}
  local stack = { '{' }

  for index = start + 1, #tokens do
    local token = tokens[index]
    if token.kind == 'string'
      and #stack == 1
      and tokens[index + 1]
      and tokens[index + 1].value == ':'
    then
      lines[token.value] = token.line
    end

    if token.value == '{' or token.value == '[' then
      stack[#stack + 1] = token.value
    elseif token.value == '}' or token.value == ']' then
      stack[#stack] = nil
      if #stack == 0 then break end
    end
  end

  return lines
end

return M
