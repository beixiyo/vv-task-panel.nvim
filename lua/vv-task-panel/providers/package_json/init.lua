-- package.json provider 入口：组合 workspace 发现、通用任务解析与命令构造

local JsonTasks = require('vv-task-panel.providers.common.json_tasks')
local Workspace = require('vv-task-panel.providers.package_json.workspace')

local M = { name = 'package_json', priority = 50 }

M.detect = Workspace.detect

---@param path string
---@param config VVTaskPanelConfig
---@return VVTaskPanel.TaskGroup|nil
function M.parse(path, config)
  local directory = vim.fn.fnamemodify(path, ':h')
  local rel_dir = vim.fn.fnamemodify(directory, ':.')
  if rel_dir == '' or rel_dir == '.' then rel_dir = '(root)' end

  local data, scripts = JsonTasks.parse(path, 'scripts', config, M.name)
  if not data then return nil end

  local manager = require('vv-task-panel.core').detect_pm(directory)
  local tasks = {}

  for _, script in ipairs(scripts) do
    tasks[#tasks + 1] = {
      name = script.name,
      argv = { manager, 'run', script.name },
      cmd = script.command,
    }
  end

  return {
    id = path,
    name = data.name or rel_dir,
    dir = directory,
    rel_dir = rel_dir,
    badge = manager,
    tasks = tasks,
  }
end

return M
