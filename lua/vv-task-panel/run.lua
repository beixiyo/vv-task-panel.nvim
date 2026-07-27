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
  vim.keymap.set('n', 'q',     close, vim.tbl_extend('force', o, { desc = 'Close task window' }))
  vim.keymap.set('n', '<Esc>', close, vim.tbl_extend('force', o, { desc = 'Close task window' }))
  vim.keymap.set('t', '<C-q>', close, vim.tbl_extend('force', o, { desc = 'Close task window' }))
  -- 终端模式 <Esc><Esc> 回到普通模式(再按 <Esc>/q 即关窗);单个 <Esc> 仍透传给进程
  vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]], vim.tbl_extend('force', o, { desc = 'Leave terminal mode' }))
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
  local cfg = core.get_config()
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

---@param group VVTaskPanel.TaskGroup
---@param task VVTaskPanel.Task
---@param on_update fun()  任务状态变化时的回调，给 UI 用
---@return VVTaskPanel.TaskRecord
function M.run(group, task, on_update)
  -- 跑新实例前,回收同 (group,task) 的已结束旧记录(隐藏 buffer / 局部 autocmd / core.tasks 条目),避免重跑累积泄漏
  -- 回收路径单一:仅 dispose 负责,prune_finished 只筛选待回收项
  for _, stale in ipairs(core.prune_finished(group.id, task.name)) do
    M.dispose(stale)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'

  local id = core.allocate_task_id()
  vim.api.nvim_buf_set_name(buf, string.format('task://%s/%s#%d', group.name, task.name, id))

  ---@type VVTaskPanel.TaskRecord
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
  core.add_task(rec)

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
  -- jobstart 在命令不可执行时会抛 E475(而非返回负值),必须 pcall 兜底,否则 on_exit 永不触发、状态卡死 running
  local ok, job = pcall(vim.fn.jobstart, rec.argv, jopts)
  if not ok or type(job) ~= 'number' or job <= 0 then
    rec.status = 'failed'
    rec.exit_code = -1
    rec.ended_at = vim.uv.now()
    vim.notify(string.format('[vv-task-panel] Failed to start task: %s', rec.cmd), vim.log.levels.ERROR)
    -- job 没起来,关掉刚开的空终端窗口并把焦点还给原窗口,避免停留在空 buffer
    if term_win and vim.api.nvim_win_is_valid(term_win) then
      pcall(vim.api.nvim_win_close, term_win, true)
    end
    if vim.api.nvim_win_is_valid(cur_win) then
      vim.api.nvim_set_current_win(cur_win)
    end
    if on_update then on_update() end
    return rec
  end
  rec.job_id = job

  -- jobstart(term=true) 会重置 buffer 选项,再次强制 hide 避免关窗时被 wipe 导致 job 被杀
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].buflisted = false

  -- 进入任务窗口(或重新显示)时自动把光标打到末尾,新输出就会跟着走;保存 id 以便 dispose 时清理,避免泄漏
  rec._au = vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
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

---@param rec VVTaskPanel.TaskRecord
function M.focus(rec)
  if not rec or not vim.api.nvim_buf_is_valid(rec.buf) then
    vim.notify('[vv-task-panel] Task buffer is no longer valid', vim.log.levels.WARN)
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

---@param rec VVTaskPanel.TaskRecord
function M.stop(rec)
  if rec.job_id and rec.status == 'running' then
    rec._stopping = true
    vim.fn.jobstop(rec.job_id)
  end
end

---@param rec VVTaskPanel.TaskRecord
function M.dispose(rec)
  M.stop(rec)
  -- 清理 buffer 局部 autocmd,否则隐藏 buffer 删除后 autocmd 仍残留累积
  if rec._au then
    pcall(vim.api.nvim_del_autocmd, rec._au)
    rec._au = nil
  end
  core.remove_task(rec.id)
  if vim.api.nvim_buf_is_valid(rec.buf) then
    pcall(vim.api.nvim_buf_delete, rec.buf, { force = true })
  end
end

return M
