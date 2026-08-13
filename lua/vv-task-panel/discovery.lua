-- Provider execution and task-group aggregation

local Async = require('vv-utils.async')
local Config = require('vv-task-panel.config')
local Registry = require('vv-task-panel.registry')
local State = require('vv-task-panel.state')

local M = {}
local async_scope = Async.scope({ cancel_previous = true })

local function is_enabled(name, config)
  if config.providers == nil then return true end
  return vim.tbl_contains(config.providers, name)
end

---@param groups VVTaskPanel.TaskGroup[]
---@param seen_id table<string, boolean>
---@param provider string
---@param path string
---@param group VVTaskPanel.TaskGroup?
local function append_group(groups, seen_id, provider, path, group)
  if type(group) ~= 'table' or type(group.tasks) ~= 'table' or #group.tasks == 0 then return end

  group.provider = provider
  group.id = group.id or path
  if seen_id[group.id] then return end

  seen_id[group.id] = true
  groups[#groups + 1] = group
end

---@param groups VVTaskPanel.TaskGroup[]
local function sort_groups(groups)
  table.sort(groups, function(a, b)
    local a_path = a.rel_dir or ''
    local b_path = b.rel_dir or ''
    local a_root = a_path == '(root)'
    local b_root = b_path == '(root)'
    if a_root ~= b_root then return a_root end
    return a_path < b_path
  end)
  return groups
end

---@param root string
---@param config VVTaskPanelResolvedConfig
---@param is_current? fun(): boolean
---@return { provider: VVTaskPanel.Provider, path: string }[]
local function detected_entries(root, config, is_current)
  local entries = {}

  for _, provider in ipairs(Registry.ordered()) do
    if is_current and not is_current() then break end

    if is_enabled(provider.name, config) then
      local detected, paths = pcall(provider.detect, root, config)
      if detected and type(paths) == 'table' then
        for _, path in ipairs(paths) do
          entries[#entries + 1] = { provider = provider, path = path }
        end
      end
    end
  end

  return entries
end

---@param root? string
---@return VVTaskPanel.TaskGroup[]
function M.discover(root)
  root = root or vim.fn.getcwd()
  local config = Config.get()
  local groups = {}
  local seen_id = {}

  for _, entry in ipairs(detected_entries(root, config)) do
    local parsed, group = pcall(entry.provider.parse, entry.path, config)
    if parsed then append_group(groups, seen_id, entry.provider.name, entry.path, group) end
  end

  sort_groups(groups)
  State.set_groups(groups)
  return groups
end

---@param root? string
---@param on_complete? fun(groups: VVTaskPanel.TaskGroup[])
---@return fun() cancel
function M.discover_async(root, on_complete)
  root = root or vim.fn.getcwd()
  local config = Config.get()
  local groups = {}
  local seen_id = {}
  local request = async_scope:begin({
    key = 'discover',
    mode = 'latest',
    cancel_previous = true,
  })
  local cancel_handles = {}
  local cancellation_requested = false
  local pending = 0
  local scheduling = true

  local function add_cancel_handle(cancel)
    if type(cancel) ~= 'function' then return end

    -- parse_async 允许在返回 producer handle 前同步调用 callback。此时
    -- request 可能已经 finish；已完成的 producer 不应在后续 discovery
    -- 重入时被当作仍在途资源取消。
    if request:reason() == 'finished' then return end

    if cancellation_requested then
      pcall(cancel)
      return
    end
    cancel_handles[#cancel_handles + 1] = cancel
  end

  request:set_cancel(function()
    cancellation_requested = true
    local handles = cancel_handles
    cancel_handles = {}
    for _, cancel in ipairs(handles) do pcall(cancel) end
  end)

  local function finish()
    if pending ~= 0 or scheduling or not request:is_current() then return end

    if request:finish() then
      sort_groups(groups)
      State.set_groups(groups)
      if on_complete then on_complete(groups) end
    end
  end

  local function complete(entry, group)
    if not request:is_current() then return end
    append_group(groups, seen_id, entry.provider.name, entry.path, group)
    pending = pending - 1
    finish()
  end

  local entries = detected_entries(root, config, request.is_current)
  if not request:is_current() then
    -- detect 本身也可能重入 discovery。不要在旧 request 已失效后继续
    -- 准备或启动它的 provider producer。
    scheduling = false
    request:cancel()
    return function() request:cancel() end
  end

  local async_entries = {}

  -- 同步 provider 保留现有 parse 契约；持有阻塞进程的 provider 通过 parse_async 加入下方调度。
  for _, entry in ipairs(entries) do
    if not request:is_current() then break end

    if type(entry.provider.parse_async) == 'function' then
      async_entries[#async_entries + 1] = entry
      pending = pending + 1
    else
      local parsed, group = pcall(entry.provider.parse, entry.path, config)
      if parsed then append_group(groups, seen_id, entry.provider.name, entry.path, group) end
    end
  end

  for _, entry in ipairs(async_entries) do
    if not request:is_current() then break end

    local called = false
    local function callback(group)
      if called then return end
      called = true

      local function deliver()
        complete(entry, group)
      end
      if vim.in_fast_event() then
        vim.schedule(deliver)
      else
        deliver()
      end
    end

    local ok, cancel = pcall(entry.provider.parse_async, entry.path, config, callback)
    if not ok then callback(nil) end
    add_cancel_handle(cancel)
  end

  scheduling = false
  finish()

  return function()
    request:cancel()
  end
end

---@return boolean
function M.cancel_async()
  if async_scope:is_disposed() then return false end
  async_scope:cancel()
  return true
end

return M
