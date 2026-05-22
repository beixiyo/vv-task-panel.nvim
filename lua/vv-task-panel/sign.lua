-- sign: 在配置文件的可运行脚本行放置状态标记（显示在 statuscol sign 槽）
--
-- 标记随任务状态变化：idle → running → success / failed / stopped
-- 图标复用 config.icons，高亮 / 图标均可通过 config.sign 按状态覆盖
local core = require('vv-task-panel.core')
local run_mod = require('vv-task-panel.run')

local M = {}

local ns = vim.api.nvim_create_namespace('vv_task_run')

---@type table<integer, { id: integer, name: string, argv: string[], cwd: string, badge: string }[]>
local buf_tasks = {}

---@alias SignParser fun(buf: integer): { lnum: integer, name: string, argv: string[], cwd: string, badge: string }[]

---@type table<string, SignParser>
local parsers = {}

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
  local s = (core.config.sign or {})[state] or {}
  return {
    icon = s.icon or core.config.icons[icon_keys[state] or 'run'] or '',
    hl = s.hl or 'VVTaskSignIdle',
  }
end

-- ======================= detect_pm =======================

---@param pkg_dir string
---@return 'pnpm' | 'yarn' | 'bun' | 'npm'
local function detect_pm(pkg_dir)
  local dir = pkg_dir
  while dir and dir ~= '/' and dir ~= '' do
    if vim.uv.fs_stat(dir .. '/pnpm-lock.yaml') then return 'pnpm' end
    if vim.uv.fs_stat(dir .. '/bun.lockb') or vim.uv.fs_stat(dir .. '/bun.lock') then return 'bun' end
    if vim.uv.fs_stat(dir .. '/yarn.lock') then return 'yarn' end
    if vim.uv.fs_stat(dir .. '/package-lock.json') then return 'npm' end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then break end
    dir = parent
  end
  return 'npm'
end

-- ======================= JSON section parser =======================

---@param section_key string
---@param make_entry fun(name: string, dir: string): { name: string, argv: string[], cwd: string, badge: string }|nil
---@return SignParser
local function json_section_parser(section_key, make_entry)
  return function(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local in_section = false
    local depth = 0
    local result = {}
    local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':h')

    for i, line in ipairs(lines) do
      if not in_section then
        if line:match('"' .. section_key .. '"') then
          in_section = true
          depth = 0
          for _ in line:gmatch('{') do depth = depth + 1 end
          for _ in line:gmatch('}') do depth = depth - 1 end
        end
      else
        for _ in line:gmatch('{') do depth = depth + 1 end
        for _ in line:gmatch('}') do depth = depth - 1 end
        if depth <= 0 then
          in_section = false
        else
          local name = line:match('"([^"]+)"%s*:')
          if name then
            local entry = make_entry(name, dir)
            if entry then
              entry.lnum = i
              result[#result + 1] = entry
            end
          end
        end
      end
    end

    return result
  end
end

-- ======================= Built-in parsers =======================

parsers['package.json'] = json_section_parser('scripts', function(name, dir)
  local pm = detect_pm(dir)
  return { name = name, argv = { pm, 'run', name }, cwd = dir, badge = pm }
end)

parsers['deno.json'] = json_section_parser('tasks', function(name, dir)
  return { name = name, argv = { 'deno', 'task', name }, cwd = dir, badge = 'deno' }
end)
parsers['deno.jsonc'] = parsers['deno.json']

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
  if not pos then return end

  local style = get_style(resolve_state(buf, entry.name))
  vim.api.nvim_buf_set_extmark(buf, ns, pos[1], 0, {
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

---@type table<integer, boolean>
local buf_keymapped = {}

local function bind_buf_keys(buf)
  if buf_keymapped[buf] then return end
  buf_keymapped[buf] = true

  local keys = (core.config.sign or {}).keys
  if not keys then return end

  for _, k in ipairs(keys) do
    local lhs = k[1]
    if lhs then
      vim.keymap.set('n', lhs, function()
        require('vv-task-panel.sign').run_at_cursor()
      end, { buffer = buf, desc = k.desc or 'Run script' })
    end
  end
end

local function place_signs(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  buf_tasks[buf] = nil

  local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
  local parser = parsers[fname]
  if not parser then return end

  local ok, entries = pcall(parser, buf)
  if not ok or not entries or #entries == 0 then return end

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
  bind_buf_keys(buf)
end

-- ======================= Task lookup & run =======================

---@param buf integer
---@param lnum integer  1-based
local function find_task_at_line(buf, lnum)
  local tasks = buf_tasks[buf]
  if not tasks then return nil end
  for _, entry in ipairs(tasks) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, entry.id, {})
    if pos and pos[1] + 1 == lnum then return entry end
  end
  return nil
end

---@param buf integer
---@param entry { id: integer, name: string, argv: string[], cwd: string, badge: string }
local function run_task(buf, entry)
  local fpath = vim.api.nvim_buf_get_name(buf)
  local rel = vim.fn.fnamemodify(entry.cwd, ':.')

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
  parsers[filename] = parser_fn
end

-- ======================= Setup =======================

function M.setup()
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

  local aug = vim.api.nvim_create_augroup('VVTaskPanelSign', { clear = true })

  local patterns = {}
  for fname in pairs(parsers) do
    patterns[#patterns + 1] = '*/' .. fname
  end

  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'TextChanged' }, {
    group = aug,
    pattern = patterns,
    callback = function(args)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          place_signs(args.buf)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = aug,
    callback = function(args)
      buf_tasks[args.buf] = nil
      buf_keymapped[args.buf] = nil
    end,
  })

  vim.api.nvim_create_user_command('VVTaskRunLine', M.run_at_cursor, {
    desc = 'Run script on current line',
  })

  vim.schedule(function()
    local ok, statuscol = pcall(require, 'vv-statuscol')
    if ok and statuscol.on_click then
      statuscol.on_click(M.handle_click)
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
