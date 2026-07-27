-- Provider registry owner

local M = {}
local providers = {}

---@param provider VVTaskPanel.Provider
function M.register(provider)
  assert(provider and type(provider.name) == 'string', 'provider.name is required')
  assert(type(provider.detect) == 'function', 'provider.detect is required')
  assert(type(provider.parse) == 'function', 'provider.parse is required')
  providers[provider.name] = provider
end

---@return VVTaskPanel.Provider[]
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
