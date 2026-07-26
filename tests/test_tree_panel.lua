-- vv-task-panel tree_panel integration
-- Run: nvim --headless -u NONE -l tests/test_tree_panel.lua

local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
local vendors = vim.fn.fnamemodify(root, ':h')
vim.opt.runtimepath:prepend(vendors .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local Model = require('vv-task-panel.panel.model')

local unusual_groups = {
  {
    id = 'pkg:/一',
    provider = 'custom:provider',
    name = '一',
    dir = '/tmp/一',
    rel_dir = 'apps/一',
    badge = 'x',
    tasks = { { name = 'dev:/一', argv = { 'true' } } },
  },
  {
    id = 'pkg:/二',
    provider = 'custom:provider',
    name = '二',
    dir = '/tmp/二',
    rel_dir = 'apps/二',
    badge = 'x',
    tasks = { { name = 'dev:/一', argv = { 'true' } } },
  },
}
local first = Model.nodes(unusual_groups)
local second = Model.nodes(unusual_groups)
assert(first[1].id == second[1].id, 'node ids should remain stable across rebuilds')
assert(first[1].id ~= first[2].id, 'package node ids should be globally unique')
assert(first[1].children[1].id ~= first[2].children[1].id,
  'same task names in different packages should remain unique')

local duplicate = vim.deepcopy(unusual_groups[1])
duplicate.tasks = {
  { name = 'dev', argv = { 'true' } },
  { name = 'dev', argv = { 'true' } },
}
local ok, error = pcall(Model.nodes, { duplicate })
assert(not ok and tostring(error):find('duplicate task id', 1, true),
  'duplicate task identities in one package should fail clearly')

local run_count = 0
package.loaded['vv-task-panel.run'] = {
  run = function(_, _, callback)
    run_count = run_count + 1
    callback()
  end,
  focus = function() end,
  stop = function() end,
  dispose = function() end,
}

local persisted = {}
local state = {
  get = function(_, field, default)
    local value = persisted[field]
    return value == nil and default or value
  end,
  set = function(_, field, value)
    persisted[field] = value
    return true
  end,
}

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
local previous_cwd = vim.fn.getcwd()
vim.cmd.cd(vim.fn.fnameescape(tmp))

local task_panel = require('vv-task-panel')
task_panel.setup({
  providers = { 'test' },
  width = 36,
  state = state,
  position = 'right',
})
task_panel.register_provider({
  name = 'test',
  detect = function()
    return { '/tmp/pkg-a', '/tmp/pkg-b' }
  end,
  parse = function(path)
    local name = path:match('([^/]+)$')
    return {
      id = path,
      name = name,
      dir = path,
      rel_dir = 'packages/' .. name,
      badge = 'test',
      tasks = {
        { name = 'dev', argv = { 'test', 'dev' }, cmd = 'test dev' },
        { name = 'build', argv = { 'test', 'build' }, cmd = 'test build' },
      },
    }
  end,
})

task_panel.open()
local win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(buf) == 'vv-tree-panel://vv-task-panel-main',
  'main sidebar should be owned by vv-utils tree_panel')

local expanded_count = vim.api.nvim_buf_line_count(buf)
vim.api.nvim_win_set_cursor(win, { 2, 0 })
vim.api.nvim_feedkeys('h', 'x', false)
assert(vim.api.nvim_win_get_cursor(win)[1] == 2, 'collapsing a package should keep the cursor on it')
assert(vim.api.nvim_buf_line_count(buf) == expanded_count - 2,
  'collapsing one package should hide only its tasks')

vim.api.nvim_feedkeys('l', 'x', false)
assert(vim.api.nvim_buf_line_count(buf) == expanded_count, 'expanding should restore that package tasks')

vim.api.nvim_win_set_cursor(win, { 3, 0 })
vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
assert(run_count == 1, 'Enter on a task should run exactly once')
assert(vim.api.nvim_win_is_valid(win), 'Enter should keep the task panel open')

vim.cmd('vertical resize 48')
vim.api.nvim_exec_autocmds('WinResized', {})
vim.wait(250, function() return persisted.width == 48 end)
assert(persisted.width == 48, 'real :vertical resize should use shared width state')

task_panel.close()
task_panel.open()
assert(vim.api.nvim_win_get_width(0) == 48, 'reopening should restore the shared width state')
task_panel.close()

local replacement_state = {
  get = function(_, _, default) return default end,
  set = function() return true end,
}
task_panel.setup({
  providers = { 'test' },
  width = 57,
  state = replacement_state,
  position = 'right',
})
task_panel.open()
local replacement_win = vim.api.nvim_get_current_win()
assert(vim.api.nvim_win_get_width(replacement_win) == 57,
  'repeated setup should rebuild the panel with the latest config')
task_panel.disable()
assert(not vim.api.nvim_win_is_valid(replacement_win),
  'disable should close the main panel and release its UI lifecycle')

vim.cmd.cd(vim.fn.fnameescape(previous_cwd))
vim.fn.delete(tmp, 'rf')
print('vv-task-panel tree panel: PASS')
