local H = dofile('tests/helpers.lua')
local T, child = H.new_set()

T["扫描首帧、成功失败与取代清帧，关闭后不启动提供者"] = function()
  child.lua_func(function()
    -- 扫描在途时面板的 loading 状态：首帧先于扫描、空状态不误报、各终结路径清除帧

    local root = vim.env.VV_TEST_REPO

    local TaskPanel = require('vv-task-panel')
    local State = require('vv-task-panel.state')
    local core = require('vv-task-panel.core')
    local ui = require('vv-task-panel.ui')

    local provider_name = 'scanning-state-test'
    local callbacks = {}
    local cancelled = 0

    TaskPanel.setup({ providers = { provider_name } })
    TaskPanel.register_provider({
      name = provider_name,
      detect = function() return { '/tmp/scanning-state-test' } end,
      parse = function() error('异步提供者不得使用同步解析路径') end,
      parse_async = function(_, _, callback)
        callbacks[#callbacks + 1] = callback
        return function() cancelled = cancelled + 1 end
      end,
    })

    local function panel_buf()
      local buf = vim.fn.bufnr('vv-tree-panel://vv-task-panel-main')
      return buf > 0 and vim.api.nvim_buf_is_valid(buf) and buf or nil
    end

    ---@return { row: integer, text: string }[]
    local function scanning_marks(buf)
      local found = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
        for _, chunk in ipairs(mark[4].virt_text or {}) do
          if chunk[1]:find('scanning', 1, true) then
            found[#found + 1] = { row = mark[2], text = chunk[1] }
          end
        end
      end
      return found
    end

    local function line(buf, row)
      return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    end

    local function wait_started(count)
      assert(vim.wait(1000, function() return #callbacks == count end), '应在下一轮事件循环启动扫描')
    end

    local function group(id)
      return {
        id = id, name = id, dir = '/tmp', rel_dir = '(root)', badge = 'test',
        tasks = { { name = 'dev', argv = { 'true' } } },
      }
    end

    -- 首次打开：扫描启动前（同步 detect / parse 之前）就已画出扫描态
    State.set_groups({})
    TaskPanel.open()
    local buf = assert(panel_buf(), '面板 buffer 应存在')
    assert(#callbacks == 0, '打开面板时扫描应推迟到首帧之后')
    assert(ui.is_discovering(), '打开面板后应处于扫描态')
    assert(not line(buf, 1):find('0', 1, true), '扫描中 header 不得显示误导性的 0 计数')
    assert(line(buf, 2) == 'Scanning…', '扫描中空状态应显示 Scanning…')
    local marks = scanning_marks(buf)
    assert(#marks == 1 and marks[1].row == 0, '扫描帧应画在 header 第 1 行')

    -- 完成：帧消失、计数与列表回到真实结果
    wait_started(1)
    callbacks[1](group('done'))
    assert(not ui.is_discovering(), '扫描完成后应退出扫描态')
    assert(#scanning_marks(buf) == 0, '扫描完成后帧应清除')
    assert(line(buf, 1):find('1 packages', 1, true), '扫描完成后 header 显示真实计数')

    -- 失败：provider 回 nil，空状态恢复为无任务提示且帧清除
    State.set_groups({})
    TaskPanel.refresh()
    assert(#scanning_marks(buf) == 1, '重扫开始应立即显示帧')
    wait_started(2)
    callbacks[2](nil)
    assert(not ui.is_discovering() and #scanning_marks(buf) == 0, '扫描失败后帧应清除')
    assert(line(buf, 2):find('No tasks discovered', 1, true), '扫描结束后才显示无任务空状态')

    -- 重复 r：旧扫描被取代，始终只有一个帧，旧回调不会提前结束新扫描
    TaskPanel.refresh()
    wait_started(3)
    TaskPanel.refresh()
    assert(cancelled >= 1, '重扫应取消旧扫描')
    assert(#scanning_marks(buf) == 1, '重复重扫不得叠加多个帧')
    wait_started(4)
    callbacks[3](group('stale'))
    assert(ui.is_discovering() and #scanning_marks(buf) == 1, '旧扫描的迟到结果不得清除新扫描的帧')
    callbacks[4](group('latest'))
    assert(not ui.is_discovering() and #scanning_marks(buf) == 0, '最新扫描完成后帧应清除')

    -- discover_async 抛错：扫描态与帧都应清除
    local original_discover = core.discover_async
    core.discover_async = function() error('boom') end
    local original_notify = vim.notify
    local notified
    vim.notify = function(msg) notified = msg end
    TaskPanel.refresh()
    assert(vim.wait(1000, function() return notified ~= nil end), '扫描抛错应通知')
    vim.notify = original_notify
    core.discover_async = original_discover
    assert(not ui.is_discovering() and #scanning_marks(buf) == 0, '扫描抛错后帧应清除')

    -- 关闭面板：在途扫描终止，重新打开前不残留扫描态
    TaskPanel.refresh()
    wait_started(5)
    TaskPanel.close()
    assert(not ui.is_discovering(), '关闭面板应结束扫描态')

    -- 扫描启动前就关闭：不应再启动 provider
    TaskPanel.open()
    TaskPanel.close()
    vim.wait(100)
    assert(#callbacks == 5, '首帧后、扫描启动前关闭面板不得再启动扫描')

    TaskPanel.disable()
  end)
end

return T
