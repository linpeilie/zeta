# 迁移拓扑分析

中文 ｜ [English](../../en/architecture/migration_topology.md)

本文件定义旧仓库 `D:\Development\Workspace\zeta` 当前 `dev` → 新 VGV 仓库的迁移边界、目标拓扑和执行顺序。逐步任务见 [migration_tasks.md](./migration_tasks.md)。

## 0. 结论

迁移可以开始，但必须先完成 P-1 的基线冻结与架构清单。目标架构严格遵守 VGV 四层：

```text
Presentation → Business Logic (Bloc/Cubit) → Repository → Data
```

除 ADR-001 的 Provider 中立契约包外，不保留旧项目的分层例外：

- Data 与 Repository 都是 `packages/` 下的独立 Dart 包，零 Flutter SDK。
- Repository 之间零依赖；跨领域编排由 Bloc/Cubit 完成。
- 业务与交互状态只在 Bloc/Cubit；Repository Stream 只表示外部数据变化。
- Widget 不调用 Repository 或平台插件，只读取 Bloc 并派发事件。
- Flutter 插件与 MethodChannel 的具体实现只存在于 app 装配边界 `lib/app/platform/`，通过纯 Dart 端口注入。
- GoRouter 是唯一导航机制；使用 typed route，不使用 `extra`。

当前没有发版，因此本次不承担历史版本、旧 Bundle ID、旧 SharedPreferences 或新旧应用共存兼容。目标是当前 `dev` 的功能等价迁移和干净安装。

---

## 1. 已确认的执行前提

| 维度 | 决策 |
| --- | --- |
| 迁移源 | 旧仓库当前 `dev`；分析基线 `bfd42412c9c3a0b39bb93598f93f9e5eca471236`，Cursor 清退后再固定最终迁移 SHA |
| 状态管理 | 全量迁到 Bloc/Cubit |
| 架构 | 严格 VGV 四层；Repository 之间零依赖 |
| Provider 契约 | 接受 ADR-001：`agent_provider_contracts` 存放多 Provider 共用的中立契约与不可变模型 |
| 目标平台 | macOS / Windows / Linux |
| UI 基础 | 保留 `shadcn_flutter`，共享设计系统为 `packages/app_ui` |
| 导航 | 引入 GoRouter；typed routes；本次仅应用内导航，不注册 OS 外部 deep link |
| Monorepo | 原生 Dart workspace；迁移初期不引入 Melos |
| 应用身份 | 三个 flavor 均使用 `cn.easii.zeta`、产品名 `Zeta`、数据目录 `~/.zeta`，不做 flavor 隔离 |
| 版本 | 采用新仓库 `1.0.0+1` |
| 数据兼容 | 无历史版本兼容；仅验证干净安装和当前 schema |
| 无障碍目标 | WCAG 2.2 AA；覆盖 macOS / Windows / Linux |
| 明确不迁移 | `app_update`、Velopack、旧仓库 `tool/packaging/` |
| 明确迁移（2026-08-19 裁决） | `third_party/codex_app_server_schema/`、`tool/` 的冒烟与门禁脚本；理由见[逐文件清单 §5](./migration_manifest.md) |
| 旧仓库 | Cursor 清退完成后 freeze，不再并行开发功能 |

“不做 flavor 隔离”意味着 development、staging、production 不能并存安装，且共享同一份本地数据。三个 entrypoint 只允许改变运行配置和日志级别，不得改变 schema、应用 ID 或目录。

产品、迁移范围与无障碍目标均已确认，当前没有需要产品决策的阻塞项。

---

## 2. 当前 `dev` 基线

统计时间：2026-08-19。生成的 l10n Dart 文件单独列出，不计入人工迁移规模。

| 范围 | 文件 | 行数 |
| --- | ---: | ---: |
| `lib/src` 人工 Dart | 348 | 101,599 |
| l10n generated Dart | 3 | 10,318 |
| `test` Dart | 265 | 86,910 |
| `package:zeta/src/...` import | 1,165 | — |
| en / zh ARB | 每种语言 1,040 键 | — |

旧仓库 feature：

| Feature | 文件 | 行数 | 目标 |
| --- | ---: | ---: | --- |
| `agent` | 184 | 62,822 | Provider Data、Conversation/Provider Repository、`agent_chat` Bloc/UI |
| `agent_management` | 14 | 6,449 | `agent_management_client`、Repository、Bloc/UI |
| `desktop_notifications` | 6 | 494 | 平台端口、Repository、Bloc |
| `ide_session` | 7 | 659 | session client、Repository、Cubit |
| `project_threads` | 5 | 1,689 | 与 ide session 共用 Repository，状态进 Bloc |
| `settings` | 13 | 2,047 | settings client、Repository、Cubit/UI |
| `usage_statistics` | 35 | 8,785 | Provider 数据源、storage client、Repository、Bloc/UI |
| `workspace` | 8 | 1,067 | file-system client、Repository、Cubit/UI |

平台与资源也属于迁移输入，不能被 Dart 拓扑遗漏：Linux 15 个文件、macOS 33 个文件、Windows 69 个文件、assets 13 个文件。生成的 plugin registrant 可重新生成；手写 Runner、MethodChannel、图标与字体必须进入 source→target 清单。

上述数字是分析快照。步骤 0 修改旧仓库后，P-1 必须重新生成最终数字和 SHA，不允许执行期继续引用本节的临时 SHA。

---

## 3. 分层判定规则

### 3.1 Data

Data 只负责外部通信和外部格式：进程、stdio、Provider 协议、本地文件、平台通道、系统字体、通知、文件选择和剪贴板。

- 返回 typed response/model，不把裸 JSON 泄漏给 Repository。
- 不含筛选、选择、展开、加载状态或用户操作规则。
- Data 包零 Flutter；Flutter adapter 位于 `lib/app/platform/`，实现纯 Dart 端口。
- app 的 Bloc/Presentation 不直接消费 Data 端口；平台能力也必须先经过 Repository。
- vendor client 互不依赖。
- 所有构造依赖可注入，测试不得启动真实进程或写真实用户目录。

### 3.2 Repository

Repository 组合 Data、转换模型、维护缓存和外部资源生命周期。

- Repository 之间不得 import。
- 不依赖 Flutter，不产出 Zeta 自有的本地化 UI 文案。
- 可暴露外部数据变化的 Stream 和同步 snapshot，但不得保存 UI 选择或页面加载状态。
- Provider 事件归一化、会话聚合、runtime lease 和协议 effect 属于领域数据编排，可留在 Repository。
- 搜索词、选中项、展开态、loading/failure status、导航目标和交互规则属于 Bloc。

### 3.3 Business Logic

Bloc/Cubit 负责业务规则、跨 Repository 编排和全部交互状态。

- Bloc 之间零直接依赖；联动由 UI `BlocListener` 或共同的外部数据 Stream 完成。
- 每个异步事件必须声明 transformer；不接受默认并发作为隐含行为。
- Bloc 不持有 `BuildContext`、GoRouter、Widget、MethodChannel 或 Data client。
- 领域失败以 typed code 进入 State；UI 再映射到 ARB。

### 3.4 Presentation

- Page 创建并注入 Bloc，View/Widget 消费 State。
- 回调用 `context.read`，build 用 `BlocBuilder` / `BlocSelector`。
- 导航使用生成的 typed route；标准跳转用 `go()`，只有需要返回值才用 `push()`。
- 路由参数只传稳定 ID；不得传文件路径对象或使用 `extra`。
- 渲染、导航、dialog/snackbar 等 Flutter side effect 通过 `BlocListener` 完成。

### 3.5 Composition root

`bootstrap.dart` 是唯一能同时看见 Data client、Repository 和 app platform adapter 的文件。`main_<flavor>.dart` 只选择 flavor 配置并调用 bootstrap，不直接 import Data package。

allowlist 必须按依赖种类精确表达：

- `lib/bootstrap.dart`：可 import Data、Repository 和 app platform adapter。
- `lib/app/platform/**`：只可 import `desktop_platform_api`、Flutter services 和对应 plugin，不可 import vendor/settings/workspace 等 Data client。
- 其余 `lib/**`：只可 import Repository 公开 barrel，不可 import 任一 Data package。

---

## 4. 目标包拓扑

### 4.1 共享契约与基础设施

| 包 | 来源 | 职责 |
| --- | --- | --- |
| `agent_provider_contracts` | `features/agent/domain/` | ADR-001；21 个 capability port、中立 Provider/会话/事件/权限/计划/用量模型；零 vendor 字段 |
| `json_rpc_transport` | `agent/data/datasources/transport/` | JSON-RPC stdio、operation scheduler、peer 生命周期 |
| `zeta_logging` | `core/logging/` + `core/security/` | 结构化日志与敏感数据脱敏 |
| `zeta_storage` | `core/storage/` + 路径工具 | 原子文件操作、目标 schema 数据路径、存储异常 |
| `desktop_platform_api` | 新建纯 Dart 端口 | 系统字体、通知、attention、目录选择、剪贴板、窗口/menu 命令的中立端口 |

ADR-001 是唯一的模型归属例外。它解决“三个独立 Data client 必须实现同一套中立 capability port”的问题。包内只允许不可变契约、typed code 和纯函数，不允许业务状态、vendor 字段、IO 或 Flutter。

### 4.2 Provider Data

| 包 | 来源 | 职责 |
| --- | --- | --- |
| `codex_app_server_client` | Codex app-server datasource、mapper、codec、CLI locator | 实现 Codex capability ports；Codex history/usage 数据读取 |
| `claude_code_client` | Claude Code datasource、mapper、codec、CLI locator | 实现 Claude capability ports；history、quota、credential probe |
| `grok_acp_client` | ACP/Grok datasource、mapper、codec、CLI locator | 实现 Grok capability ports；Grok history/usage 数据读取 |
| `agent_history_client` | Provider 无关的 history 合并/重放输入 | 只做格式读取与容错，不做 UI timeline 投影 |
| `agent_config_client` | provider config/cache/turn-context store 与 codec | Provider 配置、目录缓存、turn context 的当前 schema 持久化 |
| `agent_management_client` | 三个 management datasource、CLI process runner、auth probe | 检测、连接测试、配置/日志读写，返回 vendor-neutral response |

CLI locator 只能有一个归属：各自 vendor client。`agent_config_client` 和 Repository 不重复实现 locator。

### 4.3 其余 Data

| 包 | 来源 | 职责 |
| --- | --- | --- |
| `settings_client` | settings stores/codecs | general/appearance 当前 schema 文件读写 |
| `workspace_client` | workspace file indexer 的 IO 边界 | 文件扫描、gitignore 输入、目录读取 |
| `project_session_client` | ide session store + snapshot codec | 当前 session schema 读写 |
| `usage_statistics_storage_client` | usage partition/cache/index | 统计缓存与派生索引；Provider 原始数据由三个 vendor client 提供 |

系统字体、notification、window/menu、file selector、pasteboard 的 concrete adapter 不进入这些 Dart 包，而位于 `lib/app/platform/` 并实现 `desktop_platform_api`。

### 4.4 Repository

| 包 | Data 依赖 | 职责 |
| --- | --- | --- |
| `agent_provider_repository` | contracts、agent config、三个 vendor client | Provider 配置、bundle factory registry、model/mode/skill/permission 目录 |
| `agent_conversation_repository` | contracts、history、config、storage/logging | 会话聚合、事件管线、runtime lease、timeline snapshot；不依赖 provider repository |
| `agent_management_repository` | management client、config client、contracts | 检测/诊断/配置/日志的领域转换；不依赖 provider repository |
| `settings_repository` | settings client、desktop platform port | settings domain model、系统字体转换与持久化 |
| `workspace_repository` | workspace client | 文件树/查询数据；不保存选中或展开状态 |
| `project_session_repository` | project session client、vendor thread ports | session snapshot、thread catalog 数据；不保存搜索/选择 UI 状态 |
| `usage_statistics_repository` | 三个 vendor client、usage storage client | 聚合 Provider 用量、缓存和报告 domain model |
| `desktop_notifications_repository` | desktop platform notification ports | 发送已经本地化的通知内容、角标和 attention；不依赖 settings repository |
| `desktop_platform_repository` | desktop platform directory/clipboard/window/menu ports | 目录选择、剪贴板、窗口与菜单命令的领域封装；防止 Bloc 绕过 Repository |

跨领域场景由 Bloc 组合：

- `AgentConversationBloc` 先向 `agent_provider_repository` 取 bundle，再传给 `agent_conversation_repository`。
- `AgentConversationBloc` 通过 `desktop_platform_repository` 请求文件选择和剪贴板操作，不直接调用 platform port。
- `DesktopNotificationsBloc` 同时消费 settings 与 notifications repository。
- `IdeShellBloc` 同时消费 workspace、project session 与 desktop platform repository。

### 4.5 Shared UI

`packages/app_ui` 保留 shadcn_flutter，包含设计 token、基础组件、Workbench 原语和虚拟滚动。它可以依赖 Flutter、shadcn_flutter 和纯 UI 工具，但不得依赖 Repository、Data client 或 `AppLocalizations`。

### 4.6 App features

```text
lib/
├── app/
│   ├── app.dart
│   ├── router/                  # typed GoRouter + generated routes
│   ├── platform/                # Flutter/MethodChannel adapters
│   └── view/
├── l10n/
├── agent_chat/{bloc,view,widgets}/
├── agent_management/{bloc,view,widgets}/
├── desktop_notifications/bloc/
├── ide_session/cubit/
├── project_threads/{bloc,view}/
├── settings/{cubit,view}/
├── usage_statistics/{bloc,cubit,view,widgets}/
├── workspace/{cubit,view}/
└── ide_shell/{bloc,view,widgets}/
```

`app_update` 不存在于目标拓扑。

---

## 5. 业务状态归属

| 旧代码类别 | 目标 |
| --- | --- |
| Provider JSON/stdio/process/CLI locator | vendor Data client |
| 文件 store/codec、目录扫描、native channel | Data client / app platform adapter |
| response → domain model、缓存、会话 aggregate、runtime lease | Repository |
| 搜索、筛选、选中、展开、loading/failure、重试策略 | Bloc/Cubit |
| timeline UI slice、composer state、pending interaction state | `AgentConversationState` |
| Markdown/render/cache、frame coalescing、scroll controller | Presentation helper |
| 本地化文案 | app `lib/l10n/` |
| navigation location | GoRouter；Bloc 只持有业务 ID 和加载结果 |

Repository 的 `ChangeNotifier` 不能机械替换为 Stream。执行时先判断它代表外部数据还是 UI/业务状态：前者改 Repository Stream，后者改 Bloc State。

Conversation reducer/effect runner 的保留边界：Provider 事件到会话 domain snapshot 的确定性归并留在 Repository；任何 UI slice、展开规则、选择规则、导航和本地化移到 app。

---

## 6. GoRouter 拓扑

本次使用 `go_router` + `go_router_builder`，只做应用内导航，不配置 OS deep link。

建议层级：

```text
/home
/projects/:projectId
/projects/:projectId/threads/:threadId
/settings
/settings/agents
/settings/agents/:agentId
/usage-statistics
```

- 使用 `@TypedShellRoute` 承载 IDE shell。
- `projectId` 是由 canonical path 派生并由 Repository 可解析的稳定、URL-safe ID，URL 不直接暴露文件路径。
- Router 是当前页面、projectId、threadId 的唯一真源。
- Session restore 只计算 initial location 或 redirect；不得再让 `IdeShellBloc` 反向驱动同一份导航状态。
- 页面不存在或 ID 失效时 redirect 到 `/home` 并由 typed failure 提示。
- 原生菜单和 UI 菜单都调用 typed route；Bloc 不依赖 GoRouter。

---

## 7. Bloc 并发与生命周期

| 事件类别 | 默认 transformer | 理由 |
| --- | --- | --- |
| 搜索词、筛选、Provider/model 选择后的刷新 | `restartable()` | 新输入淘汰旧请求 |
| load more、重复刷新按钮 | `droppable()` | 防止重复并发 |
| 权限/提问/Plan 响应、持久化写、会话 open/close | `sequential()` | 必须保持顺序，禁止重复副作用 |
| Provider/timeline 外部 Stream | `restartable()` subscription | 切换时取消旧源 |
| 纯同步展开/选择 | 默认同步 handler | 无异步竞态 |

每个 Bloc/Cubit 必须：

- 在 `close()` 取消 subscription、timer 和缓存 lease。
- 对异步完成后的过期结果做 generation/key 检查。
- 用 `blocTest()` 覆盖顺序、取消、重复事件和失败路径。
- 不把 Exception/StackTrace 直接作为可渲染文案；State 保存 typed failure。

---

## 8. 国际化

- 迁入当前 `dev` 的 en/zh ARB，重新以 1,040 键为基线；Cursor 清退后再次计数。
- ARB 是 Zeta 自有 UI 文案的唯一真源。
- `app_ui` 文案由构造参数传入。
- packages 不得创建需要本地化的 Zeta UI 文案；允许承载用户内容、Provider 原文和内部诊断字符串。
- TextCatalog/Fallback 双轨全部删除，下层返回 typed code，app `lib/l10n/` 穷尽映射。
- `ZetaShadcnLocalizations` 留在 app，不进入 `app_ui`。
- Bloc 不使用 `BuildContext`。Desktop notification 使用注入的、无 BuildContext 的 app copy resolver 生成已本地化 title/body。
- 语言仍在启动时冻结；三个 flavor 共用相同 Locale 与 schema 行为。

---

## 9. 自动化架构门禁

CI 必须自动断言：

1. Data/Repository 包的 `pubspec.yaml` 不依赖 Flutter。
2. 任一 Repository 不依赖其他 `*_repository`。
3. vendor client 互不依赖。
4. feature `lib/**` 不 import `*_client`、`dart:io` 或 `package:flutter/services.dart`。
5. Data/client import 在 app 侧只允许 composition-root allowlist。
6. `app_ui` 不依赖 Repository/Data/AppLocalizations。
7. packages 不 import app 的 `lib/`。
8. 外部消费者不 import 任一 package 的 `src/`。
9. feature widget 不直接调用 Repository；Page 仅负责 Bloc 注入。
10. Bloc 之间零构造依赖。
11. GoRouter route 为 typed hierarchical route，仓库内无 `extra:` 和裸路径导航。
12. 所有 StreamController、subscription、timer 和 runtime lease 有关闭路径。
13. `pubspec.lock` 通过 OSV 漏洞扫描；任何 advisory 忽略项必须就地写明适用性理由。
14. WCAG 2.2 AA widget tests 覆盖 semantics、键盘焦点、目标尺寸、文字缩放、对比度和拖拽替代；reduce-motion 作为额外 VGV 平台门禁。

ADR-001 和 composition-root allowlist 必须由机器可读配置表达，不接受注释中的隐含例外。

---

## 10. 执行 Roadmap

| 阶段 | 目标 | 风险 | 并行度 |
| --- | --- | --- | --- |
| P-1 | Cursor 代码清退、最终 SHA、source→target 清单、ADR | 中 | 否 |
| P0 | 桌面骨架、统一身份、Dart workspace、assets/l10n/CI/门禁 | 中 | 否 |
| P1 | 共享契约、logging/storage、transport、platform ports | 中 | 部分 |
| P2 | Provider/management Data clients | 中 | 三个 vendor client 可并行 |
| P3 | settings/workspace/session/usage Data | 低 | 可并行 |
| P4 | 全部 Repository；严格清除业务状态 | 高 | 按依赖分组 |
| P5 | app_ui 与 l10n typed mapping | 中 | 可与 P2/P3 部分并行 |
| P6 | 小 feature Bloc/Presentation | 中 | 先易后难，串行定型 |
| P7 | AgentConversationBloc 与高频 UI | 高 | 否 |
| P8 | IdeShellBloc、GoRouter、bootstrap、三平台收口 | 高 | 否 |

P4 与 P7 是核心风险：P4 决定业务状态是否真正离开 Repository，P7 决定高频 Provider 事件迁到 Bloc 后是否保持顺序、性能和审批安全。

---

## 11. 最终验收

### 代码质量

- analyze / format / test / coverage 全绿；Dart/Flutter 人工代码覆盖率 100%。
- 每个 package 可独立测试。
- 全部自动化架构门禁通过。

### 功能与安全

- Codex、Claude Code、Grok 三路真实 CLI 冒烟。
- 权限响应、提问、Plan 审批、Plan 执行交接四种语义隔离，含不预授权负向测试。
- capability 缺失时 UI 入口不存在，误调用 fail closed。
- 敏感凭据与 Provider 内容不进入日志。
- Zeta 文件、assets、`--dart-define` 与 native config 不保存或编译进真实密钥；Provider 凭据只由 Provider CLI / OS 凭据存储管理。
- process 启动不拼接 shell command；project/file ID 解析、路径边界和 symlink 行为有负向测试。
- `pubspec.lock` 的 OSV 扫描及依赖许可证检查通过；未记录理由的 advisory/license 例外为零。

### 桌面与导航

- macOS/Windows/Linux debug 与 release build 通过。
- 三个平台统一 `cn.easii.zeta` / `Zeta`；三个 flavor 不加身份后缀。
- 系统字体、通知、角标、窗口/menu、目录选择、剪贴板平台契约通过。
- GoRouter 的启动恢复、redirect、back、无效 ID、菜单导航测试通过。

### 无障碍

- 按 WCAG 2.2 AA 执行 macOS VoiceOver、Windows Narrator/NVDA、Linux Orca 与纯键盘 smoke。
- 所有交互可由键盘完成并有可见焦点；icon-only 控件有语义；异步状态可播报。
- 普通文本对比度至少 4.5:1，大文本至少 3:1，UI 组件与焦点指示至少 3:1；文字放大 200% 不丢失内容。
- 交互目标满足 AA 的 24×24 dp 下限，并以 VGV 48×48 dp 为设计目标；拖拽操作具有同屏非拖拽替代。
- 焦点不被遮挡、高对比度和 reduce-motion 测试通过；reduce-motion 是额外平台质量门禁，不声明为 AA 条款。
- Linux Flutter/Orca 已知限制必须进入限制清单，不得以自动化测试替代手工验证。

### 性能与生命周期

- event-storm fixture 下无乱序、旧 subscription 幽灵更新或重复副作用。
- 长时间线滚动和高频 delta 的帧耗时、内存峰值不劣于旧 `dev` 的记录基线。
- 关闭 workspace/app 后 Provider process、subscription、timer、lease 全部释放。

### 范围确认

- 仓库内不存在迁入的 `app_update` / Velopack / 更新 native channel / packaging 任务。
- distribution signing、notarization 与 installer packaging 不在本次范围；release build smoke 不等于发布流程验收。
- 不执行历史数据升级测试；使用空目录验证干净安装和当前 schema。
- 中英文文档、README 索引和 source→target 清单一致。

---

## 附：统计口径

- 源码基线为旧仓库当前 `dev` 的 Git 跟踪内容；未跟踪的 `.workflow/feature/2026-08-18-PC端构建与版本检查/` 不属于迁移输入。
- Dart 行数含空行与注释；l10n generated 单列。
- feature 依赖图统计 `package:zeta/src/...` import；最终清单还必须单独覆盖相对 import、native Runner、assets、pubspec 和平台配置。
- source→target 清单必须让每个迁移范围内文件恰好出现一次；删除项必须写明删除理由和验证方式。
