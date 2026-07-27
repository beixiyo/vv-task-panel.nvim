-- Deno provider：读取 deno.json 或 deno.jsonc 的 tasks

local JsonTasks = require('vv-task-panel.providers.common.json_tasks')

local M = { name = 'deno', priority = 40 }

---@param root string
---@return string[]
function M.detect(root)
  local json = root .. '/deno.json'
  if vim.uv.fs_stat(json) then return { json } end

  local jsonc = root .. '/deno.jsonc'
  return vim.uv.fs_stat(jsonc) and { jsonc } or {}
end

---@param path string
---@param config VVTaskPanelConfig
---@return VVTaskPanel.TaskGroup?
function M.parse(path, config)
  local data, tasks = JsonTasks.parse(path, 'tasks', config, M.name)
  if not data then return nil end

  local directory = vim.fn.fnamemodify(path, ':h')
  local rel_dir = vim.fn.fnamemodify(directory, ':.')
  if rel_dir == '' or rel_dir == '.' then rel_dir = '(root)' end

  local entries = {}
  for _, task in ipairs(tasks) do
    entries[#entries + 1] = {
      name = task.name,
      argv = { 'deno', 'task', task.name },
      cmd = task.command,
    }
  end

  return {
    id = path,
    name = data.name or rel_dir,
    dir = directory,
    rel_dir = rel_dir,
    badge = 'deno',
    tasks = entries,
  }
end

return M
