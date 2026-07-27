-- Discovered groups and task execution records

local M = {}
local groups = {}
local tasks = {}
local next_task_id = 1

---@param value VVTaskPanel.TaskGroup[]
function M.set_groups(value)
  groups = value
end

---@return VVTaskPanel.TaskGroup[]
function M.groups()
  return groups
end

---@return table<integer, VVTaskPanel.TaskRecord>
function M.tasks()
  return tasks
end

---@return VVTaskPanel.TaskRecord[]
function M.running_tasks()
  local running = {}

  for _, task in pairs(tasks) do
    if task.status == 'running' then running[#running + 1] = task end
  end

  table.sort(running, function(a, b)
    if a.group_name ~= b.group_name then
      return a.group_name < b.group_name
    end
    return a.task_name < b.task_name
  end)

  return running
end

---@return integer
function M.allocate_task_id()
  local id = next_task_id
  next_task_id = next_task_id + 1
  return id
end

---@param record VVTaskPanel.TaskRecord
function M.add_task(record)
  tasks[record.id] = record
end

---@param id integer
function M.remove_task(id)
  tasks[id] = nil
end

---@param group_id string
---@param task_name string
---@return VVTaskPanel.TaskRecord?
function M.find_recent_task(group_id, task_name)
  local latest
  for _, task in pairs(tasks) do
    if task.group_id == group_id and task.task_name == task_name then
      if not latest or task.started_at > latest.started_at then latest = task end
    end
  end
  return latest
end

---@param group_id string
---@param task_name string
---@return VVTaskPanel.TaskRecord[]
function M.finished_before_latest(group_id, task_name)
  local keep
  for _, task in pairs(tasks) do
    if task.group_id == group_id and task.task_name == task_name and task.status ~= 'running' then
      if not keep or task.started_at > keep.started_at then keep = task end
    end
  end

  local stale = {}
  for _, task in pairs(tasks) do
    if task.group_id == group_id
      and task.task_name == task_name
      and task.status ~= 'running'
      and task ~= keep
    then
      stale[#stale + 1] = task
    end
  end
  return stale
end

return M
