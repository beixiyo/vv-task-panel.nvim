# Changelog

## 2025-05-22

### Added

- **Statuscolumn signs** — `package.json` / `deno.json` 的脚本行在 statuscolumn 显示可运行标记
  - 标记随任务状态实时变化：idle → running → success / failed / stopped
  - 点击 gutter 或 `gx` / `:VVTaskRunLine` 直接运行脚本；运行中点击聚焦终端
  - 图标复用 `config.icons`，高亮和图标均可通过 `config.sign` 按状态覆盖
- `register_sign_parser(filename, parser)` — 为新文件类型注册脚本行解析器（如 Cargo.toml、Makefile）
- `:VVTaskRunLine` 命令 — 运行当前行的脚本
- `vv-statuscol` 新增 `on_click(fn)` hook — 外部插件可注册 statuscolumn 点击处理器
