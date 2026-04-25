# vv-task-panel.nvim

可扩展的任务面板，类似 VS Code 的 Task 面板。通过 Provider 机制扫描项目配置文件，发现并管理可执行任务。

![screenshot](https://img.shields.io/badge/screenshot-placeholder-lightgrey)

## 特性

- 侧边面板展示项目任务，支持折叠/展开
- 内置 npm provider（自动识别 pnpm / yarn / bun / npm）
- workspace-aware 扫描（支持 monorepo）
- 终端窗口运行任务，支持 bottom / right / float 三种位置
- 任务列表浮窗：查看、聚焦、停止、重启、销毁
- 退出保护：有任务运行时确认退出
- 可扩展 Provider API

## 依赖

- [vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim) — npm provider 使用 `vv-utils.yaml` 解析 `pnpm-workspace.yaml`

## 安装

### lazy.nvim

```lua
{
  'beixiyo/vv-task-panel.nvim',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  cmd = { 'VVTaskPanel', 'VVTaskPanelOpen' },
  opts = {
    -- 配置项见下方
  },
}
```

### 手动

```lua
require('vv-task-panel').setup({
  -- 配置项见下方
})
```

## 配置

所有可选项及其默认值：

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `width` | `integer` | `44` | 面板宽度 |
| `position` | `'left' \| 'right'` | `'right'` | 面板位置 |
| `exclude_dirs` | `string[]` | `node_modules, .git, dist, build, .next, .turbo, .cache, coverage, .nuxt, out` | 扫描时跳过的目录 |
| `scan_strategy` | `'workspace' \| 'walk'` | `'workspace'` | 扫描策略：`workspace` 仅扫描 workspace 定义的目录；`walk` 递归遍历 |
| `max_depth` | `integer` | `8` | `walk` 策略的最大递归深度 |
| `term_position` | `'bottom' \| 'right' \| 'float'` | `'bottom'` | 任务终端窗口位置 |
| `term_height` | `integer` | `15` | bottom 模式下终端高度 |
| `term_width` | `integer` | `80` | right 模式下终端宽度 |
| `providers` | `string[] \| nil` | `nil` | Provider 白名单，`nil` 表示启用所有已注册的 |
| `icons` | `table<string, string>` | *见下方* | 图标配置 |

### 默认图标

```lua
icons = {
  pkg_open   = '',   -- 展开的组
  pkg_closed = '',   -- 折叠的组
  package    = '󰏖',   -- 包图标
  running    = '',   -- 运行中
  success    = '',   -- 成功
  failed     = '',   -- 失败
  pending    = '',   -- 待运行
  header     = '󰆍',   -- 面板标题
}
```

## 内置 Provider

### npm

自动扫描 `package.json`，按 lockfile 选择包管理器：

| lockfile | 包管理器 |
|----------|---------|
| `pnpm-lock.yaml` | pnpm |
| `bun.lockb` / `bun.lock` | bun |
| `yarn.lock` | yarn |
| `package-lock.json` | npm |

**workspace 策略**（默认）：读取 `pnpm-workspace.yaml` 或 `package.json` 的 `workspaces` 字段，展开 glob 模式收集子包。

**walk 策略**：递归遍历目录树查找 `package.json`。

## 自定义 Provider

通过 `register_provider` 注册自定义 provider：

```lua
---@class Provider
---@field name string           Provider 名称
---@field priority? integer     优先级
---@field detect fun(root: string, config: VVTaskPanelConfig): string[]  扫描配置文件路径
---@field parse fun(path: string, config: VVTaskPanelConfig): TaskGroup|nil  解析为任务组
```

### Deno 示例

```lua
require('vv-task-panel').register_provider({
  name = 'deno',
  detect = function(root, cfg)
    return vim.fs.find('deno.json', {
      path = root, type = 'file', limit = math.huge,
    })
  end,
  parse = function(path, cfg)
    local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
    if not ok or type(data.tasks) ~= 'table' then return nil end
    local dir = vim.fn.fnamemodify(path, ':h')
    local rel = vim.fn.fnamemodify(dir, ':.')
    local tasks = {}
    for name, cmd in pairs(data.tasks) do
      table.insert(tasks, {
        name = name,
        argv = { 'deno', 'task', name },
        cmd = cmd,
      })
    end
    return {
      id = path,
      name = data.name or rel,
      dir = dir,
      rel_dir = rel,
      badge = 'deno',
      tasks = tasks,
    }
  end,
})
```

## 命令

| 命令 | 说明 |
|------|------|
| `:VVTaskPanel` | 切换面板 |
| `:VVTaskPanelOpen` | 打开面板 |
| `:VVTaskPanelClose` | 关闭面板 |
| `:VVTaskPanelRefresh` | 重新扫描 workspace |
| `:VVTaskPanelTasks` | 打开任务列表浮窗 |

## API

| 函数 | 说明 |
|------|------|
| `require('vv-task-panel').setup(opts)` | 初始化 |
| `require('vv-task-panel').open()` | 打开面板 |
| `require('vv-task-panel').close()` | 关闭面板 |
| `require('vv-task-panel').toggle()` | 切换面板 |
| `require('vv-task-panel').refresh()` | 重新扫描 |
| `require('vv-task-panel').tasks()` | 打开任务列表浮窗 |
| `require('vv-task-panel').register_provider(p)` | 注册自定义 Provider |

## 面板快捷键

| 按键 | 说明 |
|------|------|
| `<CR>` | 运行 task / 展开组 / 聚焦运行中的任务 |
| `<Tab>` | 折叠/展开当前组 |
| `r` | 重新扫描 workspace |
| `R` | 展开全部 |
| `M` | 折叠全部 |
| `t` | 打开任务列表浮窗 |
| `q` / `<Esc>` | 关闭面板 |
| `?` | 显示帮助 |

## 任务列表快捷键

| 按键 | 说明 |
|------|------|
| `<CR>` | 打开任务输出终端 |
| `d` | 停止任务 |
| `D` | 销毁任务 |
| `r` | 重启任务 |
| `q` / `<Esc>` | 关闭浮窗 |

## 任务生命周期

```
discover → run → focus → stop → dispose
   │         │      │       │       │
   │         │      │       │       └─ 停止进程 + 删除 buffer + 移除记录
   │         │      │       └─ jobstop() 终止进程
   │         │      └─ 聚焦到已有终端窗口或新开窗口
   │         └─ 创建终端 buffer + jobstart() 执行命令
   └─ Provider.detect() + Provider.parse() 扫描项目
```

## 高亮组

| 高亮组 | 默认 link | 作用 |
|--------|----------|------|
| `VVTaskPanelHeader` | `Title` | 面板标题 |
| `VVTaskPanelHeaderIcon` | `Constant` | 标题图标 |
| `VVTaskPanelChevron` | `Comment` | 折叠箭头/分隔线 |
| `VVTaskPanelGroupIcon` | `MiniIconsOrange` | 组图标 |
| `VVTaskPanelGroup` | `Directory` | 组名 |
| `VVTaskPanelPath` | `Comment` | 路径 |
| `VVTaskPanelBadge` | `Special` | 徽标文字 |
| `VVTaskPanelBadgeBr` | `Comment` | 徽标括号 |
| `VVTaskPanelTask` | `Function` | 任务名 |
| `VVTaskPanelCmd` | `Comment` | 命令预览 |
| `VVTaskPanelRunning` | `DiagnosticWarn` | 运行中状态 |
| `VVTaskPanelSuccess` | `DiagnosticOk` | 成功状态 |
| `VVTaskPanelFailed` | `DiagnosticError` | 失败状态 |
| `VVTaskPanelPending` | `Comment` | 待运行状态 |
| `VVTaskPanelUptime` | `DiagnosticHint` | 运行时长 |

## Testing

Smoke test (zero deps, runs in `-u NONE`):

```bash
nvim --headless -u NONE -l tests/test_smoke.lua
```

Expected: trailing line `X passed, 0 failed`.
