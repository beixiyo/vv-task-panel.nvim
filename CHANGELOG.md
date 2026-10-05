# Changelog

## 0.2.3 - 2026-10-04

### Added

- 打开面板或 `r` 重扫时显示扫描动画，完成、失败、被新扫描取代或关闭面板时清除
- 新增 `require('vv-task-panel.ui').is_discovering()` 查询扫描状态

### Changed

- 扫描时先显示 `Scanning…` 与加载提示，无已知分组时计数显示 `…`，不再误报为 0

## 0.2.2 - 2026-08-22

### Fixed

- package.json workspace 扫描正确应用 `!` 排除 glob

## 0.2.1 - 2026-08-10

### Added

- Cargo 根据 metadata 选择 `default-run` / `src/main.rs` binary 并传递 required features，Go 检测当前构建上下文的根目录 `main` package，两者均提供 `Run main`

### Changed

- 任务发现与面板刷新改为可取消的异步流程

### Fixed

- 过期结果不再覆盖最新分组或已关闭面板，provider 回调在主事件循环执行
- Cargo / Go 缓存随源码、manifest 与构建上下文变化失效，仅在查询成功且确认可运行入口时显示 `Run main`

## 0.2.0 - 2026-07-27

### Breaking

- `npm` provider 更名为 `package_json`，相关 `providers` 与 `provider_options` 配置需改用新名称
- 运行脚本的 buffer-local 快捷键从 `gx` 改为 `g<CR>`

### Added

- 新增 Deno provider，读取项目根目录 `deno.json` / `deno.jsonc` tasks
- 新增 `provider_options.<name>.filter(task)`、`sort` 与 presets，支持任务过滤、源文件顺序及项目级常用命令覆盖

### Changed

- package.json 按 workspace 声明发现子包，根据 lockfile 选择 npm、pnpm、Yarn 或 Bun
- 面板优先显示任务名并截断长命令，快捷键与统计数字支持强调色；通知、错误和快捷键说明统一为英文

### Fixed

- Deno task 发现正确处理 JSONC 注释与尾随逗号
- 任务面板与 statuscolumn 的 `filter(task)` 使用一致的文件、目录与源码行上下文

## 0.1.2 - 2026-07-26

### Added

- 主面板改用 `vv-utils.tree_panel`，新增 `state`、`mappings`、`render`、`help`、`on_attach` 配置以自定义状态、交互与渲染

### Changed

- Provider 按 `priority` 降序、名称升序发现任务，顺序不再随机

### Fixed

- 重复 `setup()` 或 `disable()` 释放旧订阅、autocmd 与插件快捷键，不删除其他插件后来覆盖的映射
- 内置 package.json / deno.json parser 仅在对应 JSON filetype 生效，自定义 parser 仍不受 filetype 限制
- 重复 `setup()` 正确应用新面板配置，`disable()` 同时关闭主面板、历史浮窗及计时器
- `setup()` 后注册 sign parser 立即生效，无需重新 setup
- 脚本定位不再被命令字符串中的类 key 文本干扰，配置类型允许只传需要覆盖的字段

## 0.1.1 - 2026-07-19

### Changed

- 主面板与任务列表 filetype 改为 `vv-task-panel` 与 `vv-task-panel-tasks`，避免命名冲突

## 0.1.0 - 2026-07-13

### Fixed

- 启动失败正确显示「失败」，不再卡在运行中或反复拦截 `:q`
- 重跑同一脚本不再堆积隐藏 buffer 与局部 autocmd，每个脚本仅保留最近一条已结束记录，避免历史拖慢渲染
- workspace 支持裸 `*`、中间通配与含零段匹配的 `**`，跳过 `node_modules` 与点目录，`.` 不再重复显示根包
- 脚本标记正确处理命令内花括号、JSONC 注释与尾随逗号、内联脚本及单行 package.json，不再误标或漏标
- 脚本标记失效后运行与点击不再报错，经文件树预览首次打开配置文件也能显示标记
- 外部命令关闭面板不再泄漏计时器或残留引用，帮助浮窗改用统一 vv-utils 风格
- 统一包管理器探测，运行标记与面板 badge 不再判定不一致
- 自定义 provider 产生多个 `(root)` 或缺省 `rel_dir` 时不再因排序报错而打不开面板

## 2025-05-22

### Added

- package.json / deno.json 脚本行显示随任务状态变化的 statuscolumn 标记，支持自定义图标与高亮
- 点击 gutter、`gx` 或新增 `:VVTaskPanelRunLine` 可运行脚本，运行中点击聚焦终端
- 新增 `register_sign_parser(filename, parser)` 注册其他文件类型的脚本解析器
- `vv-statuscol` 新增 `on_click(fn)`，允许外部插件注册 statuscolumn 点击处理器
