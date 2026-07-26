-- Explicit :qall commands are cancellable while a task is running

local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local ExitGuard = require('vv-task-panel.exit_guard')
local State = require('vv-task-panel.state')

for _, command in ipairs({ 'qa', 'qal', 'qall', 'wqa', 'wqall', 'xa', 'xall' }) do
  assert(ExitGuard.should_guard(command), command .. ' must be guarded')
end
for _, command in ipairs({ 'qa!', 'q', 'wq', 'silent qa', 'Task qa' }) do
  assert(not ExitGuard.should_guard(command), command .. ' must not be guarded')
end

local task = {
  id = State.allocate_task_id(),
  group_id = 'package.json',
  group_name = 'app',
  task_name = 'dev',
  argv = { 'vite' },
  cmd = 'vite',
  cwd = '/tmp',
  buf = 0,
  status = 'running',
  started_at = 1,
}
State.add_task(task)

local confirmations = 0
ExitGuard.setup({
  confirm = function(message, choices, default)
    confirmations = confirmations + 1
    assert(message:find('1 task is still running:', 1, true), 'one task uses singular grammar')
    assert(message:find('stop this task?', 1, true), 'one task uses a singular question')
    assert(message:find('app ▸ dev', 1, true), 'prompt identifies the running task')
    assert(choices == '&Yes\n&No', 'prompt uses the standard Yes/No choices')
    assert(default == 2, 'No is the default')
    return 2
  end,
})

local keys = vim.api.nvim_replace_termcodes(':qa<CR>', true, false, true)
vim.api.nvim_feedkeys(keys, 'xt', false)
assert(confirmations == 1, ':qa reaches the runtime guard')
assert(State.running_tasks()[1] == task, 'cancelling exit keeps the running task')

local second_task = vim.tbl_extend('force', vim.deepcopy(task), {
  id = State.allocate_task_id(),
  task_name = 'build',
})
State.add_task(second_task)
ExitGuard.setup({
  confirm = function(message)
    assert(message:find('2 tasks are still running:', 1, true), 'multiple tasks use plural grammar')
    assert(message:find('stop these tasks?', 1, true), 'multiple tasks use a plural question')
    return 1
  end,
})
assert(ExitGuard.confirm_exit('qa'), 'explicit Yes choice allows exit')

State.remove_task(task.id)
State.remove_task(second_task.id)
assert(ExitGuard.confirm_exit('qa'), 'no running tasks allow exit without a prompt')
ExitGuard.disable()
print('vv-task-panel exit guard: PASS')
