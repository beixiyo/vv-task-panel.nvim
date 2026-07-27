-- Cargo provider：为 Rust 项目提供常用、安全的预设任务

local Presets = require('vv-task-panel.providers.common.presets')

local M = { name = 'cargo', priority = 30 }

local definitions = {
  { key = 'check', name = 'Check', argv = { 'cargo', 'check' }, default = true },
  { key = 'build', name = 'Build', argv = { 'cargo', 'build' }, default = true },
  { key = 'test', name = 'Test', argv = { 'cargo', 'test' }, default = true },
  { key = 'clippy', name = 'Clippy', argv = { 'cargo', 'clippy' }, default = true },
  { key = 'fmt', name = 'Format', argv = { 'cargo', 'fmt' } },
}

---@param root string
---@return string[]
function M.detect(root)
  local path = root .. '/Cargo.toml'
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
    badge = 'cargo',
    tasks = Presets.build(definitions, options.presets),
  }
end

return M
