# 项目 AI 规则

这是一个名为 `zeta` 的 Flutter 项目。在此仓库中进行修改时，请遵循以下规则。

## 项目背景

- 该应用是一个 Flutter 桌面端 Agent IDE 外壳，入口为 `lib/main.dart`，
  `lib/src/app` 是组合边界。
- 当前支持的生成平台目录为 `linux`、`macos` 和 `windows`。
- 项目通过 `analysis_options.yaml` 使用 `flutter_lints`。
- Dart 和 Flutter 技能安装在 `.agents/skills` 下；在处理 widget 测试、
  集成测试、静态分析、路由、本地化、JSON 序列化、响应式布局、依赖冲突
  或覆盖率等聚焦任务时，请使用相应技能。

## 默认工作流

- 优先进行小而聚焦的改动，并保持与当前 feature-sliced 项目结构一致。
- 编辑 Dart 文件后运行 `dart format .`。
- 结束代码修改前运行 `flutter analyze`。
- 当项目中已有测试，或你新增/修改了行为时，运行 `flutter test`。
- 如果生成文件或平台文件出现了非预期改动，在保留这些改动之前先说明原因。

## Flutter 与 Dart 风格

- 使用现代、可靠的空安全 Dart。
- 尽可能优先使用 `const` 构造函数和不可变 Widget。
- 用小型 Widget 组合 UI；当 `build` 方法过大时，使用私有 Widget 类拆分。
- 保持函数简短且职责单一。
- 成员使用语义清晰的 `camelCase` 命名，类使用 `PascalCase` 命名。
- 文件名使用 `snake_case.dart`。
- 避免使用 `print`；对需要保留在代码中的诊断信息，使用 `dart:developer`
  日志。
- 为公共 API 添加 `///` 文档注释，但避免写仅仅重复显而易见代码含义的注释。
- 新实现的代码优先使用中文注释；公共 API、协议适配、状态机、错误处理和不易
  直观看懂的分支应尽可能补充 `///` 或简短行内注释，同时避免只复述代码字面
  行为的空注释。

## 架构

- 将当前 `lib/src` 结构视为 feature-sliced 架构：
  `app` 负责组合运行时依赖，`core` 保存横切工具，
  `features/<feature>` 拥有 domain/application/data/presentation 代码，
  `ui/core` 保存共享主题和 shell Widget。
- 保持依赖方向清晰：presentation 依赖 application 和 domain 契约；
  application 负责工作流编排；data 实现外部协议与存储；domain 模型保持纯净，
  不依赖 UI。
- 当某个 feature 包天然是代码归属地时，不要再把新功能代码放回顶层宽泛的
  `data`、`domain` 或 `ui` 目录。
- 将 `main.dart` 限制为启动、全局错误日志、桌面窗口初始化和 `runApp`；
  应用装配逻辑放在 `lib/src/app`。
- 保持 `IdeHome` 作为持久 `WindowFrame` 和 `IdeWorkbenchScaffold`
  的唯一组合边界。主页面提供 Navigation、Canvas 和 Inspector 的槽位内容；
  feature 页面不得替换顶层 workbench，也不得把 feature 路由规则挪到共享
  scaffold 中。
- 将 Codex app-server JSON-RPC、JSONL 历史解析、provider 配置等具体协议细节
  保留在 agent 数据层和 mapper 中。UI 代码应消费中立的 domain 事件和 provider
  契约。
- Provider 原始 sourceId 只作协议 metadata；entryId、message segment、reasoning
  phase 和 narrative boundary 必须由对应 data adapter/reducer 决定。共享 decoder
  保持无状态，EventBuffer/TimelineStore 只按规范化 id dumb merge，不得猜 identity、
  增加厂商分支或要求新增 Provider 修改 Store。live/history/replay 必须使用隔离的
  reducer 实例。
- 对于简单的本地 UI 状态，优先使用 Flutter 内建能力，例如 `StatefulWidget`、
  `ValueNotifier`、`ValueListenableBuilder`、`FutureBuilder` 和
  `StreamBuilder`。
- 当状态变得共享或复杂时，将职责拆分为：不可变 domain state、负责异步编排的
  application controller，以及负责渲染的 presentation view model 或
  listenable signal。
- 对可能被后续请求覆盖的异步加载使用 token/version 守卫，并在通知监听者前检查
  disposed 状态。
- 除非 API 明确要求可变，否则对集合状态暴露不可修改快照。
- 为了可测试性，优先使用构造函数依赖注入。
- 只有在明确要求或 feature 有充分理由时，才引入第三方状态管理。

## 依赖

- 运行时依赖使用 `flutter pub add <package>` 添加。
- 开发依赖使用 `flutter pub add dev:<package>` 添加。
- 添加新包前，先检查 Flutter 或 Dart 是否已经提供了足够简单的内建方案。
- 在最终总结中说明每个新增依赖的用途。

## UI、布局与可访问性

- 主题系统建立在 `shadcn_flutter` 和 `lib/src/ui/core/` 下的设计令牌之上：
  `IdeColors`、`IdeRadius`/`IdeEffects`、`IdeSpacing`、`IdeTextStyles` 和
  `IdeMotion`。Graphite tokens 通过 `IdeThemeScope` 作为语义真源；
  `sf.ThemeData` 仅作为第三方 Widget 的投影。不要在 feature 代码中使用
  Material `ThemeData`/`ColorScheme.fromSeed` 样式、裸 `Color(0x...)`
  数值、手写 `BoxShadow` 列表或临时拼装的
  `BorderRadius.circular(...)`。
- 导入 `shadcn_flutter` 时只能使用 `sf` 别名
  （`import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;`）。
  不要再使用已移除 `shadcn_ui` 包中的裸 `Shad*` API。
- 亮度应通过 `IdeThemeScope.of(context).brightness` 或
  `sf.Theme.of(context).brightness` 获取。语义令牌优先使用
  `IdeColors.of(context)` / `IdeTextStyles.of(context)`。
- IDE 通知统一使用 `lib/src/ui/core/ide_toast.dart` 中的 `showIdeToast`；
  不要在 feature 页面中临时调用 `sf.showToast`。
- 构建既适用于桌面窗口尺寸，也适用于窄视口的响应式布局。
- 在主页面切换时保留 Agent Canvas。稳定 key 应挂在会随槽位出现或消失而移动的
  Flex 子节点上；页面切换测试必须保护 Agent 状态、草稿、滚动位置、面板宽度和
  面板可见性。
- 使用 `LayoutBuilder`、`Flexible`、`Expanded`、`Wrap`、滚动视图和
  builder 构造方式来避免溢出。
- 在引入 feature 局部视觉原语前，优先复用 `ui/core` 中的基础组件，如
  `Pane`、`PanelCard`、`PaneInteractiveSurface`、`IdeTabs`/`IdeTab`、
  `IdeChip`、`IdeContextMenu`、`IdeStatusCard`、`IdeCollapsibleCard`
  以及窗口框架。
- 保持 IDE UI 紧凑、信息密集且易于扫读。长文件路径、thread 标题、工具摘要和
  状态文本必须使用有界布局和省略号。
- 对重复出现的交互式 timeline、thread 和文件树行使用稳定的 `ValueKey`。
  对高开销或高频刷新区域（如流式 turn、高亮代码和 diff 细节）添加
  `RepaintBoundary`。
- 确保在系统文字较大时文本仍然可读。
- 为非文本控件和重要的自定义 Widget 添加语义标签。

## 导航

- 对于简单、短生命周期的流程，继续使用 `Navigator`。
- 仅在应用需要声明式路由、深链接或多个持久页面时使用 `go_router`。

## 数据与代码生成

- 对简单的本地数据优先使用普通 Dart 模型。
- 持久化 JSON 必须带版本且具备容错性。`tryDecode` 风格的读取器必须能处理缺失
  字段、损坏内容和旧版本，而不阻塞应用启动。
- 全局 provider 配置必须与项目/会话状态分离。
- 由 Zeta 拥有的配置、状态、派生索引、日志和保留缓存都放在 `~/.zeta`
  下；feature store 通过 `app` 组合层接收具体文件，而不是自行解析 HOME。
- 将旧版 Zeta 的 SharedPreferences key 仅视作迁移输入。迁移必须幂等、以目标
  文件优先，并记录在 `~/.zeta/state/migration_marker.json` 中。
- 严禁移动或重写 `~/.codex`、`~/.grok`、`~/.cursor`、项目 `.cursor`
  目录或用户源码工作区下的 Agent CLI 配置或会话历史。退役 Cursor 遗留的
  `cursor_sessions.json` 只作为受保护用户数据保留，不得读取、迁移或改写。
- 不要将 provider 原始 payload 直接泄漏到 presentation；应在数据源附近补充
  mapper 或 codec 辅助逻辑。
- 如果 JSON 模型变复杂或改为 API 驱动，优先使用 `json_serializable` 和
  `json_annotation`。
- 使用代码生成时，确保 `build_runner` 已安装，并执行：

```sh
dart run build_runner build --delete-conflicting-outputs
```

## 测试

- 使用 `flutter_test` 为 UI 行为补充 widget 测试。
- 为非 UI 逻辑补充单元测试。
- 集成测试仅用于端到端用户流程。
- 优先使用 fake 或 stub，而不是 mock；只有在确实需要时才引入 mock 包。
- 测试结构遵循 Arrange、Act、Assert。

## 仓库卫生

- 除非任务明确针对原生桌面行为，否则保留 Flutter 生成的平台目录。
- 不要提交构建产物或 `.dart_tool` 内容。
- 当项目引入路由、本地化、全局状态管理、网络、资源或正式的 feature/module
  结构时，更新此文件。
- 当架构边界发生变化时，保持 `docs/engineering_standards.md`、
  `docs/developer_guide.md` 和 `docs/design_document.md` 内容一致。

## Git 提交信息
每次你修改或更新完代码后，必须在回复的最后附加一个【Git 提交信息】模块。
该模块要求如下：
1. 使用标准化的 Conventional Commits 格式（如 feat:, fix:, docs:, refactor:, chore: 等）。
2. 用一句简短的中文/英文概括主要修改（不超过 50 个字符）。
3. 如果有必要，换行提供具体的修改点列表（Body）。
4. 使用独立的代码块包裹，确保我可以一键复制直接用于 `git commit -m` 或 Git 提交面板。

输出示例：
### 📝 Git Commit Message
```sh
feat(auth): 优化登录接口的错误处理逻辑

- 增加了对验证码过期的状态码拦截
- 修复了前端重复提交请求的 bug
```
