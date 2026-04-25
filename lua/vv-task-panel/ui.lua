-- ui：侧边面板 + 任务列表浮窗
local core = require('vv-task-panel.core')
local run = require('vv-task-panel.run')

local M = {}

local ns = vim.api.nvim_create_namespace('task_panel')

---@type { buf: integer|nil, win: integer|nil }
local panel = { buf = nil, win = nil }

---@type { buf: integer|nil, win: integer|nil }
local tasklist = { buf = nil, win = nil }

--- 模块级存储：任务列表行 → TaskRecord 映射（避免 vim.b 序列化丢失引用）
---@type table<integer, table<integer, table>>
local _task_lines = {}

---行与数据映射：{ kind='group' | 'task', group_idx, task_idx? }
---@type table<integer, table>
local line_map = {}

-- ============================================================
-- 高亮
-- ============================================================

local function setup_highlights()
  local set = function(name, opts)
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end
  set('VVTaskPanelHeader',     { link = 'Title' })
  set('VVTaskPanelHeaderIcon', { link = 'Constant' })
  set('VVTaskPanelChevron',    { link = 'Comment' })
  set('VVTaskPanelGroupIcon',  { link = 'MiniIconsOrange' })
  set('VVTaskPanelGroup',      { link = 'Directory' })
  set('VVTaskPanelPath',       { link = 'Comment' })
  set('VVTaskPanelBadge',      { link = 'Special' })
  set('VVTaskPanelBadgeBr',    { link = 'Comment' })
  set('VVTaskPanelTask',       { link = 'Function' })
  set('VVTaskPanelCmd',        { link = 'Comment' })
  set('VVTaskPanelRunning',    { link = 'DiagnosticOk' })
  set('VVTaskPanelSuccess',    { link = 'DiagnosticOk' })
  set('VVTaskPanelFailed',     { link = 'DiagnosticError' })
  set('VVTaskPanelStopped',    { link = 'DiagnosticError' })
  set('VVTaskPanelPending',    { link = 'Comment' })
  set('VVTaskPanelUptime',     { link = 'DiagnosticHint' })
  set('VVTaskPanelArrow',      { link = 'Comment' })
  set('VVTaskPanelStatusText', { link = 'Comment' })
  set('VVTaskPanelFooter',     { link = 'Comment' })
end

local function status_glyph(rec)
  local ic = core.config.icons
  if not rec then return ic.pending end
  if rec.status == 'running' then return ic.running end
  if rec.status == 'success' then return ic.success end
  if rec.status == 'stopped' then return ic.stopped end
  return ic.failed
end

local function status_hl(rec)
  if not rec then return 'VVTaskPanelPending' end
  if rec.status == 'running' then return 'VVTaskPanelRunning' end
  if rec.status == 'success' then return 'VVTaskPanelSuccess' end
  if rec.status == 'stopped' then return 'VVTaskPanelStopped' end
  return 'VVTaskPanelFailed'
end

-- ============================================================
-- 渲染
-- ============================================================

local function render_panel()
  if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then return end

  line_map = {}
  local lines = {}
  local marks = {}
  local ic = core.config.icons
  local groups = core.groups

  -- 头部
  do
    local total_tasks = 0
    for _, g in ipairs(groups) do total_tasks = total_tasks + #g.tasks end
    local title = string.format('%s  Task Panel', ic.header)
    table.insert(lines, title)
    table.insert(marks, { 0, 0, { end_col = #ic.header, hl_group = 'VVTaskPanelHeaderIcon' } })
    table.insert(marks, { 0, #ic.header, { end_col = #title, hl_group = 'VVTaskPanelHeader' } })
    table.insert(marks, { 0, #title, { virt_text = { {
      string.format('  %d grp · %d tasks', #groups, total_tasks), 'Comment',
    } }, virt_text_pos = 'eol' } })
    table.insert(lines, string.rep('─', math.max(10, core.config.width - 2)))
    table.insert(marks, { 1, 0, { end_col = -1, hl_group = 'VVTaskPanelChevron' } })
    table.insert(lines, '')
  end

  for gidx, g in ipairs(groups) do
    local chev = g._open == false and ic.pkg_closed or ic.pkg_open
    local left = string.format('%s %s  %s', chev, ic.package, g.name)
    table.insert(lines, left)
    local li = #lines - 1
    line_map[#lines] = { kind = 'group', group_idx = gidx }

    local c1 = #chev
    local c2 = c1 + 1 + #ic.package
    local c3 = c2 + 2
    table.insert(marks, { li, 0,      { end_col = c1, hl_group = 'VVTaskPanelChevron' } })
    table.insert(marks, { li, c1 + 1, { end_col = c2, hl_group = 'VVTaskPanelGroupIcon' } })
    table.insert(marks, { li, c3,     { end_col = #left, hl_group = 'VVTaskPanelGroup' } })

    table.insert(marks, { li, #left, {
      virt_text = {
        { '  ', 'Normal' },
        { '[', 'VVTaskPanelBadgeBr' },
        { g.badge or g.provider or '?', 'VVTaskPanelBadge' },
        { ']', 'VVTaskPanelBadgeBr' },
        { ' ' .. (g.rel_dir or ''), 'VVTaskPanelPath' },
      },
      virt_text_pos = 'eol',
    } })

    if g._open ~= false then
      for tidx, t in ipairs(g.tasks) do
        local rec = core.find_recent_task(g.id, t.name)
        local glyph = status_glyph(rec)
        local sline = string.format('  %s  %s', glyph, t.name)
        table.insert(lines, sline)
        local sli = #lines - 1
        line_map[#lines] = { kind = 'task', group_idx = gidx, task_idx = tidx }

        local g1 = 2
        local g2 = g1 + #glyph
        local n1 = g2 + 2
        table.insert(marks, { sli, g1, { end_col = g2,     hl_group = status_hl(rec) } })
        table.insert(marks, { sli, n1, { end_col = #sline, hl_group = 'VVTaskPanelTask' } })

        local cmd_preview = t.cmd or table.concat(t.argv, ' ')
        local vt = { { '  ', 'Normal' }, { cmd_preview, 'VVTaskPanelCmd' } }
        if rec and rec.status == 'running' then
          local up = math.floor((vim.uv.now() - rec.started_at) / 1000)
          table.insert(vt, { string.format('  (%ds)', up), 'VVTaskPanelUptime' })
        end
        table.insert(marks, { sli, #sline, { virt_text = vt, virt_text_pos = 'eol' } })
      end
    end
  end

  if #groups == 0 then
    table.insert(lines, '  (no tasks discovered)')
    table.insert(lines, '')
    table.insert(lines, "  按 'r' 重新扫描")
  end

  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(panel.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, panel.buf, ns, m[1], m[2], m[3])
  end
end

M.render_panel = render_panel

-- ============================================================
-- 面板交互
-- ============================================================

local function on_enter()
  local lnum = vim.fn.line('.')
  local info = line_map[lnum]
  if not info then return end
  local g = core.groups[info.group_idx]
  if info.kind == 'group' then
    g._open = not (g._open ~= false)  -- 切换
    render_panel()
    return
  end
  local t = g.tasks[info.task_idx]
  local recent = core.find_recent_task(g.id, t.name)
  if recent and recent.status == 'running' then
    run.focus(recent)
    return
  end
  run.run(g, t, function()
    render_panel()
    if tasklist.buf and vim.api.nvim_buf_is_valid(tasklist.buf) then
      M.render_tasklist()
    end
  end)
end

local function on_tab()
  local lnum = vim.fn.line('.')
  local info = line_map[lnum]
  if not info then return end
  local g = core.groups[info.group_idx]
  g._open = not (g._open ~= false)
  render_panel()
end

local function expand_all(open)
  for _, g in ipairs(core.groups) do g._open = open end
  render_panel()
end

-- ============================================================
-- 面板窗口
-- ============================================================

local function create_panel_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'  -- 面板关闭即销毁,下次重建,避免 E95 同名冲突
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'task-panel'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  local name = 'task-panel://' .. vim.fn.getcwd()
  -- 兜底:若意外已存在同名 buffer,尝试先删
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 and existing ~= buf then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  pcall(vim.api.nvim_buf_set_name, buf, name)

  local map = function(lhs, rhs, desc)
    vim.keymap.set('n', lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = desc })
  end
  map('<CR>',  on_enter,                 'run/toggle')
  map('<Tab>', on_tab,                   'toggle fold')
  map('r',     function() M.refresh() end, 'rescan')
  map('R',     function() expand_all(true) end,  'expand all')
  map('M',     function() expand_all(false) end, 'collapse all')
  map('q',     function() M.close_panel() end, 'close')
  map('<Esc>', function() M.close_panel() end, 'close')
  map('t',     function() M.open_tasklist() end, 'task list')
  map('?',     function() M.show_help() end, 'help')

  return buf
end

function M.open_panel()
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    vim.api.nvim_set_current_win(panel.win)
    return
  end
  core.discover(vim.fn.getcwd())
  panel.buf = create_panel_buf()

  local cmd = core.config.position == 'left' and 'topleft' or 'botright'
  vim.cmd(string.format('%s %dvsplit', cmd, core.config.width))
  panel.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(panel.win, panel.buf)

  vim.wo[panel.win].number = false
  vim.wo[panel.win].relativenumber = false
  vim.wo[panel.win].signcolumn = 'no'
  vim.wo[panel.win].wrap = false
  vim.wo[panel.win].cursorline = true
  vim.wo[panel.win].winfixwidth = true
  vim.wo[panel.win].foldcolumn = '0'
  vim.wo[panel.win].statusline = ' '
  vim.wo[panel.win].winhighlight = 'Normal:NormalFloat,CursorLine:PmenuSel,EndOfBuffer:NonText'

  render_panel()

  if not M._uptime_timer then
    M._uptime_timer = vim.uv.new_timer()
    M._uptime_timer:start(1000, 1000, vim.schedule_wrap(function()
      if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then return end
      for _, t in pairs(core.tasks) do
        if t.status == 'running' then render_panel() return end
      end
    end))
  end
end

function M.close_panel()
  if M._uptime_timer then
    M._uptime_timer:stop()
    M._uptime_timer:close()
    M._uptime_timer = nil
  end
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    vim.api.nvim_win_close(panel.win, true)
  end
  panel.win = nil
  panel.buf = nil  -- bufhidden=wipe 已自动销毁,清掉引用
end

function M.toggle_panel()
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    M.close_panel()
  else
    M.open_panel()
  end
end

function M.refresh()
  core.discover(vim.fn.getcwd())
  render_panel()
  vim.notify(string.format('[vv-task-panel] %d groups rescanned', #core.groups))
end

function M.show_help()
  local lines = {
    '# vv-task-panel',
    '',
    '<CR>    运行 task / 展开组 / 聚焦运行中的任务',
    '<Tab>   折叠/展开当前组',
    'r       重新扫描 workspace',
    'R       展开全部',
    'M       折叠全部',
    't       打开任务列表',
    'q       关闭面板',
    '?       本帮助',
  }
  vim.lsp.util.open_floating_preview(lines, 'markdown', { border = 'rounded', title = ' Help ' })
end

-- ============================================================
-- 任务列表浮窗
-- ============================================================

---@return integer max_display_width
function M.render_tasklist()
  if not tasklist.buf or not vim.api.nvim_buf_is_valid(tasklist.buf) then return 0 end
  local ic = core.config.icons
  local arrow = ' ' .. (ic.arrow or '→') .. ' '

  local rows = {}
  for _, t in pairs(core.tasks) do table.insert(rows, t) end
  table.sort(rows, function(a, b) return a.started_at > b.started_at end)

  local lines, marks = {}, {}
  local task_lines = {}
  local function add_mark(row, col, end_col, hl)
    table.insert(marks, { row, col, { end_col = end_col, hl_group = hl } })
  end

  -- title
  local title_icon = ic.header or ''
  local title_text = 'Tasks'
  local title = '  ' .. title_icon .. (title_icon ~= '' and '  ' or '') .. title_text
  lines[#lines + 1] = title
  if #title_icon > 0 then
    add_mark(0, 2, 2 + #title_icon, 'VVTaskPanelHeaderIcon')
  end
  add_mark(0, 2 + #title_icon, #title, 'VVTaskPanelHeader')
  lines[#lines + 1] = ''

  if #rows == 0 then
    local empty = '  (no tasks)'
    lines[#lines + 1] = empty
    add_mark(#lines - 1, 0, #empty, 'VVTaskPanelPending')
  else
    -- 统一 label 列显示宽度:  "{group}{arrow}{task}"
    local label_dw = 0
    for _, t in ipairs(rows) do
      local w = vim.fn.strdisplaywidth(t.group_name .. arrow .. t.task_name)
      if w > label_dw then label_dw = w end
    end
    -- 统一 status 文本列宽度 ("running" 是最长的 7 字符)
    local status_w = 7

    for _, t in ipairs(rows) do
      local glyph = status_glyph(t)
      local icon_pad = math.max(0, 2 - vim.fn.strdisplaywidth(glyph))
      local line = '  '
      local icon_start = #line
      line = line .. glyph .. string.rep(' ', icon_pad) .. '  '
      local icon_end = icon_start + #glyph

      local status_start = #line
      line = line .. string.format('%-' .. status_w .. 's', t.status)
      local status_end = #line
      line = line .. '  '

      local group_start = #line
      line = line .. t.group_name
      local group_end = #line

      local arrow_start = #line
      line = line .. arrow
      local arrow_end = #line

      local task_start = #line
      line = line .. t.task_name
      local task_end = #line

      local label_cur_dw = vim.fn.strdisplaywidth(t.group_name .. arrow .. t.task_name)
      line = line .. string.rep(' ', math.max(2, label_dw - label_cur_dw + 3))

      local end_ts = (t.status == 'running') and vim.uv.now() or (t.ended_at or vim.uv.now())
      local elapsed = math.floor((end_ts - t.started_at) / 1000)
      local elapsed_s = string.format('%ds', elapsed)
      local elapsed_start = #line
      line = line .. elapsed_s
      local elapsed_end = #line

      lines[#lines + 1] = line
      local lnum = #lines - 1
      task_lines[#lines] = t

      if #glyph > 0 then add_mark(lnum, icon_start, icon_end, status_hl(t)) end
      add_mark(lnum, status_start, status_end, 'VVTaskPanelStatusText')
      add_mark(lnum, group_start, group_end, 'VVTaskPanelGroup')
      add_mark(lnum, arrow_start, arrow_end, 'VVTaskPanelArrow')
      add_mark(lnum, task_start, task_end, 'VVTaskPanelTask')
      add_mark(lnum, elapsed_start, elapsed_end, 'VVTaskPanelUptime')
    end
  end

  lines[#lines + 1] = ''
  local footer = '  <CR> open · d stop · D remove · r restart · q close'
  lines[#lines + 1] = footer
  add_mark(#lines - 1, 0, #footer, 'VVTaskPanelFooter')

  vim.bo[tasklist.buf].modifiable = true
  vim.api.nvim_buf_set_lines(tasklist.buf, 0, -1, false, lines)
  vim.bo[tasklist.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(tasklist.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, tasklist.buf, ns, m[1], m[2], m[3])
  end
  _task_lines[tasklist.buf] = task_lines

  local max_w = 0
  for _, l in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(l)
    if w > max_w then max_w = w end
  end
  return max_w, #lines
end

function M.open_tasklist()
  if tasklist.win and vim.api.nvim_win_is_valid(tasklist.win) then
    vim.api.nvim_set_current_win(tasklist.win)
    return
  end
  tasklist.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[tasklist.buf].bufhidden = 'wipe'
  vim.bo[tasklist.buf].buftype = 'nofile'
  vim.bo[tasklist.buf].filetype = 'task-panel-tasks'

  local w = math.floor(vim.o.columns * 0.5)
  local h = math.floor(vim.o.lines * 0.4)
  tasklist.win = vim.api.nvim_open_win(tasklist.buf, true, {
    relative = 'editor', style = 'minimal', width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    border = 'rounded', title = ' Tasks ', title_pos = 'center',
  })
  vim.wo[tasklist.win].cursorline = true
  vim.wo[tasklist.win].wrap = false

  local buf = tasklist.buf

  -- 1s 定时刷新:仅当存在 running 任务时重渲染,让 elapsed 跟着走
  if not M._tasklist_timer then
    M._tasklist_timer = vim.uv.new_timer()
    M._tasklist_timer:start(1000, 1000, vim.schedule_wrap(function()
      if not tasklist.buf or not vim.api.nvim_buf_is_valid(tasklist.buf) then return end
      for _, t in pairs(core.tasks) do
        if t.status == 'running' then M.render_tasklist() return end
      end
    end))
  end

  -- buffer 被清除时移除模块级引用 + 关闭 timer
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      _task_lines[buf] = nil
      if M._tasklist_timer then
        M._tasklist_timer:stop()
        M._tasklist_timer:close()
        M._tasklist_timer = nil
      end
    end,
  })

  local get = function()
    local lnum = vim.fn.line('.')
    local tl = _task_lines[buf] or {}
    return tl[lnum]
  end
  local map = function(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc })
  end
  map('<CR>', function() local t = get(); if t then run.focus(t) end end, 'open output')
  map('d',    function() local t = get(); if t then run.stop(t) end end, 'stop')
  map('D',    function()
    local t = get(); if not t then return end
    run.dispose(t)
    M.render_tasklist()
    render_panel()
  end, 'remove')
  map('r',    function()
    local t = get(); if not t then return end
    for _, g in ipairs(core.groups) do
      if g.id == t.group_id then
        for _, task in ipairs(g.tasks) do
          if task.name == t.task_name then
            -- 移除旧记录,避免 tasklist 里出现「停止 + 重启」两条
            run.dispose(t)
            run.run(g, task, function()
              render_panel(); M.render_tasklist()
            end)
            return
          end
        end
      end
    end
  end, 'restart')
  local close_tasklist = function()
    if M._tasklist_timer then
      M._tasklist_timer:stop()
      M._tasklist_timer:close()
      M._tasklist_timer = nil
    end
    if tasklist.win and vim.api.nvim_win_is_valid(tasklist.win) then
      vim.api.nvim_win_close(tasklist.win, true)
    end
    tasklist.win = nil
  end
  map('q',     close_tasklist, 'close')
  map('<Esc>', close_tasklist, 'close')

  local max_w, total_lines = M.render_tasklist()
  -- 按内容一次性确定窗口尺寸, 之后不再 resize(避免 elapsed 增长导致窗口漂移)
  local ui = vim.api.nvim_list_uis()[1]
  local height = math.max(3, math.min(total_lines or 10, (ui and ui.height or 40) - 4))
  local width = math.max(40, math.min((max_w or 40) + 4, (ui and ui.width or 80) - 4))
  pcall(vim.api.nvim_win_set_config, tasklist.win, {
    relative = 'editor',
    row = math.floor(((ui and ui.height or 40) - height) / 2),
    col = math.floor(((ui and ui.width or 80) - width) / 2),
    width = width, height = height,
  })

  -- 光标落到首条任务 (title + blank = 2 → first task = 3)
  local tl = _task_lines[tasklist.buf] or {}
  local first_task_line
  for lnum in pairs(tl) do
    if not first_task_line or lnum < first_task_line then first_task_line = lnum end
  end
  pcall(vim.api.nvim_win_set_cursor, tasklist.win, { first_task_line or 3, 0 })
end

-- ============================================================
-- 初始化
-- ============================================================

function M.setup_commands()
  setup_highlights()
  vim.api.nvim_create_user_command('VVTaskPanel',         function() M.toggle_panel() end, {})
  vim.api.nvim_create_user_command('VVTaskPanelOpen',     function() M.open_panel() end, {})
  vim.api.nvim_create_user_command('VVTaskPanelClose',    function() M.close_panel() end, {})
  vim.api.nvim_create_user_command('VVTaskPanelRefresh',  function() M.refresh() end, {})
  vim.api.nvim_create_user_command('VVTaskPanelTasks',    function() M.open_tasklist() end, {})

  -- 退出守卫:nvim 的 ExitPre/QuitPre 都无法真正取消退出,只能在 cmdline 拦截
  -- 通过 cabbrev 把 :q :qa :wqa 等重写成 guarded_exit("q" 等);加 ! 的形式(如 :qa!)仍走原命令,不拦截
  for _, c in ipairs({ 'q', 'qa', 'qall', 'wq', 'wqa', 'wqall', 'x', 'xa', 'xall' }) do
    vim.cmd(string.format(
      [[cnoreabbrev <expr> %s (getcmdtype()==':' && getcmdline()==%q) ? 'lua require("vv-task-panel.ui").guarded_exit(%q)' : %q]],
      c, c, c, c
    ))
  end
end

---@param cmd string 原命令,如 'q' / 'wqa'
function M.guarded_exit(cmd)
  local running = {}
  for _, t in pairs(core.tasks) do
    if t.status == 'running' then
      table.insert(running, string.format('  %s ▸ %s', t.group_name, t.task_name))
    end
  end
  if #running == 0 then
    vim.cmd(cmd)
    return
  end
  local msg = string.format(
    '%d task(s) still running. Quitting will kill them:\n%s\n\nQuit anyway?',
    #running, table.concat(running, '\n')
  )
  local choice = vim.fn.confirm(msg, '&Yes\n&No', 2)
  if choice == 1 then
    -- 用户明确要走,强制退出(!绕过未保存检查等)
    vim.cmd(cmd .. '!')
  end
  -- 选 No 直接 return,啥也不做,nvim 继续活着
end

return M
