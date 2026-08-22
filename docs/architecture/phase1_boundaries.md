# 阶段 1：建立边界但不改变行为

最后更新：2026-08-22

状态：第四个增量（`zeta_agent_providers`）已落地，目标 Package 图的 5 个包全部拆出；
三轮 review 的 16 条问题已处理完毕。对应 [目标架构 §14 Phase 1](./target_architecture_riverpod_mvi_plugins_packages.md#phase-1建立边界但不改变行为)。

阶段 1 的规矩是**只搬边界，不动行为**：没有新功能、没有 UI 变化、没有持久化格式变化，
Provider wire 参数与状态 owner 全部保持原样。

---

## 1. 本增量交付了什么

| 交付物 | 位置 |
| --- | --- |
| Pub workspace | 根 [`pubspec.yaml`](../../pubspec.yaml) 的 `workspace:` 列表 |
| `zeta_foundation`（纯 Dart 公共契约） | [`packages/zeta_foundation`](../../packages/zeta_foundation) |
| `zeta_plugin_kernel`（可信插件微内核） | [`packages/zeta_plugin_kernel`](../../packages/zeta_plugin_kernel) |
| 编译期插件目录 | [`lib/src/app/plugins/zeta_plugin_catalog.dart`](../../lib/src/app/plugins/zeta_plugin_catalog.dart) |
| Agent Provider 贡献 + 兼容插件 | `lib/src/features/agent/data/agent_provider_plugin_contribution.dart`、`compatibility_agent_provider_plugin.dart` |
| 应用级依赖 Provider / 覆盖点 | [`lib/src/app/composition/app_dependencies.dart`](../../lib/src/app/composition/app_dependencies.dart) |
| Package 依赖图守卫（含跨包 `/src` 禁令） | `test/src/architecture/package_boundary_candidate_graph_test.dart` |
| Package 独立测试入口 | [`tool/test_packages.sh`](../../tool/test_packages.sh)（已接入 `tool/test_full.sh` / `.ps1`） |
| `zeta_ui`（Graphite 设计系统） | [`packages/zeta_ui`](../../packages/zeta_ui) |
| 设计系统文案注入端口 | `packages/zeta_ui/lib/src/zeta_ui_text_catalog.dart` + `AppZetaUiTextCatalog` 适配器 |
| `zeta_agent_core`（中立 Agent 内核） | [`packages/zeta_agent_core`](../../packages/zeta_agent_core) |
| `zeta_agent_providers`（Provider 适配层） | [`packages/zeta_agent_providers`](../../packages/zeta_agent_providers) |
| 日志端口 + 集合相等工具 + 文本文件端口 | `packages/zeta_foundation/lib/src/logging/zeta_logger.dart`、`src/collections/zeta_equality.dart`、`src/storage/zeta_text_file.dart` |

### 1.1 已物理拆出的 Package

```text
packages/
  zeta_foundation/        # 纯 Dart：Clock、OperationId、Transition、排版常量、日志与指标端口
  zeta_plugin_kernel/     # 纯 Dart：descriptor / contribution / registry / 生命周期
  zeta_ui/                # Flutter：Graphite token、Ide* 控件、Workbench 骨架、虚拟滚动
  zeta_agent_core/        # Flutter(foundation)：中立 Agent 领域模型与端口、Binding/runtime
                          # 契约、事件管线、纯 reducer、TimelineStore、Effect 描述
  zeta_agent_providers/   # Codex app-server / Grok ACP / Claude Code stream-json 的协议
                          # transport、data adapter、Provider-local tracker、插件入口
```

依赖方向（守卫强制）：

```text
zeta_plugin_kernel ──> zeta_foundation
zeta_ui ───────────> zeta_foundation
zeta_agent_core ───> zeta_foundation
zeta_agent_providers ──> zeta_agent_core, zeta_plugin_kernel, zeta_foundation
root app ──────────> 五者
```

`zeta_foundation` 不 import 任何外部库（连 Flutter 都没有）；`zeta_plugin_kernel` 只依赖
`zeta_foundation`，且源码里不允许出现 `codex` / `grok` / `claude` / `Agent` / `package:zeta/`
任一标识——内核认识"插件"，不认识"Agent Provider"。

`zeta_ui` 依赖 Flutter / shadcn_flutter / flutter_svg / window_manager，但守卫禁止它出现
`dart:io`、`flutter_riverpod`、`package:zeta/` 与 generated l10n：

- **文案**：控件自有文案（无障碍标签、滚动条提示、Tab 加载后缀等 8 条）改走注入的
  `ZetaUiTextCatalog`。宿主用 `AppZetaUiTextCatalog` 把 ARB 投影进去，未注入时回退英文，
  保证设计系统可以脱离宿主独立渲染与测试。
- **本机 IO**：`ide_image_preview.dart`（读本地图片并预览）**留在 app 侧**
  `lib/src/ui/core/`——它本质是宿主能力封装，不是设计系统原语。公开 API
  （`IdeLocalImageThumbnail` / `showIdeLocalImagePreview`）与行为一字未改。
- 47 个设计系统文件整体 `git mv` 进包，372 处 `package:zeta/src/ui/core/...` import
  统一改成 `package:zeta_ui/zeta_ui.dart` 顶层 barrel。

### 1.1.1 `zeta_agent_core` 的边界

搬进包的是**中立机制**：34 个 domain 文件 + 27 个 application 文件（事件管线四件套、
TimelineStore、reducer/mutation/effect/effect runner/event processor、Binding 与
BindingManager、runtime identity/registry/global runtime、listener gate、UI 更新端口与
请求、权限状态与目录、turn 上下文端口与记录器、elapsed ticker、配置存储端口）。

留在根 app 的 `lib/src/features/agent/application`（10 个文件）是 **ChangeNotifier 形态的
feature controller**：settings / mode / model selection / skills 目录 / 模型目录仓储 /
plan 执行交接 / turn 上下文叠加 / 指标采样器 / workspace 组合。它们不是"中立机制"，
而是等着在 Phase 2/3 变成 MVI 切片的业务编排。

为拆包做的三处**接口下沉**（不是行为改动）：

| 原来 | 现在 |
| --- | --- |
| 内核直接 `loggerFor(...)`（根 app 的 logger） | `ZetaLogger` 端口 + `zetaLoggerFor`；`AppLogger` 实现它，`configureAppLogging` 安装。结构化失败改走端口的 `failure(...)`，脱敏仍在 app 侧 |
| `AgentTurnContextStore` 端口与文件实现同在 data 层 | 端口 + 内存实现进内核，`FileAgentTurnContextStore` 留 data（键格式逐字保持不变） |
| `AgentProviderRuntimeRegistry` 直接 import Provider 身份映射 | 改为注入 `providerMetricLabel`；**未注入时默认 hash**，内核不认识任何 Provider（G1） |

`AgentMetricLabels`（provider ID → 指标标签）按 G1/G4 同款判定放回 data 层：它按 Provider
身份分支，属于 Provider 语义。

### 1.1.2 `zeta_agent_providers` 的边界

搬进包的是 **79 个协议适配文件**：`datasources/**`（Codex app-server、Grok ACP、
Claude Code stream-json、JSON-RPC transport、本地历史解析）、`mappers/**`、三个 CLI
定位器、静态能力表、权限迁移、`DefaultAgentProviderFactory`、插件贡献与兼容插件、
Provider 指标标签映射。

**留在根 app 的 `lib/src/features/agent/data`（5 个文件）是 Zeta 自有持久化**：provider
配置存储与 codec、模型目录缓存、turn 上下文文件存储与 codec。它们写的是 `~/.zeta`，
按 §7.5「文件实例由 app 注入」本来就属于 app 侧，不是 Provider 适配。

为拆包做的一处**接口下沉**：两个 Claude Code 侧的状态文件适配器
（`FileClaudeCodeHiddenThreadStore` / `FileClaudeCodeSessionDecisionStore`）原先直接
`AtomicTextFile(File)`，现在接受注入的 `ZetaTextFile` 端口（foundation 纯 Dart 契约，
`AtomicTextFile` 在 app 侧实现）。适配层因此不必为了写一个 JSON 文件而依赖根 app 的
存储工具类；`dart:io` 本身在这个包里是允许的（要拉起 CLI、读 Provider 私有配置）。

同时 `StructuredLogDiagnostic` 从 app 的结构化日志模块下沉到 `zeta_foundation`：
`JsonRpcException` 需要它来补充协议诊断字段，而异常类本身在适配层。

新增两条守卫：适配层不得反向依赖根 app / `zeta_ui` / Riverpod / Flutter widgets；
**wire 标识（`jsonrpc`、`session/update`）只允许出现在这个包里**——一旦漏进内核或 app
就会失败。

### 1.2 插件微内核

内核只做四件事：登记、按拓扑序激活、按类型汇总贡献、按反序关闭。全部边界 fail-closed：

| 情况 | 行为 |
| --- | --- |
| 插件 ID 重复 | 构造即抛（编译期目录写错了，不拖到运行期） |
| API 主版本不符 | 该插件 `failed`，其余照常激活 |
| 依赖缺失 / 依赖失败 | 该插件 `failed`，分类分别为 `missingDependency` / `dependencyFailed` |
| 依赖成环 | 环上插件 `dependencyCycle`，环外依赖者 `dependencyFailed`，都不进激活序列 |
| `activate` 抛异常 | 只记分类，不记异常文本（G7） |
| 核心必需插件失败 | 报告 `isDegraded = true`，应用必须显式进入 degraded 状态 |

### 1.3 兼容层账本

| 项目 | 内容 |
| --- | --- |
| 兼容层 | `CompatibilityAgentProviderPlugin` |
| owner | 架构迁移（Phase 1 引入） |
| 使用点计数 | **1**（只允许由 `ZetaPluginCatalog.compatibility` 构造，测试断言） |
| 删除 Phase | Phase 3 第 6 批：Codex / Grok / Claude Code 拆成三个显式插件贡献后删除 |
| 回滚方式 | app 组合点改回 `_agentProviderFactory = DefaultAgentProviderFactory(...)` 直连，一行 |

`DefaultAgentProviderFactory` 内部按 kind 分派的 switch **一字未动**——本阶段只是把
"谁交出工厂"从 app 直接构造改成了从插件目录取。

---

## 2. 没有搬的部分（Phase 1 后续增量）

目标 Package 图的 5 个包已全部拆出。仍留在根 app 的是**业务编排与 Zeta 自有状态**：
feature controller（ChangeNotifier 形态，等 Phase 2/3 转 MVI 切片）、Zeta 自有持久化、
presentation 与 shell 组合。

燃尽清单（守卫里的 `_knownEdgeViolations` / `_knownExternalViolations`，只允许变小）：

| 待修边界 | 数量 | 修法 |
| --- | ---: | --- |
| ~~`ui/core` → generated l10n~~ | ~~5~~ → 0 | ✅ 已改为注入 `ZetaUiTextCatalog` |
| ~~`ui/core` → `dart:io`~~ | ~~1~~ → 0 | ✅ 图片预览封装留在 app 侧 |
| ~~agent `application` → agent `data`~~ | ~~3~~ → 0 | ✅ turn context 端口下沉；静态能力随 settings controller 留在 app |
| ~~agent `application` → presentation / workspace~~ | ~~2~~ → 0 | ✅ `agent_thread_workspace_controller` 本就是 app 级组合对象，不进内核 |
| `core/` → `dart:io` / Flutter | 8 | IO 部分下沉到 app 或独立适配层，`core/` 只留纯契约 |
| `zeta_agent_core` 依赖 `flutter/foundation` | 17 个文件 | `ChangeNotifier` / `ValueListenable`，随 Phase 2/3 的 MVI 切片移除（见 §6 偏差 5） |

---

## 3. MVI 命名规范（Phase 2 起强制）

阶段 1 只定契约与命名，不建通用基类框架。每个 feature 切片按下面这套命名：

| 概念 | 命名 | 说明 |
| --- | --- | --- |
| 意图 | `<Feature>Intent`，变体用**发生的事**命名 | `SendMessageRequested`、`ThreadSelected`、`ModelCatalogLoaded`；不要用 `SetXxx` 这种命令式 setter 名 |
| 状态 | `<Feature>State` | 该 bounded context 的完整可渲染状态，不可变 |
| 转移 | `Transition<State, Effect>`（来自 `zeta_foundation`） | reducer 签名固定为 `Transition<S, E> reduce(S state, I intent)`，**纯同步** |
| 副作用 | `<Feature>Effect` | 只是**描述**，由 scope-aware runner 执行 |
| 结果意图 | `<Something>Succeeded` / `<Something>Failed` | effect 完成只能通过 result intent 回写状态 |
| 操作身份 | `OperationId`（来自 `zeta_foundation`） | 每个异步操作一个 id；迟到结果先比对 id 再决定是否写回 |
| 选择器 | `<Feature>Selectors` | 从切片派生不可变 UI 投影 |

`Transition` 是切片之间**唯一**共享的结构：不提供 `BaseStore` / `BaseReducer`。审批、提问、
Plan、文件树、设置的领域类型差异很大，强行统一只会造出一层空壳。

`Failure` 分类、`CancellationToken` 与 `Result` 留到 Phase 2 与**第一个真实调用方**一起落地——
先建无人使用的抽象违背目标架构 §1.1 第 8 条。

---

## 4. 命令

```sh
flutter analyze          # 根 Package
bash tool/test_packages.sh   # 每个内部 Package 的 analyze + test（Flutter 包自动走 flutter 工具链）
bash tool/test_full.sh       # 根测试 + 计时报告 + 上面这一步
```

Windows 用 `tool/test_full.ps1`（同样包含 Package 循环）。

---

## 5. 与阶段 0 基线的对比

| 指标 | 阶段 0 | 本增量 |
| --- | ---: | ---: |
| 根测试 | 2114 passed / 0 failed | 2122 passed / 0 failed |
| Package 测试 | — | 47 passed（foundation 23 + kernel 20 + ui 4） |
| 聚合测试耗时 | 248.4s | 244.0s（同机波动范围内） |
| `flutter analyze` | 0 issue | 0 issue |
| 流式 fixture 基线 | received 10 825 / accepted 309 / coalesced 10 516 / dispatched 309 | 未变（同一断言通过） |
| Widget 重建预算 | Shell 骨架各 1 次 | 未变 |

---

## 6. 与计划的偏差

1. **内核增加了同步激活入口**。目标架构 §5.2 只写了 `Future<ZetaPluginHandle> activate()`。
   首帧就需要 Agent Provider 工厂，纯异步激活会引入一个"还没有工厂"的中间态，
   属于行为变化。因此增加 `ZetaSynchronousPluginFactory` 与 `activateAllSynchronously()`：
   只支持异步的插件在同步入口上 **fail-closed**，不会被静默跳过。异步入口原样保留。
2. **移动的文件一律不保留旧路径兼容 barrel**。计划的回滚手段是"保留原路径 barrel"。
   两个增量都没有这么做：第一个增量只移动 3 个文件（15 处调用点），`zeta_ui` 增量是
   47 个文件、372 处调用点，都选择直接改写 import——改写是一次脚本化操作，`flutter analyze` 与 2116 个
   测试立刻验证；保留 47 个 shim 反而要再加一条守卫防止新代码继续引用旧路径，且全部
   要在 Phase 4 删除。两次的回滚方式都是 revert 单个提交。
3. **`Failure` / `Result` / `CancellationToken` 未落地**，理由见 §3。
4. **`zeta_ui` 的 36 个 Widget 测试留在根测试树**（通过 `package:zeta_ui/...` 引用），
   因为它们依赖应用侧的本地化宿主与主题 harness。包内另有独立的契约测试入口
   （文案注入 + token 解析）。把这批 Widget 测试迁进包内是后续增量；
   `zeta_agent_core` 的既有 reducer/pipeline/timeline 测试同理。
5. **`zeta_agent_core` 目前依赖 `flutter/foundation`**，与目标架构 §3.1「不依赖 Flutter」
   不符。原因是 17 个文件用 `ChangeNotifier` / `ValueListenable`，其中包括 **G1 内容冻结的
   `AgentConversationTimelineStore`**；要做到纯 Dart 必须同时（a）把 10 个 controller 换成
   MVI store、（b）为 Flutter 侧监听补桥接、（c）动 G1 冻结文件——那是 Phase 2/3 的工作，
   放在"只搬边界不改行为"的 Phase 1 里做既超范围又高风险。
   本增量的处理：把 `widgets` / `material` / `services` / Riverpod / `dart:io` / 根 app
   全部**守卫禁止**，只留 `foundation`，并冻结文件数（只允许变少）。
6. **G1 五文件的 T18 内容基线已刷新**。它们随包移动，`import` URI 必然变化。已逐字比对
   确认**只有 import 行变化**（`package:zeta/src/features/agent/...` →
   `package:zeta_agent_core/src/...`），语义零改动，因此按新内容重算 lineCount /
   byteLength / fingerprint，并在测试注释里记录了这次刷新的原因。

---

## 7. 验收对照

| Phase 1 验收标准 | 状态 |
| --- | --- |
| 行为、状态 owner、Provider lifecycle、持久化格式零变化 | ✅ 全量测试与流式基线未变；工厂内部分派逻辑未动 |
| 根 app 仍是唯一装配点；kernel 不 import 具体 Provider | ✅ 守卫测试强制 |
| 禁止跨 `/src` import 与反向依赖 | ✅ 守卫测试强制（已拆包 + 候选包两套规则） |
| analyze / test / 构建通过，基线无退化 | ✅ 见 §5；三桌面平台构建**待执行**（见下） |
| compatibility layer 有使用点计数、owner 和删除计划 | ✅ 见 §1.3，测试断言使用点为 1 |

**待执行**：三桌面平台（macOS / Windows / Linux）的实际构建验证。workspace 只影响依赖解析，
不改 Flutter 构建配置，但按 `AGENTS.md` 的规矩，没有跑过就不能推断通过。

---

## 8. 拆 `zeta_agent_providers` 之前必须先结论的两笔欠债

这两条都是**拆包前就有的设计**，被本轮拆包正式化成了包公开 API，因此在继续迁移前
必须有结论，而不是继续往下搬。当前状态：§8.1 **已冻结、已立项、未清算**（收口排在
Phase 3 第 6 批）；§8.2 **已决并已落地**。

### 8.1 内核里的集中式 Provider 目录

`agent_provider_models.dart` 持有 `AgentProviderKind` 三个枚举值、三个内置 Provider 的
稳定 ID 与默认 CLI 配置、按 ID 归一化显示名的 switch。全仓库有 29 个文件按 kind 分支，
新增一种协议要改内核枚举并牵动一串 exhaustive switch——与 §9.3「新增 Provider 只动
providers 包 + 一行注册」直接冲突。

- **冻结**：`agent_provider_catalog_freeze_test` 精确断言枚举值、内置 ID、默认命令，
  并断言"内核里出现内置 Provider 身份的文件只有这一个"。任何增删都会失败。
- **收口**：Phase 3 第 6 批。三个 Provider 转成显式插件贡献时，内置配置与显示名归一化
  移入 data 层，`AgentProviderKind` 让位给插件 descriptor 的开放注册表。

### 8.2 中立事件上的 Provider raw payload —— **已决 + 已落地（2026-08-21）**

原状：36 个中立模型字段携带协议原文（21 个事件的 `raw`，工具的 `rawInput` / `rawOutput`
等），与 §4.1「Core 不拥有 Provider raw payload」冲突；presentation 有 21 处直接读 `.raw`，
上下文面板还把它转成 JSON 渲染。

**产品结论**：上下文面板的"原始消息"卡片**保留**，但原文**只能看，不能取值**。

落地方式：

1. **不透明值类型**。原文类型换成 `AgentProviderRawPayload`（`zeta_agent_core`）：
   没有 `operator []`、没有 `keys`、没有 `toMap()`，唯一内容出口是 `toPrettyJson()`。
   任何 `raw['x']` 现在是**编译错误**，不再靠 review 盯。`toString()` 只输出条目数，
   避免误插值把整份 payload 写进日志。
2. **面板不展示的原文直接删掉**。中立内核里 Map 形态的 raw 字段清零（36 → 0），
   仍带原文的 12 个字段全部是不透明类型，且都是面板真正会渲染的那几类
   （message / permission / question / planApproval / historyEvent 的 `raw`，
   工具的 `rawInput` / `rawOutput`）。
3. **删掉后仍要的语义改成 typed 字段**，由 adapter 显式声明，而不是让内核翻原文：

   | 原来从原文里翻 | 现在的 typed 字段 | 归属 |
   | --- | --- | --- |
   | `raw['_progressAppend']` | `AgentToolCall.appendsProgress` | Codex mapper 声明 |
   | `rawInput` 里猜命令/路径/查询（~20 个键名） | `AgentToolCall.inputDetail` | `deriveAgentToolInputDetail`（providers 包） |
   | `raw['sourceItemId']` | `AgentToolCall.sourceItemId`（**仅 metadata**，身份仍是 `id`） | history parser |
   | `snapshot.raw['source']` | `AgentThreadHistorySnapshot.sourceLabel` | history reader |
   | `snapshot.raw['sessionPath']` | `AgentThreadHistorySnapshot.sessionPath` | history reader |
   | `item['inputModalities']` | `AgentModelInfo.supportsImageInput` | model list mapper |
   | guardian 拒绝动作的回传原文 | Provider 自己留存 `notification.params` | 不出 providers 包 |

4. **两处隐藏的 G1 违规同时清掉**：`AgentConversationTimelineStore` 和
   `AgentEventCoalescingPolicy` 都在读 Codex mapper 注入的 `raw['_progressAppend']`——
   等于适配层通过原文遥控内核。两个 G1 冻结文件的 baseline 已按批准刷新。
5. **原文不再进日志**：`AgentConversationEffectRunner` 里 `'diagnostic': event.raw`
   已删除。之前是"先落日志再脱敏"，现在是原文根本不到日志链路，保证更强。

守卫（`agent_core_raw_payload_freeze_test`，6 条）：

- 中立内核里 Map 形态原文字段必须为 0；
- 不透明字段数只减不增（baseline 12）；
- `AgentProviderRawPayload` 不得长出 `operator []` / `keys` / `toMap()`；
- `AgentProviderRawPayload.wrap` 只能在 `zeta_agent_providers` 里调用；
- `toPrettyJson()` 的唯一生产调用点是上下文面板；
- 原文不进持久化与指标序列（G7）。

Review 后的补漏（同批）：

- **报文时间**：面板改读 `capturedAt` 后一度没有生产者，时间列全变 `—`。现在
  `wrapAgentProviderPayload` 只负责内容盲冻结；Codex / Grok 各自的 envelope mapper
  按协议字段提取并显式传入时间，工具参数里的同名业务字段不会被误判。数值解析对
  非有限值和越界值 fail-closed，推不出就是 null，不编造"现在"。守卫钉住共享包装器
  不扫描 wire key，且适配层不得直接调 `AgentProviderRawPayload.wrap`。
- **typed 字段要贯穿重建路径**：`sourceLabel` / `sessionPath` 在 grok enrichment、
  turn-context overlay、claude 历史 reducer、空历史返回路径都补齐了。grok 的历史
  缓存命中判定比较 `sessionPath`，enrichment 丢掉它会让缓存永不命中（已加回归测试）。
- **工具卡合并要保 typed metadata**：`_mergeToolCall` 与 reasoning→think 构造
  补上 `appendsProgress` / `inputDetail` / `sourceItemId`，否则状态型 update 一到
  就把 adapter 算好的语义清成默认值。T18 baseline 随之刷新。
- **原文不可变**：`AgentProviderRawPayload.wrap` 改成 factory 并**递归冻结**传入的
  Map / List。payload 会进 UI snapshot 并参与相等性判定，适配层保留原 Map 引用继续
  改它会让已展示内容无声漂移。
- **工具条目的展示契约写清楚了**：typed 摘要在前，`rawInput` / `rawOutput` 作为
  **独立文本段**附在后面（edit 工具一律不附）。之前把 `toPrettyJson()` 字符串塞进
  摘要 JSON，会二次转义成一行 `\n`。

遗留：`AgentThreadSummary.tryDecode` 保留一次性的旧缓存迁移读取
（`raw['path']` → `sessionPath`），让升级前落盘的条目仍能恢复会话路径。这是对**自家
持久化格式**的宽容解码，不是运行期原文取值。

---

## 9. Review 修复记录

第二个增量的 review 提出 8 条问题，全部已修复并补了回归测试。

| 问题 | 修复 |
| --- | --- |
| **P1** 异步激活与 `close()` 竞态导致句柄永久泄漏 | `close()` 先 `await` 在途激活；激活循环每步重新检查 `_closed`；迟到句柄在 `_adoptHandle` 里就地释放并登记进 `_lateHandleCloses`，`close()` 等它们收尾；已关闭的 registry 的 `contributions()` 返回空 |
| **P2** 重复激活覆盖旧句柄、贡献翻倍 | 一个 registry 只能激活一次，两个入口都 fail-closed 抛 `StateError`；换代请重建 registry。原先把该行为当预期的测试已改写 |
| **P2** 标签"脱敏"仍留下可读路径 | 标签改为白名单：只接受 `^[A-Za-z][A-Za-z0-9_.-]{0,31}$`，其余**整体丢弃**而不是替换字符；观察器给未命名 provider 去掉泛型参数以保持合法 |
| **P2** CI 没有门禁到 Package 测试 | CI 的 Test 步骤改跑 `bash tool/test_full.sh`；`test_full.ps1` 的 Package 循环补上 analyze，与 shell 版对齐 |
| **P2** 退出顺序没有保证 runtime → plugin | 抽出可测的 `shutdownAgentResourcesInOrder`；窗口关闭 hook 与 `dispose` 共用同一入口，严格串行 |
| **P2** 设计系统文案未全部注入 | `ZetaUiTextCatalog` 补 `loading` / `running` / 四个窗口按钮文案，ARB 与适配器同步；窗口按钮补 `Semantics(button: true)`；新增守卫禁止包内出现字面量 tooltip / 无障碍标签 |
| **P2** `zeta_ui` 隐式依赖根 app 资产 | `WindowFrame` 改为接受注入的 `brandLogo`，包不再依赖 `flutter_svg`、不再读 `assets/branding/*`；包 pubspec 补 `uses-material-design: true`，消除 Material Icons 警告 |
| **P1** 分支门禁与文档口径不一致 | 根因是 `ide_session_restore_widget_test` 有一处 `MainApp` 没注入 fake 工厂，会真的拉起本机 Codex CLI 并留下 30 秒 JSON-RPC Timer（机器越快越不容易复现）。已注入 fake，并加守卫 `widget_test_hygiene_guard_test.dart` 断言测试里构造 `MainApp` 必须显式传 `agentProviderFactory` |

修复前 review 报告里"9 处裸 `MainApp` pump"是扫描口径问题（正则窗口没有做括号配对，把
`_pumpMainApp(` 和相邻用例一起算了进去）。**实际只有 1 处**。

### 第二轮 review 修复

| 问题 | 修复 |
| --- | --- |
| **P1** 并发 `close()` 提前返回，调用方误以为资源已释放 | 改成 `AgentProviderRuntimeRegistry` 同款 `_closeFuture`：并发调用返回同一个关闭任务；补"两个并发 close 都等到句柄真正释放"的回归测试 |
| **P2** 贡献 getter 抛异常会污染 registry，一个坏插件阻断整个 catalog | 激活时**先冻结贡献快照再原子登记**；快照失败即 `failed` + 就地关闭句柄，不进任何表。`contributions()` 改读快照，不再回调插件 getter（顺带变成无副作用纯读） |
| **P1** 指标标签只校验形态，判断不了来源 | 标签类型化为 `ZetaMetricLabel`（`constant` / `declaredIdentifier` / `hashed` 三个入口），`ZetaMetricTags` 不再接受 `String`；Provider ID 经 `AgentMetricLabels.forProviderId` 映射（内置→常量，其余→会话 hash）；新增守卫强制 `constant` 实参为字面量 |
| **P3** Widget 测试守卫能被注释绕过 | 改用 `package:analyzer` 的 AST：注释与字符串天然不参与判定；同时统计扫描到的构造点数量，防止守卫空转。守卫自带"注释伪装"回归用例，并做过一次变异验证（去掉真实注入后确实报错） |

新增 dev 依赖：`analyzer ^12.1.0`（此前是 transitive），仅用于架构守卫的 AST 解析。

### 第三轮 review 修复

| 问题 | 性质 | 修复 |
| --- | --- | --- |
| **高** 控制台日志不脱敏，与端口契约矛盾 | 控制台实现是既有的（`c16fb729`），矛盾由本轮新写的端口契约引入 | 控制台与文件走同一条脱敏链路：message 与 `error.toString()` 都过 `redactSensitiveText`，同时保留异常类型；端口契约改成如实描述"实现方负责脱敏"；补控制台渲染的回归断言 |
| **高** 新增全局可变日志 service locator | 本轮新引入的临时方案 | `zetaLoggerFor` 改返回**延迟代理**（每次写日志才解析工厂），消除"首次访问早于 install 就永久缓存 no-op"的陷阱（已有回归测试）；豁免本身从源码注释升级为目标架构 §12 的**登记例外**，写明范围与取消条件 |
| **高** 内核仍认识具体 Provider | 既有设计被搬入包；barrel 文档过度声明是本轮的账 | 改掉"不认识任何具体 Provider"的错误声明，如实写明欠债与收口计划；新增冻结守卫（见 §8.1） |
| **高** raw payload 成为内核稳定 API | 既有设计被搬入包并正式化；Phase 1 计划遗漏 | 新增冻结守卫 + 立项（见 §8.2）；产品取舍留给 owner |
