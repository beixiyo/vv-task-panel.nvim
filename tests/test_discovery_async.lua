-- 异步 discovery 的 latest-wins、取消和 provider process 回归
-- Run: nvim --headless -u NONE -l tests/test_discovery_async.lua

local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local Config = require('vv-task-panel.config')
local Discovery = require('vv-task-panel.discovery')
local Registry = require('vv-task-panel.registry')
local State = require('vv-task-panel.state')

local async_callbacks = {}
local cancel_count = 0
local completed = {}
local provider_name = 'async-discovery-test'

Registry.register({
  name = provider_name,
  detect = function() return { '/tmp/async-discovery-test' } end,
  parse = function()
    error('async provider must not use the synchronous parse path')
  end,
  parse_async = function(_, _, callback)
    async_callbacks[#async_callbacks + 1] = callback
    local cancelled = false
    return function()
      if cancelled then return end
      cancelled = true
      cancel_count = cancel_count + 1
    end
  end,
})

Config.setup({ providers = { provider_name } })
local initial = {
  {
    id = 'initial', name = 'initial', dir = '/tmp', rel_dir = '(root)',
    badge = 'test', tasks = { { name = 'idle', argv = { 'true' } } },
  },
}
State.set_groups(initial)

local old_finished = false
local old_cancel = Discovery.discover_async('/tmp', function()
  old_finished = true
end)
assert(type(old_cancel) == 'function', 'async discovery returns a cancellation handle')
assert(#async_callbacks == 1, 'async provider receives the discovery callback')

local new_finished = false
local new_cancel = Discovery.discover_async('/tmp', function(groups)
  new_finished = true
  completed = groups
end)
assert(type(new_cancel) == 'function', 'latest discovery returns a cancellation handle')
assert(cancel_count == 1, 'starting a latest discovery cancels the previous producer')
assert(not old_finished, 'superseded discovery must not publish a completion callback')
assert(vim.deep_equal(State.groups(), initial), 'superseded discovery must not write State')
assert(#async_callbacks == 2, 'latest discovery starts a fresh provider request')

-- Deliver the stale result after the replacement request is already active.
async_callbacks[1]({
  id = 'stale', name = 'stale', dir = '/tmp', rel_dir = '(root)', badge = 'test',
  tasks = { { name = 'stale', argv = { 'true' } } },
})
assert(not old_finished, 'late stale callback must stay suppressed')
assert(vim.deep_equal(State.groups(), initial), 'late stale callback must not write State')

async_callbacks[2]({
  id = 'latest', name = 'latest', dir = '/tmp', rel_dir = '(root)', badge = 'test',
  tasks = { { name = 'latest', argv = { 'true' } } },
})
assert(new_finished, 'current async discovery publishes once')
assert(completed[1].id == 'latest' and State.groups()[1].id == 'latest',
  'current discovery publishes its groups to State')

local fast_event_callback
local fast_event_done = false
local fast_event_api_ok
local fast_event_name = 'fast-event-discovery-test'
Registry.register({
  name = fast_event_name,
  detect = function() return { '/tmp/fast-event-discovery-test' } end,
  parse = function() error('fast-event provider must not use parse') end,
  parse_async = function(_, _, callback)
    fast_event_callback = callback
    return function() end
  end,
})
Config.setup({ providers = { fast_event_name } })
Discovery.discover_async('/tmp', function()
  fast_event_api_ok = pcall(vim.api.nvim_win_is_valid, vim.api.nvim_get_current_win())
  fast_event_done = true
end)
local fast_event_timer = vim.uv.new_timer()
fast_event_timer:start(0, 0, function()
  fast_event_timer:stop()
  fast_event_timer:close()
  fast_event_callback({
    id = fast_event_name,
    name = fast_event_name,
    dir = '/tmp',
    rel_dir = '(root)',
    badge = 'test',
    tasks = { { name = 'fast', argv = { 'true' } } },
  })
end)
assert(vim.wait(1000, function() return fast_event_done end),
  'fast-event provider completion should return to the main event loop')
assert(fast_event_api_ok, 'discovery on_complete should allow non-fast Neovim API calls')

local published_id = State.groups()[1].id
new_cancel()
async_callbacks[2]({
  id = 'too-late', name = 'too-late', dir = '/tmp', rel_dir = '(root)', badge = 'test',
  tasks = { { name = 'too-late', argv = { 'true' } } },
})
assert(State.groups()[1].id == published_id, 'cancelled discovery cannot rewrite State')

-- A producer may synchronously complete before returning its cancellation
-- handle. Re-entering discovery after that completion must not cancel it.
local sync_complete_cancels = 0
local sync_complete_name = 'sync-complete-discovery-test'
Registry.register({
  name = sync_complete_name,
  priority = 100,
  detect = function() return { '/tmp/sync-complete-discovery-test' } end,
  parse = function() error('sync-complete provider must not use parse') end,
  parse_async = function(_, _, callback)
    callback({
      id = sync_complete_name,
      name = sync_complete_name,
      dir = '/tmp',
      rel_dir = '(root)',
      badge = 'test',
      tasks = { { name = 'sync', argv = { 'true' } } },
    })
    return function() sync_complete_cancels = sync_complete_cancels + 1 end
  end,
})
Config.setup({ providers = { sync_complete_name } })
Discovery.discover_async('/tmp', function() end)
Discovery.discover_async('/tmp', function() end)
assert(sync_complete_cancels == 0, 'a completed producer must not be cancelled by a later discovery')

-- Re-entering from an old producer must stop that discovery before its next
-- provider is started. The nested request is allowed to start its own list.
local reentrant_name = 'reentrant-discovery-test'
local reentrant_calls = 0
local reentrant_callbacks = {}
local later_provider_calls = 0
Registry.register({
  name = reentrant_name,
  priority = 200,
  detect = function() return { '/tmp/reentrant-discovery-test' } end,
  parse = function() error('reentrant provider must not use parse') end,
  parse_async = function(_, _, callback)
    reentrant_calls = reentrant_calls + 1
    if reentrant_calls == 1 then
      Discovery.discover_async('/tmp', function() end)
    end
    reentrant_callbacks[#reentrant_callbacks + 1] = callback
    return function() end
  end,
})
Registry.register({
  name = 'later-discovery-test',
  priority = -200,
  detect = function() return { '/tmp/later-discovery-test' } end,
  parse = function() error('later provider must not use parse') end,
  parse_async = function(_, _, callback)
    later_provider_calls = later_provider_calls + 1
    return function() end
  end,
})
Config.setup({ providers = { reentrant_name, 'later-discovery-test' } })
local reentrant_cancel = Discovery.discover_async('/tmp', function() end)
assert(type(reentrant_cancel) == 'function', 'reentrant discovery returns a cancellation handle')
assert(reentrant_calls == 2, 'nested discovery starts the reentrant provider once')
assert(later_provider_calls == 1,
  'the superseded discovery must not start providers after the re-entry point')
reentrant_cancel()

-- The UI owns the discovery lifetime: closing the panel invalidates a pending
-- request before a late provider callback can refresh or publish it.
local TaskPanel = require('vv-task-panel')
local ui_callback_count = #async_callbacks
State.set_groups({
  {
    id = 'ui-before-close', name = 'ui-before-close', dir = '/tmp', rel_dir = '(root)',
    badge = 'test', tasks = { { name = 'idle', argv = { 'true' } } },
  },
})
TaskPanel.setup({ providers = { provider_name } })
TaskPanel.open()
assert(#async_callbacks == ui_callback_count + 1, 'opening the panel starts async discovery')
local ui_callback = async_callbacks[#async_callbacks]
TaskPanel.close()
ui_callback({
  id = 'after-close', name = 'after-close', dir = '/tmp', rel_dir = '(root)', badge = 'test',
  tasks = { { name = 'after-close', argv = { 'true' } } },
})
assert(State.groups()[1].id == 'ui-before-close', 'closed panel suppresses late discovery state')
TaskPanel.disable()

local original_executable = vim.fn.executable
local original_system = vim.system
local processes = {}
vim.fn.executable = function(name)
  if name == 'cargo' or name == 'go' then return 1 end
  return original_executable(name)
end
vim.system = function(command, options, callback)
  assert(type(callback) == 'function', 'async providers must use vim.system callbacks')
  local process = { command = command, cwd = options.cwd, killed = 0 }
  function process:wait()
    error('async provider called process:wait()')
  end
  function process:kill()
    self.killed = self.killed + 1
  end
  process.callback = callback
  processes[#processes + 1] = process
  return process
end

local Cargo = require('vv-task-panel.providers.cargo')
local Go = require('vv-task-panel.providers.go')
local provider_root = vim.fn.tempname()
vim.fn.mkdir(provider_root .. '/src', 'p')
vim.fn.writefile({ '[package]', 'name = "async-fixture"' }, provider_root .. '/Cargo.toml')
vim.fn.writefile({ 'fn main() {}' }, provider_root .. '/src/main.rs')
vim.fn.writefile({ 'module example.com/async-fixture', '', 'go 1.24' }, provider_root .. '/go.mod')
vim.fn.writefile({ 'package main', '', 'func main() {}' }, provider_root .. '/main.go')

Config.setup({})
local cargo_group
local cargo_cancel = Cargo.parse_async(provider_root .. '/Cargo.toml', Config.get(), function(group)
  cargo_group = group
end)
assert(type(cargo_cancel) == 'function', 'Cargo exposes process cancellation for async parsing')
assert(processes[#processes].command[1] == 'cargo', 'Cargo async parser starts cargo metadata')
processes[#processes].callback({
  code = 0,
  stdout = vim.json.encode({
    packages = {
      {
        manifest_path = provider_root .. '/Cargo.toml',
        targets = {
          {
            kind = { 'bin' }, name = 'async-fixture',
            src_path = provider_root .. '/src/main.rs',
          },
        },
      },
    },
  }),
})
assert(cargo_group and cargo_group.tasks[#cargo_group.tasks].name == 'Run main',
  'Cargo async metadata callback builds Run main')
assert(vim.deep_equal(cargo_group.tasks[#cargo_group.tasks].argv,
  { 'cargo', 'run', '--bin', 'async-fixture' }),
  'Cargo async metadata callback selects the binary')

-- A cancelled Cargo process may still deliver its queued vim.system callback.
-- The provider itself must suppress that callback, not rely on discovery.
vim.fn.writefile({ 'fn main() {}', '// invalidate metadata cache' }, provider_root .. '/src/main.rs')
local late_cargo_group
local late_cargo_cancel = Cargo.parse_async(provider_root .. '/Cargo.toml', Config.get(), function(group)
  late_cargo_group = group
end)
local late_cargo_process = processes[#processes]
late_cargo_cancel()
late_cargo_process.callback({ code = 0, stdout = vim.json.encode({ packages = {} }) })
assert(late_cargo_group == nil, 'cancelled Cargo parse suppresses a late callback')

local go_group
local go_cancel = Go.parse_async(provider_root .. '/go.mod', Config.get(), function(group)
  go_group = group
end)
assert(type(go_cancel) == 'function', 'Go exposes process cancellation for async parsing')
assert(processes[#processes].command[1] == 'go', 'Go async parser starts go list')
processes[#processes].callback({
  code = 0,
  stdout = vim.json.encode({ Name = 'main', CompiledGoFiles = { 'main.go' } }),
})
assert(go_group and go_group.tasks[#go_group.tasks].name == 'Run main',
  'Go async list callback builds Run main')

vim.fn.writefile({ 'package main', '', 'func main() {}', '// changed' }, provider_root .. '/main.go')
local late_go_group
local go_cancel_again = Go.parse_async(provider_root .. '/go.mod', Config.get(), function(group)
  late_go_group = group
end)
local cancelled_process = processes[#processes]
go_cancel_again()
go_cancel_again()
assert(cancelled_process.killed == 1, 'async provider cancellation is idempotent and physical')
cancelled_process.callback({
  code = 0,
  stdout = vim.json.encode({ Name = 'main', CompiledGoFiles = { 'main.go' } }),
})
assert(late_go_group == nil, 'cancelled Go parse suppresses a late callback')

vim.fn.executable = original_executable
vim.system = original_system
vim.fn.delete(provider_root, 'rf')
print('vv-task-panel async discovery: PASS')
