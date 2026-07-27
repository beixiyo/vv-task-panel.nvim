-- vv-task-panel configuration owner

local M = {}

---@class VVTaskPanelConfig
---@field width? integer 面板宽度 @default 44
---@field position? 'left' | 'right' @default 'right'
---@field state VVStateHandle? 面板持久状态容器
---@field mappings VVTreePanelMappings? 主面板快捷键覆盖
---@field render VVTreePanelRenderers? 主面板渲染器覆盖
---@field help false|VVTreePanelHelpOptions? 主面板帮助配置
---@field on_attach? fun(panel:VVTreePanel, buf:integer) 主面板 buffer 创建后的自定义入口
---@field exclude_dirs? string[] 扫描时跳过的目录名
---@field scan_strategy? 'workspace' | 'walk' workspace=仅扫描 workspace 定义的目录；walk=递归遍历
---@field max_depth? integer walk 策略的最大递归深度
---@field exit_guard? boolean 提醒仍在运行的任务并允许取消全局退出命令
---@field term_position? 'bottom' | 'right' | 'float'
---@field term_height? integer
---@field term_width? integer
---@field providers? string[] nil = 启用所有已注册；否则白名单
---@field provider_options? table<string, table> 按 provider 名称传入的配置；自定义 provider 从 config.provider_options[provider.name] 读取
---@field icons? table<string, string>
---@field sign? table

---@class VVTaskPanelResolvedConfig
---@field width integer
---@field position 'left' | 'right'
---@field state VVStateHandle?
---@field mappings VVTreePanelMappings
---@field render VVTreePanelRenderers
---@field help false|VVTreePanelHelpOptions?
---@field on_attach? fun(panel:VVTreePanel, buf:integer)
---@field exclude_dirs string[]
---@field scan_strategy 'workspace' | 'walk'
---@field max_depth integer
---@field exit_guard boolean
---@field term_position 'bottom' | 'right' | 'float'
---@field term_height integer
---@field term_width integer
---@field providers? string[]
---@field provider_options table<string, table>
---@field icons table<string, string>
---@field sign table

---@type VVTaskPanelResolvedConfig
local defaults = {
  width = 44,
  position = 'right',
  state = nil,
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

local current = vim.deepcopy(defaults) ---@type VVTaskPanelResolvedConfig

---@param opts VVTaskPanelConfig?
function M.setup(opts)
  current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
end

---@return VVTaskPanelResolvedConfig
function M.get()
  return vim.deepcopy(current)
end

return M
