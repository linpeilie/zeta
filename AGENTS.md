# 项目 AI 规则

Zeta 是 Flutter Desktop 的本地 Agent IDE 壳层（macOS / Windows / Linux）。它不含模型、不实现编辑器：把本机已有的 Agent CLI 拉起来，把对方的私有协议翻译成一套中立领域事件，再渲染成可审计的时间线。当前活跃 Provider 是 **Codex**（默认，app-server JSON-RPC）、**Grok**（ACP）与 **Claude Code**（stream-json）；Cursor 已退役，所有边界 fail-closed。

> **本文件是约束规则的权威源。** 它只写「必须遵守什么」和「怎么自查」。
> 「为什么这样约束」和完整正文在 `docs/`，每条门禁都给了出处，不要在本文件里复制正文。
>
> | 想要 | 去哪 |
> |---|---|
> | 十几分钟建立心智模型（带图） | [`docs/architecture/overview.md`](docs/architecture/overview.md) |
> | entryId / bundle / capability / coalescing / lease 的定义 | [`docs/guides/glossary.md`](docs/guides/glossary.md) |
> | 门禁的完整正文与评审细则 | [`docs/architecture/engineering_standards.md`](docs/architecture/engineering_standards.md) |
> | 接入清单、操作步骤、验收脚本 | [`docs/guides/developer_guide.md`](docs/guides/developer_guide.md) |
> | 人类贡献者版摘要 | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
>
> 冲突时以本文件为准，并**同步修正**被违反的那一份。

---

## 0. 收尾协议（每次改完代码必做）

按顺序执行，缺一不可：

```sh
dart format .            # 编辑过 Dart 文件就必跑
flutter analyze          # 结束改动前必跑（只覆盖根 Package）
flutter test             # 行为有变化时必跑
bash tool/test_packages.sh   # 动过 packages/ 就必跑：逐个 dart analyze + dart test
```

`dart_test.yaml` 固定 `concurrency: 2`——单个 worker 跑大 Widget 测试会加载完整 IDE Shell，放开并发会触发内存峰值。**不要为了跑得快改掉它。**

然后在回复**最后**附上【Git 提交信息】模块：

- [Conventional Commits](https://www.conventionalcommits.org/) 格式（`feat` / `fix` / `docs` / `refactor` / `test` / `chore` / `perf`）
- 摘要一句话，≤50 字符
- 必要时换行给改动点列表
- 用独立 `sh` 代码块包裹，便于直接 `git commit -m`

```sh
feat(agent): 优化 Plan 交接卡的键盘焦点

- 补齐 Esc 关闭后的焦点恢复
- 修复修订输入框在窄视口被挤压
```

---

## 1. 硬门禁

**违反其中任何一条，功能再正确也要打回。** 这八条是多 Provider 接入不互相污染的地基，不是形式主义。

### G1 · 共享适配层零 Provider 依赖

共享层是 Provider 无关的**机制层**，不是安放厂商兼容逻辑的兜底层。范围：

```
packages/zeta_agent_core/lib/src/application/agent_event_pipeline.dart
packages/zeta_agent_core/lib/src/application/agent_event_coalescing_policy.dart
packages/zeta_agent_core/lib/src/application/coalescing_event_buffer.dart
packages/zeta_agent_core/lib/src/application/bounded_event_dispatcher.dart
packages/zeta_agent_core/lib/src/application/agent_conversation_timeline_store.dart
lib/src/features/agent/data/mappers/acp_*.dart      # 共享 ACP decoder/codec/mapper
```

这些文件里**禁止**出现：具体 Provider 的 import、按 `providerId`/kind/实现类型/显示名分支、从 raw 或 extra payload 猜身份、为某个 Provider 修乱序或补 id。文件变更的 owner/change id、动作、累计快照、可回放性与 tool/turn fallback 取舍同样属于 Provider 语义。厂商差异一律退回该 Provider 自己的 adapter/reducer 消化后输出语义完整的 `AgentEvent`。

共享层若必须产出 Zeta 自有用户可见文案，只允许通过构造函数注入不可变、Provider 无关的 `AgentUiTextCatalog`；禁止 import generated l10n、Flutter `Locale` / `BuildContext`，也不得按 Provider 分支选文案。

**自查**（应无输出；注释里出现 Provider 名做说明是允许的）：

```sh
grep -rnE "(codex|grok|claude|cursor)" \
  packages/zeta_agent_core/lib/src/application/agent_event_pipeline.dart \
  packages/zeta_agent_core/lib/src/application/agent_event_coalescing_policy.dart \
  packages/zeta_agent_core/lib/src/application/coalescing_event_buffer.dart \
  packages/zeta_agent_core/lib/src/application/bounded_event_dispatcher.dart \
  packages/zeta_agent_core/lib/src/application/agent_conversation_timeline_store.dart \
  lib/src/features/agent/data/mappers/acp_*.dart \
  | grep -viE "^\S+:[0-9]+:\s*(///|//|\*)"
```

> 正文：[工程规范 §4.2](docs/architecture/engineering_standards.md#42-共享适配层纯度门禁) · 归属判定表：[开发者文档 §7「共享适配层修改判定」](docs/guides/developer_guide.md)

### G2 · 身份由 Provider 决定，Store 不猜

`sourceItemId` / `sourceMessageId` **只是协议 metadata**，不是 UI 合并键。`entryId`、message segment、reasoning phase、narrative boundary、去重、终态判定，全部由该 Provider 的 adapter/reducer 决定。`AgentConversationTimelineStore` 只做 dumb merge：同 entryId 更新、异 entryId 新建、同 tool id 原地 upsert——不读最后一条猜边界、不改写 id、不分配 segment。

文件变更也遵守同一边界：Provider-local tracker 必须在进入共享 pipeline 前产出完整的 `AgentFileChangeSnapshot`。Store 只机械替换 typed snapshot；presentation 只按中立 evidence 变体渲染，不得读取 raw/wire key、解析命令或访问工作区补算 diff。

**新增 Provider 不应该需要改 TimelineStore 或 CoalescingPolicy。** 如果你发现非改不可，先停下来开 Issue：那通常意味着抽象没做对。

> 正文：[工程规范 §4.1](docs/architecture/engineering_standards.md)

### G3 · reducer 纯同步，副作用走 EffectRunner

`AgentConversationReducer` 只能同步产出 typed state、`AgentTimelineMutation`、ThreadSnapshot、`AgentUiUpdateRequest`、`AgentConversationEffect`。**禁止** import Flutter scheduler、创建 `Timer`、执行 `Future`、调用外部回调。

副作用统一走 scope-aware EffectRunner，执行前重新校验 listener generation、runtime/epoch 和必要的 thread scope。

**live / history / replay 必须使用各自独立的 reducer 实例**，不共享 current segment、seen event/tool、terminal 或 generation 状态。共用会串味。

> 正文：[工程规范 §4](docs/architecture/engineering_standards.md) · 接入清单：[开发者文档 §7](docs/guides/developer_guide.md)

### G4 · 按 capability 渲染，不支持就抛，禁止静默成功

UI 一律按 `AgentProviderCapabilities` 和 `AgentProviderBundle` 端口是否为空渲染，**不按 provider kind 或名称硬编码**。端口缺失或 `capability = false` 时对应入口根本不出现；application / data 层执行前仍要二次校验，误调用必须抛 `UnsupportedError`。

**不得用 no-op、空 answers 或语义不等价的降级伪造能力**——静默成功会让用户以为操作生效了。

当前 bundle 端口：必选 `runtime` / `conversation`；可选 `threadCatalog` / `threadSubscription` / `threadNaming` / `threadArchival` / `threadDeletion` / `threadCompaction` / `threadBranching` / `turnSteering` / `permissionResponses` / `questions` / `deniedActionOverride` / `modelCatalog` / `conversationModes` / `skills` / `localThreadList` / `sessionConfiguration` / `planApproval` / `permissionPolicy` / `usageQuota`（见 `lib/src/features/agent/domain/agent_provider_bundle.dart`）。

> 正文：[架构总览「Provider 能力协商」](docs/architecture/overview.md) · [工程规范 §4](docs/architecture/engineering_standards.md)

### G5 · 四种审批语义隔离，且绝不预授权

这是新人最容易踩的坑。看起来都是「弹卡片让用户点」，但它们不共享 request/decision 模型和 pending registry：

| 类型 | 谁发起 | 回写路径 |
|---|---|---|
| 权限审批 | Provider | `respondToPermission`（只接受 approve/deny/cancel） |
| 用户提问 | Provider | `respondToQuestion`（结构化 answers，空 map = Skip） |
| Plan 审批 | Provider | `AgentPlanApprovalPort` |
| **Plan 执行交接** | **Zeta 本地** | 不调用上面任何端口 |

Plan 执行交接是 Zeta 自己的 application 工作流，不持久化。执行动作必须**新建一个显式的 Default `turn/start`**——不是 steer 当前 turn，不是调 `AgentPlanApprovalPort`。**任何动作都不得预授权计划里提到的命令、文件或网络操作。** 执行权限只可恢复进入 Plan 前由用户明确选择且仍在同 Binding/thread/runtime generation 有效的策略；失效时回落到 Provider catalog 声明的保守默认，目录不可用则要求用户显式选择。不得自动升级权限或持久化本次覆盖。

> 正文：[架构总览「三种审批」](docs/architecture/overview.md) · [开发者文档 §7「Plan conversation mode」](docs/guides/developer_guide.md)

### G6 · 分层依赖单向，协议只在 data 层

```
main → app → presentation/application → domain
              app → data → domain
              presentation → zeta_ui（packages/）
```

- `domain` 是纯的：无 Flutter、无 `dart:io`、无任何 Provider 协议字段。想在 domain 里 import Codex 类型，说明放错层了。
- Codex JSON-RPC、JSONL 历史解析、ACP payload、provider 配置格式**只能存在于 data 层的 adapter / mapper / codec**。UI 和 application 消费中立 domain 模型。
- Provider 自有 data adapter 可按明确功能读取对应 CLI 的配置、会话、日志、账号 metadata 等私有数据；原始结构和路径不得泄漏到 domain、application 或 presentation。读取权限不自动授权迁移、改写或删除，写操作仍须由明确的产品能力和用户动作约束。
- Flutter `Locale`、`BuildContext` 和 generated `AppLocalizations` 只允许出现在 `app` 组合层、presentation 和 `ui/`。application / data / domain 若必须产出即时文案，只依赖该 feature 的纯 Dart 文本目录 port。
- `lib/main.dart` 只做 Flutter 绑定、窗口启动、全局错误日志和 `runApp`；`lib/src/app` 是唯一装配点。
- 新代码进 `lib/src/features/<feature>/{domain,application,data,presentation}`，**不要新建顶层宽泛目录**。现有 feature：`agent`、`agent_management`、`desktop_notifications`、`ide_session`、`project_threads`、`settings`、`usage_statistics`、`workspace`。跨 feature 基础设施才进 `lib/src/core`；**跨 feature 复用的 UI 原语进 `packages/zeta_ui`**（设计系统已整体拆包，`lib/src/ui/core` 只剩需要本机 IO 的宿主侧封装）。
- 已物理拆出的内部 Package 在 `packages/`：`zeta_foundation`（纯 Dart 公共契约：Clock / OperationId / Transition / 排版常量 / 日志与指标端口）、`zeta_plugin_kernel`（可信插件微内核）、`zeta_ui`（Graphite 设计系统）与 `zeta_agent_core`（中立 Agent 内核：领域模型与端口、Binding/runtime 契约、事件管线、纯 reducer、TimelineStore、Effect 描述）。依赖方向单向：`kernel → foundation`、`ui → foundation`、`agent_core → foundation`；`zeta_foundation` / `zeta_plugin_kernel` 不依赖 Flutter；`zeta_ui` 依赖 Flutter/shadcn 但**不依赖** Riverpod、`dart:io`、generated l10n 或任何业务模型（控件自有文案走 `ZetaUiTextCatalog` 注入）；`zeta_agent_core` 目前只依赖 `flutter/foundation`（ChangeNotifier），**不依赖** widgets/material、Riverpod、`dart:io`、Provider 协议或根 app——日志走 `ZetaLogger` 端口，Provider 身份映射由组合层注入。
- **Agent feature 的分层现状**：中立内核在 `packages/zeta_agent_core`；Provider 协议适配仍在 `lib/src/features/agent/data`；ChangeNotifier 形态的 feature controller（settings / mode / model selection / skills / 目录 / workspace 组合）仍在 `lib/src/features/agent/application`，等 Phase 2/3 转成 MVI 切片。新代码按这条边界放：中立机制进包，Provider 语义进 data，UI 编排进 app。**跨 Package 只能 import 对方顶层 barrel**，禁止 `package:<name>/src/...`。新增 Package 要先在[目标架构 §3.2](docs/architecture/target_architecture_riverpod_mvi_plugins_packages.md) 的判据下论证，不按页面或团队机械拆包。

> 正文：[工程规范 §1–2](docs/architecture/engineering_standards.md) · [架构总览「分层」](docs/architecture/overview.md)

### G7 · 不落盘敏感内容，JSON 版本化且宽容

Zeta 自有数据全部在 `~/.zeta/`：`config/` · `state/` · `logs/` · `cache/`。feature store 只接收 `lib/src/app` 注入的具体文件，**presentation / application 不得自己拼 `~/.zeta` 路径**。

- 持久化 JSON 必须**版本化 + 宽容解码**：缺字段、损坏、旧版本、未知字段都不能阻断应用启动。
- 派生索引、缓存、日志、系统通知 payload **只保存规范化白名单字段**。
- **禁止落盘**：prompt、回复正文、工具输出、文件变更 evidence 正文（替换片段、写入内容、patch）、原始错误文本、session 文件路径、环境变量值、凭证、Provider raw payload、localized UI copy（ARB 字符串、文本目录输出）。
- JSON-RPC transport 日志不得记录 prompt、文件内容、认证参数或 stderr 原文；Agent 日志进 UI 前必须在 data 层完成脱敏。
- **指标同样受此约束**：只能通过 `ZetaMetricsPort`（`lib/src/core/observability/`）上报，指标名必须登记进 `ZetaMetric` 白名单枚举，标签只有 `providerId` / `component` / `outcome` 三个规范化维度。采集实现只在 `lib/src/app/observability` 组合，业务层一律只见端口且默认 no-op；Riverpod `ProviderObserver` 不得读取 provider state 或 family 参数。

> 正文：[工程规范 §5](docs/architecture/engineering_standards.md) · [开发者文档 §9](docs/guides/developer_guide.md)

### G8 · 主题走 token，`shadcn_flutter` 只能 `as sf`

```dart
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
```

语义真源是 `IdeThemeScope` 下的 Graphite token：`IdeColors.of(context)`、`IdeTextStyles.of(context)`、`IdeRadius` / `IdeEffects` / `IdeSpacing` / `IdeMotion`。`sf.ThemeData` 仅作为第三方 Widget 的投影。

**禁止**：Material `ThemeData` / `ColorScheme.fromSeed`、裸 `Color(0x...)`、手写 `BoxShadow` 列表、临时拼的 `BorderRadius.circular(...)`、已移除的 `shadcn_ui` / `Shad*` / `showShadDialog` API。通知统一 `showIdeToast`（`packages/zeta_ui/lib/src/ide_toast.dart`），不要在 feature 里散落 `sf.showToast`。

**控件高度由内容撑开，容器高度由 token 固定。**

- **控件**（Select / Tabs / Button / IconButton / 未来的 TextField）：高度 = `2 × IdeMetrics.controlPaddingYFor(size) + 内容`，下限走 `controlMinHeightFor`。**禁止**给控件套 `SizedBox(height:)` 或 `maxHeight` 把高度钉死——一旦钉死，各控件内边距的分歧就被藏起来，等哪天拆掉固定高度会一次性散成好几个高度（本项目曾经是 20/23/25/33 靠一个 34 的常数强行对齐）。需要一个具体数字（测试断言、骨架屏占位）时用 `controlNaturalHeightFor`，不要拿它回头去设高度。
- **控件内的图标**必须过 `IdeIconBox`：图标比文字行盒高就会成为决定高度的那个内容，让带图标的控件比纯文字的高（shadcn 官网 Select 比 Button 高 2px 就是这么来的）。
- **容器**（标题栏、pane 头、列表行、工具条）继续用固定 token，但要用 `minHeight` 而不是 `height`，且必须 ≥ 内部控件的自然高度，否则用户放大 UI 字号后直接溢出。
- feature 里**不要**直接用 `sf.Button` / `sf.IconButton` / `sf.TextField` / `sf.Select`：它们的尺寸由 `ButtonSize` × `ButtonDensity` 两个乘法修饰符决定，落不到设计档位上。走 `zeta_ui` 的 Ide 封装；确实缺封装就先补组件。

**自查**：

```sh
grep -rnE "Color\(0x|BoxShadow\(|BorderRadius\.circular|ColorScheme\.fromSeed|Shad[A-Z]" lib/src/features
grep -rn "import 'package:shadcn_flutter" lib | grep -v "as sf"
# 控件级 sf 原件的存量清单：只增不减就是在制造新的高度分叉。
# 当前基线是 10 处内嵌 `sf.IconButton.ghost`（行内小动作）+ 设置页 2 处需要
# 搜索弹层的 `sf.Select`；新增一律要么走 Ide 封装，要么在调用点写明为什么
# 封装满足不了，并显式对齐 IdeMetrics 的内边距。
grep -rnE "sf\.(IconButton|TextField|Button)\." lib/src/features | wc -l
```

> 正文：[工程规范 §6](docs/architecture/engineering_standards.md) · [开发者文档 §8](docs/guides/developer_guide.md)

---

## 2. 任务路由：我要动 X，先读什么

**动手前对号入座。** 只读本文件不够——右列的文档章节是必读项，不是参考资料。

| 你要动的东西 | 必守门禁 | 动手前必读 | 额外必做 |
|---|---|---|---|
| 新增或修改 `AgentEvent` | G1 G2 G3 | [开发者文档 §7「新增 AgentEvent 接入清单」](docs/guides/developer_guide.md) 的 **16 条**，逐项回答 | 每条答案用测试固定 |
| 接入新 Provider | G1 G2 G4 G6 | [工程规范 §4.2](docs/architecture/engineering_standards.md#42-共享适配层纯度门禁) + [开发者文档 §7](docs/guides/developer_guide.md) 十二步 | 改动范围应 = 自有 data 文件 + 中立 domain 契约 + `createBundle` 组合 + 契约测试；静态能力走 data 组合层，Domain 不按厂商 switch |
| Provider adapter / reducer / 流式显示 | G1 G2 G3 | [工程规范 §4.1](docs/architecture/engineering_standards.md) | 带 Provider/CLI 版本的脱敏 fixture 序列测试；有 history/replay 就补 canonical signature 逐位置回归 |
| Provider 文件变更证据 | G1 G2 G3 G6 G7 | [开发者文档 §7「文件变更证据接入」](docs/guides/developer_guide.md) | Provider-local tracker 输出完整 typed snapshot；command-only 不猜文件；live/history/replay 独立；正文不进日志或持久化 |
| 权限选项 / 审批 / Plan 模式 | G4 G5 | [开发者文档 §7「权限选项选择」+「Plan conversation mode」](docs/guides/developer_guide.md) | 覆盖两 thread 两 Canvas 的真实 wire 参数、runtime 状态仅限所属 Binding、迟到 apply、旧 generation 丢弃 |
| Provider 生命周期 / 进程 / Binding | G4 G6 | [工程规范 §4](docs/architecture/engineering_standards.md) | factory 只由 registry 调用且 acquire 显式传 scope；全局操作走 `AgentProviderGlobalRuntime`；session 只由 `AgentConversationBinding.beginTurn()` 惰性创建，回收由 Binding Manager 负责；Binding 必须显式区分 dormant/starting/attached/cleared，只有匹配 identity 的 cleared 才能结算中断；Workspace entry 一次性绑定 thread/Binding/ViewModel，真实 thread 不得原地改绑，fork 结果走 Shell 的新 thread 通用登记/选择流程；Thread 操作走 `ProviderOperationScheduler` |
| 主题、UI 原语、工作台 slot | G6 G8 | [架构总览「工作台 UI」](docs/architecture/overview.md) + [开发者文档 §8](docs/guides/developer_guide.md) | `IdeHome` 是唯一 Workbench 组合边界，feature 页只填 Navigation / Canvas / Inspector 三个 slot |
| 界面文案 / 语言 / ARB / 文本目录 | G6 G7 G8 | [开发者文档 §8「界面语言与文案」](docs/guides/developer_guide.md) + [工程规范 §5–6](docs/architecture/engineering_standards.md) | Widget 走 `context.l10n`；application/data/reducer 只注入不可变 feature 文本目录；禁止 Flutter Locale / BuildContext / generated l10n 下沉；新字面量跑 `dart run tool/check_localized_ui_strings.dart --check`；两份 ARB key/placeholder 对齐且不用 plural/date/number formatter |
| 时间线渲染 / resize 热路径 | G8 | [工程规范 §6](docs/architecture/engineering_standards.md) | 禁止 post-frame 测高、`GlobalKey` 查高、layout 后 `setState` 反馈环；Windows Profile 采样，Debug 数据不作结论 |
| 页面切换 / 跨页保活 | G6 G8 | [开发者文档 §8](docs/guides/developer_guide.md) | 用真实 `IdeHome` 补集成级 Widget 测试：常驻骨架、AgentPane Element、当前 Thread、草稿、滚动位置、Pane 宽度与可见性都不能被重置；用 `IdeRetainedPageView`，不用 `IndexedStack` |
| 持久化字段 / `~/.zeta` | G7 | [开发者文档 §9](docs/guides/developer_guide.md) | 版本化 + `tryDecode` 宽容读；覆盖损坏输入与旧版本迁移 |
| 模型目录 / Composer 模型配置 | G4 G7 | [开发者文档 §7、§8「Composer 模型配置」](docs/guides/developer_guide.md) | 只经 app 级 `AgentModelCatalogRepository`；cursor 分页必须拉完，失败不得用空目录覆盖旧缓存 |
| 使用统计 | G6 G7 | [开发者文档 §8「使用统计开发约束」](docs/guides/developer_guide.md) | Provider 私有历史解析只在自有 data 层；不按 `originator` 白名单过滤 Codex 会话；`token_count` 是 thread 累计值，写 turn 前做非负差分 |
| 桌面通知 / 任务栏未读 | G7 | [Agent 桌面通知详细设计](docs/architecture/desktop_agent_notification_design.md) | 先映射为中立 `AgentAttentionSignal`；正文不含 prompt、回复、命令、完整路径 |
| 文件树 / workspace | — | [工程规范 §7](docs/architecture/engineering_standards.md) | 懒加载、不递归全扫、不跟符号链接、忽略 `.git` / `.dart_tool` / `build` / `node_modules` |
| Codex 协议升级 | G1 G6 | [协议版本锁定](docs/protocols/codex_app_server_protocol.md) | 见下方「Codex 协议升级流程」 |

### Codex 协议升级流程

改适配层**之前**先 diff pinned schema：

```sh
./tool/gen_codex_schema.sh --diff        # Windows: ./tool/gen_codex_schema.ps1 -Diff
```

比对 `third_party/codex_app_server_schema/`，再动代码。之后跑真实 CLI 冒烟：

```sh
python tool/smoke_codex_app_server.py --expected-version 0.144.5
python tool/smoke_codex_plan_mode.py --expected-version 0.144.5
```

冒烟用临时只读 workspace、最小权限、非破坏性 prompt。记录 OS/架构、CLI 版本、Schema 类型和结果；**没有设备或凭据时必须标记「待执行/阻塞」，不得推断通过**。记录中不得包含 prompt、回复、文件内容、凭证、原始 payload、thread/turn id 或 stderr 原文。

---

## 3. 风格约定

lint 已经覆盖的不再重复，这里只写 `flutter analyze` 抓不到的部分。

**Dart / Flutter**

- 现代空安全 Dart；优先 `const` 构造函数和不可变 Widget。
- `build` 变大就拆私有 Widget 类；函数保持简短、职责单一。
- 成员 `camelCase`，类 `PascalCase`，文件 `snake_case.dart`。
- 不用 `print`。需要保留的诊断走 `dart:developer` 或 `lib/src/core/logging`。
- 公共 API 写 `///`。**新代码优先中文注释**，重点覆盖协议适配、状态机、错误处理和不直观分支；不要写只复述代码字面行为的空注释。

**状态与异步**

- 简单本地 UI 状态用 Flutter 内建能力（`StatefulWidget` / `ValueNotifier` / `ValueListenableBuilder` / `FutureBuilder` / `StreamBuilder`）。
- 状态变共享或复杂时拆成：不可变 domain state + application controller（异步编排）+ presentation view model / listenable signal（渲染）。
- 可能被后续请求覆盖的异步加载必须有 **token/version guard**，旧结果返回时丢弃；通知监听者前检查 disposed。
- `ChangeNotifier` / `ValueNotifier` / timer 持有者必须在 `dispose` 中释放。
- 对外暴露集合默认返回不可变列表或 unmodifiable view，除非 API 明确要求可变。
- 为可测试性优先构造函数注入。**不引入第三方状态管理**，除非明确要求或有充分理由。

**UI**

- 新增面板或重复项优先复用 `zeta_ui` 已有原语：`Pane`、`PanelCard`、`PaneInteractiveSurface`、`IdeTabs`/`IdeTab`、`IdeChip`、`IdeButton`、`IdeSelect`、`IdeContextMenu`、`IdeStatusCard`、`IdeCollapsibleCard`、`WindowFrame`。工具栏和筛选控件用 `IdeButton`/`IdeSelect`，不要直接拼裸 `sf.OutlineButton` / `sf.Select`。
- 保持信息密度但文本必须可读：长文件路径、thread 标题、工具摘要、状态文本一律有界布局 + 省略号。
- 用 `LayoutBuilder` / `Flexible` / `Expanded` / `Wrap` / 滚动视图避免溢出；桌面宽窗和窄视口都要能看。
- 重复的交互行用稳定 `ValueKey`；流式 turn、语法高亮、diff 明细加 `RepaintBoundary`。
- 非文本按钮给 tooltip，重要自定义控件给语义标签；系统文字放大后仍要可读。
- Zeta 自有用户可见文案走 `context.l10n` 或对应 feature 的文本目录；不要在生产 Widget / application / data 里新写中英文字面量。品牌名 `Zeta`、产品术语 `Agent` / `Provider` / `Thread` / `Token`、Provider/user/raw 内容保持原文。
- 新增 ARB key 必须同时写入 `app_en.arb` 与 `app_zh.arb`，带 description；placeholder 一律 `String`，禁用 plural/date/number formatter。日期、数字、百分比、相对时间继续用语言无关算法。

**导航**

- 简单短生命周期流程继续用 `Navigator`。只有需要声明式路由、深链接或多持久页面时才上 `go_router`。

**测试**

- 优先 fake / stub，不用 mock；确有必要才引 mock 包。结构遵循 Arrange / Act / Assert。
- domain 模型、codec、mapper、JSON 宽容解析 → 单元测试。
- application controller 的分页、恢复、竞态、错误路径 → 单元测试。
- pane、timeline、file tree 等用户可见行为 → widget 测试。
- 共享层（decoder、CoalescingPolicy/Buffer、Pipeline、TimelineStore）的测试**必须用 Provider 无关 fixture**，并配套架构守卫断言（参考 `test/src/features/agent/architecture/`）。新增 Provider 时这些测试不应依赖新 Provider 的类或 fixture。
- integration test 只用于稳定的端到端用户流程。
- **外部 CLI 的自动化测试不能替代真实平台验收。**

单个测试文件：

```sh
flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart
```

---

## 4. 依赖与仓库卫生

- 运行时依赖 `flutter pub add <package>`，开发依赖 `flutter pub add dev:<package>`。
- 加新包前先确认 Flutter / Dart 内建方案确实不够用；在最终总结里说明每个新依赖的用途。
- 关键版本：Dart SDK `^3.12.2`，`shadcn_flutter ^0.0.53`（升级前先跑一遍完整 widget 测试，这个包的小版本改过 Overlay API）。
- 保留 Flutter 生成的 `linux/` `macos/` `windows/` 目录，除非任务明确针对原生桌面行为。生成文件出现非预期改动时，先确认是不是 Flutter 工具产生的，保留就要说明原因。
- 不提交构建产物、`.dart_tool`、日志或其他工具链产物。本仓库没有 Cargo.toml，`Cargo.lock` 已加入 `.gitignore`。
- 不建空占位目录（只放 `.gitkeep` 的目录不要入库）——它们会和 G6 的「不要新建顶层宽泛目录」直接冲突。
- 走流程的任务，阶段产物写入 `.workflow/<类型>/<日期>-<任务>/<NN>-<阶段>.md` 并跟代码一起提交。约定见 [`.workflow/README.md`](.workflow/README.md)，提示词见 [`docs/prompts/`](docs/prompts/README.md)。**这些文件入 git，粘日志或路径前必须脱敏**（G7 的精神同样适用）。
- 用户可感知的变化写进 `CHANGELOG.md` 的 `[未发布]`；纯重构和内部调整不必写。
- Dart / Flutter 技能同时装在 `.agents/skills` 和 `.claude/skills`（内容一致）。处理 widget 测试、集成测试、静态分析、路由、本地化、JSON 序列化、响应式布局、依赖冲突、覆盖率这类聚焦任务时用对应技能。
- 仓库已由 CodeGraph 索引（存在 `.codegraph/`）。定位或理解代码时优先用 `codegraph explore "<问题或符号名>"`，比 grep + 逐个读文件省一个数量级的往返。

**默认分支是 `dev`**，基于它开分支和提 PR。

---

## 5. 事实清单（容易记错的）

- **活跃 Provider 是 Codex、Grok 和 Claude Code。** Claude Code 的当前协议事实以 `docs/protocols/claude_code_stream_json_protocol.md` 为准；`claude_code_provider_adapter.md` 只是历史提案。模型与套餐名称来自无 Prompt CLI initialize；`claudeCode.accountDataEnrichment` 只控制 Provider-local 的可选额度详情，不控制模型目录。
- **Cursor 已彻底清退。** 当前 schema、Provider 枚举、catalog、UI、运行时组合、测试和 fixture 均不含 Cursor 兼容值；不为未发布数据保留 decode/fallback。任何重新支持都必须另立方案并重新取得真实协议证据，相关代码不得直接回流。
- **Grok CLI 基线是 `0.2.119`**（grok-build）。更早版本不支持多会话，同时打开多个 Grok 会话时无法正确隔离会话状态和回合终态。
- `desktop_notifications` 和 `ide_session` 两个 feature 只有 `domain/application/data`，没有 `presentation/`——这是有意的。
- **界面语言只有英语与简体中文。** 首次启动只看系统首选语言第一项（显式繁体与其他语言回退英语）；已有安装保持中文。设置里切换后下次启动才生效，当前进程不跟随系统 locale。
- **产品术语 `Agent` / `Provider` / `Thread` / `Token` 保持英文。** 日期、数字、百分比、相对时间格式不随界面语言变化。

---

## 6. 改了架构边界，同步这几处

改动涉及分层、Provider 契约、事件管线、能力协商或持久化格式时，下面几处要一起改，不要只改一处：

- 本文件（约束规则权威源）
- `docs/architecture/engineering_standards.md`（门禁正文）、`design_document.md`、`overview.md`（+ `overview.en.md`）
- `docs/guides/developer_guide.md`、`docs/guides/glossary.md`（+ `glossary.en.md`，有新术语时）
- `CONTRIBUTING.md` / `CONTRIBUTING.en.md`（人类贡献者版的架构红线摘要）
- `CLAUDE.md`（若门禁编号或数量变化）

引入路由、本地化、全局状态管理、网络、资源或新的 feature 结构时，也要回来更新本文件。
