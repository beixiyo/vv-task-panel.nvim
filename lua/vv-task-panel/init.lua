-- vv-task-panel：可扩展的任务面板
--
-- 核心概念：
--   Provider  → 扫描某种配置文件,产出 TaskGroup 列表
--   TaskGroup → 一个包/项目,含一组 Task
--   Task      → 可执行的一条命令
--
-- 内置 provider：
--   package_json → 扫描 package.json，按 lockfile 选 pnpm/yarn/bun/npm
--   deno         → 读取 deno.json / deno.jsonc 的 tasks
--
require('vv-task-panel.types')

local core = require('vv-task-panel.core')
local exit_guard = require('vv-task-panel.exit_guard')
local ui = require('vv-task-panel.ui')
local sign = require('vv-task-panel.sign')

local M = {}

---@param opts VVTaskPanelConfig|nil
function M.setup(opts)
  sign.disable()
  exit_guard.disable()
  ui.disable()
  core.setup(opts)
  core.register_provider(require('vv-task-panel.providers.package_json'))
  core.register_provider(require('vv-task-panel.providers.deno'))
  ui.setup_commands()
  sign.setup()
  if core.get_config().exit_guard then exit_guard.setup() end
end

M.register_provider = core.register_provider
M.register_sign_parser = sign.register_parser

M.open      = ui.open_panel
M.close     = ui.close_panel
M.toggle    = ui.toggle_panel
M.refresh   = ui.refresh
M.tasks     = ui.open_tasklist
M.run_at_cursor = sign.run_at_cursor
function M.disable()
  sign.disable()
  exit_guard.disable()
  ui.disable()
end

M._core = core

return M
