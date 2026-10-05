-- Main tree-panel composition and public UI lifecycle

local core = require('vv-task-panel.core')
local run = require('vv-task-panel.run')
local Highlights = require('vv-task-panel.ui.highlights')
local PanelModel = require('vv-task-panel.panel.model')
local PanelRender = require('vv-task-panel.panel.render')
local TaskList = require('vv-task-panel.ui.task_list')
local TreePanel = require('vv-utils.tree_panel')
local Loading = require('vv-utils.loading')

local M = {}
local active_panel ---@type VVTreePanel?
local uptime_timer
local discovery_cancel
local discovery_id = 0
local discovering = false
local scanning_mark ---@type vv-utils.loading.Handle?

local function stop_uptime_timer()
  if not uptime_timer then return end
  uptime_timer:stop()
  uptime_timer:close()
  uptime_timer = nil
end

local function stop_scanning_mark()
  if not scanning_mark then return end
  scanning_mark:stop()
  scanning_mark = nil
end

--- 扫描帧画在 header 第 1 行行尾；面板 buffer wipe 时 handle 自行停止
---@param panel VVTreePanel
local function start_scanning_mark(panel)
  stop_scanning_mark()
  if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then return end
  scanning_mark = Loading.mark({
    buf = panel.buf,
    get_pos = function() return { row = 1 } end,
    pos = 'eol',
    label = 'scanning',
  })
end

local function finish_discovery()
  discovering = false
  discovery_cancel = nil
  stop_scanning_mark()
end

local function stop_discovery()
  discovery_id = discovery_id + 1
  if discovery_cancel then
    discovery_cancel()
    discovery_cancel = nil
  end
  finish_discovery()
  core.cancel_discover()
end

---@param panel VVTreePanel?
---@param notify boolean
local function start_discovery(panel, notify)
  stop_discovery()
  discovery_id = discovery_id + 1
  local current_id = discovery_id
  discovering = true

  local function is_live(target)
    return target and active_panel == target and target:is_open()
  end

  -- detect / parse 在 discover_async 内同步执行：先把扫描态画出来，再让出事件循环启动扫描
  if is_live(panel) then
    panel:refresh()
    start_scanning_mark(panel)
    vim.cmd.redraw()
  end

  vim.schedule(function()
    if current_id ~= discovery_id then return end
    local completed = false

    local function on_complete(groups)
      completed = true
      if current_id ~= discovery_id then return end

      finish_discovery()
      if panel and not is_live(panel) then return end
      if panel then panel:refresh() end
      if notify then
        vim.notify(('[vv-task-panel] %d groups rescanned'):format(#groups))
      end
    end

    local ok, cancel = pcall(core.discover_async, vim.fn.getcwd(), on_complete)
    if current_id ~= discovery_id then return end
    if not ok then
      finish_discovery()
      if is_live(panel) then panel:refresh() end
      vim.notify('[vv-task-panel] discovery failed: ' .. tostring(cancel), vim.log.levels.ERROR)
      return
    end
    if not completed then discovery_cancel = cancel end
  end)
end

local function render_panel()
  if active_panel and active_panel:is_open() then active_panel:refresh() end
end

M.render_panel = render_panel
M.render_tasklist = TaskList.render

--- 是否有任务扫描在途（打开面板 / 重扫后到完成、失败或取消前）
---@return boolean
function M.is_discovering()
  return discovering
end

---@param node VVTreePanelNode
local function activate_task(node)
  local data = node.data
  if not data or data.kind ~= 'task' then return end

  local group = data.group
  local task = data.task
  local recent = core.find_recent_task(group.id, task.name)
  if recent and recent.status == 'running' then
    run.focus(recent)
    return
  end

  run.run(group, task, function()
    render_panel()
    TaskList.render()
  end)
end

local function create_panel()
  local config = core.get_config()
  local render = vim.tbl_extend(
    'force',
    PanelRender.create(core, { is_discovering = M.is_discovering }),
    config.render
  )
  local state = config.state
    or require('vv-utils.state').register('vv-task-panel', 'main')

  return TreePanel.new({
    id = 'vv-task-panel-main',
    title = 'Task Panel',
    filetype = 'vv-task-panel',
    width = config.width,
    position = config.position,
    state = state,

    source = function()
      return PanelModel.nodes(core.groups())
    end,
    render = render,
    open = activate_task,
    jump = activate_task,

    on_refresh = function(context)
      start_discovery(context.panel, true)
    end,
    on_attach = function(panel, buf)
      local mappings = vim.tbl_extend('force', {
        R = 'expand_all',
        M = 'collapse_all',
        t = {
          callback = function() M.open_tasklist() end,
          desc = 'task list',
        },
        ['?'] = 'help',
      }, config.mappings)
      TreePanel.apply_default_mappings(panel, mappings)
      if config.on_attach then config.on_attach(panel, buf) end
    end,

    help = config.help == nil and {
      title = 'vv-task-panel keymaps',
      filetype = 'vv-task-panel-help',
    } or config.help,
    on_close = function()
      stop_discovery()
      stop_uptime_timer()
    end,
  })
end

local function start_uptime_timer()
  if uptime_timer then return end

  local uv = assert(vim.uv)
  local handle = assert(uv.new_timer())

  uptime_timer = handle

  handle:start(1000, 1000, vim.schedule_wrap(function()
    if not active_panel or not active_panel:is_open() then return end

    for _, task in pairs(core.tasks()) do
      if task.status == 'running' then
        active_panel:refresh()
        return
      end
    end
  end))
end

function M.open_panel()
  if active_panel and active_panel:is_open() then
    active_panel:open()
    return
  end

  active_panel = active_panel or create_panel()
  active_panel:open()
  start_uptime_timer()
  start_discovery(active_panel, false)
end

function M.close_panel()
  if active_panel then active_panel:close() end
  stop_discovery()
  stop_uptime_timer()
end

function M.open_tasklist()
  TaskList.open(render_panel)
end

function M.toggle_panel()
  if active_panel and active_panel:is_open() then
    M.close_panel()
  else
    M.open_panel()
  end
end

function M.refresh()
  start_discovery(active_panel and active_panel:is_open() and active_panel or nil, true)
end

function M.show_help()
  if active_panel and active_panel:is_open() then active_panel:execute('help') end
end

function M.disable()
  stop_discovery()
  M.close_panel()
  TaskList.close()
  active_panel = nil
end

function M.setup_commands()
  Highlights.setup(core.get_config().highlights)
  vim.api.nvim_create_user_command('VVTaskPanel', M.toggle_panel, { force = true })
  vim.api.nvim_create_user_command('VVTaskPanelOpen', M.open_panel, { force = true })
  vim.api.nvim_create_user_command('VVTaskPanelClose', M.close_panel, { force = true })
  vim.api.nvim_create_user_command('VVTaskPanelRefresh', M.refresh, { force = true })
  vim.api.nvim_create_user_command('VVTaskPanelTasks', M.open_tasklist, { force = true })
end

return M
