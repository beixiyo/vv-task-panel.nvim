-- Provider 预设任务组合器，统一处理默认开关和任务重名

local M = {}

---@class VVTaskPanel.PresetDefinition
---@field key string 配置键
---@field name string 面板显示名称
---@field argv string[]|fun(context:table):string[]
---@field default? boolean 是否默认启用 @default false

---@param definitions VVTaskPanel.PresetDefinition[]
---@param overrides? table<string, boolean>
---@param context? table
---@param existing? VVTaskPanel.Task[]
---@return VVTaskPanel.Task[]
function M.build(definitions, overrides, context, existing)
  local tasks = {}
  local names = {}

  for _, task in ipairs(existing or {}) do
    tasks[#tasks + 1] = task
    names[task.name] = true
  end

  for _, definition in ipairs(definitions) do
    local override = overrides and overrides[definition.key]
    local enabled = override == nil and definition.default == true or override == true

    if enabled and not names[definition.name] then
      local argv = type(definition.argv) == 'function'
        and definition.argv(context or {})
        or definition.argv

      tasks[#tasks + 1] = {
        name = definition.name,
        argv = argv,
      }
      names[definition.name] = true
    end
  end

  return tasks
end

return M
