# Changelog

## Unreleased

### Fixed

- 任务启动失败（如 pnpm 不在 PATH）时状态不再卡在「运行中」、`:q` 不再被反复拦截，现会正确显示「失败」
- 反复运行同一脚本不再持续堆积隐藏 buffer 和 buffer 局部 autocmd（重跑前回收同任务的已结束旧实例）
- 任务记录不再无限增长拖慢面板渲染（每个脚本只保留最近一条已结束记录）
- workspace 通配现支持裸 `*`、中间通配 `packages/*/lib`、`**` globstar（含零段匹配），子包不再被静默漏扫
- workspace 单层通配现统一跳过 `node_modules` 与点目录（与递归分支一致），`.` 模式不再让根包重复显示
- 脚本识别改用真正的 JSON 解析，脚本值里的字面花括号不再让运行标记蔓延到 `devDependencies`；带注释/尾随逗号的 `deno.jsonc` 也能正确识别
- 脚本标记的 extmark 失效时不再因守卫漏判 `pos[1]` 而报错（`update_sign` 与 `gx`/点击的 `find_task_at_line` 两处都已补判空）
- 用外部命令（`:q` / `<C-w>c` / `:only`）关闭任务面板时不再泄漏计时器、不再残留陈旧引用
- 任务面板帮助浮窗（按 `?`）改用统一的 vv-utils 帮助面板渲染，风格与 vv-git / vv-explorer 一致
- 统一包管理器探测（`detect_pm` 下沉到 core），消除 sign 行与面板 badge 对同一脚本判定不同包管理器的隐患
- 经文件树（vv-explorer 等预览式打开）首次打开 `package.json` / `deno.json` 时也能渲染脚本运行标记：sign autocmd 增加 `BufEnter`，不再因预览 `bufload` 的 `BufReadPost` 被 autocmd 嵌套规则吞掉而漏打

## 2025-05-22

### Added

- **Statuscolumn signs** — `package.json` / `deno.json` 的脚本行在 statuscolumn 显示可运行标记
  - 标记随任务状态实时变化：idle → running → success / failed / stopped
  - 点击 gutter 或 `gx` / `:VVTaskPanelRunLine` 直接运行脚本；运行中点击聚焦终端
  - 图标复用 `config.icons`，高亮和图标均可通过 `config.sign` 按状态覆盖
- `register_sign_parser(filename, parser)` — 为新文件类型注册脚本行解析器（如 Cargo.toml、Makefile）
- `:VVTaskPanelRunLine` 命令 — 运行当前行的脚本
- `vv-statuscol` 新增 `on_click(fn)` hook — 外部插件可注册 statuscolumn 点击处理器
