-- Core behavior and pure transformation coverage

local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local Config = require('vv-task-panel.config')
local Json = require('vv-task-panel.sign.json')
local PackageManager = require('vv-task-panel.package_manager')
local Registry = require('vv-task-panel.registry')

Config.setup({ width = 61, providers = {} })
local config = Config.get()
assert(config.width == 61, 'partial setup overrides the requested field')
assert(config.position == 'right', 'partial setup preserves resolved defaults')
assert(config.term_height == 15, 'resolved config contains terminal defaults')

local source_lines = {
  '{',
  '  "scripts": {',
  '    "build": "echo \\"deploy\\": fake",',
  '    // JSONC comment',
  '    "deploy": "vite",',
  '  },',
  '  "dependencies": { "wrong": "1.0.0" }',
  '}',
}
local key_lines = Json.key_lines(table.concat(source_lines, '\n'), 'scripts')
assert(key_lines.build == 3, 'direct script key keeps its source line')
assert(key_lines.deploy == 5, 'key-like command text does not steal another script position')
assert(key_lines.wrong == nil, 'keys outside scripts are excluded')

Registry.register({
  name = 'low-priority-test',
  priority = -10,
  detect = function() return {} end,
  parse = function() end,
})
Registry.register({
  name = 'high-priority-test',
  priority = 100,
  detect = function() return {} end,
  parse = function() end,
})
local ordered = Registry.ordered()
assert(ordered[1].name == 'high-priority-test', 'providers use descending priority')
assert(ordered[#ordered].name == 'low-priority-test', 'lower priority providers run last')

local package_root = vim.fn.tempname()
local package_dir = package_root .. '/packages/app'
vim.fn.mkdir(package_dir, 'p')
vim.fn.writefile({}, package_root .. '/pnpm-lock.yaml')
assert(PackageManager.detect(package_dir) == 'pnpm', 'package manager walks to parent lockfile')
vim.fn.delete(package_root, 'rf')

print('vv-task-panel smoke: PASS')
