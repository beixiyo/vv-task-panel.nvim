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

local metadata_cache = {}

---@param path string
---@return string
local function normalize_path(path)
  if type(path) ~= 'string' or path == '' then return '' end
  return vim.fn.resolve(vim.fn.fnamemodify(vim.fs.normalize(path), ':p'))
end

---@param path string
---@return string
local function file_signature(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then return path .. ':missing' end

  local mtime = stat.mtime
  local mtime_sec = type(mtime) == 'table' and mtime.sec or mtime
  local mtime_nsec = type(mtime) == 'table' and mtime.nsec or nil
  return table.concat({
    path,
    tostring(stat.size or ''),
    tostring(mtime_sec or ''),
    tostring(mtime_nsec or ''),
  }, ':')
end

---@param manifest string
---@return string[]
local function source_paths(manifest)
  local directory = vim.fn.fnamemodify(manifest, ':h')
  local paths = {}
  local seen = {}

  local function add(path)
    if type(path) ~= 'string' or path == '' then return end
    local normalized
    if path:match('^/') or path:match('^%a:[/\\]') then
      normalized = normalize_path(path)
    else
      normalized = normalize_path(directory .. '/' .. path)
    end
    if normalized == '' or seen[normalized] then return end
    seen[normalized] = true
    paths[#paths + 1] = normalized
  end

  add(manifest)
  add(directory .. '/src/main.rs')

  -- Cargo 的默认 bin（包括 src/bin 下的嵌套路径）不会全部出现在
  -- Cargo.toml 中；递归收集 Rust 源文件，避免 metadata 缓存遮住 target
  -- 源的变化。
  local function scan(directory_path)
    local handle = vim.uv.fs_scandir(directory_path)
    if not handle then return end

    while true do
      local name, kind = vim.uv.fs_scandir_next(handle)
      if not name then break end

      local path = directory_path .. '/' .. name
      if kind == 'directory' then
        scan(path)
      elseif kind == 'file' and name:match('%.rs$') then
        add(path)
      end
    end
  end
  scan(directory .. '/src')

  -- [[bin]] / [lib] / [[example]] 等自定义 target 可以把源文件放到
  -- src 之外。这里只读取 manifest 中明确声明的 path，保持签名范围可控，
  -- 同时在文件尚不存在时保留 :missing 哨兵以捕获后续创建。
  local ok, lines = pcall(vim.fn.readfile, manifest)
  if ok then
    for _, line in ipairs(lines) do
      local path = line:match('^%s*path%s*=%s*"([^"]+)"')
        or line:match("^%s*path%s*=%s*'([^']+)'")
      if path then add(path) end
    end
  end

  table.sort(paths)
  return paths
end

---@param manifest string
---@return string
local function metadata_signature(manifest)
  local signatures = {}
  for _, path in ipairs(source_paths(manifest)) do
    signatures[#signatures + 1] = file_signature(path)
  end
  return table.concat(signatures, '|')
end

---@param manifest string
---@return table?
local function cargo_metadata(manifest)
  if vim.fn.executable('cargo') ~= 1 or type(vim.system) ~= 'function' then return nil end

  local key = normalize_path(manifest)
  local signature = metadata_signature(manifest)
  local cached = metadata_cache[key]
  if cached and cached.signature == signature then return cached.data end

  local directory = vim.fn.fnamemodify(manifest, ':h')
  local ok, process = pcall(vim.system, {
    'cargo',
    'metadata',
    '--no-deps',
    '--format-version',
    '1',
    '--manifest-path',
    manifest,
  }, { cwd = directory, text = true })
  if not ok or not process then return nil end

  local waited, result = pcall(function() return process:wait() end)
  if not waited or not result or result.code ~= 0 or type(result.stdout) ~= 'string' then return nil end

  local decoded, data = pcall(vim.json.decode, result.stdout)
  if not decoded or type(data) ~= 'table' then return nil end

  metadata_cache[key] = { signature = signature, data = data }
  return data
end

---@param manifest string
---@param callback fun(data: table?)
---@return fun()?
local function cargo_metadata_async(manifest, callback)
  if vim.fn.executable('cargo') ~= 1 or type(vim.system) ~= 'function' then
    callback(nil)
    return nil
  end

  local key = normalize_path(manifest)
  local signature = metadata_signature(manifest)
  local cached = metadata_cache[key]
  if cached and cached.signature == signature then
    callback(cached.data)
    return nil
  end

  local directory = vim.fn.fnamemodify(manifest, ':h')
  local process
  local cancelled = false
  local completed = false

  local function deliver(data)
    if cancelled or completed then return end
    completed = true
    callback(data)
  end

  local ok, started = pcall(vim.system, {
    'cargo',
    'metadata',
    '--no-deps',
    '--format-version',
    '1',
    '--manifest-path',
    manifest,
  }, { cwd = directory, text = true }, function(result)
    if cancelled or completed then return end

    if not result or result.code ~= 0 or type(result.stdout) ~= 'string' then
      deliver(nil)
      return
    end

    local decoded, data = pcall(vim.json.decode, result.stdout)
    if not decoded or type(data) ~= 'table' then
      deliver(nil)
      return
    end

    if cancelled or completed then return end
    metadata_cache[key] = { signature = signature, data = data }
    deliver(data)
  end)
  if not ok or not started then
    deliver(nil)
    return nil
  end
  process = started

  return function()
    if cancelled or completed then return end
    cancelled = true
    if process and type(process.kill) == 'function' then
      pcall(function() process:kill('sigterm') end)
    end
  end
end

---@param manifest string
---@return table?, table?
local function main_target_from_data(manifest, data)
  if not data or type(data.packages) ~= 'table' then return nil end

  local normalized_manifest = normalize_path(manifest)
  local directory = vim.fn.fnamemodify(manifest, ':h')
  local expected_source = normalize_path(directory .. '/src/main.rs')

  for _, package in ipairs(data.packages) do
    if type(package) == 'table' and normalize_path(package.manifest_path or '') == normalized_manifest then
      local bins = {}
      local source_target

      for _, target in ipairs(package.targets or {}) do
        if type(target) == 'table' and type(target.kind) == 'table'
          and vim.tbl_contains(target.kind, 'bin')
        then
          if type(target.name) == 'string' and target.name ~= '' then
            bins[target.name] = target
          end
          if normalize_path(target.src_path or '') == expected_source then
            source_target = target
          end
        end
      end

      -- cargo run 遵循 package.default_run；优先选择该 target，
      -- 使显式 --bin 与 Cargo 默认目标一致，同时避免多 bin 项目的裸命令歧义。
      local default_run = type(package.default_run) == 'string' and package.default_run or nil
      return (default_run and bins[default_run]) or source_target
    end
  end

  -- virtual workspace 的 manifest 没有自身 package，不能继承成员 binary，
  -- 也不能仅凭 src/main.rs 推断入口。
  return nil
end

---@param target table
---@return string[]
local function required_features(target)
  local values = target['required-features'] or target.required_features
  if type(values) ~= 'table' then return {} end

  local features = {}
  for _, feature in ipairs(values) do
    if type(feature) == 'string' and feature ~= '' then features[#features + 1] = feature end
  end
  return features
end

---@param manifest string
---@param data? table
---@return string[]?
local function run_argv(manifest, data)
  local target = main_target_from_data(manifest, data or cargo_metadata(manifest))
  if not target or type(target.name) ~= 'string' or target.name == '' then return nil end

  local argv = { 'cargo', 'run', '--bin', target.name }
  local features = required_features(target)
  if #features > 0 then
    argv[#argv + 1] = '--features'
    argv[#argv + 1] = table.concat(features, ',')
  end
  return argv
end

---@param path string
---@param config VVTaskPanelConfig
---@param argv string[]?
---@return VVTaskPanel.TaskGroup
local function build_group(path, config, argv)
  local directory = vim.fn.fnamemodify(path, ':h')
  local options = (config.provider_options and config.provider_options[M.name]) or {}
  local tasks = Presets.build(definitions, options.presets)

  if argv then tasks[#tasks + 1] = { name = 'Run main', argv = argv } end

  return {
    id = path,
    name = vim.fn.fnamemodify(directory, ':t'),
    dir = directory,
    rel_dir = vim.fn.fnamemodify(directory, ':.'),
    badge = 'cargo',
    tasks = tasks,
  }
end

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
  local options = (config.provider_options and config.provider_options[M.name]) or {}
  local argv
  if not options.presets or options.presets.run ~= false then argv = run_argv(path) end
  return build_group(path, config, argv)
end

---@param path string
---@param config VVTaskPanelConfig
---@param callback fun(group: VVTaskPanel.TaskGroup)
---@return fun()?
function M.parse_async(path, config, callback)
  local options = (config.provider_options and config.provider_options[M.name]) or {}
  if options.presets and options.presets.run == false then
    callback(build_group(path, config, nil))
    return nil
  end

  return cargo_metadata_async(path, function(data)
    callback(build_group(path, config, data and run_argv(path, data) or nil))
  end)
end

return M
