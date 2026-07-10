# 开发者文档

最后更新：2026-07-10

## 1. 项目简介

Zeta 是一个 Flutter Desktop 项目，当前支持 macOS、Linux 和 Windows 平台目录。应用主入口在 `lib/main.dart`，核心界面是三栏 Agent IDE 工作台。

## 2. 环境要求

- Flutter SDK，需兼容 `pubspec.yaml` 中的 Dart SDK 约束 `^3.12.2`。
- 支持 Flutter desktop 的本地开发环境。
- 如需运行默认 Agent provider，需要本机可执行 `codex app-server`；未指定
  `--listen` 时使用 stdio。
- Codex 适配层按 pinned schema 开发；协议版本与升级流程见
  [Codex app-server 协议版本锁定](./codex_app_server_protocol.md)。

## 3. 常用命令

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter run -d macos
```

重新导出 Codex app-server JSON Schema（协议升级 / 审计时）：

```sh
# macOS / Linux / Git Bash
./tool/gen_codex_schema.sh

# Windows PowerShell
./tool/gen_codex_schema.ps1
```

对真实 `codex app-server --stdio` 做 Phase 1 冒烟（需本机 pinned `0.142.x`）：

```sh
python tool/smoke_codex_app_server.py
# 可选：python tool/smoke_codex_app_server.py --codex-bin "C:\...\codex.exe" --timeout 180
```

Linux 或 Windows 开发时，将 `flutter run` 的设备改为对应桌面设备。

## 4. 目录结构

```text
lib/
  main.dart
  src/
    app/
    core/
    features/
      agent/
        application/
        data/
        domain/
        presentation/
      agent_management/
        application/
        data/
        domain/
        presentation/
      ide_session/
        application/
        data/
        domain/
      project_threads/
        application/
        domain/
        presentation/
      workspace/
        application/
        domain/
        presentation/
    ui/
      core/
      features/ide/
test/
docs/
tool/
third_party/
  codex_app_server_schema/
linux/
macos/
windows/
```

重要模块：

- `lib/src/app`：应用装配、窗口启动、菜单桥接、shell controller 和常量。
- `lib/src/core`：日志、路径工具等跨功能基础设施。
- `lib/src/features/agent`：Agent provider 抽象、Codex data source、事件映射、对话状态和 Agent pane。
- `lib/src/features/agent_management`：Codex CLI 检测、在线版本查询、账号/模型诊断、
  TOML 配置安全编辑、磁盘日志读取和 Agent 管理页面。
- `lib/src/features/ide_session`：IDE 会话模型、状态构建、恢复协调和持久化。
- `lib/src/features/project_threads`：项目 thread 列表状态、恢复快照、分页控制器和 view model。
- `lib/src/features/usage_statistics`：Codex 全局历史读取、版本化派生索引、统计聚合
  controller、响应式统计页面和任务详情抽屉。
- `lib/src/features/workspace`：工作区目录规则、文件树构建、文件节点映射和 file tree pane。
- `lib/src/ui/core`：主题、窗口框架、pane、panel、empty state 和状态标签等共享 UI 原语。
- `lib/src/ui/features/ide`：IDE shell 视图、项目列表 pane 和 active provider controller。
- `test/src`：app、core、feature 各层的单元测试和 widget 测试。
- `tool/`：仓库维护脚本（含 Codex schema 导出）。
- `third_party/codex_app_server_schema/`：pinned Codex app-server JSON Schema 快照。

## 5. 开发流程

1. 修改前先理解目标模块的现有职责和依赖方向。
2. Dart 文件改动后运行 `dart format .`。
3. 完成代码改动后运行 `flutter analyze`。
4. 修改行为或新增逻辑时运行 `flutter test`，并补充对应测试。
5. 如果平台生成文件发生变化，确认是否由 Flutter 工具产生，并在提交说明中解释原因。

## 6. 编码约定

- 使用现代空安全 Dart。
- 优先使用 `const` 和不可变 widget。
- UI 状态简单时使用 Flutter 内建机制，例如 `StatefulWidget`、`ChangeNotifier`、`ValueListenableBuilder`。
- 复杂状态按“不可变 domain state + application controller + presentation view model/listenable signal”拆分。
- 对可能被后续请求覆盖的异步流程使用 token 或版本号隔离旧结果。
- 对外暴露集合时优先返回不可变集合或 unmodifiable view。
- 公共 API 添加 `///` 文档。
- 新实现中，对公共 API、协议适配、状态机、错误处理和不直观分支优先补充中文注释。
- 不使用 `print`，需要保留的诊断信息使用 `dart:developer` 或项目日志封装。

更完整的架构和评审规则见 [工程规范](./engineering_standards.md)。

## 7. Agent provider 开发指南

新增 provider 时：

1. 在领域层确认现有 `AgentProvider` 接口是否足够表达新 provider 能力。
2. 在 data 层新增具体 provider 实现，不让 UI 直接依赖 provider 协议。
3. 把 provider 原始事件映射成 `AgentEvent`、`AgentToolCall`、`AgentPermissionRequest`、`AgentThreadSummary` 等中立模型。
4. 在 factory 中接入 provider kind。
5. 添加单元测试覆盖初始化、session、turn、权限请求和错误映射。

注意：默认策略应保持保守，不自动授权命令执行或文件写入。

Agent 管理适配与会话 provider 适配保持分层：管理 data 层可以执行 `--version`、
`login status` 和 app-server `initialize` / `model/list` 等无计费探测，但不得通过
真实模型 turn 做自动连接测试。配置文件保存必须走
`CodexAgentManagementRepository` 的校验、冲突检测、备份和临时文件替换流程；
日志必须在 data 层脱敏后再交给 presentation。

修改 Codex 适配层前，先对照
[`third_party/codex_app_server_schema`](../third_party/codex_app_server_schema/)
与 [协议版本锁定文档](./codex_app_server_protocol.md)；升级 CLI 时先
`./tool/gen_codex_schema.sh --diff`（或 PowerShell `-Diff`）再改代码。

## 8. UI 开发指南

- 保持三栏工作台的职责边界：Projects 管项目和 threads，Agent 管对话，Files 管文件上下文。
- 复杂交互逻辑优先放入 view model，widget 层负责渲染和用户输入。
- 桌面工具界面需要保持信息密度，但文本必须可读，按钮和状态提示不能挤压变形。
- 非文本按钮应提供 tooltip。
- 新增面板或重复项时优先复用 `Pane`、`PanelCard`、主题常量和现有间距。
- UI 组件库使用 `shadcn_flutter`，必须 `as sf` 导入；Graphite 语义 token 通过
  `IdeThemeScope` / `IdeColors.of(context)` / `IdeTextStyles.of(context)` 读取。
- 通知反馈使用 `showIdeToast`（`lib/src/ui/core/ide_toast.dart`）。
- 不要再引入已移除的 `shadcn_ui` 或任何旧 `Shad*` API。
- Agent 管理位于设置页；桌面宽度使用表格信息密度，窄窗口改为卡片和上下布局。
- 被禁用 Agent 的历史会话只读：允许加载和查看历史，但隐藏输入区，并阻止新建、
  分叉、重命名、归档和删除等写操作。
- 使用统计是标题栏全局页面，不属于设置分区。统计表格在窄窗口保留横向滚动，
  分析区按可用宽度从双栏切换为单栏。

### 使用统计开发约束

- 新 provider 的套餐读取实现 `AgentUsageQuotaProvider` 可选能力；不要为不支持套餐的
  provider 在通用 `AgentProvider` 上制造强制实现。
- 调用统计依赖中立 `AgentUsageRecord`，provider 原始 JSON key 只允许出现在 data 层。
- Codex `token_count` 是 thread 累计值，写入 turn 记录前必须相对上一 turn 做非负差分。
- `UsageStatisticsIndexStore` 的 JSON 必须保持版本化和宽容读取；索引损坏时从 provider
  历史重建，不得阻断页面或应用启动。
- 派生索引禁止保存 Prompt、回复、工具输出、session JSONL 路径和原始错误文本。
- 历史 TTFT 缺失时保持 `null`；UI 显示“数据不足”和有效样本数，禁止用总耗时冒充。

## 9. 会话和持久化

会话状态使用版本化 JSON。变更字段时：

- 保持 `tryDecode` 宽容读取，损坏内容不能导致启动失败。
- 新字段提供默认值。
- 如破坏兼容性，提升版本并保留旧版本迁移逻辑。
- 不要把 provider 全局配置复制进每个项目状态。

## 10. 文件系统注意事项

- 文件树不应递归扫描整个项目。
- 不跟随符号链接。
- 大目录和工具缓存目录应继续忽略。
- 目录读取失败返回空列表或用户可理解状态，不让异常冒泡到 UI 崩溃。

## 11. 测试建议

- 纯逻辑、JSON 编解码和状态机使用单元测试。
- Widget 渲染和用户交互使用 `flutter_test`。
- 外部 CLI、文件系统和持久化优先使用 fake 或 callback 注入。
- 只有端到端用户流程稳定后再添加 integration test。

## 12. 常见问题

### Codex provider 启动失败

确认本机可以直接运行：

```sh
codex app-server
```

如果命令不存在或协议变更，应用会显示 provider 不可用或错误状态。
协议字段变更时，按 [协议版本锁定文档](./codex_app_server_protocol.md)
重新导出 schema 并 diff，再更新适配层。

### 会话恢复后项目消失

恢复流程会过滤不存在的目录。确认项目路径仍然存在，并且应用有权限读取。

### 文件树没有显示某些目录

被忽略目录不会显示，例如 `.git`、`.dart_tool`、`build`、`node_modules`。这是为了避免大型仓库打开时卡顿。
