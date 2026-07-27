-- Highlight groups shared by the tree panel and task list

local M = {}

local groups = {
  VVTaskPanelHeader = 'Title',
  VVTaskPanelHeaderIcon = 'Constant',
  VVTaskPanelChevron = 'Comment',
  VVTaskPanelGroupIcon = 'MiniIconsOrange',
  VVTaskPanelGroup = 'Directory',
  VVTaskPanelPath = 'Comment',
  VVTaskPanelBadge = 'Special',
  VVTaskPanelBadgeBr = 'Comment',
  VVTaskPanelTask = 'Function',
  VVTaskPanelCmd = 'Comment',
  VVTaskPanelRunning = 'DiagnosticOk',
  VVTaskPanelSuccess = 'DiagnosticOk',
  VVTaskPanelFailed = 'DiagnosticError',
  VVTaskPanelStopped = 'DiagnosticError',
  VVTaskPanelPending = 'Comment',
  VVTaskPanelUptime = 'DiagnosticHint',
  VVTaskPanelArrow = 'Comment',
  VVTaskPanelStatusText = 'Comment',
  VVTaskPanelHint = 'Comment',
  VVTaskPanelFooter = 'Comment',
}

---@param config VVTaskPanelHighlights
function M.setup(config)
  local specs = {}
  for name, link in pairs(groups) do
    specs[name] = { link = link }
  end
  specs.VVTaskPanelAccent = vim.tbl_extend(
    'force',
    config.accent or {},
    { default = false }
  )

  require('vv-utils.hl').register('vv-task-panel.hl', specs)
end

return M
