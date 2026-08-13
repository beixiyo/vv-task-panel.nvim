-- Go provider：为 Go module 提供常用、安全的预设任务

local Presets = require('vv-task-panel.providers.common.presets')

local M = { name = 'go', priority = 30 }

local definitions = {
  { key = 'build', name = 'Build all', argv = { 'go', 'build', './...' }, default = true },
  { key = 'test', name = 'Test all', argv = { 'go', 'test', './...' }, default = true },
  { key = 'vet', name = 'Vet all', argv = { 'go', 'vet', './...' }, default = true },
  { key = 'fmt', name = 'Format all', argv = { 'go', 'fmt', './...' } },
}

local package_cache = {}

-- 这些变量会参与 go list 的 build.Context 或决定其生效的模块上下文。
-- 不能只记录 GOOS/GOARCH：例如 GOAMD64/GOARM 会改变带架构后缀和
-- build constraint 的文件集合，GOFLAGS 则可能注入 -tags。
local build_context_variables = {
  'GOOS',
  'GOARCH',
  'GO386',
  'GOAMD64',
  'GOARM',
  'GOARM64',
  'GOMIPS',
  'GOMIPS64',
  'GOPPC64',
  'GORISCV64',
  'GOWASM',
  'CGO_ENABLED',
  'GOFLAGS',
  'GOEXPERIMENT',
  'GOFIPS140',
  'GO111MODULE',
  'GOWORK',
  'GOTOOLCHAIN',
}

---@param char string
---@param output string[]
local function append_blank(char, output)
  output[#output + 1] = char == '\n' and '\n' or ' '
end

---@param source string
---@return string
local function strip_non_code(source)
  local output = {}
  local state = 'code'
  local quote = nil
  local index = 1

  while index <= #source do
    local char = source:sub(index, index)
    local next_char = source:sub(index + 1, index + 1)

    if state == 'code' then
      if char == '/' and next_char == '/' then
        append_blank(char, output)
        append_blank(next_char, output)
        state = 'line_comment'
        index = index + 2
      elseif char == '/' and next_char == '*' then
        append_blank(char, output)
        append_blank(next_char, output)
        state = 'block_comment'
        index = index + 2
      elseif char == '"' or char == "'" then
        append_blank(char, output)
        state = 'quoted'
        quote = char
        index = index + 1
      elseif char == '`' then
        append_blank(char, output)
        state = 'raw_string'
        index = index + 1
      else
        output[#output + 1] = char
        index = index + 1
      end
    elseif state == 'line_comment' then
      append_blank(char, output)
      if char == '\n' then state = 'code' end
      index = index + 1
    elseif state == 'block_comment' then
      append_blank(char, output)
      if char == '*' and next_char == '/' then
        append_blank(next_char, output)
        state = 'code'
        index = index + 2
      else
        index = index + 1
      end
    elseif state == 'quoted' then
      append_blank(char, output)
      if char == '\\' then
        if index < #source then
          append_blank(next_char, output)
          index = index + 2
        else
          index = index + 1
        end
      else
        if char == quote then
          state = 'code'
          quote = nil
        end
        index = index + 1
      end
    else
      append_blank(char, output)
      if char == '`' then state = 'code' end
      index = index + 1
    end
  end

  return table.concat(output)
end

---@param source string
---@return boolean
local function has_main_function(source)
  local code = strip_non_code(source)
  -- Go 入口不能有返回类型；要求 `()` 后直接出现函数体，可拒绝 `func main() int {}` 等伪入口。
  return code:match('%f[%a_]func%s+main%s*%(%s*%)%s*{') ~= nil
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

---@param directory string
---@return string
local function package_signature(directory)
  local files = vim.fn.glob(directory .. '/*.go', false, true)
  table.sort(files)

  local parts = { file_signature(directory .. '/go.mod') }
  for _, name in ipairs(build_context_variables) do
    local value = vim.env[name]
    parts[#parts + 1] = name .. '=' .. (value == nil and '<unset>' or value)
  end
  for _, file in ipairs(files) do parts[#parts + 1] = file_signature(file) end
  return table.concat(parts, '|')
end

---@param directory string
---@return table?
local function go_package(directory)
  if vim.fn.executable('go') ~= 1 or type(vim.system) ~= 'function' then return nil end

  local key = vim.fs.normalize(directory)
  local signature = package_signature(directory)
  local cached = package_cache[key]
  if cached and cached.signature == signature then return cached.data end

  local ok, process = pcall(vim.system, {
    'go',
    'list',
    '-mod=readonly',
    '-json',
    '.',
  }, { cwd = directory, text = true })
  if not ok or not process then return nil end

  local waited, result = pcall(function() return process:wait() end)
  if not waited or not result or result.code ~= 0 or type(result.stdout) ~= 'string' then return nil end

  local decoded, data = pcall(vim.json.decode, result.stdout)
  if not decoded or type(data) ~= 'table' then return nil end

  package_cache[key] = { signature = signature, data = data }
  return data
end

---@param directory string
---@param callback fun(data: table?)
---@return fun()?
local function go_package_async(directory, callback)
  if vim.fn.executable('go') ~= 1 or type(vim.system) ~= 'function' then
    callback(nil)
    return nil
  end

  local key = vim.fs.normalize(directory)
  local signature = package_signature(directory)
  local cached = package_cache[key]
  if cached and cached.signature == signature then
    callback(cached.data)
    return nil
  end

  local process
  local cancelled = false
  local completed = false

  local function deliver(data)
    if cancelled or completed then return end
    completed = true
    callback(data)
  end

  local ok, started = pcall(vim.system, {
    'go',
    'list',
    '-mod=readonly',
    '-json',
    '.',
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
    package_cache[key] = { signature = signature, data = data }
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

---@param directory string
---@param file string
---@return string
local function source_path(directory, file)
  if file:match('^/') or file:match('^%a:[/\\]') then return file end
  return directory .. '/' .. file
end

---@param directory string
---@param package table?
---@return boolean
local function has_main_entry_from_package(directory, package)
  if not package or package.Name ~= 'main' then return false end

  -- CompiledGoFiles 已按当前 GOOS、GOARCH 和 build tags 筛选，并排除 *_test.go；
  -- 字段缺失时回退，兼容未暴露该字段的旧 Go 版本。
  local files = package.CompiledGoFiles
  if type(files) ~= 'table' or #files == 0 then
    files = {}
    for _, key in ipairs({ 'GoFiles', 'CgoFiles' }) do
      for _, file in ipairs(package[key] or {}) do files[#files + 1] = file end
    end
  end

  for _, file in ipairs(files) do
    local ok, lines = pcall(vim.fn.readfile, source_path(directory, file))
    if ok and has_main_function(table.concat(lines, '\n')) then return true end
  end

  return false
end

---@param directory string
---@return boolean
local function has_main_entry(directory)
  return has_main_entry_from_package(directory, go_package(directory))
end

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
  local tasks = Presets.build(definitions, options.presets)

  if (not options.presets or options.presets.run ~= false) and has_main_entry(directory) then
    tasks[#tasks + 1] = { name = 'Run main', argv = { 'go', 'run', '.' } }
  end

  return {
    id = path,
    name = vim.fn.fnamemodify(directory, ':t'),
    dir = directory,
    rel_dir = vim.fn.fnamemodify(directory, ':.'),
    badge = 'go',
    tasks = tasks,
  }
end

---@param path string
---@param config VVTaskPanelConfig
---@param callback fun(group: VVTaskPanel.TaskGroup)
---@return fun()?
function M.parse_async(path, config, callback)
  local directory = vim.fn.fnamemodify(path, ':h')
  local options = (config.provider_options and config.provider_options[M.name]) or {}
  local include_run = not options.presets or options.presets.run ~= false

  if not include_run then
    callback({
      id = path,
      name = vim.fn.fnamemodify(directory, ':t'),
      dir = directory,
      rel_dir = vim.fn.fnamemodify(directory, ':.'),
      badge = 'go',
      tasks = Presets.build(definitions, options.presets),
    })
    return nil
  end

  return go_package_async(directory, function(package)
    local tasks = Presets.build(definitions, options.presets)
    if has_main_entry_from_package(directory, package) then
      tasks[#tasks + 1] = { name = 'Run main', argv = { 'go', 'run', '.' } }
    end

    callback({
      id = path,
      name = vim.fn.fnamemodify(directory, ':t'),
      dir = directory,
      rel_dir = vim.fn.fnamemodify(directory, ':.'),
      badge = 'go',
      tasks = tasks,
    })
  end)
end

return M
