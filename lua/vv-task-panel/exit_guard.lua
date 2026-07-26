-- Guards explicit all-session quit commands while tasks are running

local State = require('vv-task-panel.state')

local M = {}
local group_name = 'VVTaskPanelExitGuard'
local confirm = vim.fn.confirm
local pending_command

local guarded_commands = {
  qa = true,
  qal = true,
  qall = true,
  wqa = true,
  wqal = true,
  wqall = true,
  xa = true,
  xall = true,
}

---@param command string
---@return boolean
function M.should_guard(command)
  local normalized = vim.trim(command):lower()
  if normalized:sub(-1) == '!' then return false end
  return guarded_commands[normalized] == true
end

local function message(tasks)
  local singular = #tasks == 1
  local lines = {
    singular
      and '1 task is still running:'
      or ('%d tasks are still running:'):format(#tasks),
  }

  for _, task in ipairs(tasks) do
    lines[#lines + 1] = ('  %s ▸ %s'):format(task.group_name, task.task_name)
  end

  lines[#lines + 1] = ''
  lines[#lines + 1] = singular
    and 'Quit Neovim and stop this task?'
    or 'Quit Neovim and stop these tasks?'

  return table.concat(lines, '\n')
end

---@param command string
---@return boolean allow_exit
function M.confirm_exit(command)
  if not M.should_guard(command) then return true end

  local tasks = State.running_tasks()
  if #tasks == 0 then return true end
  return confirm(message(tasks), '&Yes\n&No', 2) == 1
end

---@param opts? { confirm?:fun(message:string, choices:string, default:integer):integer }
function M.setup(opts)
  M.disable()
  confirm = opts and opts.confirm or vim.fn.confirm

  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd('CmdlineLeavePre', {
    group = group,
    pattern = ':',
    callback = function()
      pending_command = vim.fn.getcmdline()
    end,
  })
  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    pattern = ':',
    callback = function()
      local command = pending_command
      pending_command = nil
      if vim.v.event.abort or not command then return end
      if not M.confirm_exit(command) then vim.cmd('let v:event.abort = v:true') end
    end,
  })
end

function M.disable()
  pcall(vim.api.nvim_del_augroup_by_name, group_name)
  confirm = vim.fn.confirm
  pending_command = nil
end

return M
