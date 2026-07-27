-- sign: 在配置文件的可运行脚本行放置状态标记（显示在 statuscol sign 槽）
--
-- 标记随任务状态变化：idle → running → success / failed / stopped
-- 图标复用 config.icons，高亮 / 图标均可通过 config.sign 按状态覆盖
local core = require('vv-task-panel.core')
local run_mod = require('vv-task-panel.run')
local Parsers = require('vv-task-panel.sign.parsers')

local M = {}

local ns = vim.api.nvim_create_namespace('vv_task_run')

---@type table<integer, { id: integer, name: string, argv: string[], cwd: string, badge: string }[]>
local buf_tasks = {}

---@type table<string, VVTaskPanelSignParser>
local parsers = Parsers.builtins()
local click_dispose
local augroup
local enabled = false
local generation = 0
local parser_autocmds = {}
local install_parser

-- ======================= State style =======================

local icon_keys = {
  idle    = 'run',
  running = 'running',
  success = 'success',
  failed  = 'failed',
  stopped = 'stopped',
}

---@param state string
---@return { icon: string, hl: string }
local function get_style(state)
  local cfg = core.get_config()
  local s = (cfg.sign or {})[state] or {}
  return {
    icon = s.icon or cfg.icons[icon_keys[state] or 'run'] or '',
    hl = s.hl or 'VVTaskSignIdle',
  }
end

-- ======================= Sign state =======================

---@param buf integer
---@param task_name string
---@return string
local function resolve_state(buf, task_name)
  local fpath = vim.api.nvim_buf_get_name(buf)
  local rec = core.find_recent_task(fpath, task_name)
  if not rec then return 'idle' end
  return rec.status
end

---@param buf integer
---@param entry { id: integer, name: string }
local function update_sign(buf, entry)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, entry.id, {})
  -- id 不存在时该 API 返回空表 {} 而非 nil，需额外判 pos[1]（与 find_task_at_line 一致）
  if not pos or not pos[1] then return end

  local style = get_style(resolve_state(buf, entry.name))
  -- set_extmark 失败不应中断 refresh 调用链，加 pcall 兜底
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, pos[1], 0, {
    id = entry.id,
    sign_text = style.icon,
    sign_hl_group = style.hl,
    priority = 1,
  })
end

local function refresh_buf_signs(buf)
  local tasks = buf_tasks[buf]
  if not tasks then return end
  for _, entry in ipairs(tasks) do
    update_sign(buf, entry)
  end
end

---@param fpath string
local function refresh_signs_for_file(fpath)
  for buf in pairs(buf_tasks) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == fpath then
      refresh_buf_signs(buf)
    end
  end
end

-- ======================= Sign placement =======================

---@type table<integer, { lhs:string, callback:function }[]>
local buf_keymapped = {}

local function clear_buf_keys(buf)
  local keys = buf_keymapped[buf]
  if not keys then return end

  for _, owned in ipairs(keys) do
    local current
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_call(buf, function()
        current = vim.fn.maparg(owned.lhs, 'n', false, true)
      end)
    end
    if current and current.callback == owned.callback then
      pcall(vim.keymap.del, 'n', owned.lhs, { buffer = buf })
    end
  end

  buf_keymapped[buf] = nil
end

local function bind_buf_keys(buf, has_entries)
  clear_buf_keys(buf)
  if not has_entries then return end
  local keys = (core.get_config().sign or {}).keys
  if not keys then return end

  local installed = {}
  for _, k in ipairs(keys) do
    local lhs = k[1]
    if lhs then
      local callback = function()
        require('vv-task-panel.sign').run_at_cursor()
      end
      vim.keymap.set('n', lhs, callback, { buffer = buf, desc = k.desc or 'Run script' })
      installed[#installed + 1] = { lhs = lhs, callback = callback }
    end
  end
  if #installed > 0 then buf_keymapped[buf] = installed end
end

local function place_signs(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  buf_tasks[buf] = nil

  local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
  local parser = parsers[fname]
  if not parser or (parser.filetypes and not parser.filetypes[vim.bo[buf].filetype]) then
    clear_buf_keys(buf)
    return
  end

  local ok, entries = pcall(parser.parse, buf)
  if not ok or not entries or #entries == 0 then
    clear_buf_keys(buf)
    return
  end

  local tasks = {}

  for _, e in ipairs(entries) do
    local style = get_style(resolve_state(buf, e.name))
    local mark_id = vim.api.nvim_buf_set_extmark(buf, ns, e.lnum - 1, 0, {
      sign_text = style.icon,
      sign_hl_group = style.hl,
      priority = 1,
    })
    tasks[#tasks + 1] = {
      id = mark_id,
      name = e.name,
      argv = e.argv,
      cwd = e.cwd,
      badge = e.badge,
    }
  end

  buf_tasks[buf] = tasks
  bind_buf_keys(buf, #tasks > 0)
end

-- ======================= Task lookup & run =======================

---@param buf integer
---@param lnum integer  1-based
local function find_task_at_line(buf, lnum)
  local tasks = buf_tasks[buf]
  if not tasks then return nil end
  for _, entry in ipairs(tasks) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, entry.id, {})
    -- id 失效时该 API 返回空表 {}（truthy）而非 nil，需额外判 pos[1]（与 update_sign 一致），
    -- 否则 nil + 1 抛 "attempt to perform arithmetic on a nil value"
    if pos and pos[1] and pos[1] + 1 == lnum then return entry end
  end
  return nil
end

---@param buf integer
---@param entry { id: integer, name: string, argv: string[], cwd: string, badge: string }
local function run_task(buf, entry)
  local fpath = vim.api.nvim_buf_get_name(buf)
  local rel = vim.fn.fnamemodify(entry.cwd, ':.')

  ---@type VVTaskPanel.TaskRecord?
  local existing = core.find_recent_task(fpath, entry.name)
  if existing and existing.status == 'running' then
    run_mod.focus(existing)
    return
  end

  local group = {
    id = fpath,
    name = rel == '.' and '(root)' or vim.fn.fnamemodify(entry.cwd, ':t'),
    dir = entry.cwd,
    rel_dir = rel,
    badge = entry.badge,
    tasks = {},
  }
  local task = {
    name = entry.name,
    argv = entry.argv,
    cmd = table.concat(entry.argv, ' '),
  }

  local ui = require('vv-task-panel.ui')
  run_mod.run(group, task, function()
    pcall(ui.render_panel)
    pcall(ui.render_tasklist)
    refresh_signs_for_file(fpath)
  end)

  update_sign(buf, entry)
end

-- ======================= Public API =======================

function M.run_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local entry = find_task_at_line(buf, lnum)
  if not entry then
    vim.notify('[vv-task-panel] No runnable script on this line', vim.log.levels.WARN)
    return
  end
  run_task(buf, entry)
end

---@param pos { winid: integer, line: integer }
---@return boolean
function M.handle_click(pos)
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  local entry = find_task_at_line(buf, pos.line)
  if not entry then return false end
  run_task(buf, entry)
  return true
end

function M.register_parser(filename, parser_fn)
  assert(type(filename) == 'string', 'filename must be a string')
  assert(type(parser_fn) == 'function', 'parser must be a function')
  parsers[filename] = Parsers.descriptor(filename, nil, parser_fn)
  if enabled then install_parser(filename, generation) end
end

-- ======================= Setup =======================

function M.disable()
  enabled = false
  generation = generation + 1
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  parser_autocmds = {}
  if click_dispose then
    click_dispose()
    click_dispose = nil
  end
  for buf in pairs(buf_keymapped) do clear_buf_keys(buf) end
  buf_tasks = {}
end

---@param filename string
---@param setup_generation integer
install_parser = function(filename, setup_generation)
  if parser_autocmds[filename] then
    pcall(vim.api.nvim_del_autocmd, parser_autocmds[filename])
  end
  parser_autocmds[filename] = vim.api.nvim_create_autocmd(
    { 'BufReadPost', 'BufEnter', 'BufWritePost', 'TextChanged' },
    {
      group = augroup,
      pattern = '*/' .. vim.fn.escape(filename, [[ *?[{\]]),
      callback = function(args)
        vim.schedule(function()
          if enabled
            and generation == setup_generation
            and vim.api.nvim_buf_is_valid(args.buf)
          then
            place_signs(args.buf)
          end
        end)
      end,
    }
  )
end

function M.setup()
  M.disable()
  enabled = true
  generation = generation + 1
  local setup_generation = generation
  local function hl(name, link)
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, { link = link })
    end
  end

  hl('VVTaskSignIdle',    'DiagnosticInfo')
  hl('VVTaskSignRunning', 'DiagnosticOk')
  hl('VVTaskSignSuccess', 'DiagnosticOk')
  hl('VVTaskSignFailed',  'DiagnosticError')
  hl('VVTaskSignStopped', 'DiagnosticError')

  augroup = vim.api.nvim_create_augroup('VVTaskPanelSign', { clear = true })

  for fname in pairs(parsers) do
    install_parser(fname, setup_generation)
  end

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    callback = function(args)
      buf_tasks[args.buf] = nil
      clear_buf_keys(args.buf)
    end,
  })

  vim.api.nvim_create_user_command('VVTaskPanelRunLine', M.run_at_cursor, {
    desc = 'Run script on current line',
    force = true,
  })

  vim.schedule(function()
    if not enabled or generation ~= setup_generation then return end
    local ok, statuscol = pcall(require, 'vv-statuscol')
    if ok and statuscol.on_click then
      if click_dispose then click_dispose() end
      click_dispose = statuscol.on_click(M.handle_click)
    end
  end)

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
      if parsers[fname] then place_signs(buf) end
    end
  end
end

return M
