-- TaskGroup 数据到 vv-utils tree_panel 节点的纯转换

local M = {}

---@param kind string
---@param parts string[]
---@return string
local function opaque_id(kind, parts)
  local encoded = { kind }
  for _, part in ipairs(parts) do
    part = tostring(part)
    encoded[#encoded + 1] = ('%d:%s'):format(#part, part)
  end
  return table.concat(encoded, '|')
end

---@param groups VVTaskPanel.TaskGroup[]
---@return VVTreePanelNode[]
function M.nodes(groups)
  local nodes = {}

  for _, group in ipairs(groups or {}) do
    local provider = group.provider or ''
    local group_id = opaque_id('group', { provider, group.id })
    local children = {}
    local seen_tasks = {}

    for _, task in ipairs(group.tasks or {}) do
      local identity = task.id or task.name
      assert(type(identity) == 'string' and identity ~= '',
        ('task in group %s requires a non-empty id or name'):format(group.id))
      assert(not seen_tasks[identity],
        ('duplicate task id in group %s: %s'):format(group.id, identity))
      seen_tasks[identity] = true

      children[#children + 1] = {
        id = opaque_id('task', { provider, group.id, identity }),
        label = task.name,
        data = {
          kind = 'task',
          group = group,
          task = task,
        },
      }
    end

    nodes[#nodes + 1] = {
      id = group_id,
      label = group.name,
      selectable = false,
      children = children,
      data = {
        kind = 'group',
        group = group,
      },
    }
  end

  return nodes
end

return M
