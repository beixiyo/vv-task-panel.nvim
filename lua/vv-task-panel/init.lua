-- vv-task-panel：可扩展的任务面板
--
-- 核心概念：
--   Provider  → 扫描某种配置文件,产出 TaskGroup 列表
--   TaskGroup → 一个包/项目,含一组 Task
--   Task      → 可执行的一条命令
--
-- 内置 provider：
--   npm   → 递归扫 package.json,按 lockfile 选 pnpm/yarn/bun/npm
--
-- 自定义示例：
--   require('vv-task-panel').register_provider({
--     name = 'deno',
--     detect = function(root, cfg) return vim.fs.find('deno.json', { path = root, type = 'file', limit = math.huge }) end,
--     parse = function(path, cfg)
--       local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
--       if not ok or type(data.tasks) ~= 'table' then return nil end
--       local dir = vim.fn.fnamemodify(path, ':h')
--       local rel = vim.fn.fnamemodify(dir, ':.')
--       local tasks = {}
--       for name, cmd in pairs(data.tasks) do
--         table.insert(tasks, { name = name, argv = { 'deno', 'task', name }, cmd = cmd })
--       end
--       return { id = path, name = data.name or rel, dir = dir, rel_dir = rel, badge = 'deno', tasks = tasks }
--     end,
--   })

local core = require('vv-task-panel.core')
local ui = require('vv-task-panel.ui')

local M = {}

---@param opts VVTaskPanelConfig|nil
function M.setup(opts)
  core.setup(opts)
  -- 注册内置 provider
  core.register_provider(require('vv-task-panel.providers.npm'))
  ui.setup_commands()
end

M.register_provider = core.register_provider

-- 公开 UI 入口（供 keymap / API 调用）
M.open      = ui.open_panel
M.close     = ui.close_panel
M.toggle    = ui.toggle_panel
M.refresh   = ui.refresh
M.tasks     = ui.open_tasklist

-- 访问内部 state（调试/扩展用）
M._core = core

return M
