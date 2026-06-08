-- core：Provider 注册表、配置、任务发现与全局状态
local M = {}

---@class VVTaskPanelConfig
---@field width integer 面板宽度 @default 44
---@field position 'left' | 'right' @default 'right'
---@field exclude_dirs string[] 扫描时跳过的目录名 @default { 'node_modules', '.git', 'dist', ... }
---@field scan_strategy 'workspace' | 'walk' workspace=仅扫描 workspace 定义的目录；walk=递归遍历 @default 'workspace'
---@field max_depth integer walk 策略的最大递归深度 @default 8
---@field term_position 'bottom' | 'right' | 'float' @default 'bottom'
---@field term_height integer @default 15
---@field term_width integer @default 80
---@field providers? string[] nil = 启用所有已注册；否则白名单 @default nil
---@field icons table<string, string> @default { pkg_open = '', pkg_closed = '', ... }
---@field sign { idle: VVTaskSignState, running: VVTaskSignState, success: VVTaskSignState, failed: VVTaskSignState, stopped: VVTaskSignState, keys: { [integer]: { [1]: string, desc: string } } } @default { idle = { hl = 'VVTaskSignIdle' }, ..., keys = { { 'gx', desc = 'Run script' } } }

---@class VVTaskSignState
---@field icon? string  覆盖 icons 表中的图标（nil 则复用 icons 同名项）
---@field hl string     高亮组名

local config = {
  width = 44,
  position = 'right',
  exclude_dirs = { 'node_modules', '.git', 'dist', 'build', '.next', '.turbo', '.cache', 'coverage', '.nuxt', 'out' },
  scan_strategy = 'workspace',
  max_depth = 8,
  term_position = 'bottom',
  term_height = 15,
  term_width = 80,
  providers = nil,
  icons = {
    pkg_open   = '',
    pkg_closed = '',
    package    = '󰏖',
    running    = '',
    success    = '',
    failed     = '',
    stopped    = '',
    pending    = '',
    header     = '󰆍',
    arrow      = '→',
    run        = '',
  },
  sign = {
    idle    = { hl = 'VVTaskSignIdle' },
    running = { hl = 'VVTaskSignRunning' },
    success = { hl = 'VVTaskSignSuccess' },
    failed  = { hl = 'VVTaskSignFailed' },
    stopped = { hl = 'VVTaskSignStopped' },
    keys = { { 'gx', desc = 'Run script' } },
  },
}

---@class Task
---@field name string              显示名（如 'dev' / 'build'）
---@field argv string[]            实际 argv（如 { 'pnpm', 'run', 'dev' }）
---@field cmd? string              命令预览字符串（UI 展示，不执行）
---@field cwd? string              覆盖 group.dir（通常省略）
---@field env? table<string,string>
---@field tags? string[]

---@class TaskGroup
---@field id string                唯一 id（通常 = 配置文件绝对路径）
---@field name string              显示名（包名/crate 名/文件名）
---@field dir string               运行 cwd
---@field rel_dir string           相对 workspace 的路径，用于 UI
---@field badge string             徽标，例如 'pnpm' / 'bun' / 'deno'
---@field provider? string         产出该 group 的 provider 名（由 core 回填）
---@field tasks Task[]

---@class Provider
---@field name string
---@field priority? integer
---@field detect fun(root: string, config: VVTaskPanelConfig): string[]
---@field parse fun(path: string, config: VVTaskPanelConfig): TaskGroup|nil

---@type table<string, Provider>
M.providers = {}

---@type TaskGroup[]
M.groups = {}

---@class TaskRecord
---@field id integer
---@field group_id string
---@field group_name string
---@field task_name string
---@field argv string[]
---@field cmd string
---@field cwd string
---@field env? table<string,string>
---@field buf integer
---@field job_id integer|nil
---@field status 'running' | 'success' | 'failed' | 'stopped'
---@field _stopping? boolean   M.stop 调用时置 true,让 on_exit 区分主动停止 vs 进程失败
---@field exit_code? integer
---@field started_at integer epoch ms
---@field ended_at? integer   on_exit 时置位,让 UI 冻结 elapsed
---@field _au? integer        BufWinEnter/WinEnter autocmd id,dispose 时 nvim_del_autocmd 清理

---@type table<integer, TaskRecord>
M.tasks = {}
M._next_task_id = 1

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
end

---注册 provider
---@param p Provider
function M.register_provider(p)
  assert(p and type(p.name) == 'string', 'provider.name 必填')
  assert(type(p.detect) == 'function', 'provider.detect 必填')
  assert(type(p.parse) == 'function', 'provider.parse 必填')
  M.providers[p.name] = p
end

---@param provider_name string
---@return boolean
local function is_enabled(provider_name)
  local enabled = config.providers
  if enabled == nil then return true end
  return vim.tbl_contains(enabled, provider_name)
end

---扫描 workspace，聚合所有启用 provider 的输出
---@param root? string
---@return TaskGroup[]
function M.discover(root)
  root = root or vim.fn.getcwd()
  local groups = {}
  local seen_id = {}

  for name, p in pairs(M.providers) do
    if is_enabled(name) then
      local ok_d, paths = pcall(p.detect, root, config)
      if ok_d and type(paths) == 'table' then
        for _, path in ipairs(paths) do
          local ok_p, g = pcall(p.parse, path, config)
          if ok_p and g and type(g.tasks) == 'table' and #g.tasks > 0 then
            g.provider = name
            g.id = g.id or path
            if not seen_id[g.id] then
              seen_id[g.id] = true
              table.insert(groups, g)
            end
          end
        end
      end
    end
  end

  table.sort(groups, function(a, b)
    if a.rel_dir == '(root)' then return true end
    if b.rel_dir == '(root)' then return false end
    return a.rel_dir < b.rel_dir
  end)
  M.groups = groups
  return groups
end

---查找某 group.task 最近一次任务记录
---@param group_id string
---@param task_name string
---@return TaskRecord|nil
function M.find_recent_task(group_id, task_name)
  local latest
  for _, t in pairs(M.tasks) do
    if t.group_id == group_id and t.task_name == task_name then
      if not latest or t.started_at > latest.started_at then latest = t end
    end
  end
  return latest
end

---挑出同 (group,task) 中【需回收】的已结束旧记录:保留最近一条已结束记录,其余返回给调用方 dispose
---只负责筛选,不动 buffer/autocmd/M.tasks,实际回收交由 run.dispose 单一负责,避免重复回收
---@param group_id string
---@param task_name string
---@return TaskRecord[]  待回收的旧记录(不含保留的那条 / 不含 running 记录)
function M.prune_finished(group_id, task_name)
  -- 先找出同组同任务里最近一条已结束记录,作为「保留」基准
  local keep
  for _, t in pairs(M.tasks) do
    if t.group_id == group_id and t.task_name == task_name and t.status ~= 'running' then
      if not keep or t.started_at > keep.started_at then keep = t end
    end
  end

  -- 其余已结束记录全部回收(running 的不碰)
  local stale = {}
  for _, t in pairs(M.tasks) do
    if t.group_id == group_id and t.task_name == task_name
      and t.status ~= 'running' and t ~= keep then
      stale[#stale + 1] = t
    end
  end
  return stale
end

---按 lockfile 探测包管理器：从 pkg_dir 起逐级向上找锁文件，命中即返回
---探测顺序固定：pnpm-lock.yaml → bun.lockb/bun.lock → yarn.lock → package-lock.json
---@param pkg_dir string
---@return 'pnpm' | 'yarn' | 'bun' | 'npm'
function M.detect_pm(pkg_dir)
  local dir = pkg_dir
  while dir and dir ~= '/' and dir ~= '' do
    if vim.uv.fs_stat(dir .. '/pnpm-lock.yaml') then return 'pnpm' end
    if vim.uv.fs_stat(dir .. '/bun.lockb') or vim.uv.fs_stat(dir .. '/bun.lock') then return 'bun' end
    if vim.uv.fs_stat(dir .. '/yarn.lock') then return 'yarn' end
    if vim.uv.fs_stat(dir .. '/package-lock.json') then return 'npm' end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then break end
    dir = parent
  end
  return 'npm'
end

---获取当前配置（只读副本）
---@return VVTaskPanelConfig
function M.get_config()
  return vim.deepcopy(config)
end

return M
