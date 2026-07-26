-- Main tree-panel composition and public UI lifecycle

local core = require('vv-task-panel.core')
local run = require('vv-task-panel.run')
local Highlights = require('vv-task-panel.ui.highlights')
local PanelModel = require('vv-task-panel.panel.model')
local PanelRender = require('vv-task-panel.panel.render')
local TaskList = require('vv-task-panel.ui.task_list')
local TreePanel = require('vv-utils.tree_panel')

local M = {}
local active_panel ---@type VVTreePanel?
local uptime_timer

local function stop_uptime_timer()
  if not uptime_timer then return end
  uptime_timer:stop()
  uptime_timer:close()
  uptime_timer = nil
end

local function render_panel()
  if active_panel and active_panel:is_open() then active_panel:refresh() end
end

M.render_panel = render_panel
M.render_tasklist = TaskList.render

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
    PanelRender.create(core),
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
      core.discover(vim.fn.getcwd())
      context.panel:refresh()
      vim.notify(('[vv-task-panel] %d groups rescanned'):format(#core.groups()))
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
    on_close = stop_uptime_timer,
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

  core.discover(vim.fn.getcwd())
  active_panel = active_panel or create_panel()
  active_panel:open()
  start_uptime_timer()
end

function M.close_panel()
  if active_panel then active_panel:close() end
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
  core.discover(vim.fn.getcwd())
  render_panel()
  vim.notify(('[vv-task-panel] %d groups rescanned'):format(#core.groups()))
end

function M.show_help()
  if active_panel and active_panel:is_open() then active_panel:execute('help') end
end

function M.disable()
  M.close_panel()
  TaskList.close()
  active_panel = nil
end

function M.setup_commands()
  Highlights.setup()
  vim.api.nvim_create_user_command('VVTaskPanel', M.toggle_panel, { force = true })
  vim.api.nvim_create_user_command('VVTaskPanelOpen', M.open_panel, { force = true })
  vim.api.nvim_create_user_command('VVTaskPanelClose', M.close_panel, { force = true })
  vim.api.nvim_create_user_command('VVTaskPanelRefresh', M.refresh, { force = true })
  vim.api.nvim_create_user_command('VVTaskPanelTasks', M.open_tasklist, { force = true })
end

return M
