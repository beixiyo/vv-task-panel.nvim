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
  VVTaskPanelFooter = 'Comment',
}

function M.setup()
  for name, link in pairs(groups) do
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, { link = link })
    end
  end
end

return M
