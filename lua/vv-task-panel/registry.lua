-- Provider registry owner

local M = {}
local providers = {}

---@class Provider
---@field name string
---@field priority? integer 数值越大越先执行，同优先级按名称排序 @default 0
---@field detect fun(root: string, config: VVTaskPanelConfig): string[]
---@field parse fun(path: string, config: VVTaskPanelConfig): TaskGroup|nil

---@param provider Provider
function M.register(provider)
  assert(provider and type(provider.name) == 'string', 'provider.name 必填')
  assert(type(provider.detect) == 'function', 'provider.detect 必填')
  assert(type(provider.parse) == 'function', 'provider.parse 必填')
  providers[provider.name] = provider
end

---@return Provider[]
function M.ordered()
  local ordered = {}

  for _, provider in pairs(providers) do
    ordered[#ordered + 1] = provider
  end

  table.sort(ordered, function(a, b)
    local a_priority = a.priority or 0
    local b_priority = b.priority or 0
    if a_priority ~= b_priority then return a_priority > b_priority end
    return a.name < b.name
  end)
  return ordered
end

return M
