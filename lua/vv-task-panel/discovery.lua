-- Provider execution and task-group aggregation

local Config = require('vv-task-panel.config')
local Registry = require('vv-task-panel.registry')
local State = require('vv-task-panel.state')

local M = {}

local function is_enabled(name, config)
  if config.providers == nil then return true end
  return vim.tbl_contains(config.providers, name)
end

---@param root? string
---@return VVTaskPanel.TaskGroup[]
function M.discover(root)
  root = root or vim.fn.getcwd()
  local config = Config.get()
  local groups = {}
  local seen_id = {}

  for _, provider in ipairs(Registry.ordered()) do
    local name = provider.name

    if is_enabled(name, config) then
      local detected, paths = pcall(provider.detect, root, config)

      if detected and type(paths) == 'table' then
        for _, path in ipairs(paths) do
          local parsed, group = pcall(provider.parse, path, config)

          if parsed and group and type(group.tasks) == 'table' and #group.tasks > 0 then
            group.provider = name
            group.id = group.id or path
            if not seen_id[group.id] then
              seen_id[group.id] = true
              groups[#groups + 1] = group
            end
          end
        end
      end
    end
  end

  table.sort(groups, function(a, b)
    local a_path = a.rel_dir or ''
    local b_path = b.rel_dir or ''
    local a_root = a_path == '(root)'
    local b_root = b_path == '(root)'
    if a_root ~= b_root then return a_root end
    return a_path < b_path
  end)

  State.set_groups(groups)
  return groups
end

return M
