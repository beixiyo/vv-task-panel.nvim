-- g<CR> 可用性与 statuscol 生命周期回归覆盖
-- 运行方式：nvim --headless -u NONE -l tests/test_sign_lifecycle.lua

local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local subscriptions = 0
local disposals = 0
package.loaded['vv-statuscol'] = {
  on_click = function()
    subscriptions = subscriptions + 1
    local done = false
    return function()
      if done then return end
      done = true
      disposals = disposals + 1
    end
  end,
}

local runs = 0
package.loaded['vv-task-panel.run'] = {
  run = function(_, _, callback)
    runs = runs + 1
    callback()
  end,
  focus = function() end,
  stop = function() end,
  dispose = function() end,
}

local task = require('vv-task-panel')
task.setup({
  providers = {},
  provider_options = {
    package_json = {
      filter = function(script)
        return not vim.startswith(script.name, '//')
      end,
    },
  },
})
vim.wait(100, function() return subscriptions == 1 end)

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/package.json')
vim.bo[buf].filetype = 'json'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '{',
  '  "scripts": {',
  '    "// section": "Display only",',
  '    "dev": "vite"',
  '  },',
  '  "not-a-script": "dev"',
  '}',
})
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
assert(vim.wait(100, function() return vim.fn.maparg('g<CR>', 'n', false, true).buffer == 1 end),
  '解析真实 scripts 条目后，g<CR> 必须是 buffer-local')

vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.api.nvim_feedkeys(vim.keycode('g<CR>'), 'xt', false)
vim.wait(20)
assert(runs == 0, '被过滤的伪脚本不得执行')

vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.api.nvim_feedkeys(vim.keycode('g<CR>'), 'xt', false)
assert(vim.wait(100, function() return runs == 1 end), 'g<CR> 必须在已解析条目行执行')

local external_key = function() return 'external' end
vim.keymap.set('n', 'g<CR>', external_key, { buffer = buf, desc = 'external g<CR>' })
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{ "name": "no scripts" }' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
vim.wait(100)
assert(
  vim.fn.maparg('g<CR>', 'n', false, true).callback == external_key,
  '移除 scripts 时必须保留更新的 buffer-local g<CR> 所有者'
)
vim.keymap.del('n', 'g<CR>', { buffer = buf })

vim.bo[buf].filetype = 'lua'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{ "scripts": { "dev": "vite" } }' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
vim.wait(20)
assert(vim.fn.maparg('g<CR>', 'n', false, true).buffer ~= 1, '不支持的文件类型不得获得 g<CR>')

task.register_sign_parser('tasks[1].lua', function(target)
  return {
    {
      lnum = 1,
      name = 'custom',
      argv = { 'true' },
      cwd = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(target), ':h'),
      badge = 'custom',
    },
  }
end)
local custom = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(custom, vim.fn.tempname() .. '/tasks[1].lua')
vim.bo[custom].filetype = 'lua'
vim.api.nvim_buf_set_lines(custom, 0, -1, false, { 'return {}' })
vim.api.nvim_set_current_buf(custom)
vim.api.nvim_exec_autocmds('BufEnter', { buffer = custom })
assert(
  vim.wait(100, function() return vim.fn.maparg('g<CR>', 'n', false, true).buffer == 1 end),
  'setup 后注册的解析器无需再次 setup 即可生效'
)
assert(
  subscriptions == 1,
  '注册解析器不会重建 statuscol 订阅'
)

task.setup({ providers = {} })
assert(
  vim.wait(100, function() return subscriptions == 2 end),
  ('重复 setup 必须创建一个替换订阅，实际为 %d'):format(subscriptions)
)
assert(
  disposals == subscriptions - 1,
  ('重复 setup 必须释放全部旧订阅，实际为 %d/%d'):format(disposals, subscriptions)
)
task.disable()
assert(disposals == subscriptions, 'disable 必须释放当前 statuscol 订阅')

local settled_subscriptions = subscriptions
local settled_disposals = disposals
task.setup({ providers = {} })
task.setup({ providers = {} })
task.disable()
vim.wait(50)
assert(
  subscriptions == settled_subscriptions,
  '立即重复 setup/disable 不得留下已调度的订阅'
)
assert(
  disposals == settled_disposals,
  '立即重复 setup/disable 不得释放不属于当前所有者的已调度订阅'
)

print('vv-task-panel sign 生命周期：通过')
