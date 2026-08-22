-- 任务运行时可以取消显式 :qall 命令

local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local ExitGuard = require('vv-task-panel.exit_guard')
local State = require('vv-task-panel.state')

for _, command in ipairs({ 'qa', 'qal', 'qall', 'wqa', 'wqall', 'xa', 'xall' }) do
  assert(ExitGuard.should_guard(command), command .. ' 必须受到拦截')
end
for _, command in ipairs({ 'qa!', 'q', 'wq', 'silent qa', 'Task qa' }) do
  assert(not ExitGuard.should_guard(command), command .. ' 不得受到拦截')
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
    assert(message:find('1 task is still running:', 1, true), '单个任务使用单数语法')
    assert(message:find('stop this task?', 1, true), '单个任务使用单数疑问句')
    assert(message:find('app ▸ dev', 1, true), '提示信息会标识运行中的任务')
    assert(choices == '&Yes\n&No', '提示信息使用标准 Yes/No 选项')
    assert(default == 2, 'No 是默认选项')
    return 2
  end,
})

local keys = vim.api.nvim_replace_termcodes(':qa<CR>', true, false, true)
vim.api.nvim_feedkeys(keys, 'xt', false)
assert(confirmations == 1, ':qa 会触发运行时拦截器')
assert(State.running_tasks()[1] == task, '取消退出会保留运行中的任务')

local second_task = vim.tbl_extend('force', vim.deepcopy(task), {
  id = State.allocate_task_id(),
  task_name = 'build',
})
State.add_task(second_task)
ExitGuard.setup({
  confirm = function(message)
    assert(message:find('2 tasks are still running:', 1, true), '多个任务使用复数语法')
    assert(message:find('stop these tasks?', 1, true), '多个任务使用复数疑问句')
    return 1
  end,
})
assert(ExitGuard.confirm_exit('qa'), '显式选择 Yes 允许退出')

State.remove_task(task.id)
State.remove_task(second_task.id)
assert(ExitGuard.confirm_exit('qa'), '没有运行中的任务时无需提示即可退出')
ExitGuard.disable()
print('vv-task-panel 退出拦截：通过')
