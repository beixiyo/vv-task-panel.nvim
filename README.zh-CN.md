<div align="center">

<h1>vv-task-panel.nvim</h1>

<a href="./README.md">English</a> | 中文

<img src="https://github.com/beixiyo/vv-task-panel.nvim/releases/download/assets-2026-07-25/vv-task-panel.png" alt="vv-task-panel 演示" width="900" />

想要我的 Neovim 配置？查看 <a href="https://github.com/beixiyo/dotfiles">dotfiles</a>

  <em>可扩展的任务面板 — 自动发现项目脚本、终端运行、monorepo 支持</em>

<br />

  <img src="https://img.shields.io/badge/Neovim-0.11+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.11+" />
  <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />
</div>

---

## 依赖

任务发现由 Lua 完成；运行任务时，需要安装距离项目最近的 lockfile 所对应的包管理器：

- [pnpm](https://github.com/pnpm/pnpm)：对应 `pnpm-lock.yaml`
- [Bun](https://github.com/oven-sh/bun)：对应 `bun.lockb` 或 `bun.lock`
- [Yarn](https://github.com/yarnpkg/berry)：对应 `yarn.lock`
- [npm](https://github.com/npm/cli)：对应 `package-lock.json`，未发现受支持的 lockfile 时也默认使用 npm
- [Deno](https://github.com/denoland/deno)：运行 `deno.json` 或 `deno.jsonc` 中的任务时需要
- [Cargo](https://doc.rust-lang.org/cargo/)：运行 Rust 预设与 `Run main`；后者通过 `cargo metadata` 选择 package 的 `default-run` 或 `src/main.rs` binary，并传递其 required features
- [Go](https://go.dev/)：运行 Go 预设与 `Run main`；仅当 `go list` 在当前构建上下文选择到含 `func main()` 的 main package 时显示后者

## 安装

```lua
{
  'beixiyo/vv-task-panel.nvim',
  dependencies = {
    'beixiyo/vv-utils.nvim',
    { 'beixiyo/vv-statuscol.nvim', optional = true },  -- 鼠标点击 sign 运行任务需要此插件
  },
  cmd = { 'VVTaskPanel', 'VVTaskPanelOpen' },
  ---@type VVTaskPanelConfig
  opts = {
    width = 44,                     -- 面板宽度
    position = 'right',             -- 'left' | 'right'
    state = nil,                    -- 可选 VVStateHandle；默认 vv-task-panel/main
    mappings = {},                  -- 覆盖 vv-utils tree_panel 快捷键
    render = {},                    -- 覆盖 winbar/header/node/empty 渲染
    exclude_dirs = {                -- 扫描时跳过的目录
      'node_modules', '.git', 'dist', 'build', '.next',
      '.turbo', '.cache', 'coverage', '.nuxt', 'out',
    },
    scan_strategy = 'workspace',    -- 'workspace'（读 workspace 定义）| 'walk'（递归遍历）
    max_depth = 8,                  -- walk 策略的最大递归深度
    term_position = 'bottom',       -- 任务终端位置：'bottom' | 'right' | 'float'
    term_height = 15,               -- bottom 模式下终端高度
    term_width = 80,                -- right 模式下终端宽度
    providers = nil,                -- Provider 白名单（nil = 启用所有已注册的）
    provider_options = {
      package_json = {
        sort = true,                -- false 时保留 package.json 源文件顺序
        filter = function(script)
          return not vim.startswith(script.name, '//')
        end,
        presets = {
          audit = false,
          outdated = false,
        },
      },
      cargo = {
        presets = {
          run = true, -- Cargo 确认存在可运行的 default/main binary 时显示
          check = true,
          build = true,
          test = true,
          clippy = true,
          fmt = false,
        },
      },
      go = {
        presets = {
          run = true, -- Go 确认根目录存在可运行 main package 时显示
          build = true,
          test = true,
          vet = true,
          fmt = false,
        },
      },
    },
    highlights = {
      accent = { fg = '#c099ff', bold = true },
    },
    icons = {
      pkg_open   = '',
      pkg_closed = '',
      package    = '󰏖',
      running    = '●',
      success    = '',
      failed     = '',
      stopped    = '●',
      pending    = '',
      header     = '󰆍',
      arrow      = '→',
      run        = '',  -- statuscolumn idle 状态图标
    },
    sign = {                          -- statuscolumn 脚本行标记（按状态配置）
      idle    = { hl = 'VVTaskSignIdle' },
      running = { hl = 'VVTaskSignRunning' },
      success = { hl = 'VVTaskSignSuccess' },
      failed  = { hl = 'VVTaskSignFailed' },
      stopped = { hl = 'VVTaskSignStopped' },
    },
  },
}
```

## 配置

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `width` | `integer` | `44` | 面板初始宽度；手动 resize 后通过 `vv-utils.state` 持久化 |
| `position` | `'left' \| 'right'` | `'right'` | 面板位置 |
| `state` | `VVStateHandle?` | `nil` | 可选状态容器；默认注册 `vv-task-panel/main` |
| `mappings` | `VVTreePanelMappings` | `{}` | 覆盖或禁用通用 tree-panel 快捷键 |
| `render` | `VVTreePanelRenderers` | `{}` | 覆盖 `winbar`、`header`、`node` 或 `empty` 渲染 |
| `help` | `false \| VVTreePanelHelpOptions` | `nil` | 自定义或禁用通用 `g?` 帮助面板 |
| `on_attach` | `fun(panel, buf)?` | `nil` | 默认快捷键注册后追加调用方自己的 buffer 行为 |
| `exclude_dirs` | `string[]` | `{ 'node_modules', '.git', ... }` | 扫描时跳过的目录 |
| `scan_strategy` | `'workspace' \| 'walk'` | `'workspace'` | `workspace`：读 `pnpm-workspace.yaml` / `package.json` workspaces；`walk`：递归遍历 |
| `max_depth` | `integer` | `8` | `walk` 策略最大递归深度 |
| `term_position` | `'bottom' \| 'right' \| 'float'` | `'bottom'` | 任务终端窗口位置 |
| `term_height` | `integer` | `15` | `bottom` 模式下终端高度 |
| `term_width` | `integer` | `80` | `right` 模式下终端宽度 |
| `providers` | `string[]?` | `nil` | Provider 白名单；`nil` 启用所有已注册 |
| `provider_options` | `table<string, table>` | *见上方* | 按 provider 名称传入的配置；自定义 provider 从 `config.provider_options[provider.name]` 读取自己的选项 |
| `highlights` | `VVTaskPanelHighlights` | *见上方* | 高亮覆盖；`accent` 控制快捷键提示和统计数字 |
| `icons` | `table<string, string>` | *见上方* | 图标配置，可逐项覆盖 |
| `sign` | `table<string, VVTaskSignState>` | *见上方* | Statuscolumn 标记按状态配置 icon / hl |

## Statuscolumn Signs

打开 `package.json` / `deno.json` 时，脚本行的 statuscolumn 自动显示可运行标记，标记随任务状态实时变化：

| 状态 | 图标 | 颜色 | 说明 |
|------|------|------|------|
| idle | `icons.run` | 蓝 (`DiagnosticInfo`) | 未运行，可点击执行 |
| running | `icons.running` | 绿 (`DiagnosticOk`) | 运行中，点击聚焦终端 |
| success | `icons.success` | 绿 (`DiagnosticOk`) | 运行成功 |
| failed | `icons.failed` | 红 (`DiagnosticError`) | 运行失败 |
| stopped | `icons.stopped` | 红 (`DiagnosticError`) | 手动终止 |

**运行方式**：

- 鼠标点击 gutter 区域的标记图标（需安装 [vv-statuscol.nvim](https://github.com/beixiyo/vv-statuscol.nvim)，未安装时点击无效）
- 光标移到脚本行，按 `g<CR>` 或执行 `:VVTaskPanelRunLine`

**覆盖单个状态的图标 / 高亮**：

```lua
opts = {
  sign = {
    running = { icon = '⟳', hl = 'MyCustomRunning' },
  },
}
```

未设置 `icon` 的状态自动复用 `icons` 表同名项

### 自定义 Sign Parser

为新文件类型注册脚本行解析器，即可在 statuscolumn 显示运行标记：

```lua
require('vv-task-panel').register_sign_parser('Cargo.toml', function(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':h')
  local result = {}

  for i, line in ipairs(lines) do
    local name = line:match('^name%s*=%s*"([^"]+)"')
    if name then
      result[#result + 1] = {
        lnum = i,
        name = name,
        argv = { 'cargo', 'run', '--bin', name },
        cwd = dir,
        badge = 'cargo',
      }
    end
  end
  return result
end)
```

---

### 内置 Provider

- `package_json`：npm、pnpm、Yarn 与 Bun 的 package scripts、workspace 和包管理命令
- `deno`：读取 `deno.json` 或 `deno.jsonc` 中的 tasks
- `cargo`：Rust 常用的构建、测试、检查、lint 和格式化命令；`Run main` 通过 Cargo metadata 选择 default/main binary 并传递 required features
- `go`：Go 常用的构建、测试、vet 和格式化命令；Go 在当前构建上下文确认根目录可运行 main package 后显示 `Run main`

### 自定义 Provider

```lua
require('vv-task-panel').register_provider({
  name = 'project_tasks',
  priority = 10, -- 数值越大越先执行，同优先级按名称排序
  detect = function(root, cfg)
    local path = root .. '/tasks.json'
    return vim.uv.fs_stat(path) and { path } or {}
  end,
  parse = function(path, cfg)
    local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
    if not ok or type(data.tasks) ~= 'table' then return nil end

    local dir = vim.fn.fnamemodify(path, ':h')
    local tasks = {}

    for name, cmd in pairs(data.tasks) do
      tasks[#tasks + 1] = { name = name, argv = { vim.o.shell, '-c', cmd }, cmd = cmd }
    end

    return {
      id = path, name = data.name or vim.fn.fnamemodify(dir, ':.'),
      dir = dir, rel_dir = vim.fn.fnamemodify(dir, ':.'),
      badge = 'custom', tasks = tasks,
    }
  end,
})
```
