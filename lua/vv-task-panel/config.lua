-- vv-task-panel configuration owner

local M = {}

---用户可配置项（已归一化），不含运行时依赖
---@class VVTaskPanelSettings
---@field width integer 面板初始宽度 @default 44
---@field position 'left' | 'right' 面板位置 @default 'right'
---@field mappings VVTreePanelMappings 主面板快捷键覆盖 @default {}
---@field render VVTreePanelRenderers 主面板渲染器覆盖 @default {}
---@field help? false|VVTreePanelHelpOptions 主面板帮助配置；false 禁用，nil 使用内置帮助 @default nil
---@field on_attach? fun(panel:VVTreePanel, buf:integer) 主面板 buffer 创建后的自定义入口 @default nil
---@field exclude_dirs string[] 扫描时跳过的目录名；给出时整体替换默认列表 @default { 'node_modules', '.git', 'dist', 'build', '.next', '.turbo', '.cache', 'coverage', '.nuxt', 'out' }
---@field scan_strategy 'workspace' | 'walk' workspace=仅扫描 workspace 定义的目录；walk=递归遍历 @default 'workspace'
---@field max_depth integer walk 策略的最大递归深度 @default 8
---@field exit_guard boolean 提醒仍在运行的任务并允许取消全局退出命令 @default true
---@field term_position 'bottom' | 'right' | 'float' 任务终端位置 @default 'bottom'
---@field term_height integer bottom 模式的终端高度 @default 15
---@field term_width integer right 模式的终端宽度 @default 80
---@field providers? string[] provider 白名单；nil 启用所有已注册 provider @default nil
---@field provider_options table<string, table> 按 provider 名称传入的配置；自定义 provider 从 config.provider_options[provider.name] 读取 @default {}
---@field highlights VVTaskPanelHighlights 面板高亮配置
---@field icons table<string, string> 面板与 sign 图标，可逐项覆盖
---@field sign table 状态列 sign 的按状态图标、高亮与按键

---@class VVTaskPanelHighlights
---@field accent vim.api.keyset.highlight 快捷键和统计数字的强调色 @default { fg = '#c099ff', bold = true }

---解析后的完整配置：用户配置加运行时派生值
---@class VVTaskPanelConfig: VVTaskPanelSettings
---@field state VVStateHandle 面板持久状态句柄；合并后派生，由 setup 第二参数 deps.state 注入，未给则为 register('vv-task-panel', 'main')

---运行时依赖，不属于用户配置，不进入 `VVTaskPanelOpts`
---@class VVTaskPanelDeps
---@field state? VVStateHandle 面板持久状态句柄，主要用于自定义存储或测试 @default vv-utils.state.register('vv-task-panel', 'main')

-- 输入类型：由 Settings 派生（不含派生值 state），嵌套表各自 partial
---@class (partial) VVTaskPanelHighlightsOpts: VVTaskPanelHighlights

---`setup()` 输入配置，由 `VVTaskPanelSettings` 派生，所有字段可选
---@class (partial) VVTaskPanelOpts: VVTaskPanelSettings
---@field highlights? VVTaskPanelHighlightsOpts

---@type VVTaskPanelSettings
local defaults = {
  width = 44,
  position = 'right',
  mappings = {},
  render = {},
  help = nil,
  on_attach = nil,
  exclude_dirs = {
    'node_modules',
    '.git',
    'dist',
    'build',
    '.next',
    '.turbo',
    '.cache',
    'coverage',
    '.nuxt',
    'out',
  },
  scan_strategy = 'workspace',
  max_depth = 8,
  exit_guard = true,
  term_position = 'bottom',
  term_height = 15,
  term_width = 80,
  providers = nil,
  provider_options = {},
  highlights = {
    accent = { fg = '#c099ff', bold = true },
  },
  icons = {
    pkg_open = '',
    pkg_closed = '',
    package = '󰏖',
    running = '',
    success = '',
    failed = '',
    stopped = '',
    pending = '',
    header = '󰆍',
    arrow = '→',
    run = '',
  },
  sign = {
    idle = { hl = 'VVTaskSignIdle' },
    running = { hl = 'VVTaskSignRunning' },
    success = { hl = 'VVTaskSignSuccess' },
    failed = { hl = 'VVTaskSignFailed' },
    stopped = { hl = 'VVTaskSignStopped' },
    keys = { { 'g<CR>', desc = 'Run script' } },
  },
}

---合并用户配置与默认值，再派生运行时字段
---@param opts? VVTaskPanelOpts
---@param deps? VVTaskPanelDeps
---@return VVTaskPanelConfig
local function resolve(opts, deps)
  local config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {}) --[[@as VVTaskPanelConfig]]

  -- 派生值：合并后再赋值，由第二参数 deps 注入的 state 保持原引用
  config.state = (deps and deps.state) or require('vv-utils.state').register('vv-task-panel', 'main')

  return config
end

-- setup 之前也提供完整配置，与未调用 setup 时直接使用 API 的行为一致
local current = resolve()

---@param opts? VVTaskPanelOpts
---@param deps? VVTaskPanelDeps
function M.setup(opts, deps)
  current = resolve(opts, deps)
end

---@return VVTaskPanelConfig
function M.get()
  return vim.deepcopy(current)
end

return M
