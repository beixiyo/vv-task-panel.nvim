-- g<CR> eligibility and statuscol lifecycle regression coverage
-- Run: nvim --headless -u NONE -l tests/test_sign_lifecycle.lua

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
  'g<CR> must be buffer-local after a real scripts entry is parsed')

vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.api.nvim_feedkeys(vim.keycode('g<CR>'), 'xt', false)
vim.wait(20)
assert(runs == 0, 'filtered pseudo-script must not be executable')

vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.api.nvim_feedkeys(vim.keycode('g<CR>'), 'xt', false)
assert(vim.wait(100, function() return runs == 1 end), 'g<CR> must execute on the parsed entry line')

local external_key = function() return 'external' end
vim.keymap.set('n', 'g<CR>', external_key, { buffer = buf, desc = 'external g<CR>' })
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{ "name": "no scripts" }' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
vim.wait(100)
assert(
  vim.fn.maparg('g<CR>', 'n', false, true).callback == external_key,
  'removing scripts must preserve a newer buffer-local g<CR> owner'
)
vim.keymap.del('n', 'g<CR>', { buffer = buf })

vim.bo[buf].filetype = 'lua'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{ "scripts": { "dev": "vite" } }' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
vim.wait(20)
assert(vim.fn.maparg('g<CR>', 'n', false, true).buffer ~= 1, 'unsupported filetypes must not get g<CR>')

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
  'parsers registered after setup become active without another setup'
)
assert(
  subscriptions == 1,
  'registering a parser does not rebuild the statuscol subscription'
)

task.setup({ providers = {} })
assert(
  vim.wait(100, function() return subscriptions == 2 end),
  ('repeated setup must create one replacement subscription, got %d'):format(subscriptions)
)
assert(
  disposals == subscriptions - 1,
  ('repeated setup must dispose every previous subscription, got %d/%d'):format(disposals, subscriptions)
)
task.disable()
assert(disposals == subscriptions, 'disable must dispose the active statuscol subscription')

local settled_subscriptions = subscriptions
local settled_disposals = disposals
task.setup({ providers = {} })
task.setup({ providers = {} })
task.disable()
vim.wait(50)
assert(
  subscriptions == settled_subscriptions,
  'immediate repeated setup/disable must not leave scheduled subscriptions'
)
assert(
  disposals == settled_disposals,
  'immediate repeated setup/disable must not dispose an unowned scheduled subscription'
)

print('vv-task-panel sign lifecycle: PASS')
