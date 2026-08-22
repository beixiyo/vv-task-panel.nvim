-- 核心行为与纯转换覆盖

local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local Config = require('vv-task-panel.config')
local Json = require('vv-task-panel.providers.common.json')
local PackageManager = require('vv-task-panel.package_manager')
local Registry = require('vv-task-panel.registry')

Config.setup({ width = 61, providers = {} })
local config = Config.get()
assert(config.width == 61, '部分 setup 会覆盖请求的字段')
assert(config.position == 'right', '部分 setup 会保留解析后的默认值')
assert(config.term_height == 15, '解析后的配置包含终端默认值')

local source_lines = {
  '{',
  '  "scripts": {',
  '    "build": "echo \\"deploy\\": fake",',
  '    // JSONC 注释',
  '    "deploy": "vite",',
  '  },',
  '  "dependencies": { "wrong": "1.0.0" }',
  '}',
}
local key_lines = Json.key_lines(table.concat(source_lines, '\n'), 'scripts')
assert(key_lines.build == 3, '直接脚本键保留其源文件行号')
assert(key_lines.deploy == 5, '类似键的命令文本不会占用其他脚本位置')
assert(key_lines.wrong == nil, 'scripts 外的键会被排除')

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
assert(ordered[1].name == 'high-priority-test', '提供者按优先级降序排列')
assert(ordered[#ordered].name == 'low-priority-test', '低优先级提供者最后运行')

local package_root = vim.fn.tempname()
local package_dir = package_root .. '/packages/app'
vim.fn.mkdir(package_dir, 'p')
vim.fn.writefile({}, package_root .. '/pnpm-lock.yaml')
assert(PackageManager.detect(package_dir) == 'pnpm', '包管理器会向上查找父目录锁文件')
vim.fn.delete(package_root, 'rf')

print('vv-task-panel 冒烟测试：通过')
