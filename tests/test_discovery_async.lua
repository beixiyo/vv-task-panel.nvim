local H = dofile('tests/helpers.lua')
local T, child = H.new_set()

T["异步任务发现 latest-wins、重入、快速事件与进程取消"] = function()
  child.lua_func(function()
    -- 异步 discovery 的 latest-wins、取消和 provider process 回归

    local root = vim.env.VV_TEST_REPO

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
        error('异步提供者不得使用同步解析路径')
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
    assert(type(old_cancel) == 'function', '异步发现返回取消句柄')
    assert(#async_callbacks == 1, '异步提供者收到发现回调')

    local new_finished = false
    local new_cancel = Discovery.discover_async('/tmp', function(groups)
      new_finished = true
      completed = groups
    end)
    assert(type(new_cancel) == 'function', '最新发现返回取消句柄')
    assert(cancel_count == 1, '开始最新发现时会取消之前的生产者')
    assert(not old_finished, '被替代的发现不得发布完成回调')
    assert(vim.deep_equal(State.groups(), initial), '被替代的发现不得写入 State')
    assert(#async_callbacks == 2, '最新发现会发起新的提供者请求')

    -- 在替换请求已激活后再投递过期结果
    async_callbacks[1]({
      id = 'stale', name = 'stale', dir = '/tmp', rel_dir = '(root)', badge = 'test',
      tasks = { { name = 'stale', argv = { 'true' } } },
    })
    assert(not old_finished, '延迟的过期回调必须保持抑制')
    assert(vim.deep_equal(State.groups(), initial), '延迟的过期回调不得写入 State')

    async_callbacks[2]({
      id = 'latest', name = 'latest', dir = '/tmp', rel_dir = '(root)', badge = 'test',
      tasks = { { name = 'latest', argv = { 'true' } } },
    })
    assert(new_finished, '当前异步发现只发布一次')
    assert(completed[1].id == 'latest' and State.groups()[1].id == 'latest',
      '当前发现会将分组发布到 State')

    local fast_event_callback
    local fast_event_done = false
    local fast_event_api_ok
    local fast_event_name = 'fast-event-discovery-test'
    Registry.register({
      name = fast_event_name,
      detect = function() return { '/tmp/fast-event-discovery-test' } end,
      parse = function() error('快速事件提供者不得使用 parse') end,
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
      '快速事件提供者完成后应返回主事件循环')
    assert(fast_event_api_ok, '发现的 on_complete 应允许调用非快速 Neovim API')

    local published_id = State.groups()[1].id
    new_cancel()
    async_callbacks[2]({
      id = 'too-late', name = 'too-late', dir = '/tmp', rel_dir = '(root)', badge = 'test',
      tasks = { { name = 'too-late', argv = { 'true' } } },
    })
    assert(State.groups()[1].id == published_id, '已取消的发现不得改写 State')

    -- 生产者可能在返回取消句柄前同步完成
    -- 完成后重新进入发现不得取消它
    local sync_complete_cancels = 0
    local sync_complete_name = 'sync-complete-discovery-test'
    Registry.register({
      name = sync_complete_name,
      priority = 100,
      detect = function() return { '/tmp/sync-complete-discovery-test' } end,
      parse = function() error('同步完成提供者不得使用 parse') end,
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
    assert(sync_complete_cancels == 0, '已完成的生产者不得被后续发现取消')

    -- 从旧生产者重新进入时，必须在启动下一个提供者前停止该发现
    -- 嵌套请求可以启动自己的提供者列表
    local reentrant_name = 'reentrant-discovery-test'
    local reentrant_calls = 0
    local reentrant_callbacks = {}
    local later_provider_calls = 0
    Registry.register({
      name = reentrant_name,
      priority = 200,
      detect = function() return { '/tmp/reentrant-discovery-test' } end,
      parse = function() error('可重入提供者不得使用 parse') end,
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
      parse = function() error('后续提供者不得使用 parse') end,
      parse_async = function(_, _, callback)
        later_provider_calls = later_provider_calls + 1
        return function() end
      end,
    })
    Config.setup({ providers = { reentrant_name, 'later-discovery-test' } })
    local reentrant_cancel = Discovery.discover_async('/tmp', function() end)
    assert(type(reentrant_cancel) == 'function', '可重入发现返回取消句柄')
    assert(reentrant_calls == 2, '嵌套发现会启动一次可重入提供者')
    assert(later_provider_calls == 1,
      '被替代的发现不得在重新进入点后启动提供者')
    reentrant_cancel()

    -- UI 拥有发现生命周期：关闭面板后，延迟的提供者回调无法刷新或发布待处理请求
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
    -- 面板先画扫描态，再在下一轮事件循环启动 discovery
    assert(vim.wait(1000, function() return #async_callbacks == ui_callback_count + 1 end),
      '打开面板会启动异步发现')
    local ui_callback = async_callbacks[#async_callbacks]
    TaskPanel.close()
    ui_callback({
      id = 'after-close', name = 'after-close', dir = '/tmp', rel_dir = '(root)', badge = 'test',
      tasks = { { name = 'after-close', argv = { 'true' } } },
    })
    assert(State.groups()[1].id == 'ui-before-close', '关闭的面板会抑制延迟发现状态')
    TaskPanel.disable()

    local original_executable = vim.fn.executable
    local original_system = vim.system
    local processes = {}
    vim.fn.executable = function(name)
      if name == 'cargo' or name == 'go' then return 1 end
      return original_executable(name)
    end
    vim.system = function(command, options, callback)
      assert(type(callback) == 'function', '异步提供者必须使用 vim.system 回调')
      local process = { command = command, cwd = options.cwd, killed = 0 }
      function process:wait()
        error('异步提供者调用了 process:wait()')
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
    assert(type(cargo_cancel) == 'function', 'Cargo 为异步解析提供进程取消能力')
    assert(processes[#processes].command[1] == 'cargo', 'Cargo 异步解析器启动 cargo metadata')
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
      'Cargo 异步 metadata 回调构建 Run main')
    assert(vim.deep_equal(cargo_group.tasks[#cargo_group.tasks].argv,
      { 'cargo', 'run', '--bin', 'async-fixture' }),
      'Cargo 异步 metadata 回调选择二进制目标')

    -- 已取消的 Cargo 进程仍可能投递排队的 vim.system 回调
    -- 提供者自身必须抑制该回调，不能依赖发现流程
    vim.fn.writefile({ 'fn main() {}', '// 使元数据缓存失效' }, provider_root .. '/src/main.rs')
    local late_cargo_group
    local late_cargo_cancel = Cargo.parse_async(provider_root .. '/Cargo.toml', Config.get(), function(group)
      late_cargo_group = group
    end)
    local late_cargo_process = processes[#processes]
    late_cargo_cancel()
    late_cargo_process.callback({ code = 0, stdout = vim.json.encode({ packages = {} }) })
    assert(late_cargo_group == nil, '已取消的 Cargo 解析会抑制延迟回调')

    local go_group
    local go_cancel = Go.parse_async(provider_root .. '/go.mod', Config.get(), function(group)
      go_group = group
    end)
    assert(type(go_cancel) == 'function', 'Go 为异步解析提供进程取消能力')
    assert(processes[#processes].command[1] == 'go', 'Go 异步解析器启动 go list')
    processes[#processes].callback({
      code = 0,
      stdout = vim.json.encode({ Name = 'main', CompiledGoFiles = { 'main.go' } }),
    })
    assert(go_group and go_group.tasks[#go_group.tasks].name == 'Run main',
      'Go 异步 list 回调构建 Run main')

    vim.fn.writefile({ 'package main', '', 'func main() {}', '// 已变更' }, provider_root .. '/main.go')
    local late_go_group
    local go_cancel_again = Go.parse_async(provider_root .. '/go.mod', Config.get(), function(group)
      late_go_group = group
    end)
    local cancelled_process = processes[#processes]
    go_cancel_again()
    go_cancel_again()
    assert(cancelled_process.killed == 1, '异步提供者取消操作具备幂等性且会实际终止进程')
    cancelled_process.callback({
      code = 0,
      stdout = vim.json.encode({ Name = 'main', CompiledGoFiles = { 'main.go' } }),
    })
    assert(late_go_group == nil, '已取消的 Go 解析会抑制延迟回调')

    vim.fn.executable = original_executable
    vim.system = original_system
    vim.fn.delete(provider_root, 'rf')
  end)
end

return T
