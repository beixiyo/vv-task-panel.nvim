-- Floating task-history view and its lifecycle

local core = require('vv-task-panel.core')
local run = require('vv-task-panel.run')

local M = {}
local namespace = vim.api.nvim_create_namespace('vv_task_panel_list')
local view = { buf = nil, win = nil }
local task_lines = {}
local timer
local refresh_panel = function() end

---@param record VVTaskPanel.TaskRecord?
---@return string
local function status_glyph(record)
  local icons = core.get_config().icons
  if not record then return icons.pending end
  return icons[record.status] or icons.failed
end

---@param record VVTaskPanel.TaskRecord?
---@return string
local function status_highlight(record)
  if not record then return 'VVTaskPanelPending' end
  return ({
    running = 'VVTaskPanelRunning',
    success = 'VVTaskPanelSuccess',
    failed = 'VVTaskPanelFailed',
    stopped = 'VVTaskPanelStopped',
  })[record.status] or 'VVTaskPanelFailed'
end

local function stop_timer()
  if not timer then return end
  timer:stop()
  timer:close()
  timer = nil
end

---@return VVTaskPanel.TaskRecord?
local function selected_task()
  if not view.buf then return end
  return (task_lines[view.buf] or {})[vim.fn.line('.')]
end

---@return integer max_display_width, integer line_count
function M.render()
  if not view.buf or not vim.api.nvim_buf_is_valid(view.buf) then return 0, 0 end

  local icons = core.get_config().icons
  local arrow = ' ' .. (icons.arrow or '→') .. ' '
  local rows = {}

  for _, task in pairs(core.tasks()) do rows[#rows + 1] = task end
  table.sort(rows, function(a, b) return a.started_at > b.started_at end)

  local lines = {}
  local marks = {}
  local mapped_lines = {}
  local function add_mark(row, col, end_col, highlight)
    marks[#marks + 1] = {
      row,
      col,
      { end_col = end_col, hl_group = highlight },
    }
  end

  local title_icon = icons.header or ''
  local title = '  ' .. title_icon .. (title_icon ~= '' and '  ' or '') .. 'Tasks'
  lines[#lines + 1] = title

  if title_icon ~= '' then
    add_mark(0, 2, 2 + #title_icon, 'VVTaskPanelHeaderIcon')
  end

  add_mark(0, 2 + #title_icon, #title, 'VVTaskPanelHeader')
  lines[#lines + 1] = ''

  if #rows == 0 then
    local empty = '  (no tasks)'
    lines[#lines + 1] = empty
    add_mark(#lines - 1, 0, #empty, 'VVTaskPanelPending')
  else
    local label_width = 0
    for _, task in ipairs(rows) do
      label_width = math.max(
        label_width,
        vim.fn.strdisplaywidth(task.group_name .. arrow .. task.task_name)
      )
    end

    for _, task in ipairs(rows) do
      local glyph = status_glyph(task)
      local line = '  '
      local icon_start = #line
      line = line .. glyph .. string.rep(' ', math.max(0, 2 - vim.fn.strdisplaywidth(glyph))) .. '  '
      local icon_end = icon_start + #glyph

      local status_start = #line
      line = line .. string.format('%-7s', task.status)
      local status_end = #line
      line = line .. '  '

      local group_start = #line
      line = line .. task.group_name
      local group_end = #line
      local arrow_start = #line
      line = line .. arrow
      local arrow_end = #line
      local task_start = #line
      line = line .. task.task_name
      local task_end = #line

      local current_width = vim.fn.strdisplaywidth(task.group_name .. arrow .. task.task_name)
      line = line .. string.rep(' ', math.max(2, label_width - current_width + 3))

      local end_time = task.status == 'running'
        and vim.uv.now()
        or task.ended_at or vim.uv.now()
      local elapsed_start = #line
      line = line .. ('%ds'):format(math.floor((end_time - task.started_at) / 1000))
      local elapsed_end = #line

      lines[#lines + 1] = line
      local row = #lines - 1
      mapped_lines[#lines] = task
      if glyph ~= '' then add_mark(row, icon_start, icon_end, status_highlight(task)) end

      add_mark(row, status_start, status_end, 'VVTaskPanelStatusText')
      add_mark(row, group_start, group_end, 'VVTaskPanelGroup')
      add_mark(row, arrow_start, arrow_end, 'VVTaskPanelArrow')
      add_mark(row, task_start, task_end, 'VVTaskPanelTask')
      add_mark(row, elapsed_start, elapsed_end, 'VVTaskPanelUptime')
    end
  end

  lines[#lines + 1] = ''
  local footer = '  Open ↵ · Stop d · Remove ⇧D · Restart r · Close q'
  lines[#lines + 1] = footer
  add_mark(#lines - 1, 0, #footer, 'VVTaskPanelFooter')

  vim.bo[view.buf].modifiable = true
  vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
  vim.bo[view.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(view.buf, namespace, 0, -1)
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(view.buf, namespace, mark[1], mark[2], mark[3])
  end
  task_lines[view.buf] = mapped_lines

  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  return max_width, #lines
end

function M.close()
  stop_timer()
  if view.win and vim.api.nvim_win_is_valid(view.win) then
    vim.api.nvim_win_close(view.win, true)
  end
  if view.buf then task_lines[view.buf] = nil end
  view = { buf = nil, win = nil }
end

---@param on_panel_refresh? fun()
function M.open(on_panel_refresh)
  refresh_panel = on_panel_refresh or refresh_panel
  if view.win and vim.api.nvim_win_is_valid(view.win) then
    vim.api.nvim_set_current_win(view.win)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  view.buf = buf
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'vv-task-panel-tasks'

  local width = math.floor(vim.o.columns * 0.5)
  local height = math.floor(vim.o.lines * 0.4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    style = 'minimal',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = 'rounded',
    title = ' Tasks ',
    title_pos = 'center',
  })
  view.win = win
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false

  local uv = assert(vim.uv)
  local handle = assert(uv.new_timer())
  timer = handle
  handle:start(1000, 1000, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    for _, task in pairs(core.tasks()) do
      if task.status == 'running' then
        M.render()
        return
      end
    end
  end))

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      task_lines[buf] = nil
      stop_timer()
      if view.buf == buf then view = { buf = nil, win = nil } end
    end,
  })

  local function map(lhs, callback, description)
    vim.keymap.set('n', lhs, callback, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = description,
    })
  end

  map('<CR>', function()
    local task = selected_task()
    if task then run.focus(task) end
  end, 'open output')

  map('d', function()
    local task = selected_task()
    if task then run.stop(task) end
  end, 'stop')

  map('D', function()
    local task = selected_task()
    if not task then return end
    run.dispose(task)
    M.render()
    refresh_panel()
  end, 'remove')

  map('r', function()
    local record = selected_task()
    if not record then return end

    for _, group in ipairs(core.groups()) do
      if group.id == record.group_id then

        for _, task in ipairs(group.tasks) do
          if task.name == record.task_name then
            run.dispose(record)
            run.run(group, task, function()
              refresh_panel()
              M.render()
            end)
            return
          end
        end
      end
    end
  end, 'restart')

  map('q', M.close, 'close')
  map('<Esc>', M.close, 'close')

  local max_width, line_count = M.render()
  local ui = vim.api.nvim_list_uis()[1]
  local ui_height = ui and ui.height or 40
  local ui_width = ui and ui.width or 80
  local fitted_height = math.max(3, math.min(line_count, ui_height - 4))
  local fitted_width = math.max(40, math.min(max_width + 4, ui_width - 4))

  vim.api.nvim_win_set_config(win, {
    relative = 'editor',
    row = math.floor((ui_height - fitted_height) / 2),
    col = math.floor((ui_width - fitted_width) / 2),
    width = fitted_width,
    height = fitted_height,
  })

  local first_task_line
  for line in pairs(task_lines[buf] or {}) do
    if not first_task_line or line < first_task_line then first_task_line = line end
  end
  vim.api.nvim_win_set_cursor(win, { first_task_line or 3, 0 })
end

return M
