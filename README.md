<div align="center">

# vv-task-panel.nvim

English | <a href="./README.zh-CN.md">中文</a>

<img src="https://github.com/beixiyo/vv-task-panel.nvim/releases/download/assets-2026-07-25/vv-task-panel.png" alt="vv-task-panel demo" width="900" />

Want my Neovim config? See <a href="https://github.com/beixiyo/dotfiles">dotfiles</a>.

<em>An extensible task panel with project-script discovery, terminal execution, and monorepo support</em>

<br />

<img src="https://img.shields.io/badge/Neovim-0.11+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.11+" />
<img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />

</div>

---

## Requirements

Task discovery itself is implemented in Lua. Running a discovered script requires the package manager selected from the nearest lockfile:

- [pnpm](https://github.com/pnpm/pnpm) for `pnpm-lock.yaml`
- [Bun](https://github.com/oven-sh/bun) for `bun.lockb` or `bun.lock`
- [Yarn](https://github.com/yarnpkg/berry) for `yarn.lock`
- [npm](https://github.com/npm/cli) for `package-lock.json`, or when no supported lockfile is found
- [Deno](https://github.com/denoland/deno) when running tasks from `deno.json` or `deno.jsonc`
- [Cargo](https://doc.rust-lang.org/cargo/) for Rust presets and `Run main`; the latter uses `cargo metadata` to select the package's `default-run` target or the `src/main.rs` binary and passes its required features
- [Go](https://go.dev/) for Go presets and `Run main`; the latter is shown only when `go list` selects a main package with `func main()` for the active build context

## Installation

```lua
{
  'beixiyo/vv-task-panel.nvim',
  dependencies = {
    'beixiyo/vv-utils.nvim',
    { 'beixiyo/vv-statuscol.nvim', optional = true },
  },
  cmd = { 'VVTaskPanel', 'VVTaskPanelOpen' },
  ---@type VVTaskPanelConfig
  opts = {
    width = 44,
    position = 'right',
    state = nil,              -- Optional VVStateHandle; defaults to vv-task-panel/main
    mappings = {},            -- Override vv-utils tree_panel mappings
    render = {},              -- Override winbar/header/node/empty renderers
    exclude_dirs = {
      'node_modules', '.git', 'dist', 'build', '.next',
      '.turbo', '.cache', 'coverage', '.nuxt', 'out',
    },
    scan_strategy = 'workspace',
    max_depth = 8,
    term_position = 'bottom',
    term_height = 15,
    term_width = 80,
    providers = nil,
    provider_options = {
      package_json = {
        sort = true,
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
          run = true, -- Shown when Cargo confirms a runnable default/main binary
          check = true,
          build = true,
          test = true,
          clippy = true,
          fmt = false,
        },
      },
      go = {
        presets = {
          run = true, -- Shown when Go confirms a runnable root main package
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
      pkg_open = '', pkg_closed = '', package = '󰏖', running = '●',
      success = '', failed = '', stopped = '●', pending = '',
      header = '󰆍', arrow = '→', run = '',
    },
    sign = {
      idle = { hl = 'VVTaskSignIdle' }, running = { hl = 'VVTaskSignRunning' },
      success = { hl = 'VVTaskSignSuccess' }, failed = { hl = 'VVTaskSignFailed' },
      stopped = { hl = 'VVTaskSignStopped' },
    },
  },
}
```

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `width` | `integer` | `44` | Initial panel width; manual resize is persisted through `vv-utils.state` |
| `position` | `'left' \| 'right'` | `'right'` | Panel side |
| `state` | `VVStateHandle?` | `nil` | Optional state container; defaults to `vv-task-panel/main` |
| `mappings` | `VVTreePanelMappings` | `{}` | Override or disable shared tree-panel mappings |
| `render` | `VVTreePanelRenderers` | `{}` | Override `winbar`, `header`, `node`, or `empty` rendering |
| `help` | `false \| VVTreePanelHelpOptions` | `nil` | Customize or disable the shared `g?` help panel |
| `on_attach` | `fun(panel, buf)?` | `nil` | Add caller-owned buffer behavior after default mappings |
| `exclude_dirs` | `string[]` | `{ 'node_modules', '.git', ... }` | Directories skipped while scanning |
| `scan_strategy` | `'workspace' \| 'walk'` | `'workspace'` | Read workspace definitions or recursively walk directories |
| `max_depth` | `integer` | `8` | Maximum depth for the walk strategy |
| `term_position` | `'bottom' \| 'right' \| 'float'` | `'bottom'` | Task terminal placement |
| `term_height` | `integer` | `15` | Terminal height in bottom mode |
| `term_width` | `integer` | `80` | Terminal width in right mode |
| `providers` | `string[]?` | `nil` | Provider allowlist; `nil` enables every registered provider |
| `provider_options` | `table<string, table>` | See above | Provider-owned options; custom providers receive the full config and can read `config.provider_options[provider.name]` |
| `highlights` | `VVTaskPanelHighlights` | See above | Highlight overrides; `accent` colors shortcut hints and summary numbers |
| `icons` | `table<string, string>` | See above | Individually overridable icons |
| `sign` | `table<string, VVTaskSignState>` | See above | Status-column icon and highlight settings by state |

## Status-column signs

When `package.json` or `deno.json` is open, executable script lines receive status-column signs that update with task state.

| State | Icon | Color | Behavior |
|---|---|---|---|
| idle | `icons.run` | Blue (`DiagnosticInfo`) | Ready to run |
| running | `icons.running` | Green (`DiagnosticOk`) | Running; clicking focuses the terminal |
| success | `icons.success` | Green (`DiagnosticOk`) | Completed successfully |
| failed | `icons.failed` | Red (`DiagnosticError`) | Failed |
| stopped | `icons.stopped` | Red (`DiagnosticError`) | Stopped manually |

Run a task by clicking its gutter sign when `vv-statuscol.nvim` is installed, or place the cursor on the script line and press `g<CR>` or run `:VVTaskPanelRunLine`.

Override a state independently:

```lua
opts = {
  sign = {
    running = { icon = '⟳', hl = 'MyCustomRunning' },
  },
}
```

A state without an explicit `icon` reuses the same-named entry from `icons`.

### Custom sign parser

Register a parser for another file type to expose executable lines in the status column:

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

### Built-in providers

- `package_json`: package scripts, workspaces, and package-manager maintenance commands for npm, pnpm, Yarn, and Bun
- `deno`: tasks from `deno.json` or `deno.jsonc`
- `cargo`: common Rust build, test, check, lint, and format commands; `Run main` uses Cargo metadata to select the default/main binary and required features
- `go`: common Go build, test, vet, and format commands; `Run main` is shown when Go confirms a root `main` package with `func main()` in the active build context

### Custom provider

```lua
require('vv-task-panel').register_provider({
  name = 'project_tasks',
  priority = 10, -- Higher values run first; equal priorities sort by name
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
