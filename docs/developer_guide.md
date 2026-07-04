# 开发者文档

最后更新：2026-07-04

## 1. 项目简介

Zeta 是一个 Flutter Desktop 项目，当前支持 macOS、Linux 和 Windows 平台目录。应用主入口在 `lib/main.dart`，核心界面是三栏 Agent IDE 工作台。

## 2. 环境要求

- Flutter SDK，需兼容 `pubspec.yaml` 中的 Dart SDK 约束 `^3.12.2`。
- 支持 Flutter desktop 的本地开发环境。
- 如需运行默认 Agent provider，需要本机可执行 `codex app-server --stdio`。

## 3. 常用命令

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter run -d macos
```

Linux 或 Windows 开发时，将最后一条命令的设备改为对应桌面设备。

## 4. 目录结构

```text
lib/
  main.dart
  src/
    app/
    core/
    data/
    domain/
    ui/
test/
docs/
third_party/
linux/
macos/
windows/
```

重要模块：

- `lib/src/app`：应用装配、窗口启动、常量。
- `lib/src/core`：日志等基础设施。
- `lib/src/domain/agent`：Agent 领域模型和 provider 接口。
- `lib/src/data/agent`：Codex provider、JSON-RPC stdio 和 provider 配置存储。
- `lib/src/data/session`：IDE 会话状态和持久化。
- `lib/src/data/file_system`：文件树构建和路径工具。
- `lib/src/ui/features/ide`：IDE 工作台 UI、view model 和 panes。
- `test/src`：领域、data 和 view model 测试。

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
- 公共 API 添加 `///` 文档。
- 新实现中，对公共 API、协议适配、状态机、错误处理和不直观分支优先补充中文注释。
- 不使用 `print`，需要保留的诊断信息使用 `dart:developer` 或项目日志封装。

## 7. Agent provider 开发指南

新增 provider 时：

1. 在领域层确认现有 `AgentProvider` 接口是否足够表达新 provider 能力。
2. 在 data 层新增具体 provider 实现，不让 UI 直接依赖 provider 协议。
3. 把 provider 原始事件映射成 `AgentEvent`、`AgentToolCall`、`AgentPermissionRequest` 等中立模型。
4. 在 factory 中接入 provider kind。
5. 添加单元测试覆盖初始化、session、turn、权限请求和错误映射。

注意：默认策略应保持保守，不自动授权命令执行或文件写入。

## 8. UI 开发指南

- 保持三栏工作台的职责边界：Projects 管项目和 threads，Agent 管对话，Files 管文件上下文。
- 复杂交互逻辑优先放入 view model，widget 层负责渲染和用户输入。
- 桌面工具界面需要保持信息密度，但文本必须可读，按钮和状态提示不能挤压变形。
- 非文本按钮应提供 tooltip。
- 新增面板或重复项时优先复用 `Pane`、`PanelCard`、主题常量和现有间距。

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
codex app-server --stdio
```

如果命令不存在或协议变更，应用会显示 provider 不可用或错误状态。

### 会话恢复后项目消失

恢复流程会过滤不存在的目录。确认项目路径仍然存在，并且应用有权限读取。

### 文件树没有显示某些目录

被忽略目录不会显示，例如 `.git`、`.dart_tool`、`build`、`node_modules`。这是为了避免大型仓库打开时卡顿。
