-- Built-in sign parser definitions

local Json = require('vv-task-panel.sign.json')
local PackageManager = require('vv-task-panel.package_manager')

local M = {}

---@class VVTaskPanelSignParser
---@field filename string
---@field filetypes? table<string, boolean>
---@field parse SignParser

---@param filename string
---@param filetypes table<string, boolean>?
---@param parser SignParser
---@return VVTaskPanelSignParser
function M.descriptor(filename, filetypes, parser)
  return {
    filename = filename,
    filetypes = filetypes,
    parse = parser,
  }
end

---@param section_key string
---@param make_entry fun(name:string, dir:string): table?
---@return SignParser
local function json_section(section_key, make_entry)
  return function(buf)
    local source = table.concat(
      vim.api.nvim_buf_get_lines(buf, 0, -1, false),
      '\n'
    )

    local directory = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':h')
    local entries = {}

    for name, line in pairs(Json.key_lines(source, section_key)) do
      local entry = make_entry(name, directory)
      if entry then
        entry.lnum = line
        entries[#entries + 1] = entry
      end
    end

    table.sort(entries, function(a, b) return a.lnum < b.lnum end)
    return entries
  end
end

---@return table<string, VVTaskPanelSignParser>
function M.builtins()
  local package_json = M.descriptor(
    'package.json',
    { json = true, jsonc = true },
    json_section('scripts', function(name, directory)
      local manager = PackageManager.detect(directory)

      return {
        name = name,
        argv = { manager, 'run', name },
        cwd = directory,
        badge = manager,
      }
    end)
  )

  local deno = json_section('tasks', function(name, directory)
    return {
      name = name,
      argv = { 'deno', 'task', name },
      cwd = directory,
      badge = 'deno',
    }
  end)

  local deno_json = M.descriptor(
    'deno.json',
    { json = true, jsonc = true },
    deno
  )
  local deno_jsonc = M.descriptor('deno.jsonc', { jsonc = true }, deno)

  return {
    [package_json.filename] = package_json,
    [deno_json.filename] = deno_json,
    [deno_jsonc.filename] = deno_jsonc,
  }
end

return M
