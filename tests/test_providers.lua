-- package.json 与 Deno 提供者的真实解析行为
-- 运行方式：nvim --headless -u NONE -l tests/test_providers.lua

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
local original_executable = vim.fn.executable
local original_system = vim.system
local system_calls = {}

local function copy_command(command)
  return vim.deepcopy(command)
end

vim.fn.executable = function(name)
  if name == 'cargo' or name == 'go' then return 1 end
  return original_executable(name)
end

vim.system = function(command, options)
  local cwd = assert(options.cwd, '提供者系统命令必须使用项目 cwd')
  system_calls[#system_calls + 1] = { command = copy_command(command), cwd = cwd }
  local result

  if command[1] == 'cargo' then
    local manifest = cwd .. '/Cargo.toml'
    local target = cwd .. '/src/main.rs'
    if cwd:match('/cargo_error$') then
      result = { code = 1, stdout = '', stderr = 'metadata failed' }
    elseif cwd:match('/cargo_invalid$') then
      result = { code = 0, stdout = '{invalid json' }
    else
      local targets
      local default_run
      if cwd:match('/cargo_default$') then
        default_run = 'runner'
        targets = {
          {
            kind = { 'bin' }, name = 'main-bin', src_path = target,
            ['required-features'] = { 'main-feature' },
          },
          {
            kind = { 'bin' }, name = 'runner', src_path = cwd .. '/src/bin/runner.rs',
            ['required-features'] = { 'cli', 'logging' },
          },
        }
      elseif vim.uv.fs_stat(target) then
        targets = {
          {
            kind = { 'bin' }, name = 'fixture-cli', src_path = target,
            ['required-features'] = { 'cli', 'logging' },
          },
        }
      else
        targets = {}
      end
      result = {
        code = 0,
        stdout = vim.json.encode({
          packages = cwd:match('/virtual$') and {} or {
            { manifest_path = manifest, default_run = default_run, targets = targets },
          },
        }),
      }
    end
  elseif command[1] == 'go' then
    if cwd:match('/go_error$') then
      result = { code = 1, stdout = '', stderr = 'package listing failed' }
    elseif cwd:match('/go_invalid$') then
      result = { code = 0, stdout = '{invalid json' }
    else
      local compiled = cwd:match('/go_build_tag$') and { 'helper.go' } or { 'main.go' }
      result = { code = 0, stdout = vim.json.encode({ Name = 'main', CompiledGoFiles = compiled }) }
    end
  else
    error('收到未预期的提供者命令：' .. table.concat(command, ' '))
  end

  return { wait = function() return result end }
end

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

local function last_system_call(name)
  for index = #system_calls, 1, -1 do
    if system_calls[index].command[1] == name then return system_calls[index] end
  end
  error('未记录名称为 ' .. name .. ' 的系统调用')
end

Config.setup({ provider_options = { package_json = { sort = true } } })
assert(vim.deep_equal(names(assert(PackageJson.parse(path, Config.get()))), { '// section', 'alpha', 'zebra' }),
  '默认保留脚本并按名称排序')

Config.setup({ provider_options = { package_json = { sort = false } } })
assert(vim.deep_equal(names(assert(PackageJson.parse(path, Config.get()))), { 'zebra', '// section', 'alpha' }),
  'sort=false 时保持 package.json 的源顺序')

Config.setup({
  provider_options = {
    package_json = {
      filter = function(task)
        assert(task.path == path, '过滤器接收清单路径')
        assert(task.directory == directory, '过滤器接收包目录')
        return task.name == 'alpha'
      end,
      sort = false,
    },
  },
})
assert(vim.deep_equal(names(assert(PackageJson.parse(path, Config.get()))), { 'alpha' }),
  '自定义过滤器接收稳定上下文并决定哪些脚本会转换为任务')

local workspace_dir = directory .. '/workspace'
vim.fn.mkdir(workspace_dir .. '/packages/included', 'p')
vim.fn.mkdir(workspace_dir .. '/packages/excluded', 'p')
vim.fn.writefile({ '{}' }, workspace_dir .. '/package.json')
vim.fn.writefile({ '{}' }, workspace_dir .. '/packages/included/package.json')
vim.fn.writefile({ '{}' }, workspace_dir .. '/packages/excluded/package.json')
vim.fn.writefile({ 'packages:', "  - 'packages/*'", "  - '!packages/excluded'" },
  workspace_dir .. '/pnpm-workspace.yaml')
Config.setup({ scan_strategy = 'workspace' })
assert(vim.deep_equal(PackageJson.detect(workspace_dir, Config.get()), {
  workspace_dir .. '/package.json',
  workspace_dir .. '/packages/included/package.json',
}), '负工作区 glob 会移除匹配的包')

Config.setup({
  provider_options = {
    package_json = {
      presets = { audit = true },
    },
  },
})
local package_with_preset = assert(PackageJson.parse(path, Config.get()))
assert(package_with_preset.tasks[#package_with_preset.tasks].name == 'Audit dependencies',
  '包管理器预设是可选的')
assert(vim.deep_equal(package_with_preset.tasks[#package_with_preset.tasks].argv, { 'npm', 'audit' }),
  '包管理器预设会使用检测到的包管理器')

local deno_path = directory .. '/deno.jsonc'
vim.fn.writefile({
  '{',
  '  // Deno 允许 JSONC 注释',
  '  "tasks": {',
  '    "check": "deno check main.ts",',
  '    "dev": "deno run --watch main.ts", // 行尾注释',
  '  },',
  '}',
}, deno_path)

Config.setup({ provider_options = { deno = { sort = false } } })
assert(vim.deep_equal(Deno.detect(directory), { deno_path }), 'Deno 在项目根目录发现 deno.jsonc')
local deno = assert(Deno.parse(deno_path, Config.get()))
assert(vim.deep_equal(names(deno), { 'check', 'dev' }), 'deno.jsonc 任务保持源文件顺序')
assert(vim.deep_equal(deno.tasks[2].argv, { 'deno', 'task', 'dev' }), 'Deno 任务使用 deno task')

local cargo_path = directory .. '/Cargo.toml'
vim.fn.writefile({ '[package]', 'name = "fixture"' }, cargo_path)
Config.setup({ provider_options = { cargo = { presets = { build = false, fmt = true } } } })
local cargo = Cargo.parse(cargo_path, Config.get())
assert(vim.deep_equal(names(cargo), { 'Check', 'Test', 'Clippy', 'Format' }),
  'Cargo 预设同时支持默认、禁用和可选任务')

vim.fn.mkdir(directory .. '/src', 'p')
vim.fn.writefile({ 'fn main() {}' }, directory .. '/src/main.rs')
Config.setup({})
cargo = Cargo.parse(cargo_path, Config.get())
assert(cargo.tasks[#cargo.tasks].name == 'Run main', 'Cargo 的 src/main.rs 提供 Run main 任务')
assert(vim.deep_equal(cargo.tasks[#cargo.tasks].argv,
  { 'cargo', 'run', '--bin', 'fixture-cli', '--features', 'cli,logging' }),
  'Cargo Run main 显式选择 target 并传递 required-features')
local cargo_call = last_system_call('cargo')
assert(vim.deep_equal(cargo_call.command,
  { 'cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', cargo_path }),
  'Cargo metadata 使用完整且可复现的外部命令')

-- 元数据缓存必须同时考虑默认 src/bin 目标和显式声明的目标
-- 以及 src 外的目标，否则源码变更后可能留下过期的 Run main 数据
local cargo_cache_calls = #system_calls
vim.fn.mkdir(directory .. '/src/bin', 'p')
vim.fn.writefile({ 'fn main() {}' }, directory .. '/src/bin/tool.rs')
Cargo.parse(cargo_path, Config.get())
assert(#system_calls == cargo_cache_calls + 1,
  '新增 src/bin 目标时，Cargo 元数据缓存会失效')

local custom_source = directory .. '/custom/main.rs'
vim.fn.mkdir(directory .. '/custom', 'p')
vim.fn.writefile({ 'fn main() {}' }, custom_source)
vim.fn.writefile({
  '[package]',
  'name = "fixture"',
  '',
  '[[bin]]',
  'name = "custom"',
  'path = "custom/main.rs"',
}, cargo_path)
Cargo.parse(cargo_path, Config.get())
local custom_cache_calls = #system_calls
vim.fn.writefile({ 'fn main() {}', '// 自定义源文件已变更' }, custom_source)
Cargo.parse(cargo_path, Config.get())
assert(#system_calls == custom_cache_calls + 1,
  '自定义目标源码变更时，Cargo 元数据缓存会失效')

local cargo_default_dir = directory .. '/cargo_default'
local cargo_default_path = cargo_default_dir .. '/Cargo.toml'
vim.fn.mkdir(cargo_default_dir .. '/src/bin', 'p')
vim.fn.writefile({ '[package]', 'name = "default-fixture"' }, cargo_default_path)
vim.fn.writefile({ 'fn main() {}' }, cargo_default_dir .. '/src/main.rs')
vim.fn.writefile({ 'fn main() {}' }, cargo_default_dir .. '/src/bin/runner.rs')
Config.setup({})
local cargo_default = Cargo.parse(cargo_default_path, Config.get())
assert(vim.deep_equal(cargo_default.tasks[#cargo_default.tasks].argv,
  { 'cargo', 'run', '--bin', 'runner', '--features', 'cli,logging' }),
  'Cargo Run main 遵循 metadata.default_run 选择 binary target')

local cargo_error_dir = directory .. '/cargo_error'
vim.fn.mkdir(cargo_error_dir, 'p')
local cargo_error_path = cargo_error_dir .. '/Cargo.toml'
vim.fn.writefile({ '[package]', 'name = "error-fixture"' }, cargo_error_path)
vim.fn.mkdir(cargo_error_dir .. '/src', 'p')
vim.fn.writefile({ 'fn main() {}' }, cargo_error_dir .. '/src/main.rs')
Config.setup({})
local cargo_error = Cargo.parse(cargo_error_path, Config.get())
assert(cargo_error.tasks[#cargo_error.tasks].name ~= 'Run main', 'Cargo metadata 非零退出时不显示 Run main')

local cargo_invalid_dir = directory .. '/cargo_invalid'
vim.fn.mkdir(cargo_invalid_dir .. '/src', 'p')
local cargo_invalid_path = cargo_invalid_dir .. '/Cargo.toml'
vim.fn.writefile({ '[package]', 'name = "invalid-fixture"' }, cargo_invalid_path)
vim.fn.writefile({ 'fn main() {}' }, cargo_invalid_dir .. '/src/main.rs')
Config.setup({})
local cargo_invalid = Cargo.parse(cargo_invalid_path, Config.get())
assert(cargo_invalid.tasks[#cargo_invalid.tasks].name ~= 'Run main', 'Cargo metadata 非法 JSON 时不显示 Run main')

Config.setup({ provider_options = { cargo = { presets = { run = false } } } })
cargo = Cargo.parse(cargo_path, Config.get())
assert(cargo.tasks[#cargo.tasks].name ~= 'Run main', 'Cargo presets.run=false 隐藏 Run main')

local virtual_dir = directory .. '/virtual'
vim.fn.mkdir(virtual_dir .. '/src', 'p')
vim.fn.writefile({ '[workspace]' }, virtual_dir .. '/Cargo.toml')
vim.fn.writefile({ 'fn main() {}' }, virtual_dir .. '/src/main.rs')
Config.setup({})
local virtual_cargo = Cargo.parse(virtual_dir .. '/Cargo.toml', Config.get())
assert(virtual_cargo.tasks[#virtual_cargo.tasks].name ~= 'Run main', 'Cargo 虚拟 workspace 不显示 Run main')

local go_path = directory .. '/go.mod'
vim.fn.writefile({ 'module example.com/fixture', '', 'go 1.24' }, go_path)
Config.setup({ provider_options = { go = { presets = { vet = false, fmt = true } } } })
local go = Go.parse(go_path, Config.get())
assert(vim.deep_equal(names(go), { 'Build all', 'Test all', 'Format all' }),
  'Go 预设支持默认、禁用和可选任务')

vim.fn.writefile({ 'package main', '', 'func main() {}' }, directory .. '/main.go')
Config.setup({})
go = Go.parse(go_path, Config.get())
assert(go.tasks[#go.tasks].name == 'Run main', 'Go 根目录 package main 提供 Run main 任务')
assert(vim.deep_equal(go.tasks[#go.tasks].argv, { 'go', 'run', '.' }), 'Go Run main 使用 go run .')
local go_call = last_system_call('go')
assert(vim.deep_equal(go_call.command, { 'go', 'list', '-mod=readonly', '-json', '.' }),
  'Go list 使用完整且可复现的外部命令')

-- 每个架构相关的构建上下文变量都必须参与缓存 key 生成
-- 使用 mock 的 go list，以校验生产者调用次数
local build_context_variables = {
  'GOOS', 'GOARCH', 'GO386', 'GOAMD64', 'GOARM', 'GOARM64',
  'GOMIPS', 'GOMIPS64', 'GOPPC64', 'GORISCV64', 'GOWASM',
  'CGO_ENABLED', 'GOFLAGS', 'GOEXPERIMENT', 'GOFIPS140',
  'GO111MODULE', 'GOWORK', 'GOTOOLCHAIN',
}
local original_context = {}
for _, name in ipairs(build_context_variables) do
  original_context[name] = vim.env[name]
  vim.env[name] = (original_context[name] or '') .. '-cache-check'
  local before = #system_calls
  Go.parse(go_path, Config.get())
  assert(#system_calls == before + 1, 'Go 缓存键包含 ' .. name)
  vim.env[name] = original_context[name]
end

Config.setup({ provider_options = { go = { presets = { run = false } } } })
go = Go.parse(go_path, Config.get())
assert(go.tasks[#go.tasks].name ~= 'Run main', 'Go presets.run=false 隐藏 Run main')

vim.fn.writefile({ 'package main' }, directory .. '/main.go')
Config.setup({})
go = Go.parse(go_path, Config.get())
assert(go.tasks[#go.tasks].name ~= 'Run main', '没有 func main 的 Go package 不显示 Run main')

vim.fn.writefile({ 'package main', '', 'func main() int {', '  return 0', '}' }, directory .. '/main.go')
Config.setup({})
go = Go.parse(go_path, Config.get())
assert(go.tasks[#go.tasks].name ~= 'Run main', '带返回值的 func main 不显示 Run main')

vim.fn.writefile({ 'package main', '', 'func helper() {', '  // 注释中的 func main() {}', '}' }, directory .. '/main.go')
go = Go.parse(go_path, Config.get())
assert(go.tasks[#go.tasks].name ~= 'Run main', '注释中的 func main 不显示 Run main')

local tagged_dir = directory .. '/go_build_tag'
vim.fn.mkdir(tagged_dir, 'p')
vim.fn.writefile({ 'module example.com/tagged', '', 'go 1.24' }, tagged_dir .. '/go.mod')
vim.fn.writefile({ '//go:build windows', '', 'package main', '', 'func main() {}' }, tagged_dir .. '/main.go')
vim.fn.writefile({ 'package main', '', 'func helper() {}' }, tagged_dir .. '/helper.go')
go = Go.parse(tagged_dir .. '/go.mod', Config.get())
assert(go.tasks[#go.tasks].name ~= 'Run main', '被 go list 排除的 build-tag 入口不显示 Run main')

local go_error_dir = directory .. '/go_error'
vim.fn.mkdir(go_error_dir, 'p')
local go_error_path = go_error_dir .. '/go.mod'
vim.fn.writefile({ 'module example.com/error', '', 'go 1.24' }, go_error_path)
vim.fn.writefile({ 'package main', '', 'func main() {}' }, go_error_dir .. '/main.go')
Config.setup({})
local go_error = Go.parse(go_error_path, Config.get())
assert(go_error.tasks[#go_error.tasks].name ~= 'Run main', 'Go list 非零退出时不显示 Run main')

local go_invalid_dir = directory .. '/go_invalid'
vim.fn.mkdir(go_invalid_dir, 'p')
local go_invalid_path = go_invalid_dir .. '/go.mod'
vim.fn.writefile({ 'module example.com/invalid', '', 'go 1.24' }, go_invalid_path)
vim.fn.writefile({ 'package main', '', 'func main() {}' }, go_invalid_dir .. '/main.go')
Config.setup({})
local go_invalid = Go.parse(go_invalid_path, Config.get())
assert(go_invalid.tasks[#go_invalid.tasks].name ~= 'Run main', 'Go list 非法 JSON 时不显示 Run main')

vim.fn.executable = original_executable
vim.system = original_system

-- 工具链可用时，使用真实 go list 结果运行真实的生产提供者进行验证
-- 架构相关文件用于证明是 CompiledGoFiles 而非每个 GoFiles 条目触发 Run main
if vim.fn.executable('go') == 1 then
  local real_go_dir = vim.fn.tempname()
  local real_go_path = real_go_dir .. '/go.mod'
  vim.fn.mkdir(real_go_dir, 'p')
  vim.fn.writefile({ 'module example.com/compiled-files', '', 'go 1.24' }, real_go_path)
  vim.fn.writefile({
    '//go:build amd64',
    '',
    'package main',
    '',
    'func main() {}',
  }, real_go_dir .. '/main_amd64.go')
  vim.fn.writefile({
    '//go:build arm64',
    '',
    'package main',
    '',
    'func helper() {}',
  }, real_go_dir .. '/main_arm64.go')

  local original_goarch = vim.env.GOARCH
  vim.env.GOARCH = 'amd64'
  Config.setup({})
  local amd64 = Go.parse(real_go_path, Config.get())
  assert(amd64.tasks[#amd64.tasks].name == 'Run main',
    '真实 go list 的 CompiledGoFiles 包含 amd64 主入口')

  vim.env.GOARCH = 'arm64'
  Config.setup({})
  local arm64 = Go.parse(real_go_path, Config.get())
  assert(arm64.tasks[#arm64.tasks].name ~= 'Run main',
    '真实 go list 的构建上下文会排除非入口 arm64 代码')
  vim.env.GOARCH = original_goarch
  vim.fn.delete(real_go_dir, 'rf')
end

if vim.fn.executable('cargo') == 1 then
  local real_cargo_dir = vim.fn.tempname()
  local real_cargo_path = real_cargo_dir .. '/Cargo.toml'
  vim.fn.mkdir(real_cargo_dir .. '/custom', 'p')
  vim.fn.writefile({
    '[package]',
    'name = "compiled-targets"',
    'version = "0.1.0"',
    'default-run = "custom-run"',
    '',
    '[[bin]]',
    'name = "custom-run"',
    'path = "custom/main.rs"',
  }, real_cargo_path)
  vim.fn.writefile({ 'fn main() {}' }, real_cargo_dir .. '/custom/main.rs')
  Config.setup({})
  local real_cargo = Cargo.parse(real_cargo_path, Config.get())
  assert(vim.deep_equal(real_cargo.tasks[#real_cargo.tasks].argv,
    { 'cargo', 'run', '--bin', 'custom-run' }),
    '真实 cargo 元数据会选择自定义的默认二进制目标')
  vim.fn.delete(real_cargo_dir, 'rf')
end

vim.fn.delete(directory, 'rf')
print('vv-task-panel 提供者测试：通过')
