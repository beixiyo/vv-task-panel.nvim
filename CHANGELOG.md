# Changelog

## [0.1.2] - 2026-07-26

### Added

- 主面板改用 `vv-utils.tree_panel`
- 新增 `state`、`mappings`、`render`、`help` 与 `on_attach` 配置，可注入持久状态并覆盖主面板交互和渲染

### Changed

- 配置、provider 注册、任务发现、包管理器探测和运行记录拆分为独立 owner
- 任务历史浮窗与高亮定义从主 UI 模块拆分，删除已由通用 tree panel 取代的旧帮助模块
- Provider 发现顺序改为按 `priority` 降序、名称升序执行，不再依赖 Lua table 的无序遍历

### Fixed

- 重复 `setup()` 或 `disable()` 会释放旧的 statuscolumn 点击订阅、autocmd 与插件拥有的 buffer-local 快捷键，且不会删除后来由其他插件覆盖的映射
- 内置 `package.json` / `deno.json` parser 只在对应 JSON filetype 生效；自定义 parser 仍保持 filetype 无关
- 重复 `setup()` 会销毁旧 tree panel 实例，使新的宽度、位置、状态、渲染器、快捷键和帮助配置实际生效
- `disable()` 会同时关闭主面板、任务历史浮窗及其计时器，不再残留 UI 资源
- `setup()` 后注册的 sign parser 会立即安装自己的 buffer 事件，无需再次 setup
- JSON / JSONC 脚本行使用字符串与嵌套结构感知的 token 定位，命令字符串中的类 key 文本不再抢占真实脚本位置
- 用户配置与解析后配置使用独立类型，允许只传需要覆盖的字段

## [0.1.1] - 2026-07-19

### Changed

- 主面板与任务列表的 filetype 统一加 `vv-` 命名空间，分别改为 `vv-task-panel` 与 `vv-task-panel-tasks`，避免与其他任务面板发生名称冲突

## [0.1.0] - 2026-07-13

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
- 脚本行解析改为逐行 `gmatch` 全部 key 并扫描 `"scripts":` 声明行本身，与 `"scripts": {` 同行书写的内联脚本、以及压缩成单行的 `package.json` 不再漏打运行标记
- `core.discover()` 的分组排序比较器改为全序且 nil 安全（nil 视作 `''`，仅一侧为 `(root)` 时才排前），自定义 provider 产出多个 `(root)` 或缺省 `rel_dir` 时不再触发 `invalid order function for sorting` / `attempt to compare nil with string` 导致面板打不开

## 2025-05-22

### Added

- **Statuscolumn signs** — `package.json` / `deno.json` 的脚本行在 statuscolumn 显示可运行标记
  - 标记随任务状态实时变化：idle → running → success / failed / stopped
  - 点击 gutter 或 `gx` / `:VVTaskPanelRunLine` 直接运行脚本；运行中点击聚焦终端
  - 图标复用 `config.icons`，高亮和图标均可通过 `config.sign` 按状态覆盖
- `register_sign_parser(filename, parser)` — 为新文件类型注册脚本行解析器（如 Cargo.toml、Makefile）
- `:VVTaskPanelRunLine` 命令 — 运行当前行的脚本
- `vv-statuscol` 新增 `on_click(fn)` hook — 外部插件可注册 statuscolumn 点击处理器
