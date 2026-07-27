-- 基于 JSON/JSONC 对象的通用任务读取、过滤与排序

local Json = require('vv-task-panel.providers.common.json')

local M = {}

---@class VVTaskPanel.JsonTask
---@field provider string provider 名称
---@field name string 任务名称
---@field command? string 任务命令；只解析行标记时为空
---@field path string 配置文件绝对路径
---@field directory string 配置文件所在目录
---@field line integer 任务在配置文件中的行号

---@class VVTaskPanel.JsonTaskOptions
---@field filter? fun(task: VVTaskPanel.JsonTask): boolean 返回 false 时跳过任务
---@field sort? boolean 是否按名称排序；false 时保留源文件顺序 @default true

---@param config VVTaskPanelConfig|VVTaskPanelResolvedConfig
---@param provider string
---@return VVTaskPanel.JsonTaskOptions
function M.options(config, provider)
  return (config.provider_options and config.provider_options[provider]) or {}
end

---@param config VVTaskPanelConfig|VVTaskPanelResolvedConfig
---@param task VVTaskPanel.JsonTask
---@return boolean
function M.include(config, task)
  local filter = M.options(config, task.provider).filter
  return not filter or filter(task)
end

---@param config VVTaskPanelConfig|VVTaskPanelResolvedConfig
---@param provider string
---@param tasks VVTaskPanel.JsonTask[]
function M.sort(config, provider, tasks)
  if M.options(config, provider).sort == false then
    table.sort(tasks, function(a, b)
      if a.line ~= b.line then return a.line < b.line end
      return a.name < b.name
    end)
    return
  end

  table.sort(tasks, function(a, b) return a.name < b.name end)
end

---@param path string
---@param section string
---@param config VVTaskPanelConfig|VVTaskPanelResolvedConfig
---@param provider string
---@param allow_empty? boolean
---@return table?, VVTaskPanel.JsonTask[]?
function M.parse(path, section, config, provider, allow_empty)
  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read then return nil end

  local source = table.concat(lines, '\n')
  local data = Json.decode(source)
  if not data or (not allow_empty and type(data[section]) ~= 'table') then return nil end

  local directory = vim.fn.fnamemodify(path, ':h')
  local key_lines = Json.key_lines(source, section)
  local tasks = {} ---@type VVTaskPanel.JsonTask[]

  for name, command in pairs(data[section] or {}) do
    local task = {
      provider = provider,
      name = name,
      command = command,
      path = path,
      directory = directory,
      line = key_lines[name] or math.huge,
    }

    if M.include(config, task) then tasks[#tasks + 1] = task end
  end

  M.sort(config, provider, tasks)
  return data, tasks
end

return M
