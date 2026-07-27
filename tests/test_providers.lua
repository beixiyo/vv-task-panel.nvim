-- package.json 与 Deno provider 的真实解析行为
-- Run: nvim --headless -u NONE -l tests/test_providers.lua

local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local Config = require('vv-task-panel.config')
local Cargo = require('vv-task-panel.providers.cargo')
local PackageJson = require('vv-task-panel.providers.package_json')
local Deno = require('vv-task-panel.providers.deno')
local Go = require('vv-task-panel.providers.go')
local directory = vim.fn.tempname()
local path = directory .. '/package.json'

vim.fn.mkdir(directory, 'p')
vim.fn.writefile({
  '{',
  '  "name": "fixture",',
  '  "scripts": {',
  '    "zebra": "echo zebra",',
  '    "// section": "Display only",',
  '    "alpha": "echo alpha"',
  '  }',
  '}',
}, path)

local function names(group)
  return vim.tbl_map(function(task) return task.name end, group.tasks)
end

Config.setup({ provider_options = { package_json = { sort = true } } })
assert(vim.deep_equal(names(assert(PackageJson.parse(path, Config.get()))), { '// section', 'alpha', 'zebra' }),
  'scripts remain intact by default and sort orders names')

Config.setup({ provider_options = { package_json = { sort = false } } })
assert(vim.deep_equal(names(assert(PackageJson.parse(path, Config.get()))), { 'zebra', '// section', 'alpha' }),
  'sort=false preserves package.json source order')

Config.setup({
  provider_options = {
    package_json = {
      filter = function(task)
        assert(task.path == path, 'filter receives the manifest path')
        assert(task.directory == directory, 'filter receives the package directory')
        return task.name == 'alpha'
      end,
      sort = false,
    },
  },
})
assert(vim.deep_equal(names(assert(PackageJson.parse(path, Config.get()))), { 'alpha' }),
  'custom filter receives stable context and decides which scripts become tasks')

Config.setup({
  provider_options = {
    package_json = {
      presets = { audit = true },
    },
  },
})
local package_with_preset = assert(PackageJson.parse(path, Config.get()))
assert(package_with_preset.tasks[#package_with_preset.tasks].name == 'Audit dependencies',
  'package manager presets are opt-in')
assert(vim.deep_equal(package_with_preset.tasks[#package_with_preset.tasks].argv, { 'npm', 'audit' }),
  'package manager presets use the detected manager')

local deno_path = directory .. '/deno.jsonc'
vim.fn.writefile({
  '{',
  '  // Deno allows JSONC comments',
  '  "tasks": {',
  '    "check": "deno check main.ts",',
  '    "dev": "deno run --watch main.ts", // trailing comment',
  '  },',
  '}',
}, deno_path)

Config.setup({ provider_options = { deno = { sort = false } } })
assert(vim.deep_equal(Deno.detect(directory), { deno_path }), 'Deno discovers deno.jsonc at the project root')
local deno = assert(Deno.parse(deno_path, Config.get()))
assert(vim.deep_equal(names(deno), { 'check', 'dev' }), 'deno.jsonc tasks preserve source order')
assert(vim.deep_equal(deno.tasks[2].argv, { 'deno', 'task', 'dev' }), 'Deno tasks use deno task')

local cargo_path = directory .. '/Cargo.toml'
vim.fn.writefile({ '[package]', 'name = "fixture"' }, cargo_path)
Config.setup({ provider_options = { cargo = { presets = { build = false, fmt = true } } } })
local cargo = Cargo.parse(cargo_path, Config.get())
assert(vim.deep_equal(names(cargo), { 'Check', 'Test', 'Clippy', 'Format' }),
  'Cargo presets support default, disabled, and opt-in tasks')

local go_path = directory .. '/go.mod'
vim.fn.writefile({ 'module example.com/fixture', '', 'go 1.24' }, go_path)
Config.setup({ provider_options = { go = { presets = { vet = false, fmt = true } } } })
local go = Go.parse(go_path, Config.get())
assert(vim.deep_equal(names(go), { 'Build all', 'Test all', 'Format all' }),
  'Go presets support default, disabled, and opt-in tasks')

vim.fn.delete(directory, 'rf')
print('vv-task-panel providers: PASS')
