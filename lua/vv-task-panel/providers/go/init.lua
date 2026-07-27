-- Go provider：为 Go module 提供常用、安全的预设任务

local Presets = require('vv-task-panel.providers.common.presets')

local M = { name = 'go', priority = 30 }

local definitions = {
  { key = 'build', name = 'Build all', argv = { 'go', 'build', './...' }, default = true },
  { key = 'test', name = 'Test all', argv = { 'go', 'test', './...' }, default = true },
  { key = 'vet', name = 'Vet all', argv = { 'go', 'vet', './...' }, default = true },
  { key = 'fmt', name = 'Format all', argv = { 'go', 'fmt', './...' } },
}

---@param root string
---@return string[]
function M.detect(root)
  local path = root .. '/go.mod'
  return vim.uv.fs_stat(path) and { path } or {}
end

---@param path string
---@param config VVTaskPanelConfig
---@return VVTaskPanel.TaskGroup
function M.parse(path, config)
  local directory = vim.fn.fnamemodify(path, ':h')
  local options = (config.provider_options and config.provider_options[M.name]) or {}

  return {
    id = path,
    name = vim.fn.fnamemodify(directory, ':t'),
    dir = directory,
    rel_dir = vim.fn.fnamemodify(directory, ':.'),
    badge = 'go',
    tasks = Presets.build(definitions, options.presets),
  }
end

return M
