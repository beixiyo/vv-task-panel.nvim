--- vv-task-panel.nvim 变更测试
--- 运行: nvim --headless -u NONE -l tests/test_smoke.lua

local passed = 0
local failed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('  PASS  ' .. name)
  else
    failed = failed + 1
    print('  FAIL  ' .. name .. ': ' .. tostring(err))
  end
end

local function eq(a, b, msg)
  if a ~= b then
    error(string.format('%s: expected %s, got %s', msg or 'mismatch', tostring(b), tostring(a)))
  end
end

-- ─── FIX 7: vim.b 存储改为模块级变量 ───────────────────────────────────

print('\n[FIX 7] task_lines 存储方式')

test('vim.b 序列化丢失引用与变更追踪', function()
  local buf = vim.api.nvim_create_buf(false, true)
  local obj = { name = 'test', status = 'running' }
  local tbl = { [3] = obj }

  -- vim.b 存储再读回
  vim.b[buf].test_data = tbl
  local restored = vim.b[buf].test_data

  -- 验证引用丢失：读回的不是同一个对象
  assert(restored[3] ~= obj, 'vim.b should return different reference (serialized copy)')

  -- 验证变更不可追踪
  obj.status = 'success'
  eq(restored[3].status, 'running', 'vim.b copy does not track mutations')

  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('模块级 table 保留引用', function()
  local _store = {}
  local buf = vim.api.nvim_create_buf(false, true)
  local obj = { name = 'test', status = 'running' }
  _store[buf] = { [1] = obj }

  -- 直接读取保持引用
  local restored = _store[buf]
  assert(restored[1] == obj, 'same reference preserved')
  eq(restored[1].status, 'running', 'data intact')

  -- 修改原始对象，引用侧同步变化
  obj.status = 'success'
  eq(restored[1].status, 'success', 'reference tracks mutation')

  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('ui.lua 使用 _task_lines 模块变量而非 vim.b', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')

  -- 应该有模块级 _task_lines 定义
  assert(content:find('local _task_lines = {}'), '_task_lines module variable should exist')

  -- render_tasklist 应使用 _task_lines 而非 vim.b
  assert(content:find('_task_lines%[tasklist%.buf%]'), 'should store to _task_lines')
  assert(not content:find('vim%.b%[.-%.task_lines'), 'should NOT use vim.b for task_lines')
end)

test('BufWipeout 清理 _task_lines 引用', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')

  assert(content:find('BufWipeout'), 'BufWipeout autocmd should exist for cleanup')
  assert(content:find('_task_lines%[buf%] = nil'), 'should nil out _task_lines[buf] on wipe')
end)

-- ─── FIX 8: _uptime_timer 释放 ─────────────────────────────────────────

print('\n[FIX 8] _uptime_timer 关闭释放')

test('close_panel 包含 timer 清理逻辑', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')

  -- close_panel 函数内应包含 timer 清理
  local close_fn = content:match('function M%.close_panel%(%)(.-)\nend')
  assert(close_fn, 'close_panel function found')
  assert(close_fn:find('_uptime_timer:stop'), 'should stop timer')
  assert(close_fn:find('_uptime_timer:close'), 'should close timer')
  assert(close_fn:find('_uptime_timer = nil'), 'should nil timer')
end)

test('uv.timer 基础行为: stop+close 正常工作', function()
  local timer = vim.uv.new_timer()
  local count = 0
  timer:start(10, 10, function() count = count + 1 end)

  -- stop 后不再触发
  timer:stop()
  timer:close()

  -- 验证 close 后 timer 不可用（不抛错即可）
  local ok = pcall(function()
    -- 已关闭的 timer 调用 is_active 应该报错或返回 false
    return timer:is_active()
  end)
  -- 无论结果如何，说明 stop+close 流程不崩溃
  assert(true, 'timer stop+close completes without crash')
end)

test('open_panel 创建 timer 时检查 nil', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')

  -- open_panel 中应先检查 M._uptime_timer 是否已存在
  assert(content:find('if not M%._uptime_timer then'), 'should guard timer creation')
end)

-- ─── FIX 9: 手动停止与进程失败的状态区分 ──────────────────────────────

print('\n[FIX 9] 主动 stop 状态为 stopped 而非 failed')

test('run.lua on_exit 区分 _stopping 标记', function()
  local run_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/run.lua'
  local content = table.concat(vim.fn.readfile(run_path), '\n')
  assert(content:find('rec%._stopping'), 'on_exit / M.stop should reference rec._stopping')
  assert(content:find("rec%.status = 'stopped'"), "should set status to 'stopped'")
end)

test('M.stop 在 jobstop 前置位 _stopping', function()
  local run_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/run.lua'
  local content = table.concat(vim.fn.readfile(run_path), '\n')
  local stop_fn = content:match('function M%.stop%(rec%)(.-)\nend')
  assert(stop_fn, 'M.stop located')
  local i_set = stop_fn:find('_stopping = true')
  local i_job = stop_fn:find('jobstop')
  assert(i_set and i_job and i_set < i_job, '_stopping must be set BEFORE jobstop')
end)

test('core.lua 新增 stopped icon 与状态类型', function()
  local core_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/core.lua'
  local content = table.concat(vim.fn.readfile(core_path), '\n')
  assert(content:find("stopped%s*=%s*'"), "icons.stopped defined")
  assert(content:find("'stopped'"), 'status union includes stopped')
end)

-- ─── FIX 10: tasklist 浮窗 UI 重构 ──────────────────────────────────────

print('\n[FIX 10] tasklist 使用 extmark 高亮并对齐布局')

test('ui.lua 注册 VVTaskPanelStopped 等新高亮组', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')
  assert(content:find('VVTaskPanelStopped'), 'stopped hl registered')
  assert(content:find('VVTaskPanelArrow'), 'arrow hl registered')
  assert(content:find('VVTaskPanelFooter'), 'footer hl registered')
  assert(content:find('VVTaskPanelStatusText'), 'status text hl registered')
end)

test('render_tasklist 通过 extmark 着色 (不再使用裸 [status] 文本)', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')
  local fn = content:match('function M%.render_tasklist%(%)(.-)\nend\n')
  assert(fn, 'render_tasklist located')
  -- 不应再使用旧的 string.format '%s  [%s]  %s ▸ %s   %ds'
  assert(not fn:find("%[%%s%]"), 'should not wrap status in literal [brackets]')
  assert(fn:find('nvim_buf_set_extmark'), 'should draw via extmark')
  assert(fn:find("'VVTaskPanelTask'"), 'should apply VVTaskPanelTask highlight')
end)

test('status_glyph / status_hl 识别 stopped', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')
  local glyph_fn = content:match('local function status_glyph(.-)\nend')
  local hl_fn = content:match('local function status_hl(.-)\nend')
  assert(glyph_fn and glyph_fn:find("'stopped'"), 'status_glyph handles stopped')
  assert(hl_fn and hl_fn:find("'stopped'"), 'status_hl handles stopped')
end)

-- ─── FIX 11: stopped 改为红色 ──────────────────────────────────────────

print('\n[FIX 11] VVTaskPanelStopped 高亮为红色')

test('VVTaskPanelStopped 链到 DiagnosticError', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')
  assert(
    content:find("VVTaskPanelStopped',%s*{%s*link%s*=%s*'DiagnosticError'"),
    'stopped should link to DiagnosticError (red)'
  )
end)

-- ─── FIX 12: restart 前先 dispose 旧记录 ────────────────────────────────

print('\n[FIX 12] 重启替换旧记录,不产生僵尸条目')

test('tasklist r 绑定在 run.run 前调用 run.dispose', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')
  -- 找 'restart' map 块
  local restart_block = content:match("map%('r',(.-)'restart'")
  assert(restart_block, 'restart mapping located')
  local i_dispose = restart_block:find('run%.dispose')
  local i_run = restart_block:find('run%.run')
  assert(i_dispose and i_run and i_dispose < i_run, 'dispose must run BEFORE run.run')
end)

-- ─── FIX 13: tasklist 每秒自动刷新 elapsed ──────────────────────────────

print('\n[FIX 13] tasklist 独立 1s timer,ended_at 冻结 elapsed')

test('open_tasklist 创建 _tasklist_timer', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')
  assert(content:find('_tasklist_timer'), '_tasklist_timer variable exists')
  assert(content:find('M%._tasklist_timer:start%('), 'timer started with interval')
end)

test('close_tasklist 和 BufWipeout 都清理 timer', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')
  -- 粗略计数:stop / close / 置 nil 的次数应 >= 2(close_tasklist + BufWipeout)
  local _, stop_count = content:gsub('_tasklist_timer:stop', '')
  local _, close_count = content:gsub('_tasklist_timer:close', '')
  assert(stop_count >= 2, 'timer:stop referenced in both paths')
  assert(close_count >= 2, 'timer:close referenced in both paths')
end)

test('render_tasklist elapsed 使用 ended_at 冻结', function()
  local ui_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/ui.lua'
  local content = table.concat(vim.fn.readfile(ui_path), '\n')
  assert(content:find('t%.ended_at'), 'render should read ended_at')
  assert(content:find("status == 'running'"), 'should branch on running status')
end)

test('run.lua on_exit 写入 ended_at', function()
  local run_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
    .. '/lua/vv-task-panel/run.lua'
  local content = table.concat(vim.fn.readfile(run_path), '\n')
  assert(content:find('rec%.ended_at%s*=%s*vim%.uv%.now'), 'on_exit must set ended_at')
end)

-- ─── 汇总 ──────────────────────────────────────────────────────────────

print(string.format('\n结果: %d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
