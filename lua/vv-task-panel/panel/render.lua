-- vv-task-panel 对通用 tree_panel 的行渲染适配

local Path = require('vv-utils.path')

local M = {}

---@param core table
---@return VVTreePanelRenderers
function M.create(core)
  return {
    winbar = function()
      local icons = core.get_config().icons
      return {
        chunks = {
          { ' ' .. icons.header .. ' Task Panel', 'VVTaskPanelHeader' },
          { '  CR Run  h/l Fold  t Tasks  g? Help', 'VVTaskPanelFooter' },
        },
      }
    end,
    header = function()
      local total = 0
      local groups = core.groups()
      for _, group in ipairs(groups) do total = total + #group.tasks end
      return {
        text = ('%d packages · %d tasks'):format(#groups, total),
        hl = 'Comment',
      }
    end,
    node = function(ctx)
      local data = ctx.node.data
      local cfg = core.get_config()
      local icons = cfg.icons
      local indent = string.rep('  ', ctx.depth or 0)

      if data.kind == 'group' then
        local group = data.group
        local closed = icons.pkg_closed ~= '' and icons.pkg_closed or ''
        local opened = icons.pkg_open ~= '' and icons.pkg_open or ''
        local marker = ctx.folded and closed or opened
        local path = Path.collapse_middle(group.rel_dir or '', { head = 1, tail = 2 })
        return {
          chunks = {
            { indent .. marker .. ' ', 'VVTaskPanelChevron' },
            { icons.package .. ' ', 'VVTaskPanelGroupIcon' },
            { group.name, 'VVTaskPanelGroup' },
          },
          virt_text = {
            { '[', 'VVTaskPanelBadgeBr' },
            { group.badge or group.provider or '?', 'VVTaskPanelBadge' },
            { ']', 'VVTaskPanelBadgeBr' },
            { path ~= '' and (' ' .. path) or '', 'VVTaskPanelPath' },
          },
        }
      end

      local group = data.group
      local task = data.task
      local record = core.find_recent_task(group.id, task.name)
      local glyph = icons.pending
      local glyph_hl = 'VVTaskPanelPending'
      if record then
        glyph = icons[record.status] or icons.failed
        glyph_hl = ({
          running = 'VVTaskPanelRunning',
          success = 'VVTaskPanelSuccess',
          stopped = 'VVTaskPanelStopped',
          failed = 'VVTaskPanelFailed',
        })[record.status] or 'VVTaskPanelFailed'
      end

      local command = task.cmd or table.concat(task.argv or {}, ' ')
      local virtual = { { command, 'VVTaskPanelCmd' } }
      if record and record.status == 'running' then
        local uptime = math.floor((vim.uv.now() - record.started_at) / 1000)
        virtual[#virtual + 1] = { ('  (%ds)'):format(uptime), 'VVTaskPanelUptime' }
      end

      return {
        chunks = {
          { indent .. '  ', 'Comment' },
          { glyph .. ' ', glyph_hl },
          { task.name, 'VVTaskPanelTask' },
        },
        virt_text = virtual,
      }
    end,
    empty = function()
      return {
        text = 'No tasks discovered · press r to rescan',
        hl = 'Comment',
      }
    end,
  }
end

return M
