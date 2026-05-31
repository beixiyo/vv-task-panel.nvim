-- ? 键浮窗：委托给 vv-utils.help_panel
-- action 分类/图标、title 等 vv-task-panel 特有的数据在这里维护

local HelpPanel = require('vv-utils.help_panel')

local M = {}

local ACTIONS = {
  ['run/toggle']  = { cat = 'Navigate', icon = '' },
  ['toggle fold'] = { cat = 'Navigate', icon = '' },
  ['expand all']  = { cat = 'View',     icon = '' },
  ['collapse all'] = { cat = 'View',    icon = '' },
  ['task list']   = { cat = 'View',     icon = '' },
  ['rescan']      = { cat = 'View',     icon = '' },
  ['help']        = { cat = 'View',     icon = '' },
  ['close']       = { cat = 'View',     icon = '' },
}

local CATEGORIES = { 'Navigate', 'View' }

---@param source_buf integer 面板 buffer
function M.open(source_buf)
  if not (source_buf and vim.api.nvim_buf_is_valid(source_buf)) then return end
  HelpPanel.open({
    source_buf  = source_buf,
    desc_prefix = 'vv-task-panel: ',
    actions     = ACTIONS,
    categories  = CATEGORIES,
    title       = 'vv-task-panel keymaps',
    title_icon  = '',
    filetype    = 'vv-task-panel-help',
  })
end

return M
