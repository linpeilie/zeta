# VGV 分层迁移任务清单

中文 ｜ [English](./migration_tasks.en.md)

本文件是 [migration_topology.md](./migration_topology.md) 中 P0–P7 共 34 个步骤的**逐步执行设计**：每步给出 Data / Repository / Bloc / UI 四层的具体类名设计与可勾选任务。

拓扑分析、包划分依据、风险评估见拓扑文档，本文件不重复。

**进度总览**

| 阶段 | 步骤 | 状态 |
| --- | --- | --- |
| **步骤 0 Cursor 前置清退**（旧仓库） | 0 | ☐ |
| P0 工程地基 | 1–6 | ☐ |
| P1 Data 层契约 | 7–8 | ☐ |
| P2 Data 层实现 | 9–11 | ☐ |
| P3 Repository 层 | 12–15 | ☐ |
| P4 设计系统 | 16–17 | ☐ |
| P5 Bloc 与 Presentation | 18–24 | ☐ |
| P6 Agent 会话 | 25–27 | ☐ |
| P7 应用外壳与收口 | 28–33 | ☐ |

---

## 0. 全局设计约定

动手前先读完本节，后面每一步都默认遵守。

### 0.1 命名

| 角色 | 约定 | 示例 |
| --- | --- | --- |
| Data 层契约包 | `<domain>_api` | `agent_provider_api` |
| Data 层实现包 | `<vendor>_client` | `codex_app_server_client` |
| Repository 包 | `<domain>_repository` | `agent_conversation_repository` |
| 抽象数据源 | `XxxApi` | `AppReleaseApi` |
| 具体实现 | `XxxClient` | `HttpAppReleaseClient` |
| 能力端口 | **保留 `XxxPort`** | `AgentConversationPort` |
| 仓库 | `XxxRepository` | `SettingsRepository` |
| 状态 | `XxxState` | `WorkspaceState` |
| 事件 | `XxxEvent` + 具体事件类 | `AppUpdateManualCheckRequested` |

> **为什么 capability port 不改叫 `Api`**：`AgentProviderBundle` 的 21 个端口是**可选能力**（`threadArchival`、`planApproval` 等为 null 表示 provider 不支持），语义是"能力协商"而非"数据源"。改名成 `Api` 会丢失这层含义。包名遵循 VGV（`agent_provider_api`），类名保留 `Port`。

### 0.2 DTO 策略

**不为 provider 协议引入独立 DTO 类。**

旧仓库是 `Map<String, Object?>` →（29 个 mapper 纯函数）→ Entity 的直接映射，mapper 已有完整测试。插一层 DTO 会让 29 个 mapper 翻倍且无实际收益。

**例外——需要往回写的持久化结构，必须有显式 codec 充当 DTO**，旧仓库已存在，原样迁移：

- [ ] `AgentProviderConfigCodec`（205 行）
- [ ] `AgentTurnContextCodec`（115 行）
- [ ] `GeneralSettingsCodec`
- [ ] `AppUpdateStateCodec`
- [ ] `ProjectThreadsSessionSnapshotCodec`
- [ ] `AgentModelCodec`（49 行）

所有 codec 的 `fromJson` **必须宽容解码**（未知字段忽略、缺失字段取默认、未知枚举值回退），这是老用户数据可读的唯一保障。

### 0.3 异常转换

**Data 层抛协议/IO 异常，Repository 转成领域异常，Bloc 只处理领域异常。**

每个 repository 定义一个 sealed 异常族：

```dart
sealed class AgentRepositoryException implements Exception {
  const AgentRepositoryException(this.message, [this.cause, this.stackTrace]);
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
}
```

转换在 repository 边界完成，**永远带上原始 cause 与 stackTrace**：

```dart
try {
  return await _bundle.conversation.sendMessage(...);
} on JsonRpcException catch (e, st) {
  throw AgentTurnRejectedException('turn rejected by provider', e, st);
} on ProcessException catch (e, st) {
  throw AgentProviderUnavailableException('provider process not reachable', e, st);
}
```

**能力缺失一律抛 `AgentCapabilityUnsupportedException`，禁止静默成功**——静默成功会让用户以为操作生效了。

### 0.4 Bloc 约定

以下全部来自 `bloc` skill，写代码前先读 `.claude/skills/bloc/SKILL.md`。

- 简单状态用 `Cubit`，有明确状态机或多来源事件用 `Bloc`
- **Bloc 之间不得互相依赖**；需要联动时在 app 层用 `BlocListener` 桥接
- **事件用 `sealed class`**，多状态类型也用 `sealed`，以支持 Dart 3 `switch` 穷尽匹配
- State 与 Event 一律 `extends Equatable` 并重写 `props`
- 单状态类形态必须提供 `copyWith`
- 每个 State 带 `status` 枚举（`initial` / `loading` / `success` / `failure`），不用 `bool loading` + `String? error` 的组合
- **事件命名 = `BlocSubject` + `Noun` + `VerbPastTense`**，例：`TodoListSubscriptionRequested`、`AppUpdateManualCheckRequested`。本文件后续步骤中形如 `ThreadSelected` 的简写需补全 Bloc 主语（→ `ProjectThreadsThreadSelected`）
- 业务逻辑只在 Bloc/Cubit 里，绝不在 widget、page、view 中
- 回调里用 `context.read`，`build` 里用 `context.watch` 或 `BlocBuilder`；**绝不在 `build` 之外用 `context.watch`**

#### Page / View 分离（强制）

`bloc` skill 要求每个 feature 的 UI 拆成两个文件：

```
lib/<feature>/
├── <feature>.dart          # barrel
├── bloc/                   # 或 cubit/
│   ├── <feature>_bloc.dart
│   ├── <feature>_event.dart
│   └── <feature>_state.dart
└── view/
    ├── <feature>_page.dart # 只负责 BlocProvider 创建与注入
    └── <feature>_view.dart # 只负责 BlocBuilder / BlocListener 消费状态
```

**Page 提供 Bloc，View 消费状态。** 本文件 P5–P7 各步骤中凡写作"视图"的，都按这个结构落地。

### 0.5 每步的完成定义

一个步骤打勾，必须同时满足：

- [ ] **动手前已查过 §0.7 的 skill 映射**，按 skill 的规范实现
- [ ] 代码迁移完成
- [ ] 对应测试迁移完成 + 缺口补齐
- [ ] 四道质量门全绿（analyze / format / test / coverage）
- [ ] 不引入新的跨层依赖（P0 步骤 6 的分层检查通过）
- [ ] **对应文档的中英两版已更新**（映射见 §0.6）

**质量门必须走 MCP 工具，不走 Bash**（`green-gate` skill 规定，且 Bash 的 test 路径被 `block-cli-workarounds.sh` hook 拦截）：

| 门 | 工具 |
| --- | --- |
| analyze | `mcp__dart__analyze_files`（`applyFixes: true`） |
| format | `mcp__dart__dart_format` |
| test + coverage | `mcp__very-good-cli__test`，**`coverage: true` + `min_coverage: 100` + `check_ignore: true` 三者同时传** |

> 三个参数少传一个门禁就失效：漏 `coverage: true` 不会生成 `lcov.info`；漏 `check_ignore: true` 会让 `// coverage:ignore` 变成空操作。
>
> 单包跑测试要传 `directory`（如 `directory: 'packages/agent_provider_api'`）与 `timeout_seconds`（Flutter 测试遇到无超时的 `pumpAndSettle()` 会挂死）。

### 0.6 文档约定

#### 目录结构

照搬旧仓库 `docs/` 的组织方式：

```
docs/
├── architecture/   架构总览、分层设计、工程规范、迁移文档
├── guides/         开发者文档、术语表、国际化指南
├── product/        产品需求、故障排查与数据说明
├── protocols/      Provider 协议锁定与适配方案
├── release/        发版流程
├── history/        已退役能力与开发流水，仅存档
└── images/         截图与拍摄清单
```

#### 双语规则

**旧仓库只有 5 个文件做了英文版，本仓库要求全量双语。**

| 项 | 约定 |
| --- | --- |
| 文件命名 | `xxx.md`（中文）+ `xxx.en.md`（英文） |
| 中文头 | `中文 ｜ [English](./xxx.en.md)`，置于一级标题下空一行 |
| 英文头 | `[中文](./xxx.md) ｜ English`，同上 |
| 交叉链接 | 中文文档链到中文，英文文档链到英文；索引条目附对方语言链接 |
| 索引 | 新增文档必须同时登记进 `docs/README.md` 与 `docs/README.en.md` |
| 提交粒度 | **中英两版在同一个 commit 内提交**，不允许先中后英分两次 |

> 术语一致性：类名、包名、方法名、枚举值在两版中保持英文原样，不翻译。表格与代码块结构对齐，便于 diff 比对。

#### 步骤与文档的映射

每个迁移步骤至少更新一处文档。中英各一个勾。

| 步骤 | 目标文档 | 中 | 英 |
| --- | --- | :-: | :-: |
| **0 Cursor 前置清退** | `history/cursor_retirement` — **新建**，归档说明（写在**旧仓库**） | ☐ | ☐ |
| 1 平台矩阵 | `guides/developer_guide` — 环境与构建命令 | ☐ | ☐ |
| 2 Monorepo 骨架 | `architecture/overview` — 包结构总览<br>`guides/developer_guide` — melos 命令 | ☐ | ☐ |
| 3 l10n 基线 | `guides/internationalization` — **新建** | ☐ | ☐ |
| 4 CI 接入 | `architecture/engineering_standards` — CI 门禁 | ☐ | ☐ |
| 5 基础设施包 | `architecture/overview` — L0 层说明 | ☐ | ☐ |
| 6 分层依赖检查 | `architecture/engineering_standards` — 分层规则与例外登记 | ☐ | ☐ |
| 7 `agent_provider_api` | `architecture/layering` — **新建**，Data 层契约<br>`guides/glossary` — 21 个端口与能力术语 | ☐ | ☐ |
| 8 `json_rpc_transport` | `protocols/` — 传输层与异常族 | ☐ | ☐ |
| 9 三个 provider client | `protocols/codex_app_server_protocol`<br>`protocols/claude_code_stream_json_protocol`<br>`protocols/grok_acp_protocol` — **新建** | ☐ | ☐ |
| 10 `agent_history_client` | `protocols/` — 本地历史格式与宽容解析 | ☐ | ☐ |
| 11 测试与 fixtures | `guides/developer_guide` — 测试细则与 fixture 组织 | ☐ | ☐ |
| 12 `agent_conversation_repository` | `architecture/design_document` — 事件管线与会话编排<br>`architecture/layering` — **ChangeNotifier→Stream 改造手法** | ☐ | ☐ |
| 13 `agent_provider_repository` | `architecture/design_document` — Provider 配置与目录；两 repository 的单向依赖 | ☐ | ☐ |
| 14 settings + workspace + session repo | `architecture/layering` — Repository 层职责 | ☐ | ☐ |
| 15 `usage_statistics_repository` | `architecture/design_document` — 用量聚合 | ☐ | ☐ |
| 16 `app_ui` | `guides/developer_guide` — UI 包使用与组件清单<br>`guides/internationalization` — 共享组件文案传参 | ☐ | ☐ |
| 17 `app_ui` 测试 | `guides/developer_guide` — widget 测试约定 | ☐ | ☐ |
| 18 `workspace` bloc | `architecture/layering` — Cubit 模式示例 | ☐ | ☐ |
| 19 `settings` bloc | `architecture/layering` — 反向边处理手法 | ☐ | ☐ |
| 20 `app_update` bloc | `architecture/layering` — Bloc 状态机模式示例 | ☐ | ☐ |
| 21 `desktop_notifications` bloc | `architecture/engineering_standards` — **分层例外登记** | ☐ | ☐ |
| 22 threads + session bloc | `architecture/design_document` — 两 bloc 共享 repository | ☐ | ☐ |
| 23 `agent_management` bloc | `architecture/design_document` — CLI 检测与诊断 | ☐ | ☐ |
| 24 `usage_statistics` bloc | `architecture/design_document` — 两套状态的划分 | ☐ | ☐ |
| 25 `AgentConversationBloc` | `architecture/overview` — 事件管线全链路<br>`guides/glossary` — 5 个 state slice 术语 | ☐ | ☐ |
| 26 presentation widgets | `guides/developer_guide` — `BlocSelector` 订阅粒度约定 | ☐ | ☐ |
| 27 capability 渲染测试 | `architecture/overview` — 能力协商与 fail-closed | ☐ | ☐ |
| 28 `ide_shell` | `architecture/design_document` — 三栏工作台 | ☐ | ☐ |
| 29 装配层 | `architecture/layering` — **注入方式与 bloc 作用域图** | ☐ | ☐ |
| 30 l10n 收口 | `guides/internationalization` — typed code → ARB 映射、Locale 冻结 | ☐ | ☐ |
| 31 三 flavor | `release/release_guide` — **新建**，flavor 与构建产物 | ☐ | ☐ |
| 32 数据迁移验证 | `product/troubleshooting` — **新建**，`~/.zeta` 数据说明与重置 | ☐ | ☐ |
| 33 文档收口 | 全部文档终审 + `docs/README` 索引校对 | ☐ | ☐ |

#### 迁移期的文档欠账

以下文档已在 `docs/README.md` 索引中登记，需在对应步骤补齐：

- [ ] `architecture/overview.md` + `.en.md` —— 步骤 2 起草，步骤 27 定稿
- [ ] `architecture/layering.md` + `.en.md` —— 步骤 7 起草，步骤 29 定稿
- [ ] `architecture/engineering_standards.md` + `.en.md` —— 步骤 4 起草
- [ ] `architecture/design_document.md` + `.en.md` —— 步骤 12 起草，步骤 28 定稿
- [ ] `guides/developer_guide.md` + `.en.md` —— 步骤 1 起草
- [ ] `guides/glossary.md` + `.en.md` —— 步骤 7 起草
- [ ] `guides/internationalization.md` + `.en.md` —— 步骤 3 起草
- [ ] `product/product_requirements.md` + `.en.md` —— 可从旧仓库直接迁移
- [x] 本文件与拓扑文档的 `.en.md` 版本

### 0.7 Skill 优先

仓库 `.claude/skills`（软链到 `.agents/skills/`）下有 15 个 VGV 官方 skill，共 3,864 行。

**写任何代码前，先查本节映射表，按 skill 的规范实现。** skill 与本文件冲突时以 skill 为准，除非该冲突已登记在下方的「偏离登记」中。

#### Skill 清单

| Skill | 行数 | 覆盖范围 |
| --- | --- | --- |
| `layered-architecture` | 403 | 四层职责、包结构、barrel、路径依赖、构造注入、反模式表 |
| `bloc` | 218 | Cubit/Bloc 选型、事件与状态命名、Page/View 分离、`BlocSelector` |
| `testing` | 479 | 测试组织、私有 mock、`pumpApp`、命名规范、golden tag |
| `green-gate` | 308 | 四道质量门的工具、参数、顺序与覆盖率目标 |
| `ui-package` | 101 | UI 包结构、`ThemeExtension`、barrel、组件 API 规范 |
| `internationalization` | 156 | ARB、`context.l10n`、**共享组件的文案传参策略**、RTL |
| `material-theming` | 233 | `ThemeData`、`ColorScheme`、`TextTheme`、组件主题 |
| `static-security` | 327 | 密钥、用户数据、网络通信、输入校验、依赖漏洞 |
| `accessibility` | 318 | WCAG 2.2 跨平台无障碍 |
| `animations` | 399 | 隐式/显式动画、页面转场、Material 3 motion token |
| `navigation` | 227 | GoRouter 路由、深链、重定向 |
| `create-project` | 101 | Very Good CLI 模板脚手架 |
| `very-good-analysis-upgrade` | 248 | lint 包升级 |
| `dart-flutter-sdk-upgrade` | 235 | SDK 版本约束升级 |
| `license-compliance` | 111 | 依赖许可证审计 |

#### 步骤 → Skill 映射

| 步骤 | 必查 Skill | 关键约束 |
| --- | --- | --- |
| 1 平台矩阵 | — | |
| 2 Monorepo 骨架 | `layered-architecture`、`create-project` | 用 `mcp__very-good-cli__create` 建包，不手搓；本地包一律 `path:` 依赖，禁用 `git:`/版本号 |
| 3 l10n 基线 | `internationalization` | ARB 为唯一真源；`context.l10n` 扩展；**共享组件文案传参而非依赖 `AppLocalizations`** |
| 4 CI 接入 | `green-gate` | 四道门的工具与参数，见 §0.5 |
| 5 基础设施包 | `layered-architecture` | `create dart_package`；barrel 导出；`lib/src/` 私有 |
| 6 分层依赖检查 | `layered-architecture` | 反模式表的 8 条即检查项 |
| 7 `agent_provider_api` | `layered-architecture` | barrel；无 Flutter；**见偏离登记 D1** |
| 8 `json_rpc_transport` | `layered-architecture`、`static-security` | 传输层日志脱敏；异常族 |
| 9 三个 provider client | `layered-architecture`、`static-security`、`testing` | 构造注入；私有 mock；密钥不落盘 |
| 10 `agent_history_client` | `layered-architecture`、`static-security` | 宽容解析；敏感内容不入日志 |
| 11 测试与 fixtures | `testing` | `_MockX` 私有 mock；group 层级读成自然句；`'returns $Type'` 插值 |
| 12 `agent_conversation_repository` | `layered-architecture`、`bloc` | 构造注入 data client；观察者出口改 `Stream`（不得依赖 `flutter/foundation`）；领域模型转换 |
| 13 `agent_provider_repository` | `layered-architecture` | 一个 domain 一个 repository；**不得反向依赖 conversation 包** |
| 14 settings + workspace + session repo | `layered-architecture` | 一个 domain 一个 repository |
| 14 `project_session_repository` | `layered-architecture` | 同上 |
| 15 `usage_statistics_repository` | `layered-architecture` | 同上 |
| 16 `app_ui` | `ui-package`、`material-theming`、`internationalization`、`accessibility` | barrel 且 `lib/src/` 私有；一文件一组件；token 走 `ThemeExtension`；const 构造；每个公开成员写 dartdoc；**见偏离登记 D2、D3** |
| 17 `app_ui` 测试 | `testing`、`ui-package` | 每个组件配 widget 测试；用包自己的 `pumpApp`，禁止内联 `MaterialApp` |
| 18–24 各 feature bloc | `bloc`、`testing` | `sealed` 事件；`Equatable` 状态 + `copyWith`；**Page/View 分离**；`blocTest()`；`mocktail` |
| 25 `AgentConversationBloc` | `bloc`、`testing`、`static-security` | 同上 + 权限语义隔离的负向用例 |
| 26 presentation widgets | `bloc`、`accessibility`、`animations` | `BlocSelector` 按 slice 订阅；语义标签；转场用 Material 3 motion token |
| 27 capability 渲染测试 | `testing` | widget 测试验证入口不出现 |
| 28 `ide_shell` | `bloc`、`navigation` | Page/View 分离；路由若引入 GoRouter 走 `navigation` skill |
| 29 装配层 | `layered-architecture`、`bloc` | `main_<flavor>.dart` 创建 client 与 repository 并注入；`MultiRepositoryProvider` |
| 30 l10n 收口 | `internationalization` | delegate 组合；Locale 冻结 |
| 31 三 flavor | `layered-architecture` | flavor 只改配置，架构不变 |
| 32 数据迁移验证 | `static-security` | 持久化不落敏感内容 |
| 33 Cursor 清退 | — | |
| 34 文档收口 | `license-compliance` | 顺带跑一次依赖许可证审计 |

#### 包内结构（`layered-architecture` 强制）

每个 `packages/*` 一律：

```
packages/<name>/
├── lib/
│   ├── <name>.dart          # barrel —— 消费方只导入这个
│   └── src/                 # 私有，禁止被外部直接 import
│       ├── <name>.dart
│       └── models/
│           ├── models.dart  # 子 barrel
│           └── ...
├── test/                    # 镜像 lib/ 结构
└── pubspec.yaml             # 本地包用 path: 依赖
```

- [ ] 每个包用 `mcp__very-good-cli__create` 的 `create dart_package` 脚手架，不手工建目录
- [ ] Repository 通过**构造注入**接收 data client，绝不在内部 `new`
- [ ] app 的 `pubspec.yaml` **只依赖 repository 包**，data 包是传递依赖

#### 偏离登记

以下三处明知与 skill 相左，理由已确认，**不得在未讨论的情况下擅自「修正」回 skill 的写法**。

**D1 — 领域实体放在 Data 层的共享契约包**

- Skill 立场：`layered-architecture` 反模式表列有「Domain models in data layer」；领域模型应在 repository 包，data 包只放贴合外部结构的 response model
- 本项目做法：约 190 个中立领域实体放在 `packages/agent_provider_api`
- 理由：Zeta 有 **3 个厂商 client 必须产出同一套中立类型**。若实体放进 repository 层，三个 client 就要反向依赖 repository，层级直接倒置。skill 的模型假设「一个 data 包包一个外部源、自带 response model」，不覆盖「多源归一到同一契约」的形态
- 代偿：`agent_provider_api` 不含任何厂商字段与业务规则，只有契约与不可变实体；反模式真正防的「外部 API 结构泄漏到领域」在此不成立
- 复核时机：若将来只剩单一 provider，应回归 skill 的标准形态

**D2 — `app_ui` 建在 shadcn_flutter 而非 Material**

- Skill 立场：`ui-package` 要求用 `app_ui_package` 模板、建在 `flutter/material.dart` 上、barrel 再导出 `material.dart`
- 本项目做法：保留 shadcn_flutter，沿用旧仓库 49 个 `Ide*` 组件
- 理由：**用户已明确决策**（迁移四项前提之一）。换底意味着 49 个组件加全部调用方重做，且视觉回归无法自动验证
- 仍然适用的 skill 条款：barrel 导出、`lib/src/` 私有、一文件一组件、统一 `Ide*` 前缀、token 走 `ThemeExtension`、`const` 构造、公开成员写 dartdoc、每组件配 widget 测试、用包自己的 `pumpApp`

**D3 — l10n 收敛为单一路径（这条是 skill 纠正了原设计）**

原设计有**两套本地化机制并存**，违反「一旦改造就改造彻底」：`app_ui` 自带 118 键 ARB + TextCatalog 抽象向下注入已本地化字符串。skill 的两条规定同时否定了它们：

> Pass localized strings as parameters to reusable widgets — never couple shared widgets directly to `AppLocalizations`
>
> ARB files are the single source of truth

**改后：全项目只有一条本地化路径 —— ARB 是唯一文案真源，app 层是唯一本地化点。**

| 场景 | 原设计 | 改后 |
| --- | --- | --- |
| `app_ui` 共享组件文案 | 自带 118 键 ARB | **构造参数传入**，包内零 l10n 依赖 |
| data / repository 层文案 | TextCatalog 注入已本地化字符串 | **返回 `sealed` typed code**，app 层 `switch` 映射到 ARB |
| `Fallback*` 硬编码文案 | 395 行，与 ARB 双轨 | **废除**，文案并入 ARB |
| shadcn 本地化 | 迁入 `app_ui` | 留在 app `lib/l10n/` |

收益：ARB 无需拆分（1,072 键整体留在 app）；`app_ui` 与全部 `packages/` 可在无 Flutter 环境复用；`sealed` + `switch` 穷尽匹配让新增失败类型时编译期报错，不会漏翻译。

代价：4 组接口与 866 行桥接废除，60+ 消费点改为收发 typed code。分摊在 P1（契约）、P3（repository）、P5–P7（UI 映射）。

固化为检查项：**`packages/` 下任何包都不得引用 `AppLocalizations`，也不得产出用户可见字符串。**

---

## 步骤 0 · Cursor 前置清退（在旧仓库内完成）

**迁移的前置条件，不属于任何 P 阶段。出口条件未达成不进入 P0。**

原设计把 Cursor 清退放在 P7，但它的 5 个调用点会在 P2 / P3 / P5 陆续迁移——中间整个迁移期都背着已废弃的代码，正是"新旧两套逻辑并存"。**整体前置到旧仓库，一次清干净。**

Cursor 兼容代码不是死代码，它是老用户持久化配置的过滤层。**顺序不可颠倒。**

#### 1. 先做数据清洗

- [ ] 在旧仓库的 `zeta_storage_migrator` 中新增一次性迁移
- [ ] 从持久化的 provider 配置中物理删除 cursor 条目
- [ ] `activeProviderId` 指向 cursor 时改写为默认 provider
- [ ] 删除或归档 `cursor_sessions.json`

#### 2. 再删兼容层（11 处）

- [ ] `agent/domain/cursor_retirement_policy.dart`（122 行）
- [ ] `agent/domain/agent_models.dart:8` 的 re-export
- [ ] `agent/data/agent_provider_config_codec.dart:52`
- [ ] `agent/data/default_agent_provider_factory.dart:37,39,52`
- [ ] `agent/data/agent_provider_static_capabilities.dart:92`
- [ ] `agent/application/agent_provider_settings_controller.dart`（8 处）
- [ ] `agent/application/agent_turn_context_recorder.dart:7,92`
- [ ] `agent_management/application/agent_management_controller.dart:792`
- [ ] `ui/features/ide/views/new_thread_provider_popover.dart:39`
- [ ] `core/storage/zeta_data_paths.dart:86-88` 的 `cursorSessionsFile`
- [ ] l10n：zh / en 各 8 条 `cursorRetired` 文案
- [ ] **保留** `AgentProviderKind.cursorAcp` 枚举值，或在 `fromJson` 中加未知值兜底——否则老配置反序列化抛异常（G7 宽容解码）。这条兜底会随契约迁入 `agent_provider_api`

#### 3. 回归验证

- [ ] 用含 cursor 条目的真实旧版本配置跑升级：不崩溃、菜单无 cursor、活动 provider 正确降级
- [ ] 旧仓库 `flutter analyze` 零告警
- [ ] 旧仓库全量测试绿

**出口条件**：以上三项全绿。达成后旧仓库进入 freeze（§5.2），开始 P0。

---

## P0 · 工程地基

### 步骤 1 — 平台矩阵

仅桌面三端。

- [ ] `flutter create --platforms=linux .` 补齐 `linux/`
- [ ] 删除 `android/`、`ios/`、`web/`
- [ ] 校正 `pubspec.yaml`：移除移动端专属依赖占位
- [ ] 三平台各跑一次 `flutter build` 确认脚手架可编译

### 步骤 2 — Monorepo 骨架

- [ ] 引入 melos 或 Dart workspace，根 `pubspec.yaml` 声明 workspace 成员
- [ ] 建立 `packages/` 目录
- [ ] 统一 `analysis_options.yaml`：根配置 `include: package:very_good_analysis/analysis_options.yaml`，各包继承根配置
- [ ] 各包 `pubspec.yaml` 统一 SDK 约束（`sdk: ^3.12.0` / `flutter: ^3.44.0`）

### 步骤 3 — l10n 基线

详见拓扑文档 §2.5。ARB 是纯数据、无代码依赖，提前迁让后续每阶段直接引用键名。

- [ ] 写入合并后的 `l10n.yaml`（保留 `header:`，迁入 `required-resource-attributes` / `use-escaping`，丢弃 `format: true`）
- [ ] 删除 `lib/l10n/arb/app_es.arb`
- [ ] 迁入旧仓库 `app_en.arb` / `app_zh.arb` 全量 1,072 键（**全部留在 app，不拆分**，见 §0.7 偏离登记 D3）
- [ ] 迁 `l10n.dart` 扩展，含 `l10n` 与 `l10nOrNull` 两个 getter
- [ ] `flutter gen-l10n` 生成成功，生成文件带 `// coverage:ignore-file`
- [ ] 确立约束：**`packages/` 下任何包都不得引用 `AppLocalizations`**，共享组件文案一律构造参数传入

### 步骤 4 — CI 接入

- [ ] `very_good test --coverage --min-coverage 100`
- [ ] `bloc_lint`
- [ ] `dart format --set-exit-if-changed`
- [ ] `flutter analyze --fatal-infos`
- [ ] melos 脚本：一条命令跑全部包

### 步骤 5 — 基础设施包

**`packages/zeta_logging`**（493 行）

- Data 层：无外部数据源，纯工具包
- 迁移内容：`app_logging.dart`（结构化日志）、`structured_error_logging.dart`、`sensitive_data_redactor.dart`

- [ ] 建包，`pubspec.yaml` 仅依赖 `logger`
- [ ] 迁 `AppLogging` / 结构化错误日志
- [ ] 迁 `SensitiveDataRedactor`（39 行）——**所有日志出口必须经它脱敏**
- [ ] 迁 `test/src/core/logging/`，补齐至 100%

**`packages/zeta_storage`**（268 行）

- Data 层：`AtomicTextFile`（原子写）、`ZetaDataPaths`（数据路径解析）、`PathUtils`、`SystemFileManager`
- **这是全项目唯一允许直接文件 IO 的底层包**

- [ ] 建包，依赖 `zeta_logging`
- [ ] 迁 `AtomicTextFile`、`ZetaDataPaths`、`PathUtils`、`SystemFileManager`
- [ ] 定义异常族：`sealed class StorageException` → `StorageWriteException` / `StorageReadException` / `StoragePathException`
- [ ] 迁 `test/src/core/storage/`，补齐至 100%

### 步骤 6 — 分层依赖检查

一个测试遍历各包 `pubspec.yaml`，把 VGV 分层规则变成 CI 门禁。

- [ ] `*_api` 包不依赖任何 `*_repository` 与 `*_client`
- [ ] `*_client` 包互不依赖（`codex` / `claude_code` / `grok` 三方隔离）
- [ ] `*_repository` 包不依赖 `flutter`（例外见步骤 21）
- [ ] `app_ui` 不依赖任何 `*_repository`
- [ ] app 侧 `lib/` 下 `import 'dart:io'` 计数快照——**建立基线，P3 结束必须为 0**

---

## P1 · Data 层契约

### 步骤 7 — `packages/agent_provider_api`

6,148 行、33 个文件、约 190 个公开类型。**全项目的语义枢纽**。

#### Data 层：抽象接口

`AgentProviderBundle` 的 21 个 capability port 原样迁移。必选 2 个，可选 19 个：

| 分类 | 端口 |
| --- | --- |
| **必选** | `AgentRuntimePort`、`AgentConversationPort` |
| Thread 管理 | `AgentThreadCatalogPort`、`AgentThreadSubscriptionPort`、`AgentThreadNamingPort`、`AgentThreadArchivalPort`、`AgentThreadDeletionPort`、`AgentThreadCompactionPort`、`AgentThreadBranchingPort`、`AgentLocalThreadListPort` |
| 交互回写 | `AgentPermissionResponsePort`、`AgentQuestionResponsePort`、`AgentDeniedActionOverridePort`、`AgentPlanApprovalPort`、`AgentTurnSteeringPort` |
| 目录查询 | `AgentModelCatalogPort`、`AgentConversationModeCatalogPort`、`AgentSkillsPort` |
| 配置 | `AgentSessionConfigurationPort`、`AgentPermissionPolicyPort`、`AgentUsageQuotaProvider` |

外加工厂接口 `AgentProviderBundleFactory`。

#### 不可变实体（按主题分组）

| 主题 | 关键实体 |
| --- | --- |
| 事件 | `AgentEvent` 族（827 行）：`AgentTurnStartedEvent`、`AgentTurnCompletedEvent`、`AgentToolCallEvent`、`AgentTokenUsageEvent`、`AgentStatusEvent`、`AgentSystemItemEvent`、`AgentThread*Event` 系列 |
| 会话 | `AgentSession`、`AgentTurn`、`AgentContext`、`AgentTurnConfiguration`、`AgentTurnModelConfig` |
| Thread | `AgentThreadSummary`、`AgentThreadPage`、`AgentThreadListQuery`、`AgentThreadHistorySnapshot`、`AgentThreadTurnContext` |
| 工具 | `AgentToolCall`、`AgentToolKind`、`AgentToolStatus` |
| 文件变更 | `AgentTextReplacementEvidence`、`AgentWrittenContentEvidence`、`AgentUnifiedPatchEvidence`、`AgentFileChangeKind`、`AgentFileChangeReplayability` |
| 权限 | `AgentPermissionRequestSnapshot`、`AgentPermissionDecision`、`AgentPermissionKind`、`AgentPermissionApplyScope`、`AgentPermissionRequestSource` |
| 计划 | `AgentPlanApprovalDecision`、`AgentPlanEntryStatus`、`AgentPlanApprovalContinuation`、`AgentPlanExecutionPermissionOrigin` |
| 用量 | `AgentTokenUsage`、`AgentUsageQuotaSnapshot`、`AgentUsageWindow`、`AgentUsageCredits` |
| 能力 | `AgentProviderCapabilities`、`AgentProviderKind`、`AgentProviderLifecycleState`、`AgentRuntimeCompatibilityStatus` |
| 输入 | `AgentUserInput`、`AgentTextUserInput`、`AgentSkillUserInput`、`AgentUserInputOption` |
| 失败语义 | `sealed class AgentProviderFailure` 族（**新增**，替代废除的 TextCatalog）：`AgentCliNotFound`、`AgentCapabilityUnsupported`、`AgentTurnRejected` 等，只带语义与参数，不带文案 |

#### Checklist

- [ ] 建包，`pubspec.yaml` **只允许**依赖 `meta` / `collection`——不得出现 `flutter`
- [ ] 迁 21 个 capability port + `AgentProviderBundleFactory`
- [ ] 迁全部实体，逐文件核验零 `dart:io`、零 Flutter、零厂商字段
- [ ] **`AgentUiTextCatalog`（260 行）+ `FallbackAgentUiTextCatalog`（395 行）不迁**（§0.7 D3）；改为定义 `sealed class AgentProviderFailure` 失败类型族，只承载语义与参数
- [ ] `FallbackAgentUiTextCatalog` 的 395 行文案逐条并入 app 的 ARB，登记对照表供 P7 步骤 30 核验
- [ ] `cursor_retirement_policy.dart` **不迁**（P7 步骤 33 清退）
- [ ] 验证包可用纯 `dart test` 运行，不引入 `flutter_test`
- [ ] 迁 `test/src/features/agent/domain/`，补齐至 100%

### 步骤 8 — `packages/json_rpc_transport`

1,299 行。

- Data 层：`JsonRpcStdioTransport`（stdio 传输）、`ProviderOperationScheduler`（操作调度）、`ProviderRuntimeJsonRpcPeer`（peer 生命周期）
- 异常：`sealed class TransportException` → `TransportClosedException` / `TransportTimeoutException` / `TransportProtocolException`

- [ ] 建包，依赖 `zeta_logging`（日志脱敏）
- [ ] 迁三个传输文件
- [ ] 定义 `TransportException` 族，替换裸 `throw`
- [ ] 迁 `test/src/features/agent/data/datasources/transport/`，补齐至 100%

---

## P2 · Data 层实现

三个 client 包**可并行**，互不依赖。每个包的结构相同：`<Vendor>AgentProviderBundle` 实现 `AgentProviderBundle` 的端口子集，mapper 负责协议字段 → 中立实体。

### 步骤 9 — 三个 provider client

#### `packages/codex_app_server_client`（≈6.3k 行）

| 角色 | 类 |
| --- | --- |
| Bundle 实现 | `CodexAppServerAgentProvider`（1,253 行） |
| 传输客户端 | `CodexAppServerClient` |
| Mapper | `CodexNotificationMapper`（983）、`CodexAppServerHelpers`（1,447）、`CodexApprovalMapper`、`CodexQuestionMapper`、`CodexModelListMapper`、`CodexSkillsMapper`、`CodexFileChangeTracker`、`CodexCollaborationModeMapper`、`CodexTurnStartParamsEncoder` |
| Codec | `CodexConversationModeCodec`、`CodexPermissionPolicyCodec`、`ContextWindowCodec` |
| CLI 定位 | `CodexCliLocator` |

#### `packages/claude_code_client`（≈7.4k 行）

| 角色 | 类 |
| --- | --- |
| Bundle 实现 | `ClaudeCodeAgentProvider`（1,391 行） |
| 会话历史 | `ClaudeCodeSessionHistoryReader`（1,242 行） |
| 适配器 | `ClaudeCodeControlRequestHandler`、`ClaudeCodeEventMapper`、`ClaudeCodePermissionPolicyAdapter`、`ClaudeCodePlanApprovalAdapter`、`ClaudeCodeUsageQuotaAdapter` |
| Mapper | `ClaudeCodeInitializeMetadataMapper`、`ClaudeCodeUsageQuotaMapper`、`ClaudeCodeStreamIdentity` |
| Codec | `ClaudeCodePermissionModeCodec` |
| CLI 定位 | `ClaudeCodeCliLocator` |

#### `packages/grok_acp_client`（≈6.5k 行）

| 角色 | 类 |
| --- | --- |
| Bundle 实现 | `GrokAcpAgentProvider`（2,574 行） |
| ACP 共享 | `AcpContentCodec`、`AcpPermissionMapper`、`AcpSessionConfigMapper`、`AcpSessionUpdateDecoder` |
| Mapper | `GrokAcpNotificationMapper`、`GrokSessionUpdateMapper`、`GrokBillingQuotaMapper`、`GrokQuestionMapper`、`GrokSkillsMapper`、`GrokFileChangeTracker`、`GrokStreamIdentity`、`GrokErrorNormalizer` |
| Codec | `GrokPermissionModeCodec` |
| CLI 定位 | `GrokCliLocator` |

> ACP mapper 暂归 grok 包（当前唯一使用者），出现第二个 ACP provider 再抽 `acp_shared`。

#### Checklist（三个包各做一遍）

- [ ] 建包，依赖**仅** `agent_provider_api` + `json_rpc_transport` + `zeta_logging` + `zeta_storage`
- [ ] `pubspec.yaml` 不出现另外两个 client 包
- [ ] 迁 Bundle 实现，按 capability 正确填充可选端口——**不支持的能力填 `null` 并让 `capabilities` 返回 false**
- [ ] 迁全部 mapper 与 codec
- [ ] 迁 CLI locator
- [ ] 协议异常统一经 `GrokErrorNormalizer` 之类的归一化出口（其余两家补齐等价实现）
- [ ] **契约测试**：断言 entryId 归属、消息分段、去重、终态判定由本 client 自行决定（`sourceItemId` 只是 metadata）

### 步骤 10 — `packages/agent_history_client`

3,085 行，本地会话历史读取。

| 角色 | 类 |
| --- | --- |
| Codex | `CodexJsonlHistoryParser`、`CodexThreadHistoryReader` |
| Grok | `GrokUpdatesHistoryParser` |

- [ ] 建包，依赖 `agent_provider_api` + `zeta_storage`
- [ ] 迁三个 parser / reader
- [ ] 异常：`HistoryParseException`（含文件路径与行号，便于定位坏数据）
- [ ] **宽容解析**：单行解析失败跳过并记日志，不整体失败

### 步骤 11 — 测试与 fixtures

- [ ] 迁 `test/src/features/agent/data/datasources/{acp,app_server,claude_code,local_history}/`
- [ ] 迁 `test/src/features/agent/data/mappers/`
- [ ] 迁 `test/fixtures/`（`agent_file_change_evidence`、`agent_stream_identity`、`grok/acp`、`grok/local_history`）
- [ ] 三个包各自补齐至 100%

**P2 验收门**：三个 client 的 `pubspec.yaml` 互不引用；契约测试全绿。

---

## P3 · Repository 层

**本阶段是全项目第二大的重构**（仅次于 P6）。三项横切改造同时发生：

| 改造 | 规模 | 客观指标 |
| --- | --- | --- |
| `dart:io` 下沉到 Data 层 | 60+ 文件 | app 侧 `dart:io` 导入数 → **0** |
| **观察者机制 `ChangeNotifier` → `Stream`** | **10,730 行 / 29 文件** | repository 包中 `ChangeNotifier` / `ValueNotifier` → **0** |
| **废除 TextCatalog，改 typed code** | 4 组接口 + 866 行桥接 + 60+ 消费点 | `packages/` 下 `AppLocalizations` 引用 → **0** |

#### 横切改造一：观察者机制

旧代码的观察者出口全部来自 `package:flutter/foundation.dart`，与「repository 包不依赖 Flutter」硬冲突，且保留会造成 ChangeNotifier 与 Bloc 两套状态机制并存。

统一改法：

```dart
// 改造前
class XxxController extends ChangeNotifier {
  Xxx get value => _value;
  void _update(Xxx next) { _value = next; notifyListeners(); }
}

// 改造后 —— 纯 Dart，无 Flutter
class XxxController {
  final _controller = StreamController<Xxx>.broadcast();
  Stream<Xxx> get changes => _controller.stream;
  Xxx get value => _value;                       // 同步快照保留
  void _update(Xxx next) { _value = next; _controller.add(next); }
  Future<void> dispose() => _controller.close();
}
```

- [ ] `broadcast` 流（多订阅者），且**必须提供同步快照 getter**——bloc 初始化时需要当前值，不能只靠流
- [ ] 每个 `StreamController` 都有对应的 `close()`，并在 repository 的 `dispose()` 中调用
- [ ] 订阅方保存 `StreamSubscription` 并在 `close` 时取消——**泄漏的订阅在 P6 会表现为 UI 幽灵刷新**
- [ ] 行为等价性：先把旧测试的断言改写成 Stream 等价版本跑通，**再**补 Stream 特有用例（多订阅者、迟到订阅、取消后不再收到）

#### 横切改造二：TextCatalog → typed code

- [ ] 各 repository 的失败路径改为返回/抛出 `sealed` 失败类型（见下方异常族）
- [ ] `Fallback*` 的硬编码文案并入 ARB，登记对照表供 P7 步骤 30 核验
- [ ] 4 组接口与 866 行桥接删除，仓库内无残留引用

---

### 步骤 12 — `packages/agent_conversation_repository`（≈10k 行）

拆包理由与边界见拓扑文档 §2.2。本包负责**一次会话的生命周期**。

#### 内部构成

**事件管线**（5,349 行，纯同步）

`AgentEventPipeline` → `CoalescingEventBuffer` → `BoundedEventDispatcher` → `AgentConversationEventProcessor` → `AgentConversationReducer` → `AgentConversationTimelineStore` → `AgentConversationEffectRunner`

**会话编排**（≈4.7k 行）

`AgentConversationBinding`、`AgentConversationBindingManager`、`AgentProviderRuntimeRegistry`、`AgentProviderGlobalRuntime`、`AgentThreadWorkspaceController`、`AgentPlanExecutionHandoffController`、`AgentTurnContextRecorder` / `AgentTurnContextOverlay`

> ⚠️ 这两部分中 **7,446 行依赖 `flutter/foundation`**，其中包括 `agent_conversation_timeline_store.dart`（2,017 行）。**不是纯搬运**——观察者出口必须按上方"横切改造一"重写。

#### 对外接口设计

**只暴露纯 Dart 接口，bloc 看不到 JSON-RPC、进程、文件。**

```dart
abstract interface class AgentConversationRepository {
  // 会话生命周期
  Stream<AgentTimelineSnapshot> timelineFor(AgentConversationKey key);
  AgentTimelineSnapshot snapshotFor(AgentConversationKey key);   // 同步快照，bloc 初始化用
  Future<void> openThread(AgentConversationKey key, {String? threadId});
  Future<void> closeConversation(AgentConversationKey key);

  // 回合
  Future<void> submitTurn(AgentConversationKey key, AgentTurnRequest request);
  Future<void> steerTurn(AgentConversationKey key, AgentTurnRequest request);
  Future<void> cancelActiveTurn(AgentConversationKey key);

  // 四种审批语义 —— 严格隔离，各自独立方法
  Future<void> respondToPermission(AgentConversationKey key, AgentPermissionDecision d);
  Future<void> respondToQuestion(AgentConversationKey key, AgentQuestionResponse r);
  Future<void> respondToPlanApproval(AgentConversationKey key, AgentPlanApprovalDecision d);
  Future<void> startPlanExecution(AgentConversationKey key, AgentPlanExecutionRequest r);

  // Thread 操作（能力不支持时抛 AgentCapabilityUnsupportedException）
  Future<void> renameThread(String threadId, String name);
  Future<void> archiveThread(String threadId);
  Future<void> compactThread(String threadId);
  Future<AgentSession> forkThread(String threadId, AgentForkBoundary boundary);
}
```

> 目录查询（`listModels` / `listConversationModes` / `listSkills`）**不在本包**——归 `agent_provider_repository`（步骤 13）。

#### 异常族

```dart
sealed class AgentRepositoryException implements Exception { ... }

final class AgentProviderUnavailableException extends AgentRepositoryException {}
final class AgentCapabilityUnsupportedException extends AgentRepositoryException {}
final class AgentTurnRejectedException extends AgentRepositoryException {}
final class AgentThreadNotFoundException extends AgentRepositoryException {}
final class AgentPermissionResponseRejectedException extends AgentRepositoryException {}
final class AgentConfigPersistenceException extends AgentRepositoryException {}
```

转换点：`TransportException` / `ProcessException` / `FileSystemException` → 上述领域异常，保留 cause 与 stackTrace。

#### Checklist

- [ ] 用 `create dart_package` 建包，`pubspec.yaml` **不得依赖 flutter**；依赖 `agent_provider_api`、`agent_provider_repository`、三个 client、`agent_history_client`、`zeta_storage`、`zeta_logging`
- [ ] 迁事件管线 14 个文件；**此阶段不碰 Bloc**，但观察者出口按横切改造一重写
- [ ] 迁会话编排（binding / binding_manager / registry / global runtime / workspace controller / turn context）
- [ ] 定义 `AgentConversationRepository` 接口 + 默认实现，含**同步快照 getter**
- [ ] 定义异常族，在所有 client 调用点做转换
- [ ] **live / history / replay 使用各自独立的 reducer 实例**——共用会串味
- [ ] 核验包内 `ChangeNotifier` / `ValueNotifier` 出现次数为 0
- [ ] 迁 `test/src/features/agent/application/` 中管线与会话相关部分，补齐至 100%

### 步骤 13 — `packages/agent_provider_repository`（≈3.8k 行）

Provider 的**配置与目录**，与会话生命周期无关。被 `agent_conversation_repository`、`settings`、`agent_management` 三方消费——这是它必须独立成包的实证依据。

#### 内部构成

**Provider 组装**（1,944 行）：`DefaultAgentProviderFactory`、`NativeAgentProviderBundles`、`CliCommandLocator`、`CodexCliLocator` / `ClaudeCodeCliLocator` / `GrokCliLocator`、`AgentProviderConfigStore` / `Codec`、`AgentProviderStaticCapabilities`、`AgentModelCatalogCacheStore`、`AgentTurnContextStore`、`AgentIgnoredMessageLogger`

**目录与配置 controller**（≈1.9k 行）：`AgentConversationModelSelectionController`、`AgentConversationPermissionSelectionController`、`AgentConversationModeController`、`AgentSkillsCatalogController`、`AgentModelCatalogRepository`、`AgentPermissionCatalogController`、`AgentProviderSettingsController`

#### 对外接口设计

```dart
abstract interface class AgentProviderRepository {
  // Provider 配置
  Stream<List<AgentProviderConfig>> get configChanges;
  List<AgentProviderConfig> get configs;                        // 同步快照
  Future<void> setProviderEnabled(String providerId, {required bool enabled});
  Future<AgentProviderBundle> bundleFor(String providerId);

  // 目录查询（能力不支持时抛 AgentCapabilityUnsupportedException）
  Future<AgentModelList> listModels(String providerId, {bool forceRefresh = false});
  Future<AgentConversationModeCatalog> listConversationModes(String providerId);
  Future<AgentSkillsCatalog> listSkills(String providerId, {List<String> cwds});
  Future<AgentPermissionCatalog> listPermissionOptions(String providerId);

  // 选择持久化
  Future<void> persistModelSelection(String providerId, AgentModelSelection selection);
  Future<void> persistPermissionPreference(String providerId, AgentPermissionOption option);
}
```

#### Checklist

- [ ] 用 `create dart_package` 建包，**不依赖 flutter**，且**不依赖 `agent_conversation_repository`**（依赖方向单向）
- [ ] 迁 provider 组装、CLI locator、store / codec
- [ ] 迁目录与配置 controller，观察者出口按横切改造一改为 `Stream`
- [ ] **废除 `AgentManagementTextCatalog` + Fallback**（§0.7 D3）：改为返回 `sealed class AgentManagementFailure`；Fallback 文案并入 ARB
- [ ] `AgentProviderKind.cursorAcp` 的 `fromJson` 未知值兜底保留（G7 宽容解码）
- [ ] 核验包内 `ChangeNotifier` / `ValueNotifier` 出现次数为 0
- [ ] 迁对应测试，补齐至 100%

### 步骤 14 — `settings_repository` + `workspace_repository` + `project_session_repository`

#### `packages/settings_repository`（≈1.2k 行）

- **Data**：`SettingsStorageApi`（抽象）+ `FileSettingsStorageClient`（`zeta_storage` 实现）；`SystemFontCatalogApi` + `SystemFontCatalogClient`
- **DTO**：`GeneralSettingsCodec`、`AppearanceSettingsStore`
- **Entity**：`GeneralSettings`、`AppearanceSettings`、`AgentNotificationSettings`、`AppearanceFontChoice`、`SystemFontFamily`、`AppLanguage`、`MessageSendShortcut`、`AppearanceFontChoiceKind`
- **接口**：

```dart
abstract interface class SettingsRepository {
  Future<GeneralSettings> loadGeneral();
  Stream<GeneralSettings> get generalChanges;
  Future<void> setMessageSendShortcut(MessageSendShortcut shortcut);
  Future<GeneralSettingsUpdateResult> setAppLanguage(AppLanguage language);
  Future<void> setNotificationsEnabled({required bool enabled});
  Future<void> setTurnTerminalNotificationsEnabled({required bool enabled});
  Future<void> setActionRequiredNotificationsEnabled({required bool enabled});
  Future<AppearanceSettings> loadAppearance();
  Future<void> setAppearance(AppearanceSettings settings);
  Future<List<SystemFontFamily>> listSystemFonts();
}
```

- **异常**：`SettingsPersistenceException`、`SettingsDecodeException`

> `setAppLanguage` 返回 `GeneralSettingsUpdateResult` 而非 `void`——语言切换有特殊后果（Locale 冻结见 P7 步骤 30），保留这个返回值。

- [ ] 用 `create dart_package` 建包，不依赖 flutter
- [ ] 迁 Entity 与 codec
- [ ] 观察者出口改 `Stream`（本包 1,031 / 1,333 行依赖 `flutter/foundation`）
- [ ] 迁 `GeneralSettingsController` / `AppearanceSettingsController` / `AppLanguageResolver` 的逻辑到 repository
- [ ] 定义接口 + 异常族
- [ ] 迁测试，补齐至 100%

#### `packages/workspace_repository`（≈0.8k 行）

- **Data**：`WorkspaceFileSystemApi` + `DartIoWorkspaceFileSystemClient`
- **Entity**：`WorkspaceNode`、`WorkspaceNodeType`、`GitignoreMatcher`、`GitignorePattern`、`WorkspaceFileQuery`
- **接口**：

```dart
abstract interface class WorkspaceRepository {
  Future<List<WorkspaceNode>> indexProject(String root);
  List<WorkspaceNode>? filesFor(String root);
  bool isIndexReady(String root);
  void invalidate(String root);
  Future<List<WorkspaceNode>> buildTree(String root);
  Future<void> revealInSystemFileManager(String path);
}
```

- **异常**：`WorkspaceIndexException`、`WorkspacePathAccessDeniedException`

- [ ] 用 `create dart_package` 建包，不依赖 flutter
- [ ] 观察者出口改 `Stream`（本包 272 / 966 行依赖 `flutter/foundation`）
- [ ] 迁 `WorkspaceFileIndexController` / `WorkspaceFileIndexer` / `WorkspaceTreeBuilder`
- [ ] 迁 `GitignoreMatcher`（gitignore 语义要有针对性测试）
- [ ] 定义接口 + 异常族
- [ ] 迁测试，补齐至 100%

#### `packages/project_session_repository`（≈2.1k 行）

**合并 `project_threads` 与 `ide_session`**，把旧仓库的双向环内化为包内调用。

- **Data**：`IdeSessionStoreApi` + `FileIdeSessionStoreClient`
- **DTO**：`ProjectThreadsSessionSnapshotCodec`
- **Entity**：`ProjectThreadListState`、`ProjectThreadsSessionSnapshot`、`IdeSessionState`、`IdeWorkbenchLayoutState`、`RecentProjectSummary`
- **接口**：

```dart
abstract interface class ProjectSessionRepository {
  // 会话恢复与持久化
  Future<IdeSessionRestoreResult> restore();
  void requestSave(IdeSessionState snapshot);
  Future<void> saveNow(IdeSessionState snapshot);
  void cancelPendingRestore();

  // Thread 列表
  ProjectThreadListState stateFor(String projectPath);
  Stream<ProjectThreadListState> watchProject(String projectPath);
  Future<void> loadInitial(String projectPath);
  Future<void> loadMore(String projectPath);
  Future<void> setArchivedView(String projectPath, {required bool archived});
  void setSearchTerm(String projectPath, String term);
  Future<void> renameThread(String projectPath, String threadId, String name);
  Future<void> archiveThread(String projectPath, String threadId);
  Future<void> deleteThread(String projectPath, String threadId);
}
```

- **异常**：`SessionRestoreException`、`SessionPersistenceException`、`ThreadListLoadException`

- [ ] 用 `create dart_package` 建包，不依赖 flutter
- [ ] **本包 0 行依赖 Flutter，是唯一可纯搬运的 repository**
- [ ] 迁 `ProjectThreadsController`（1,122 行）+ `IdeSessionPersistenceCoordinator` + `IdeSessionStateBuilder`
- [ ] **解开双向环**：`ProjectThreadsSessionSnapshot` 与 `IdeSessionState` 现在同包，互相引用合法
- [ ] 定义接口 + 异常族
- [ ] 迁测试，补齐至 100%

### 步骤 15 — `packages/usage_statistics_repository`（≈6.5k 行）

- **Data**：`AgentTokenUsageSourceApi`（抽象）+ 三个实现
  - `CodexTokenUsageClient` + `CodexUsageLogScanner`
  - `ClaudeCodeTokenUsageClient`
  - `GrokTokenUsageClient` + `GrokUsageLogScanner`
  - `BuiltInAgentTokenUsageSourceRegistry`（注册表）
  - `GlobalRuntimeAgentUsageQuotaClient`
- **Entity**：`UsageStatisticsReport`、`UsageOverview`、`UsageTrendPoint`、`UsageTokenBreakdown`、`UsageModelShare`、`UsageProjectRankEntry`、`UsageAgentRankEntry`、`UsageErrorBreakdown`、`UsageMetricComparison`、`UsageDateWindow`、`UsageStatisticsFilter`、`AgentUsageRecord`、`AgentUsageQuery`、`AgentUsageWarning`、`AgentUsagePanelEntry`、`AgentUsageProviderSnapshot` + 6 个枚举
- **接口**：

```dart
abstract interface class UsageStatisticsRepository {
  Future<UsageStatisticsReport> query(AgentUsageQuery query, {bool forceRefresh = false});
  Future<UsageStatisticsSourceSnapshot> sourceSnapshot();
  Future<List<AgentUsageProviderDescriptor>> discoverProviders();
}

abstract interface class AgentUsagePanelRepository {
  Future<AgentUsagePanelProviderResult> loadPanel(String providerId, {bool forceRefresh = false});
  Future<List<AgentUsageProviderDescriptor>> synchronizeProviders();
}
```

- **异常**：`UsageSourceUnavailableException`、`UsageParseException`、`UsageCapabilityUnsupportedException`

- [ ] 用 `create dart_package` 建包，不依赖 flutter
- [ ] 观察者出口改 `Stream`（本包 686 / 5,759 行依赖 `flutter/foundation`）
- [ ] 迁三个 provider 的 usage source 与 scanner
- [ ] 迁 `UsageStatisticsController` / `AgentUsagePanelController` / `AgentUsageQueryService` 的查询逻辑
- [ ] **废除 `UsageStatisticsTextCatalog` + Fallback**（§0.7 D3）：枚举标签（`UsageTimeRangePreset` / `UsageTaskStatus` 等）改由 app 层 `switch` 映射到 ARB
- [ ] 定义两个接口 + 异常族
- [ ] 迁 `test/src/features/usage_statistics/{application,data,domain}/`，补齐至 100%

**P3 验收门（关键，全部可自动化核对）**

| 指标 | 迁移前 | 目标 |
| --- | --- | --- |
| repository 包 `pubspec.yaml` 的 `flutter` 依赖数 | — | **0** |
| app 侧 `lib/` 下 `dart:io` 导入数 | 60+ | **0** |
| repository 包中 `ChangeNotifier` / `ValueNotifier` 出现次数 | 29 文件 / 10,730 行 | **0** |
| `packages/` 下 `AppLocalizations` 引用数 | — | **0** |
| `agent_provider_repository` → `agent_conversation_repository` 的依赖 | — | **0**（方向单向） |
| 各包覆盖率 | — | **100%** |

- [ ] 上表六项逐条核对通过
- [ ] 全部 `StreamController` 都有配对的 `close()`，无泄漏订阅

---

## P4 · 设计系统

### 步骤 16 — `packages/app_ui`（10,754 行）

#### 保留的纯视图组件

**设计 token**（不含业务逻辑，纯常量与主题扩展）

`IdeColors`、`IdeSpacing`、`IdeTextStyles`、`IdeMetrics`、`IdeMotion`、`IdeEffects`、`AppTypography`（从 core 下沉）、`AppTheme`

**基础组件**（24 个）

`IdeButton`、`IdeChip`、`IdeChoiceCard`、`IdeCollapsibleCard`、`IdeContextMenu`、`IdeDialog`、`IdeIconBox`、`IdeImagePreview`、`IdePopover`、`IdeResizeHandle`、`IdeSelect`、`IdeSkeleton`、`IdeStatusCard`、`IdeSwitch`、`IdeTabs`、`IdeToast`、`IdeActivityRail`、`IdeStableOverlayHandler`、`WindowFrame`、`PaneWidgets`

**行与容器**：`IdeDataRow`、`IdeKeyValueRow`、`IdeListRow`、`IdeRowDivider`、`IdeRowGroup`、`IdeSettingsRow`、`IdeSurface`

**Workbench 原语**：`IdeWorkbenchScaffold`、`IdeToolbar`、`IdeSection`、`IdePageHeader`、`IdePageBody`、`IdeRetainedPageView`

**虚拟滚动子系统**（7 文件）：`IdeDynamicSliverList`、`IdeExtentIndex`、`IdeSmoothScrollController`、`IdeVirtualItem`、`IdeVirtualListController`、`IdeVirtualScrollCoordinator`、`IdeVirtualScrollbar`

**布局**：`IdeConstraintBucketBuilder`、`CompactMetricBar`

> 全部为**无状态或仅含 UI 局部状态**的组件，不持有 repository、不发起 IO。这是它们能进 `app_ui` 的前提——迁移时逐个核验。

#### l10n 处理（按 `internationalization` skill，见偏离登记 D3）

**`app_ui` 零 l10n 依赖，不持有 ARB。** 原「拆出 118 键」的设计已废弃。

- [ ] 11 个组件文案改为**构造参数**，由调用方传入：`commonMenu`、`imagePreviewUnavailable`、`imagePreviewView`、`imagePreviewViewLarge`、`tabsLoadingSuffix`、`timelineBackToBottom`、`timelineNewContent`、`timelineScrollToEnd`、`timelineScrollbar`、`workbenchCloseOverlay`、`workbenchLogoSemantics`
- [ ] `ZetaShadcnLocalizations`（384 行）与 107 个 `shadcn*` 键**留在 app** 的 `lib/l10n/`，不进 `app_ui`
- [ ] `formatInvariantNumber` 随 `ZetaShadcnLocalizations` 留在 app
- [ ] 核验 `app_ui` 中无任何 `AppLocalizations` 引用

#### Checklist

- [ ] 用 `mcp__very-good-cli__create` 建包（`app_ui_package` 模板不适用，见 D2；用 `flutter_package`）
- [ ] 依赖 `flutter` + `shadcn_flutter` + `zeta_logging`
- [ ] **不依赖任何 `*_repository` 包，不依赖 app 的 l10n**
- [ ] 迁全部 token 与组件，`shadcn_flutter` 统一 `as sf` 导入
- [ ] **一文件一组件**，文件名 = 组件名 snake_case
- [ ] `lib/src/` 私有；barrel `app_ui.dart` 导出全部公开组件与 token
- [ ] 设计 token 走 `ThemeExtension`，注册到 `ThemeData.extensions`，经 `BuildContext` 扩展读取
- [ ] 全部构造尽可能 `const`；每个公开成员写 dartdoc
- [ ] app 侧 ARB 保持 1,072 键完整，**无需拆分**

### 步骤 17 — `app_ui` 测试

按 `testing` + `ui-package` skill。

- [ ] 建 `test/helpers/pump_app.dart` —— 包自己的 `pumpApp` 助手，**禁止在测试里内联 `pumpWidget(MaterialApp(...))`**
- [ ] 迁 `test/src/ui/core/`（含虚拟滚动 7 文件测试），`test/` 镜像 `lib/` 结构
- [ ] **每个公开组件都有对应 widget 测试**，测行为而非静态视觉属性
- [ ] 静态视觉属性用 golden 测试覆盖，并打 `TestTag.golden` 标签（标签用 `abstract class TestTag` 的 `static const`，不写字面量）
- [ ] 补齐至 100%
- [ ] `app_ui` 可独立跑 `mcp__very-good-cli__test`（传 `directory: 'packages/app_ui'`）

---

## P5 · Bloc 与 Presentation

**按 feature 串行**，先易后难，用小模块建立 Bloc 迁移手法。

### 步骤 18 — `workspace` → `WorkspaceCubit`

状态简单，无多来源事件，用 Cubit。

```dart
enum WorkspaceStatus { initial, indexing, ready, failure }

final class WorkspaceState extends Equatable {
  final WorkspaceStatus status;
  final String? root;
  final List<WorkspaceNode> tree;
  final Set<String> expandedPaths;
  final String? selectedPath;
  final WorkspaceRepositoryException? error;
}
```

Cubit 方法：`indexProject(root)`、`invalidate(root)`、`toggleDirectory(path)`、`selectNode(path)`、`revealInFileManager(path)`

- **UI**：文件树视图（纯展示，接收 `WorkspaceState`）
- **注入**：`RepositoryProvider<WorkspaceRepository>` 在 app 层，`BlocProvider<WorkspaceCubit>` 在 IDE shell 层

- [ ] 建 `lib/workspace/{cubit,view}/` + barrel
- [ ] 实现 `WorkspaceCubit` + `WorkspaceState`
- [ ] 视图改为 `BlocBuilder<WorkspaceCubit, WorkspaceState>`
- [ ] `bloc_test` 覆盖 4 个 status 的全部迁移路径
- [ ] 补齐至 100%

### 步骤 19 — `settings` → `SettingsCubit`

```dart
enum SettingsStatus { initial, loading, ready, persisting, failure }

final class SettingsState extends Equatable {
  final SettingsStatus status;
  final GeneralSettings general;
  final AppearanceSettings appearance;
  final List<SystemFontFamily> systemFonts;
  final SettingsPersistenceException? error;
  final bool languageChangeRequiresRestart;   // 承接 GeneralSettingsUpdateResult
}
```

Cubit 方法与 `SettingsRepository` 一一对应。

- **反向边处理**
  - [ ] **#4**：`settings_page` 不再直接 import `agent_management` 的 presentation。改为 app 层注入 `WidgetBuilder`，或在 settings 路由内用 `BlocProvider.value` 复用 `AgentManagementBloc`
  - [ ] **#6**：`GeneralSettings` 模型已在 `settings_repository`，agent 侧从包导入

- [ ] 建 `lib/settings/{cubit,view}/` + barrel
- [ ] 实现 `SettingsCubit` + `SettingsState`
- [ ] 处理反向边 #4 与 #6
- [ ] `bloc_test` 覆盖，含持久化失败路径
- [ ] 补齐至 100%

### 步骤 20 — `app_update` → `AppUpdateBloc`

有明确状态机（`AppUpdatePhase`），用 Bloc。

**Event**

```dart
sealed class AppUpdateEvent
final class AppUpdateInitialized extends AppUpdateEvent {}
final class AppUpdateStartupCheckRequested extends AppUpdateEvent {}
final class AppUpdateManualCheckRequested extends AppUpdateEvent {}
final class AppUpdateSnoozeRequested extends AppUpdateEvent {}
final class AppUpdateReleasePageOpened extends AppUpdateEvent {}
```

**State**：复用现有 `AppUpdateState`（含 `AppUpdatePhase`、`AppReleaseInfo`、`AppInstallationInfo`、`AppUpdateFailureReason`），加 `Equatable`。

- **UI**：更新提示卡片、手动检查入口
- **注入**：`BlocProvider<AppUpdateBloc>` 在 app 顶层（启动检查需要在 shell 之前触发）

- [ ] 建 `lib/app_update/{bloc,view}/` + barrel
- [ ] 实现 5 个 Event 的 handler
- [ ] `bloc_test` 覆盖全部 `AppUpdatePhase` 迁移 + 全部 `AppUpdateFailureReason`
- [ ] 补齐至 100%

### 步骤 21 — `desktop_notifications` → `DesktopNotificationsBloc`

> **分层例外**：本模块的 data client 依赖 `flutter_local_notifications` 与 MethodChannel，无法进纯 Dart repository 包。因此 repository 留在 app 内 `lib/desktop_notifications/repository/`，并在 P0 步骤 6 的分层检查中显式登记为例外。

**Event**

```dart
final class DesktopNotificationsInitialized extends DesktopNotificationsEvent {}
final class DesktopVisibilityChanged extends DesktopNotificationsEvent {}
final class AgentAttentionReceived extends DesktopNotificationsEvent {}
final class ThreadMarkedRead extends DesktopNotificationsEvent {}
final class NotificationActivated extends DesktopNotificationsEvent {}
```

**State**：`DesktopNotificationsState { unreadCount, visibility, pendingAttentions }`

- **反向边 #5**：不再依赖 `settings` 的 controller。改为消费 `SettingsRepository`，或在 app 层用 `BlocListener<SettingsCubit>` 把通知开关变化桥接过来

- [ ] 建 `lib/desktop_notifications/{bloc,repository}/` + barrel
- [ ] **废除 `DesktopAttentionTextCatalog` + Fallback**（§0.7 D3）：通知标题与正文改由 bloc 从 `context.l10n` 取值后传给 repository
- [ ] 处理反向边 #5
- [ ] 在分层检查中登记 Flutter 依赖例外
- [ ] `bloc_test` 覆盖，补齐至 100%

### 步骤 22 — `project_threads` + `ide_session`

两个 bloc 共享 `ProjectSessionRepository`。

**`ProjectThreadsBloc`**

| Event | 来源方法 |
| --- | --- |
| `ProjectActivated` | `activateProject` |
| `ProjectsRetained` | `retainProjects` |
| `ProjectToggled` | `toggleProject` |
| `ArchivedViewChanged` | `setArchivedView` |
| `SearchTermChanged` | `setSearchTerm` |
| `InitialThreadsRequested` | `loadInitial` |
| `MoreThreadsRequested` | `loadMore` |
| `ThreadSelected` / `ThreadSelectionCleared` | `selectThread` / `clearSelectedThread` |
| `ThreadRenamed` / `ThreadArchived` / `ThreadDeleted` | 对应方法 |
| `ThreadRunningChanged` | `setThreadRunning` |
| `CompletedThreadDismissed` | `dismissCompletedThread` |
| `RuntimeSnapshotSynced` | `syncRuntimeSnapshot` |

**State**：`ProjectThreadsState { Map<String, ProjectThreadListState> byProject, activeProjectPath, status, error }`

**`IdeSessionCubit`**：`restore()`、`requestSave(snapshot)`、`saveNow(snapshot)`；State 含 `IdeSessionState` + `isRestoring`

- [ ] 建两个 feature 目录 + barrel
- [ ] 实现 `ProjectThreadsBloc`（15+ Event）
- [ ] 实现 `IdeSessionCubit`
- [ ] 两个 bloc **不互相依赖**，联动经 app 层 `BlocListener`
- [ ] `bloc_test` 覆盖，补齐至 100%

### 步骤 23 — `agent_management` → `AgentManagementBloc`

**Event**

```dart
final class AgentManagementInitialized      // initialize({autoDetect})
final class AgentDetectionRequested         // detect
final class AgentSelected                   // selectAgent
final class AgentEnabledChanged             // setEnabled
final class ClaudeAccountEnrichmentChanged  // setClaudeCodeAccountDataEnrichmentEnabled
final class AgentConnectionTestRequested    // testConnection
final class AgentConfigurationLoaded        // loadConfiguration
final class AgentConfigurationSaved         // saveConfiguration
final class AgentLogsRequested              // loadLogs
final class AgentRuntimeStateRefreshed      // refreshRuntimeState
```

**State**

```dart
final class AgentManagementState extends Equatable {
  final AgentManagementStatus status;
  final List<ManagedAgent> agents;
  final String? selectedAgentId;
  final AgentDetectionProgress? detection;
  final AgentConnectionTestResult? lastTestResult;
  final AgentConfigurationDocument? configuration;
  final List<AgentLogEntry> logs;
  final AgentRepositoryException? error;
}
```

> `validateConfiguration(content)` 是**同步纯函数**，不走 Event——保留为 repository 的同步方法，UI 直接调用做即时校验。

- **UI**：`agent_management_page.dart`（1,734 行）——本阶段仅改造为 `BlocBuilder`，**不拆分**（§5.4）
- **注入**：`BlocProvider<AgentManagementBloc>` 在设置路由层

- [ ] 建 `lib/agent_management/{bloc,view,widgets}/` + barrel
- [ ] 实现 10 个 Event 的 handler
- [ ] 保留 `validateConfiguration` 为同步调用
- [ ] `bloc_test` 覆盖全部 `AgentInstallationState` / `AgentRuntimeState` / `AgentAccountState` 组合
- [ ] 补齐至 100%

### 步骤 24 — `usage_statistics` → `UsageStatisticsBloc` + `AgentUsagePanelCubit`

两套独立状态，分别对应两个 controller。

**`UsageStatisticsBloc`**

| Event | 来源 |
| --- | --- |
| `UsageStatisticsInitialized` | `initialize` |
| `UsageRefreshRequested` | `refresh` |
| `TimePresetSelected` | `selectTimePreset` |
| `CustomRangeSelected` | `selectCustomRange` |
| `ProjectFilterSelected` | `selectProject` |
| `ProviderFilterSelected` | `selectProvider` |
| `ModelFilterSelected` | `selectModel` |
| `RankSortSelected` | `selectRankSort` |

**State**（由 controller 的 13 个 getter 归并）

```dart
final class UsageStatisticsState extends Equatable {
  final UsageStatisticsStatus status;
  final UsageStatisticsFilter filter;   // preset/customStart/customEnd/project/provider/model/rankSort
  final UsageStatisticsReport? report;
  final UsageStatisticsSourceSnapshot? source;
  final List<String> warnings;
  final DateTime? lastUpdated;
  final UsageSourceUnavailableException? error;
}
```

**`AgentUsagePanelCubit`**：`refresh()`、`synchronizeProviders()`、`selectProvider(id)`、`restorePreferredProviderId(id)`、`selectProviderFromTurn(id)`

State：`{ providers, selectedProviderId, preferredProviderId, entries, lastUpdated, status, error }`

- **UI**：`usage_statistics_page.dart`（1,669 行）、`agent_usage_panel.dart`（1,215 行）——改造为 `BlocBuilder` / `BlocSelector`，不拆分
- **注入**：`UsageStatisticsBloc` 在统计页路由层；`AgentUsagePanelCubit` 在 IDE shell 层（侧栏常驻）

- [ ] 建 `lib/usage_statistics/{bloc,cubit,view,widgets}/` + barrel
- [ ] 实现 `UsageStatisticsBloc`（8 Event）
- [ ] 实现 `AgentUsagePanelCubit`
- [ ] 图表组件（`fl_chart`）保持纯视图，只接收已计算好的 `UsageTrendPoint` 等实体
- [ ] `bloc_test` 覆盖，补齐至 100%

---

## P6 · Agent 会话（最高风险，单独立项）

### 步骤 25 — `AgentConversationViewModel`（4,190 行）→ `AgentConversationBloc`

#### 关键发现：状态切片已经存在

`agent_conversation_ui_state.dart`（1,098 行）已经把状态切成 **5 个独立 slice**，各自暴露 `ValueListenable`：

| 现有 slice | 职责 |
| --- | --- |
| `AgentHeaderState` | Provider 名称、能力、thread 状态胶囊 |
| `AgentComposerState` | 输入框、模型选择、模式、Skill |
| `AgentPendingInteractionState` | 权限 / 提问 / Plan 审批 / Plan 执行四类待处理项 |
| `AgentExpansionState` | 工具调用、Plan、命令组、文件编辑的展开态 |
| `AgentConversationHistoryState` | 时间线条目与历史 turn |

**这个切分是为性能存在的**（避免整树重建），迁移**必须保留**。

**设计决策**：一个 `AgentConversationBloc`，State 是这 5 个 slice 的复合；UI 用 `BlocSelector` 订阅单个 slice。**不拆成 5 个 bloc**——它们共享同一条事件流与同一个 reducer，拆开会引入 bloc 间依赖（VGV 明令禁止）。

```dart
final class AgentConversationState extends Equatable {
  final AgentHeaderState header;
  final AgentComposerState composer;
  final AgentPendingInteractionState pending;
  final AgentExpansionState expansion;
  final AgentConversationHistoryState history;
  final AgentConversationStatus status;
  final AgentRepositoryException? error;
}
```

#### 24a — 状态类

- [ ] 5 个 slice 类加 `Equatable`，迁入 `lib/agent_chat/bloc/`
- [ ] 定义复合 `AgentConversationState`
- [ ] 保留 `AgentConversationUiStateDiagnostics`（诊断字段，用于排查合并与调度问题）

#### 24b — 事件流接入

- [ ] 订阅 `AgentRepository.timelineFor(key)`，转为 `AgentTimelineUpdated` 事件
- [ ] reducer 与 EffectRunner **留在 repository 层**，bloc 只消费结果
- [ ] 保留按 frame 合并的 UI 更新调度（`AgentUiUpdateScheduler`，269 行）

#### 24c — 用户操作接入（安全关键）

**四种审批语义严格隔离，四组独立 Event 类型，绝不预授权任何操作。**

| 语义 | Event | 对应 repository 方法 |
| --- | --- | --- |
| 权限响应 | `PermissionResponded` | `respondToPermission` |
| 提问回答 | `QuestionResponded` | `respondToQuestion` |
| Plan 审批 | `PlanApprovalResponded` | `respondToPlanApproval` |
| Plan 执行交接 | `PlanExecutionStarted` / `PlanExecutionRevised` / `PlanExecutionDismissed` | `startPlanExecution` 等 |

其余 Event 分组：

| 分组 | Event |
| --- | --- |
| 会话 | `ConversationOpened`、`ThreadReopenRetried`、`ContextUpdated` |
| 回合 | `MessageSubmitted`、`ActiveTurnCancelled`、`LastUserMessageEdited` |
| 模型配置 | `ModelSelected`、`ReasoningEffortSelected`、`ServiceTierSelected`、`FastEnabledChanged`、`ModelsRefreshRequested`、`ModelCompatibilityConflictResolved`、`ModelConfigurationSaveRetried` |
| 模式与 Skill | `ConversationModeSelected`、`ConversationModesRetried`、`SkillsCatalogRequested` |
| Thread 操作 | `CurrentThreadRenamed`、`CurrentThreadArchived`、`CurrentThreadCompacted`、`CurrentThreadForked` |
| 展开态 | `ToolCallToggled`、`PlanMessageToggled`、`ActivePlanToggled`、`CommandGroupToggled`、`FileEditItemToggled` |
| 权限偏好 | `PermissionOptionSelected`、`PermissionPreferencePersistenceRetried`、`GuardianDeniedActionApproved` |
| 其他 | `ProviderSwitched`、`SessionConfigOptionSelected`、`ContextPanelToggled` |

- [ ] 四种审批语义各自独立 Event，**不共用基类字段**
- [ ] `bloc_test` 补**负向用例**：验证任一审批 Event 不会连带授予其他语义的权限

#### 24d — UI 派生逻辑

- [ ] 把 view model 中的派生计算（`shouldShowActivePlan`、`threadStatusCapsuleLabel`、`canSelectConversationMode` 等）改为 State 的 getter 或独立 selector 函数
- [ ] 时间线投影缓存（`AgentTimelineProjectionCache`、`AgentFileChangeProjectionCache`、`AgentMarkdownCache`）保留为纯函数 + 缓存对象，不进 State

### 步骤 26 — Presentation widgets（18 文件 / 13,017 行）

#### 保留的纯视图组件

| 文件 | 行数 | 处理 |
| --- | --- | --- |
| `agent_pane_cards.dart` | 2,220 | `BlocSelector<_, AgentConversationHistoryState>`；**建议拆分** |
| `agent_model_config.dart` | 1,971 | `BlocSelector<_, AgentComposerState>`；**建议拆分** |
| `agent_pane_composer.dart` | 1,607 | `BlocSelector<_, AgentComposerState>`；**建议拆分** |
| `agent_pane_sections.dart` | 1,130 | `BlocSelector` |
| `agent_pane_context_panel.dart` | 891 | `BlocSelector` |
| `agent_pane_messages.dart` | 854 | `BlocSelector<_, AgentConversationHistoryState>` |
| `agent_pane_navigation_rail.dart` | 670 | `BlocSelector<_, AgentHeaderState>` |
| `agent_file_change_evidence_views.dart` | 505 | 纯视图，无需改造 |
| `agent_pane_plan_panel.dart` | 465 | `BlocSelector<_, AgentPendingInteractionState>` |
| `agent_mode_selector.dart` | 442 | `BlocSelector<_, AgentComposerState>` |
| `agent_pane_styles.dart` | 440 | 纯样式，无需改造 |
| `agent_slash_command_picker.dart` | 413 | 纯视图 |
| `agent_pane_header.dart` | 369 | `BlocSelector<_, AgentHeaderState>` |
| `agent_file_change_evidence_card.dart` | 275 | 纯视图 |
| `agent_mention_file_picker.dart` | 233 | 纯视图（消费 `WorkspaceCubit`） |
| `composer_selector_popover.dart` | 229 | 纯视图 |
| `agent_skill_picker.dart` | 190 | 纯视图 |
| `agent_provider_icon.dart` | 113 | 纯视图 |

- [ ] 逐文件改造为 `BlocBuilder` / `BlocSelector`
- [ ] **每个 widget 只订阅它需要的那个 slice**——订阅整个 State 会让性能切分白做
- [ ] 拆分三个 >1.5k 行的文件（P6 是 §5.4 的唯一例外）
- [ ] 迁 `test/src/features/agent/presentation/harness/` 与 widget 测试

### 步骤 27 — Capability 渲染测试

- [ ] 对 19 个可选端口，各写一条 widget 测试：端口为 null 或 `capability = false` 时，对应 UI 入口**不出现在菜单里**
- [ ] 应用层误调用不支持的能力时抛 `AgentCapabilityUnsupportedException`——**验证不是静默成功**

**P6 验收门**

- [ ] 四种审批语义隔离在 `bloc_test` 中被显式断言（含负向用例）
- [ ] 真实 CLI 三路冒烟：Codex + Claude Code + Grok
- [ ] 补齐至 100%

---

## P7 · 应用外壳与收口

### 步骤 28 — `ide_shell` → `IdeShellBloc`

合并 `ui/features/ide/`（4,059 行）+ `app/shell/ide_shell_controller.dart`（1,467 行）。反向边 #2 消失。

**Event**（由 `IdeShellController` 的公开方法归并）

| 分组 | Event |
| --- | --- |
| 项目 | `ProjectOpenRequested`、`RecentProjectOpened`、`KnownProjectSelected`、`ProjectRemoved`、`ProjectRevealedInFileManager`、`RecentHomeDataRefreshed` |
| Thread | `ProjectThreadSelected`、`AgentThreadActivated`、`NewThreadStarted`、`ProjectThreadRenamed`、`ProjectThreadArchived`、`ProjectThreadUnarchived`、`ProjectThreadDeleted`、`ProjectThreadForked`、`CompletedProjectThreadDismissed`、`MoreThreadsRequested`、`ThreadsRetried` |
| 布局 | `LeftSidebarVisibilityChanged`、`LeftSidebarWidthChanged`、`AgentUsageProviderSelected` |
| 文件树 | `TreeExpansionChanged`、`TreeNodeTapped` |
| 持久化 | `SessionSaveRequested` |

**State**

```dart
final class IdeShellState extends Equatable {
  final IdeShellStatus status;
  final List<String> projects;
  final String? activeProjectPath;
  final bool isProjectHomeActive;
  final List<AgentThreadWorkspaceEntry> workspaceEntries;
  final String? selectedWorkspaceEntryId;
  final IdeWorkbenchLayoutState layout;
  final List<RecentProjectSummary> recentProjects;
  final List<AgentThreadSummary> recentThreads;
  final bool initialRestoreCompleted;
  final String? recentHomeRefreshError;
}
```

> **注意**：旧 `IdeShellController` 直接持有 `AgentConversationViewModel`（`selectedAgentViewModel`）。VGV 下 bloc 不得持有另一个 bloc——改为 shell 只持有 `AgentConversationKey`，由 UI 层按 key 取对应的 `BlocProvider`。

#### 保留的纯视图组件

`ide_home.dart`（1,162）、`project_list_pane.dart`（1,157）、`global_home_page.dart`（702）、`project_home_page.dart`（591）、`new_thread_provider_popover.dart`（230）、`project_agent_sidebar.dart`（81）

- [ ] 建 `lib/ide_shell/{bloc,view,widgets}/` + barrel
- [ ] 实现 `IdeShellBloc`（25+ Event）
- [ ] **解除对 ViewModel 的直接持有**，改为按 key 索引
- [ ] 迁 6 个视图文件，改造为 `BlocBuilder` / `BlocSelector`
- [ ] 反向边 #2 消失（`menu_action_bridge` 与 shell controller 同包）
- [ ] `bloc_test` 覆盖，补齐至 100%

### 步骤 29 — `lib/app/` 装配层

**注入方式：`RepositoryProvider` 在最外层，`BlocProvider` 按作用域分层。**

```
MultiRepositoryProvider           ← 全部 repository，app 根部单例
  └─ MultiBlocProvider            ← 全局 bloc
       ├─ SettingsCubit           （全局：语言、外观、通知开关）
       ├─ AppUpdateBloc           （全局：启动检查早于 shell）
       ├─ DesktopNotificationsBloc（全局：托盘与角标）
       └─ MaterialApp.router
            └─ IdeShellBloc       （shell 作用域）
                 ├─ WorkspaceCubit
                 ├─ ProjectThreadsBloc
                 ├─ IdeSessionCubit
                 ├─ AgentUsagePanelCubit
                 └─ AgentConversationBloc  ← 每个 workspace entry 一个实例，按 key 创建
```

路由内按需创建：`AgentManagementBloc`（设置页）、`UsageStatisticsBloc`（统计页）。

- [ ] `MultiRepositoryProvider` 注入全部 repository
- [ ] 三个全局 bloc 在 `MaterialApp` 之上
- [ ] shell 作用域 bloc 在 shell 之下
- [ ] `AgentConversationBloc` 按 `AgentConversationKey` 创建，随 entry 关闭而 close
- [ ] bloc 间联动全部经 `BlocListener`，**无直接依赖**
- [ ] `zeta_startup_bootstrap` 接入 VGV `bootstrap.dart`

### 步骤 30 — l10n 收口

- [ ] 建 `lib/l10n/failure_messages.dart`：全部 `sealed` 失败类型 → ARB 键的 `switch` 映射函数，**这是全项目唯一的本地化点**
- [ ] 核验 `Fallback*` 的 395 行文案已全部并入 ARB（对照 P1 步骤 7 登记的对照表），无遗漏、无重复
- [ ] 确认 4 组 TextCatalog 接口与 `ZetaTextCatalogs`（866 行桥接）已全部删除，仓库内无残留引用
- [ ] `ZetaAppLocalizationsDelegate`（`SynchronousFuture` 同步加载，避免首帧空白）就位
- [ ] `ZetaLocalization.delegates` 组合 5 个 delegate
- [ ] **Locale 冻结**：`_frozenDisplayLocale` 逻辑迁入 `bootstrap.dart` + `lib/app/`
- [ ] `supportedLocales` 保留 `zh-Hans` 与 `zh` 两个条目

### 步骤 31 — 三 flavor

- [ ] `main_development.dart` / `main_staging.dart` / `main_production.dart` 对接 `bootstrap.dart`
- [ ] 三平台 × 三 flavor 各构建一次

### 步骤 32 — 数据迁移专项验证

- [ ] 老用户 provider 配置的版本化读取与宽容解码
- [ ] 会话索引（`ide_session_store`）升级
- [ ] turn context 存储升级
- [ ] 用真实旧版本数据文件跑升级回归

> Cursor 数据清洗**不在本步骤**——已随退役代码整体前置到**步骤 0**，在旧仓库内完成。到 P7 时新仓库已无任何 cursor 痕迹。

### 步骤 33 — 文档收口

- [ ] [migration_topology.md](./migration_topology.md) 更新为最终架构说明
- [ ] 本文件标记全部完成
- [ ] `CONTRIBUTING.md` 补 VGV 分层规则与包边界说明
- [ ] `docs/architecture/layering.md` 定稿：四层职责、注入方式、bloc 作用域图
- [ ] **双语终审**：§0.6 映射表全部打勾；`docs/README.md` 与 `docs/README.en.md` 索引与实际文件一一对应，无死链
- [ ] 校验每个 `xxx.md` 都有 `xxx.en.md` 配对，且语言切换头正确

**P7 验收门**

- [ ] 三平台构建通过
- [ ] 全量测试绿，覆盖率 100%
- [ ] 老版本数据升级回归通过
- [ ] 真实 CLI 端到端冒烟
- [ ] 中英文各跑一次 UI 冒烟（Locale 冻结生效、缺键正确回退英文）

---

## 附：跨阶段追踪项

这些项贯穿多个阶段，单独列出避免遗漏。

### 反向边

- [ ] #1 `settings → app`（步骤 3 自动消失）
- [ ] #2 `ui/features → app`（步骤 28 自动消失）
- [ ] #3 `ide_session ↔ project_threads`（步骤 14 合并解开）
- [ ] #4 `settings → agent_management/presentation`（步骤 19）
- [ ] #5 `desktop_notifications → settings/application`（步骤 21）
- [ ] #6 `agent → settings/domain`（步骤 19）

### 承接的产品需求（架构不自动保证）

- [ ] **四种审批语义隔离、绝不预授权**（步骤 25c，含负向用例）
- [ ] **持久化宽容解码**（§0.2 全部 codec + 步骤 32）
- [ ] **能力缺失不静默成功**（步骤 27）
- [ ] **entryId 归属由各 client 自定**（步骤 9 契约测试）

### 客观指标

| 指标 | 迁移前 | 目标 | 验证阶段 |
| --- | --- | --- | --- |
| app 侧 `dart:io` 导入数 | 60+ | **0** | P3 |
| client 包互相依赖数 | — | **0** | P2 |
| repository 包 flutter 依赖数 | — | **0**（1 例外） | P3 |
| **repository 包中 `ChangeNotifier` / `ValueNotifier` 数** | **29 文件 / 10,730 行** | **0** | P3 |
| **`packages/` 下 `AppLocalizations` 引用数** | — | **0** | P3 / P4 |
| **仓库内 `TextCatalog` 残留引用数** | 4 组 + 866 行桥接 | **0** | P7 |
| **仓库内 `cursor` 相关标识符数** | 11 处 | **0** | 步骤 0 |
| bloc 间直接依赖数 | — | **0** | P5–P7 |
| 覆盖率 | — | **100%** | 每阶段 |
