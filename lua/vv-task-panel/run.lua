-- run：任务执行、终端窗口、任务聚焦
local core = require('vv-task-panel.core')

local M = {}

---@param buf integer
---@param win integer
local function bind_term_keys(buf, win)
  local o = { buffer = buf, silent = true, nowait = true }
  local close = function()
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set('n', 'q',     close, vim.tbl_extend('force', o, { desc = '关闭任务窗口' }))
  vim.keymap.set('n', '<Esc>', close, vim.tbl_extend('force', o, { desc = '关闭任务窗口' }))
  vim.keymap.set('t', '<C-q>', close, vim.tbl_extend('force', o, { desc = '关闭任务窗口' }))
  -- 终端模式 <Esc><Esc> 回到普通模式(再按 <Esc>/q 即关窗);单个 <Esc> 仍透传给进程
  vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]], vim.tbl_extend('force', o, { desc = '离开终端模式' }))
end

---把光标打到 buffer 末尾,终端接下来的输出会自动跟随
---@param win integer
---@param buf integer
local function scroll_to_end(win, buf)
  if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then return end
  local last = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_win_set_cursor, win, { last, 0 })
end

---@param buf integer
---@param title string
---@return integer win
local function open_term_win(buf, title)
  local cfg = core.config
  local win
  if cfg.term_position == 'bottom' then
    vim.cmd(string.format('botright %dsplit', cfg.term_height))
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  elseif cfg.term_position == 'right' then
    vim.cmd(string.format('botright %dvsplit', cfg.term_width))
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  else
    local w, h = math.floor(vim.o.columns * 0.8), math.floor(vim.o.lines * 0.7)
    win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor', width = w, height = h,
      row = math.floor((vim.o.lines - h) / 2),
      col = math.floor((vim.o.columns - w) / 2),
      border = 'rounded', title = title, title_pos = 'center',
    })
  end
  scroll_to_end(win, buf)
  return win
end

---@param group TaskGroup
---@param task Task
---@param on_update fun()  任务状态变化时的回调，给 UI 用
---@return TaskRecord
function M.run(group, task, on_update)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'

  local id = core._next_task_id
  core._next_task_id = id + 1
  vim.api.nvim_buf_set_name(buf, string.format('task://%s/%s#%d', group.name, task.name, id))

  ---@type TaskRecord
  local rec = {
    id = id,
    group_id = group.id,
    group_name = group.name,
    task_name = task.name,
    argv = task.argv,
    cmd = task.cmd or table.concat(task.argv, ' '),
    cwd = task.cwd or group.dir,
    env = task.env,
    buf = buf,
    status = 'running',
    started_at = vim.uv.now(),
  }
  core.tasks[id] = rec

  local cur_win = vim.api.nvim_get_current_win()
  local term_win = open_term_win(buf, string.format(' %s ▸ %s ', group.name, task.name))
  bind_term_keys(buf, term_win)

  local jopts = {
    cwd = rec.cwd,
    term = true,
    on_exit = function(_, code)
      rec.exit_code = code
      rec.ended_at = vim.uv.now()
      if rec._stopping then
        rec.status = 'stopped'
      else
        rec.status = code == 0 and 'success' or 'failed'
      end
      vim.schedule(function()
        if on_update then on_update() end
      end)
    end,
  }
  if rec.env then jopts.env = rec.env end
  rec.job_id = vim.fn.jobstart(rec.argv, jopts)

  -- jobstart(term=true) 会重置 buffer 选项,再次强制 hide 避免关窗时被 wipe 导致 job 被杀
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].buflisted = false

  -- 进入任务窗口(或重新显示)时自动把光标打到末尾,新输出就会跟着走
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
    buffer = buf,
    callback = function()
      local w = vim.fn.bufwinid(buf)
      if w ~= -1 then scroll_to_end(w, buf) end
    end,
  })

  -- 起跑后立即让当前终端窗口落到末尾
  scroll_to_end(term_win, buf)

  if vim.api.nvim_win_is_valid(cur_win) then
    vim.api.nvim_set_current_win(cur_win)
  end
  if on_update then on_update() end
  return rec
end

---@param rec TaskRecord
function M.focus(rec)
  if not rec or not vim.api.nvim_buf_is_valid(rec.buf) then
    vim.notify('[vv-task-panel] task buffer 已失效', vim.log.levels.WARN)
    return
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == rec.buf then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
  local win = open_term_win(rec.buf, string.format(' %s ▸ %s ', rec.group_name, rec.task_name))
  bind_term_keys(rec.buf, win)
end

---@param rec TaskRecord
function M.stop(rec)
  if rec.job_id and rec.status == 'running' then
    rec._stopping = true
    vim.fn.jobstop(rec.job_id)
  end
end

---@param rec TaskRecord
function M.dispose(rec)
  M.stop(rec)
  core.tasks[rec.id] = nil
  if vim.api.nvim_buf_is_valid(rec.buf) then
    pcall(vim.api.nvim_buf_delete, rec.buf, { force = true })
  end
end

return M
