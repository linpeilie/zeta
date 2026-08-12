# 贡献指南

中文 ｜ [English](CONTRIBUTING.en.md)

感谢你对 Zeta 感兴趣。这份文档说明如何搭环境、改代码、提 PR，以及本项目在架构上有哪些**不能碰的红线**。

先读一遍再动手，能省掉大部分返工。

## 目录

- [先说三件事](#先说三件事)
- [搭建开发环境](#搭建开发环境)
- [日常命令](#日常命令)
- [提交前必做](#提交前必做)
- [提交信息格式](#提交信息格式)
- [Pull Request 流程](#pull-request-流程)
- [架构红线](#架构红线)
- [测试要求](#测试要求)
- [报告问题](#报告问题)
- [许可](#许可)

## 先说三件事

1. **默认分支是 `dev`**，请基于它开分支和提 PR。
2. **改动要小而聚焦。** 大规模重构、新增 Provider、改动事件管线契约，请先开 Issue 讨论方案，不要直接甩一个几千行的 PR。
3. **本项目有严格的分层约束。** 违反[架构红线](#架构红线)的 PR 无论功能是否正确都不会合并——这些约束是为了让多 Provider 接入不互相污染，不是形式主义。[架构总览](docs/architecture/overview.md)用十几分钟讲清了为什么。

## 搭建开发环境

**基础要求**

- Flutter SDK（stable 通道），需兼容 `pubspec.yaml` 的 Dart SDK 约束 `^3.12.2`
- CI 使用 **Flutter stable 3.44.4**，本地版本差太远可能出现分析结果不一致
- 支持 Flutter Desktop 的本地环境（macOS / Windows / Linux）

**Linux 额外的构建依赖**

```sh
sudo apt-get update && sudo apt-get install --yes \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libfontconfig1-dev
```

**运行 Agent 功能还需要**

- **Codex**（默认 Provider）：本机能执行 `codex app-server`。未指定 `--listen` 时走 stdio。协议按 pinned schema 开发，见 [Codex app-server 协议版本锁定](docs/protocols/codex_app_server_protocol.md)。
- **Grok**（可选）：Grok CLI（grok-build）**0.2.119 或更高**。这是多会话兼容基线，更早的版本在同时打开多个 Grok 会话时无法正确隔离会话状态和回合终态。
- **Claude Code**（可选）：本机能执行并已登录 `claude`。当前 stream-json 取样基线是 CLI **2.1.224**（不是最低版本承诺），协议边界与升级检查见 [Claude Code stream-json 协议基线](docs/protocols/claude_code_stream_json_protocol.md)。

只改 UI 或文档的话，不装这些 CLI 也能跑起来，只是 Agent 面板会显示未检测到。

**启动**

```sh
flutter pub get
flutter run -d macos    # 或 -d windows / -d linux
```

## 日常命令

```sh
dart format .           # 编辑 Dart 文件后必跑
flutter analyze         # 结束改动前必跑
flutter test            # 行为变化时必跑
```

跑单个测试文件：

```sh
flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart
```

> `dart_test.yaml` 固定了 `concurrency: 2`。大 Widget 测试单个 worker 会加载完整 IDE Shell，放开并发容易触发内存峰值。**请不要为了跑得快而改掉它。**

**Codex 协议升级时**（改适配层之前）：

```sh
./tool/gen_codex_schema.sh --diff        # Windows: ./tool/gen_codex_schema.ps1 -Diff
```

先对比 `third_party/codex_app_server_schema/` 的差异，再动适配层。之后用真实 CLI 冒烟：

```sh
python tool/smoke_codex_app_server.py --expected-version 0.144.5
python tool/smoke_codex_plan_mode.py --expected-version 0.144.5
```

冒烟脚本使用临时只读 workspace，输出不含 Prompt、回复、文件内容、凭证或原始 JSONL。详见 [开发者文档 §3](docs/guides/developer_guide.md)。

## 提交前必做

按顺序跑完这三条，缺一不可：

```sh
dart format .
flutter analyze
flutter test
```

CI 会重跑同样的检查（外加 `dart format --set-exit-if-changed` 和 `--enforce-lockfile`），本地先过一遍能省一轮往返。

另外：

- 如果 `linux/`、`macos/`、`windows/` 等平台生成目录出现了非预期改动，**先确认是不是 Flutter 工具产生的**，保留的话要在 PR 里说明原因。
- 新增第三方依赖前，先确认 Flutter / Dart 内建方案确实不够用，并在 PR 描述里说明每个新依赖的用途。

## 提交信息格式

使用 [Conventional Commits](https://www.conventionalcommits.org/)，摘要不超过 50 字符：

```
feat: add grok thread archiving
fix: guard stale model catalog overwrite
docs: add bilingual contributing guide
refactor: extract plan handoff controller
chore: bump flutter action pin
```

常用类型：`feat` / `fix` / `docs` / `refactor` / `test` / `chore` / `perf`。

## Pull Request 流程

1. 从 `dev` 开分支，分支名建议 `feat/xxx`、`fix/xxx`。
2. 保持提交历史清晰，避免把无关改动混进同一个 PR。
3. 填写 PR 模板，特别是**架构门禁勾选项**——如果某项不适用，写明为什么。
4. 确保 CI 全绿。
5. 等待 review。涉及事件管线、Provider 契约或持久化格式的改动，review 会比较细，请有心理准备。

**行为变化必须配测试。** 没有测试的行为改动一般不会合并。

## 架构红线

**第一次读代码，先看[架构总览](docs/architecture/overview.md)**（十几分钟，带图）和[术语表](docs/guides/glossary.md)。完整规则见[工程规范](docs/architecture/engineering_standards.md)和[开发者文档 §7](docs/guides/developer_guide.md)。以下是最常被踩的几条：

**分层与依赖方向**

- 依赖单向：`main → app → presentation/application → domain`，`app → data → domain`，`presentation → ui/core`。
- 新代码进对应的 `features/<feature>/{domain,application,data,presentation}`，不要回到顶层宽泛目录。
- `main.dart` 只做启动；`lib/src/app` 是唯一装配点。

**Provider 隔离（最重要）**

- Provider 的原始协议**只能存在于 data 层**。UI 和 application 消费中立的 domain 事件与契约。
- 共享层（decoder、CoalescingPolicy/Buffer、Pipeline、TimelineStore）**禁止出现任何 Provider 的 import、kind 分支、id 分支或 raw 字段读取**。
- 新增 Provider 的正常改动范围 = 自有 data 文件 + 中立 domain 契约 + factory 组合 + 契约测试。如果你发现必须改共享层，说明抽象没做对，先开 Issue 讨论。
- UI 一律按 **capability** 渲染，不按 provider kind 或名称硬编码。未支持的能力必须 `capability = false` 并抛 `UnsupportedError`，**不得静默成功**。
- Provider 进程只由 `AgentProviderRuntimeRegistry` 创建；全局操作走 `AgentProviderGlobalRuntime`，会话实例只由 `AgentConversationBinding.beginTurn()` 惰性创建。ViewModel 不持有 lease/scope/pin，空闲回收归 Binding Manager。
- Workspace entry 创建时一次性绑定 thread、Binding 与 ViewModel；ViewModel 不提供跨 thread 切换/恢复兼容入口，只允许更新 project/file context。Registry 获取 runtime 必须显式传 scope。
- 真实 thread 的 Binding 不得原地改绑；fork 返回的 session 走 Shell 的新 thread 通用登记/选择流程，后续操作只作用于 fork 结果。
- `AgentProviderBundle` / `AgentRuntimePort` 不暴露原始 `AgentProvider`；每个 Binding 独占一份不可变权限快照，不得恢复跨 provider/runtime/thread 的权限注册表。

**事件管线**

- 新增或修改 `AgentEvent` 前，必须逐项回答[开发者文档 §7 的 16 条接入清单](docs/guides/developer_guide.md)，并用测试固定行为。
- reducer 必须纯同步：不得出现 Flutter scheduler、`Timer`、`Future` 或外部回调，副作用走 scope-aware EffectRunner。
- live / history / replay 必须使用**独立的 reducer 实例**。

**权限模型**

- 权限审批、用户提问、Plan 审批是**三种独立的领域语义**，不共享 request/decision 模型。
- Plan 终态后的「执行确认」是 Zeta 本地工作流，不是 Provider 计划审批：必须新建显式 Default 回合，不得预授权命令、文件或网络操作。
- 执行权限只恢复同 Binding/thread/runtime 中仍有效的 Plan 前用户选择；否则使用 Provider catalog 的保守默认。卡内覆盖仅限该 turn，不能 apply 或持久化。**任何自动升级授权的改动都不会被接受。**

**主题与 UI**

- `shadcn_flutter` 只能 `as sf` 导入；语义 token 走 `IdeThemeScope` / `IdeColors.of(context)` / `IdeTextStyles.of(context)`。
- 禁止 Material `ThemeData` / `ColorScheme.fromSeed`、裸 `Color(0x...)`、手写 `BoxShadow`、临时 `BorderRadius.circular(...)`。
- 通知统一用 `showIdeToast`，不要在 feature 里直接调 `sf.showToast`。
- 时间线禁止 post-frame 测量、`GlobalKey` 查高、layout 后 `setState` 反馈环。

**持久化与隐私**

- Zeta 自有数据全部在 `~/.zeta/`，JSON 必须版本化 + 宽容 `tryDecode`（缺字段或损坏不能阻断启动）。
- Provider 自有 data adapter 可以按明确功能读取对应 CLI 的私有数据；协议字段、原始内容和路径不得泄漏到上层。读取权限不等于迁移、改写或删除授权。
- 派生索引与缓存只保存规范化白名单字段。**禁止持久化 prompt、回复、工具输出、原始错误文本、环境变量、凭证或 Provider raw payload。**

**其他**

- 不使用 `print`，诊断信息走 `dart:developer` 或 `lib/src/core/logging`。
- 公共 API 写 `///` 文档；新代码优先中文注释，重点覆盖协议适配、状态机、错误处理和不直观分支。
- **Cursor 已退役**，相关代码不接受回流。

## 测试要求

- 行为变化至少覆盖风险最高的状态转换。
- 优先用 fake / stub 而不是 mock，遵循 Arrange / Act / Assert。
- 依赖通过构造函数注入。
- 共享层（decoder、Coalescing、TimelineStore）的测试必须使用 **Provider 无关的 fixture**，并配套架构守卫测试。
- 改动页面切换行为时，要用真实的 `IdeHome` 补 Widget 测试，验证 Element、草稿、滚动位置、面板宽度不被重置。

## 报告问题

开 Issue 之前，先翻一下[故障排查与数据说明](docs/product/troubleshooting.md)——CLI 检测不到、通知不弹、统计对不上这类问题多半在那里有答案。

请使用 [Issue 模板](https://github.com/linpeilie/zeta/issues/new/choose)。Zeta 的问题高度依赖环境，模板里的这些信息请尽量填全：

- 操作系统与版本
- Zeta 版本（关于页面或安装包文件名）
- `flutter --version` 输出（如果是从源码运行）
- Agent CLI 与版本（`codex --version` / `grok --version`）

**贴日志前请先脱敏。** `~/.zeta/logs/` 下的日志可能包含你的项目路径和文件名。日志本身不记录 prompt、回复正文和凭证，但路径信息仍可能敏感。

**安全漏洞请不要开公开 Issue**，改用 GitHub 的私密漏洞上报（Security → Report a vulnerability）。威胁模型与范围界定见[安全策略](SECURITY.md)。

## 许可

参与本项目即表示你同意遵守[行为准则](CODE_OF_CONDUCT.md)。

本项目采用 **GPL-3.0** 许可，见 [LICENSE](LICENSE)。提交贡献即表示你同意以相同许可授权你的代码。
