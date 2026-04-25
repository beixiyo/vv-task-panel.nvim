-- npm provider：workspace-aware 扫描，按 lockfile 选包管理器
-- 扫描策略（config.scan_strategy）：
--   'workspace' (默认) — 仅扫描 workspace 定义的目录，无 workspace 则只取 root/package.json
--   'walk'              — 递归遍历（受 max_depth 和 exclude_dirs 约束）
local M = { name = 'npm', priority = 50 }

local yaml = require('vv-utils.yaml')

---@param pkg_dir string
---@return 'pnpm' | 'yarn' | 'bun' | 'npm'
local function detect_pm(pkg_dir)
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

--- 展开 workspace glob 模式（如 "packages/*"）为含 package.json 的目录列表
---@param root string
---@param patterns string[]
---@param excludes table<string, boolean> 排除目录名集合
---@return string[] package.json 路径列表
local function expand_globs(root, patterns, excludes)
  local results = {}
  local seen = {}

  for _, pattern in ipairs(patterns) do
    -- 跳过排除规则
    if pattern:sub(1, 1) == '!' then goto continue end

    -- 去掉尾部 /* 或 /**，取基础目录
    local base = pattern:gsub('/[*]+$', '')
    local is_recursive = pattern:match('%*%*')
    local base_dir = root .. '/' .. base

    if not vim.uv.fs_stat(base_dir) then goto continue end

    if is_recursive then
      -- 递归收集所有含 package.json 的子目录
      local function collect(dir)
        local handle = vim.uv.fs_scandir(dir)
        if not handle then return end
        while true do
          local name, typ = vim.uv.fs_scandir_next(handle)
          if not name then break end
          local full = dir .. '/' .. name
          if typ == 'directory' and not excludes[name] and name:sub(1, 1) ~= '.' then
            if vim.uv.fs_stat(full .. '/package.json') and not seen[full] then
              seen[full] = true
              table.insert(results, full .. '/package.json')
            end
            collect(full)
          end
        end
      end
      collect(base_dir)
    else
      -- 单层：枚举 base_dir 下的直接子目录
      local handle = vim.uv.fs_scandir(base_dir)
      if handle then
        while true do
          local name, typ = vim.uv.fs_scandir_next(handle)
          if not name then break end
          if typ == 'directory' then
            local pkg = base_dir .. '/' .. name .. '/package.json'
            if vim.uv.fs_stat(pkg) and not seen[pkg] then
              seen[pkg] = true
              table.insert(results, pkg)
            end
          end
        end
      end
    end

    ::continue::
  end

  return results
end

--- 从 pnpm-workspace.yaml 读取 workspace 模式
---@param root string
---@return string[]|nil
local function read_pnpm_workspaces(root)
  local filepath = root .. '/pnpm-workspace.yaml'
  if not vim.uv.fs_stat(filepath) then
    filepath = root .. '/pnpm-workspace.yml'
    if not vim.uv.fs_stat(filepath) then return nil end
  end
  local data = yaml.parse_file(filepath)
  if data and type(data.packages) == 'table' then
    return data.packages
  end
  return nil
end

--- 从 package.json 读取 workspaces 字段
---@param root string
---@return string[]|nil
local function read_pkg_workspaces(root)
  local filepath = root .. '/package.json'
  if not vim.uv.fs_stat(filepath) then return nil end
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok then return nil end
  local ok_json, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok_json or type(data) ~= 'table' then return nil end
  -- "workspaces": ["packages/*"] 或 "workspaces": { "packages": ["packages/*"] }
  local ws = data.workspaces
  if type(ws) == 'table' then
    if ws[1] then return ws end
    if type(ws.packages) == 'table' then return ws.packages end
  end
  return nil
end

--- workspace 策略：检测 workspace 配置 → 展开 globs → 收集 package.json
---@param root string
---@return string[]
local function detect_workspace(root)
  local results = {}

  -- 1. 检测 workspace 定义
  local patterns = read_pnpm_workspaces(root) or read_pkg_workspaces(root)

  if patterns then
    -- 2. 展开 globs 收集子包
    local cfg = require('vv-task-panel.core').config
    local excludes = {}
    for _, d in ipairs(cfg.exclude_dirs or {}) do excludes[d] = true end
    results = expand_globs(root, patterns, excludes)
  end

  -- 3. root 自身的 package.json（始终包含）
  local root_pkg = root .. '/package.json'
  if vim.uv.fs_stat(root_pkg) then
    table.insert(results, 1, root_pkg)
  end

  return results
end

--- walk 策略：递归遍历（受 max_depth 和 exclude_dirs 约束）
---@param root string
---@param config VVTaskPanelConfig
---@return string[]
local function detect_walk(root, config)
  local excludes = {}
  for _, d in ipairs(config.exclude_dirs or {}) do excludes[d] = true end
  local max_depth = config.max_depth or 8
  local results = {}

  local function walk(dir, depth)
    if depth > max_depth then return end
    local handle = vim.uv.fs_scandir(dir)
    if not handle then return end
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if typ == 'directory' then
        if not excludes[name] and name:sub(1, 1) ~= '.' then
          walk(dir .. '/' .. name, depth + 1)
        end
      elseif name == 'package.json' then
        table.insert(results, dir .. '/' .. name)
      end
    end
  end

  walk(root, 1)
  return results
end

---@param root string
---@param config VVTaskPanelConfig
---@return string[]
function M.detect(root, config)
  local strategy = config.scan_strategy or 'workspace'
  if strategy == 'walk' then
    return detect_walk(root, config)
  end
  return detect_workspace(root)
end

---@param path string
---@return TaskGroup|nil
function M.parse(path)
  local pkg_dir = vim.fn.fnamemodify(path, ':h')
  local rel_dir = vim.fn.fnamemodify(pkg_dir, ':.')
  if rel_dir == '' or rel_dir == '.' then rel_dir = '(root)' end

  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read then return nil end
  local ok_json, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok_json or type(data) ~= 'table' then return nil end
  if type(data.scripts) ~= 'table' then return nil end

  local pm = detect_pm(pkg_dir)

  local names = {}
  for k in pairs(data.scripts) do table.insert(names, k) end
  table.sort(names)

  local tasks = {}
  for _, n in ipairs(names) do
    table.insert(tasks, {
      name = n,
      argv = { pm, 'run', n },
      cmd = data.scripts[n],
    })
  end

  return {
    id = path,
    name = data.name or rel_dir,
    dir = pkg_dir,
    rel_dir = rel_dir,
    badge = pm,
    tasks = tasks,
  }
end

return M
