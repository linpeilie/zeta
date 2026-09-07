# 工程规范

最后核对：2026-09-07（文档整理）

本文维护长期工程约束和专项细则。AI 开发核心规则见 [AGENTS.md](../../../AGENTS.md)，接入步骤见[开发者指南](../development/developer_guide.md)。

## 1. 代码组织

`lib/src` 按功能分层，各 feature 按实际需要设置以下目录：

```text
lib/
  main.dart
  src/
    app/
    core/
    features/<feature>/
      domain/
      application/
      data/
      presentation/
    ui/core/
    ui/features/ide/
```

- `main.dart` 只负责 Flutter 绑定、窗口启动、全局错误日志和 `runApp`。
- `app` 是运行时装配层，负责组合窗口、shell controller、provider factory、持久化 store 和应用根组件。
- `core` 放跨功能基础设施，例如日志、路径工具等，不依赖具体 feature。
- `features/<feature>/domain` 放纯模型、枚举、接口和领域状态。
- `features/<feature>/application` 放用例协调、恢复计划、分页加载、状态编排和跨对象协作。
- `features/<feature>/data` 放外部协议、存储、datasource、mapper 和 codec。
- `features/<feature>/presentation` 放 feature 私有 pane、widget、region selector 和 UI 分组逻辑。会话命令入口是 application 的 Actions/Notifier，RuntimeController 只负责执行与运行事实。
- `zeta_ui`（`packages/zeta_ui`）放跨 feature 可复用的主题、窗口框架、pane、panel 和状态展示组件；它不依赖业务模型、Riverpod、`dart:io` 或 generated l10n。
- `zeta_markdown`（`packages/zeta_markdown`）是 Markdown 渲染包，fork 自 `mixin_markdown_widget 0.3.1`（MIT）。它是依赖图的叶子，不依赖任何内部包；Graphite token 到渲染参数的映射发生在根应用侧。所有定制走「新增注入点 + 默认值与上游一致」，改动前后都要读写 `packages/zeta_markdown/UPSTREAM.md`。
- `agent_management` 负责 CLI 检测、版本/账号/模型诊断、配置文件安全写入、
  磁盘日志读取与管理页面；它复用 `agent` 的 provider 抽象，不复制会话协议实现。

新增代码优先进入对应 feature 内部。除非是跨 feature 的基础能力，否则不要新增宽泛的顶层 `data`、`domain` 或 `ui` 目录。

## 2. 依赖方向

依赖方向必须保持单向、清晰：

```text
main -> app -> presentation/application -> domain
                       app -> data -> domain
                       presentation -> zeta_ui
                       presentation -> zeta_markdown
```

- presentation 订阅 application 的状态和命令契约；application 不依赖 presentation。UI 不直接解析 Provider 原始协议。
- application 负责异步流程、恢复、分页、竞态隔离和状态写入，不负责绘制 widget。
- data 实现 provider、JSON-RPC、JSONL、版本化本地 JSON 文件等具体细节，并把外部 payload 映射为 domain 模型。Provider 自有 data adapter 可按明确功能读取对应 CLI 的私有数据，但原始结构与路径不得泄漏到上层。
- domain 禁止 Flutter、`dart:io`、Riverpod 和厂商协议；不可变标记用 `meta`，集合比较用 foundation 的纯 Dart 工具。
- app 可以引用具体 data 实现，因为 app 是依赖注入和默认实现装配点。

内部包只通过公开 barrel 相互引用。`zeta_plugin_kernel → zeta_foundation`、`zeta_agent_core → zeta_foundation`、`zeta_ui → zeta_foundation`；kernel/core 与 foundation 核心契约不依赖 Flutter，foundation 的宿主工具例外仅限 `src/platform/`。`zeta_markdown` 不依赖任何内部包；UI 的禁止依赖见 §1。新增包先论证独立职责与依赖边界，不按页面拆包。

### 2.1 Provider 插件包边界

宿主侧中立装配契约位于 `zeta_agent_provider_api`；共享 transport、ACP codec、payload/CLI 工具与独立测试套件位于 `zeta_agent_provider_sdk`；Codex、Grok、Claude Code 分别位于 `zeta_agent_provider_codex`、`zeta_agent_provider_grok`、`zeta_agent_provider_claude_code`。三个插件为纯 Dart 包，可使用 `dart:io`，不得依赖 Flutter、Riverpod、根应用或其他插件。

依赖方向为 `api → {core, kernel, foundation}`、`sdk → {api, core, kernel, foundation}`、`插件 → {api, sdk, core, kernel, foundation}`。api 与 core 同为中立契约层；sdk 的 testing barrel 单独暴露测试依赖，不得进入生产导入链。

`lib/src/app/plugins/agent_provider_manifest.dart` 是编译期登记入口，集中静态 definitions、保持原顺序的 settings、工厂与插件专属宿主注入。`ZetaPluginCatalog` 只消费工厂列表并保持原有激活/关闭/fail-closed 语义。静态指标目录不读取激活链；配置 codec 继续使用既有的激活目录接缝，不改变语言冻结顺序。

根测试的身份常量经 manifest 取得，实现类型只经 `test/src/testing/agent_provider_implementations.dart` 访问插件的独立 testing barrel。插件生产 barrel 仅暴露登记和宿主注入所需符号；management/usage 实现和私有配置键不再作为过渡 API 导出。

management repository 与 Token source/scanner/partition codec 都在各自插件包；每个激活 Provider 自己贡献一份管理定义/工厂和一份按 providerType 路由的用量工厂。宿主目录校验同一插件的身份与贡献完备性，两个 Riverpod 接缝共享校验后的不可变快照；组合层只读可覆盖接缝，空表和重复身份抛错，未知用量类型仍返回 unsupported。内核关闭后重新解析不得返回过期贡献。

管理插件仅借用 `AgentManagementHostServices` 的文本目录、runtime registry 和模型缓存窄端口。用量插件仅借用 `AgentUsagePartitionPort`，不获得 `StorageService` 或宿主路径；v4 根索引 Store 留宿主。原默认文案逐字保留，usage 未自动改成本地化目录。`AgentCliManagementCapabilities` 用可空增强键同时声明能力与持久化键，连接测试确认按能力门；整卡 Claude 安装指引是本节登记的单一品牌内容例外，范围如下。

通用版本比较、配置遮挡、日志清洗与用量扫描缓存属于 sdk 机制；宿主日志和插件共用的纯文本脱敏、显式环境 HOME 解析位于 foundation。旧测试断言与持久化身份保持不变，结构性守卫随物理路径更新，不允许扫描已删除目录而静默通过。隔离守卫动态发现所有 Provider 插件，含条件 import、export、相对路径；旧目录消失不能缩小保护范围。

本节由 `test/src/architecture/provider_package_isolation_guard_test.dart`、`test/src/app/plugins/agent_provider_manifest_test.dart` 与现有 DAG/raw/feature 守卫共同执行，反例与真实仓库使用相同的 AST 判定器。静态 manifest 与激活目录必须双向同序一致，内置 id/type、配置版本 2、用量根索引版本 4 和增强键有冻结样本。所有 Provider（含新增插件）均须声明三类贡献；功能端口可以不支持，但不可通过缺失贡献或空成功伪装完整装配。

Provider 图标的 SVG 与 `AgentProviderDefinition.icon` 由各插件包拥有；包内 `flutter.assets` 仅声明静态资源，不引入 Flutter SDK 依赖。宿主入口通过 `agentProviderIconsOverride` 注入静态查询，统一处理主题、尺寸、语义与失败回退；图标查询不得触发插件激活、猜测自定义实例品牌或写入持久化配置。未知 Provider 或缺省图标显示中立扩展图标。宿主不再保留厂商资源表；AST 守卫不豁免图标文件中的身份字面量。管理页 `_setupGuideAgentId` 仅选择整张 Claude 安装指引卡；内容含厂商品牌，不作为可复用能力。不得用此例外新增业务分支。第二家需要安装指引时，须一并设计内容契约并移除该例外；连接确认与额度增强仍按 capability。

插件文案目录遵循 `AgentUiTextCatalog` 的纯 Dart 接口 + 不可变 fallback + 宿主 ARB 实现模式；management 迁完整目录，usage source 只接五成员窄端口。持久化身份冻结要求变更评审核对配置 codec/store 的 diff，并对索引版本、分区 codec 与样本字节进行回归，不用源码路径是否存在代替行为验证。

CI 使用自动发现的 package 矩阵，`test_packages.sh --only` 的分析与测试失败均使 job 失败；新增测试包不需要改第二份 CI 名单。根六片按语义归组：Agent 界面、通用 UI、其他 feature、app、契约/数据、Agent application。重平衡用 `report_test_timings.dart` 的报告，不将本地 suite 累计耗时宣称为 CI 墙钟。

## 3. 状态与异步编排

### 3.0 状态所有权与 Riverpod 边界

核心模式是 MVI：**不可变 state + 同步 reducer + effect runner**。Riverpod 承担其中的
**发布机制与依赖装配**，MVI 的三段式本身不变。

跨 Widget 状态由 application 的 `Notifier` / `AsyncNotifier` 独占；不额外建立手写 Store、listener 列表或镜像 Notifier。

| 层 | Riverpod 使用 |
| --- | --- |
| domain / data / 内部包 | 禁止；core 通知使用 `AgentListenable` |
| application | 仅状态与命令 API，禁止 Widget、WidgetRef、ProviderScope |
| presentation / app / 宿主 UI | 可用 |

只从 `flutter_riverpod` 导入，必要时使用其 `misc.dart`。不直接导入传递依赖 `riverpod`，不引入状态管理 codegen。application 同时禁止直接导入 `package:flutter/`；跨包 barrel 带入的 Widget 符号也不例外。守卫：`feature_layering_guard_test`。

**会话 UI 发布是两跳。** RuntimeController 经 AgentUiUpdateScheduler 投影 regions，application 的 AgentConversationSliceNotifier 对每个 request 做一次 RegionsRefreshed，再由纯 selector / AgentRegionBuilder 订阅。没有手写 Store 或镜像 Notifier；live-turn 增量通道保持不变。上下文面板显隐属于 Widget 状态。

Workspace 与 Conversation 的所有权：`AgentConversationWorkspaceNotifier` 直接拥有 entry 资源表与不可变 workspace state；每个 entry 的 `AgentConversationSliceNotifier` 独占轻量 regions 和命令账本。`AgentConversationOwnerKey(entryId, lifetimeToken)` 在草稿晋升和 runtime restart 时不变，同 thread 关闭重开分配新 token；BindingKey 只作查询别名。Live 解析真实 owner，Closing/Closed 返回无正文的终止投影，Unknown 返回不可用空投影。

`workbenchSessionProvider` 先构造完整 Shell，组合根在语言冻结后、Widget 挂载前启动事实源、管理 ingress 和幂等 `Shell.start()`。IdeHome 只借用已有 workbench 与订阅；卸载不关闭 owner、Binding 或 runtime。草稿与滚动快照仅驻留 presentation 内存，按 controller 弱身份保存并在 entry 关闭时清理；焦点、弹层和 IME composing 不保留。诊断 snapshot 按需读取唯一 owner，不使用 Shell relay。

关闭顺序为：停止 Shell/M/P 命令 → 刷新已有 session 保存 → 等待 M/P 真实执行排空 → 关闭管理消费者与事实源 → 逐 entry 关闭 ingress、撤下可见项、退订、dispose controller、await lease release → BindingManager → runtime registry → plugin catalog → container。entry/app 重复关闭共享同一 Future；失败保持 Closing/失败终态，不标记释放、不销毁容器掩盖失败。lease release 只证明 consumer 释放，CLI 退出仍以 registry close 为准。

物理 Conversation family 在 build 取得显式 `keepAlive`，协调器保留容器级订阅。只有 lease 释放成功且终止空投影无人观察后才撤销保活并 invalidate；`autoDispose` 此时仅回收已关闭投影，不决定业务资源寿命。这是对原非 autoDispose 伪代码的实现修正：当前 Riverpod 普通 family 的 invalidate 不删除缓存节点。Workspace、Management、Project Threads 的 app owner 仍非 autoDispose。会话命令统一经 Actions，接线见下文。

Conversation 的 UI 写操作统一调用 `AgentConversationActions`，Live 句柄就是该 entry 的 `AgentConversationSliceNotifier`；关闭/未知目标只返回无状态拒绝句柄。每次调用冻结 typed payload、OperationId、owner lifetime 和 scope，经同步 reducer/runner 执行并返回 typed outcome。四类审批独立去重；只串行权限偏好与同项 session config，取消和审批不排在配置后面。关闭立即以 staleTarget 结算全部 UI waiter，底层 I/O 与租约释放仍由既有生命周期负责。

模型保存逐请求区分 succeeded、requiresConfirmation、superseded、unchanged 与失败；fork 返回 outcome、内存中的 createdSession 和 activated，不能用“创建了 session”推断激活成功。编辑后分支交接经 Shell 新 entry 的 Actions 发送并回传真实结果。Widget/弹层捕获稳定 Actions，不能在迟到回调中重新解析 BindingKey；RuntimeController 只保留 executor、内部初始化与只读查询职责。正文、权限快照、产物与错误原文不进入新增状态、日志或持久化。

依赖注入使用 Riverpod overrides。无安全默认值的依赖声明为抛错的 Provider；有安全默认值的实现放在 provider body。`ZetaAppComposition.create` 只接收 overrides，不装调用方需要替换的默认 override。

feature application 声明但无法依赖 data 实现的端口，由入口装配；窗口宿主先 `prepareDesktopWindow`。测试使用 `zetaTestComposition` / `zetaTestApp` 提供内存存储、无头窗口和隔离的探测实现；同一 provider 只覆盖一次。

环境差异用实现表达，例如 Native/Headless WindowHost，不向业务代码传递环境布尔开关。平台 WindowListener 只允许在 app 窗口模块，`MainApp` / `IdeHome` 不持有原生窗口监听。

`ref.onDispose` 只做幂等退订与清引用。需要 await 的资源由应用生命周期关闭；autoDispose 不决定 Binding、runtime、进程或文件句柄寿命。Conversation family 按前述显式释放条件撤销保活。

Runner 通过 `Runner Function(Notifier)` 工厂取得 owner/result sink。禁止 Deferred 空壳、可变 relay 或 Runner 持 Ref 回读 owner。AsyncNotifier 的竞态使用 ref 生命周期；跨会话业务操作仍必须保留 identity、scope 和 generation 复核，不能用 `ref.mounted` 替代。

Management 的状态、operation waiter 与执行账本由应用会话级 `AgentManagementSliceNotifier` 独占；`agentManagementSliceProvider` 非 family、非 autoDispose。`build` 只读取冻结依赖，Runner factory 接收具名 `AgentManagementResultSink`，不得持 Ref 回读 owner。设置与运行事实经独立 app ingress 输入，Page、Editor、LogView 只读 provider 与 `AgentManagementOperations`，没有旧 Store、Deferred 或状态镜像。

关闭先封命令入口；探测等待者结算为 typed `closed`，其他操作仍以原 `StateError` 结算，再 `await drainExecutions()` 等待已发出的真实 I/O，最后释放 runtime registry、插件和容器；`ZetaAppComposition.close()` 可等待且幂等，同步 `dispose()` 只启动同一关闭过程。Runner 返回的执行 Future 包含探测后的持久化与日志的两段读取，不能拿已结算的调用方 Future 当作资源释放证据。原初始化/保存错误和堆栈只沿 Future 传播，不加入新状态或日志。

首页探测与管理页共用同一 owner。`AgentManagementDetectionState` 区分逐 Provider confirmed、pending partial、outcome、失败与缓存写入警告；只有正式成功覆盖本 Provider 的确认记录，部分失败保留其他成功结果和失败项的旧记录。成功的 `notInstalled` 才能移除已安装行。`agentsById` 仅为由显示定义、确认记录、当前 settings、显式连接检查和运行事实计算出的安全只读 getter，没有可写 backing field。

`ensureDetected()` 消耗工作台的一次自动尝试；`refreshDetection()` 是显式重试。首次 await/dispatch 前占住同一 caller Future，并登记物理执行；初始化期间、正在运行和取消后的排空期间均加入同一 Future。逻辑取消立即结算 `canceled`、清空临时进度，仍等待已发出的仓储/持久化完成。异常映射为 normalized failure，不把原始异常写入新 state；observer 异常不改变已接受的成功回执。贡献目录在 app 会话内冻结；新目录代次取消旧 run，相同 id 的旧结果不能进入新定义。

`ContributedAgentManagementDetectionAdapter` 在 app 中将仓储 `ManagedAgent` 转成安全 `AgentDetectionDetails` / partial，逐 Provider 隔离失败。持久化前读取最新配置，只合并现有探测白名单，不回写旧 enabled、command、arguments、environment、权限或无关 extra；确认未安装时移除旧 `cliPath`。缓存写失败不撤销探测成功。显式连接测试的摘要和非空模型覆盖单列保存，空模型保留探测目录；进程相关配置变化会清除显式覆盖并拒绝尚未返回的旧检查结果。

路径和详细诊断只在 app 的 `AppAgentManagementDetailsCatalog` 中。application 仅持 opaque handle、是否定位到程序以及日志文件数；presentation 只能取得缩略/脱敏显示，复制和打开位置由 catalog 内部完成。新 handle 在成功事件发布前可读，回执拒绝即丢弃；探测和显式连接检查各自最多保留一个确认槽，替换令旧 handle 失效，关闭清空。配置编辑和日志读取继续走原独立端口。

首页通过 `agentManagementHomeProvider` 订阅同一 state。app coordinator 在初始恢复完成且没有活动项目时调用 ensure，管理页首次需要时加入该入口；切页/卸载不取消探测。首页测试统一覆盖 `agentManagementDetectionPortProvider`，不得恢复专用 Home loader 或列表回滚缓存。


### 3.1 容器与控制器

- 纯状态容器只暴露不可变状态和同步 intent 入口，例如
  `ProjectThreadsSliceNotifier`。
- effect runner 收敛分页、恢复、缓存、provider 调用和竞态处理，例如 `ProjectThreadsSliceRunner`；
  状态由对应的 application Notifier 独占，runner 只经 typed ingress 回流。
- 高频 UI 订阅结构相等的不可变 state slice；core 的 `AgentListenable` 仅在 presentation 适配为 Flutter listenable。不得用整数
  version/revision 作为主要刷新协议。Timeline 的 live turn 保留稳定对象和增量 mutation，
  不得因不可变状态迁移在每个 delta 复制完整历史。
- Agent UI 更新由 application 的 `AgentConversationRuntimeController` 经
  `AgentUiUpdateScheduler` 提交类型化 request；`SchedulerBinding` 只允许出现在
  presentation 的 `SchedulerBindingAgentFrameScheduler`。普通请求按下一 Flutter frame
  合并，immediate 请求吸收 pending 后在安全边界发布；不得重新引入固定毫秒 Timer、
  post-frame 释放门闩或 idle task 队列。
- `AgentConversationRuntimeController` 是会话命令 executor 与 region 投影来源，位于
  application 层。Widget 经 `AgentRegionBuilder` 与 family selector 读所需 region；
  高频 live turn 可经 presentation 的 Flutter listenable 适配。Shell 只能监听
  `AgentConversationThreadSnapshot`（`selectedAgentController`）。不得再引入
  `AgentConversationViewModel`、`AgentConversationUiStateStore` 或
  `AgentConversationSliceComposition`。
- Workspace entry 构造时必须一次性注入匹配的 thread summary、Binding 与
  RuntimeController。一个 RuntimeController 只能承载该 Binding 的固定 thread；不得提供
  跨 thread `switch`、带 restored session/provider 的通用 workspace 更新或 reset
  conversation 入口。project/file context 更新不得清空会话状态，切换 thread 必须选择
  另一个 entry。
- 跨模块共享的运行时指示（如侧栏 thread busy）若依赖独立 snapshot listenable，
  stream flush 与分区 publish 都必须同步该 snapshot，不得只 bump 面板 version。
- 对会被新请求覆盖的异步加载使用 token/version guard，旧结果返回时必须被丢弃。
- 乐观持久化必须分离“当前快照”与“最近确认快照”；快速连续更新应串行、
  合并或取消过期请求，保存失败时整体回滚关联字段并保留可重试快照。
- 业务选择态与短生命周期的 UI 展开态必须分离；例如 Composer 的
  `selectedModelId` 可持久化，`expandedModelId` 只由 Popover 持有。
- `ref.onDispose` 只做同步退订与清引用，需要 await 的业务资源按 §3.0 关闭。presentation 持有的 `ChangeNotifier`、`ValueNotifier` 或 Timer 也须显式释放；不得据此在 application/domain 引入 Flutter 通知器。
- 对外暴露的集合默认使用不可变列表、不可变 map 或 unmodifiable view。

### Project Threads 规则与索引所有权

Project Threads 的同步命令、列表事实和 thread → project 反查索引由 `ProjectThreadsSliceNotifier` 独占，Shell、Widget 与业务回归统一经 `ProjectThreadsOperations` 调用。`ProjectThreadsSliceRunner` 只通过 `run(effect)` 执行 Provider I/O、分页与搜索调度；远端归属查询经 `ProjectThreadsStateOwner.threadFor` 读取当前项目第一个匹配摘要，不猜活跃 Provider。分页提交只补齐映射，保留窗口外显式登记；整体恢复重建索引，retain/remove/close 清理对应归属，关闭后的 ingress 不再改变索引或触发选中项移除回调。

Project Threads 不使用手写 listener、presentation 镜像与 Deferred；`projectThreadsSliceProvider` 是非 family、非 autoDispose 的应用级 owner，build 用 `ref.read` 冻结依赖，runner factory 只接收 `ProjectThreadsStateOwner`。Shell 借用 Operations 与独立 Riverpod 订阅；停止 Shell 只解除回调/订阅，owner 由应用关闭。BindingManager 与 global runtime 由 app provider 提供，Workspace 与 Runner 共享同一实例。

关闭先封入口：pending void 正常完成、fork 返回 null；Runner.close 取消未触发的搜索 Timer、失效加载 token，`drainExecutions()` 等待已启动的恢复/激活/搜索、聚合查询和写入全部结束（eagerError: false，失败 Future 不替换），然后 app 关闭 BindingManager → runtime registry → plugin → container。所有未知/重复回执仍按 OperationId 判 stale；错误及堆栈只结算 Future，不进入列表状态或持久化。

同步业务测试使用固定注入时钟和 recording effect runner；I/O 测试必须通过真实 `projectThreadsSliceOverrides()` 与 `projectThreadsCompositionInputsProvider`，不得恢复一套测试专用 Runner 业务入口。结构守卫：`project_threads_state_owner_guard_test`。

## 4. Provider 与协议边界

`AgentProviderBundle` 是 application / presentation 的稳定能力边界；
`AgentProvider` 只作为 data adapter 的生命周期宿主与 bundle 适配入口。

- UI 只消费 `AgentEvent`、`AgentThreadSummary`、`AgentPermissionRequest`、
  `AgentQuestionRequest`、`AgentToolCall` 等中立模型。
- 能力域（`conversation`、`threadCatalog`、`threadSubscription`、
  `threadNaming`、`threadArchival`、`threadDeletion`、`threadCompaction`、
  `threadBranching`、`turnSteering`、`permissionResponses`、`questions`、
  `deniedActionOverride`、`modelCatalog`、`skills`、
  `localThreadList`、`sessionConfiguration`、`planApproval`、`conversationModes`、
  `permissionPolicy`、`usageQuota`）通过 bundle 端口访问；Bundle 和
  `AgentRuntimePort` 不得向 controller / RuntimeController 暴露原始 `AgentProvider`；
  controller / RuntimeController 不再通过 provider kind、`is SomeProvider` 或直接调用
  已迁移旧方法做分支。
- 权限选项选择只走中立 `AgentPermissionPolicyPort`（`listPermissionOptions` /
  `applyPermissionSelection`）。共享层仅使用 `AgentPermissionOption` /
  `AgentPermissionSelection.optionId`；Codex approval/sandbox/profile 与 Grok mode
  协议字段只允许出现在 data adapter/codec。是否展示权限选择器由
  `bundle.permissionPolicy != null` 决定，不得再使用
  `supportsPermissionPolicySelection` / `supportsPermissionProfile*` 静态位。
- Provider 默认权限偏好持久化在 Zeta 数据目录 的 provider settings 当前格式中，唯一依据为单一
  `selectedPermissionOptionId`。`AgentProviderSettingsCodec` 只解码当前外层版本；损坏或
  不支持版本回退到插件默认设置。Domain `AgentProviderConfig` 只保存归一化 optionId，
  不提供配置 `tryDecode` 门面。
  每个 `AgentConversationBinding` 独占一个 `AgentConversationPermissionState` 不可变快照；
  快照只保存该 Binding 的 thread、provider default、session effective、一次性 turn
  override、runtime selection 和精确 runtime identity，不得再维护跨 provider/runtime/thread
  的 map 或 active-runtime 注册表；
  provider default、thread effective、state source、last scope、warning 与持久化失败不得
  分散回 RuntimeController 字段。catalog 加载由独立 `AgentPermissionCatalogController` 管理：只提交
  adapter 返回的完整成功目录，transient/malformed 失败保留 last-known-good；旧 refresh
  generation 不得覆盖新目录。Codex 只有明确 unsupported 才允许降级静态 built-ins。
- 所有权限 apply 路径必须消费完整 `AgentPermissionApplyResult`：`currentTurn` 只形成下一次
  请求的一次性 override，`currentSession` 只更新目标 thread，`runtime` 更新显式 runtime
  state 且只影响拥有该 runtime 的 Binding，`nextSession` 只更新默认/待生效状态。所有迟到
  apply 必须用精确 identity/generation 拒绝；不得靠遍历或广播改写其他 Binding。
- Provider apply 成功后的偏好持久化失败不得回滚 effective/runtime 状态；application 必须保留
  可见错误与只重试持久化的入口，重试不得再次调用 Provider apply。
- create/resume/fork/send 必须携带不可变 `AgentPermissionRequestSnapshot`，由
  application 按 thread-effective → provider default → catalog default 解析。Codex
  client/encoder 只能在该快照没有 selection 时使用 Provider 构造时冻结的 config
  fallback；用户选择或 `thread/settings/updated` 不得改写跨 thread 共享的请求权限状态。
  旧裸 `permissionSelection` 参数、`AgentTurnConfiguration.permissionSelection` 与 Provider
  内兼容合并 setter/facade 均不得恢复。
- session runtime 激活后，Binding 内的 `AgentConversationPermissionState` 是 provider
  default、session effective 与 runtime selection 的唯一运行态唯一依据；provider config 只负责初次
  seed 和持久化。Project Threads 必须优先从已存在 Binding 冻结 thread 请求；没有
  Binding 时才使用 provider default 与 catalog default，禁止从其他会话借用 runtime 状态。
  `AgentPermissionRequestResolver` 只能是无状态优先级函数，不得缓存 selection。
- 所有异步 catalog/apply/request 路径必须验证足以判定新鲜度的语义状态，而不是引入额外的
  自增计数器：runtime 相关路径（apply、apply 后的 persist）以精确
  `AgentProviderRuntimeIdentity`（provider + generation）、apply port 实例与
  disposed 状态判定；无 runtime 的 dormant persist 路径以「要保存的 selection 是否仍是
  当前 provider default」判定，被更晚的选择顶掉即视为过期。catalog 刷新的乱序回写由
  `AgentPermissionCatalogController` 自身的 refresh generation 单独守卫，不与 selection
  controller 的 binding 生命周期耦合——绑定新的 catalog-only port（如 global runtime 目录
  刷新）不得连带丢弃正在进行的 session apply 结果。快速切换 Provider 后的旧结果、已销毁
  Canvas 的迟到结果以及 retired runtime 回写均必须丢弃，且不得触发偏好持久化。
- `thread/settings/updated` 的 Codex profile/approval/sandbox 必须由 data codec 一次性解码
  为 `AgentPermissionSelection`；domain event 不得暴露协议字段。reducer 允许权限事实按事件
  threadId 路由到对应 Binding；Binding 只接受自己的 thread，其他 thread 的迟到通知必须丢弃。
  同一通知不得更新 provider default、不得再次调用 Provider apply，模型和协作模式仍只作用于当前 thread。
- 每个 provider 必须通过不可变 `AgentProviderCapabilities` 声明真实能力；presentation
  隐藏不支持入口，application 和 data 层执行前仍要校验。禁止以静默 no-op 或语义不等价
  的降级伪造 thread/turn 能力。
- bundle 端口为空时，对应 capability 必须不可用；不支持功能不得靠 no-op 伪装成“已实现”。
- Session config 仅以 `sessionConfiguration` 端口声明能力。executor 返回 typed
  `AgentCommandOutcome`，缺端口继续抛 `UnsupportedError`，presentation 边界翻译为
  `failed(unsupported)`。同 configId 队列在入队前冻结目标，执行前/返回后复核
  thread、runtime identity 与 scope；dispose 立即结算 waiter。currentValue 只消费
  Provider 事件；请求失败不写全局 status.details，不记录配置 id、值或原始异常。
- 已绑定真实 thread 的 `AgentConversationBinding` 不得原地改绑到另一个 thread。fork
  返回 `AgentSession` 后必须走 Shell 的新 thread 通用流程：由
  `ProjectThreadsOperations.registerSession`（生产实现为 Store） 登记列表，再通过 `selectProjectThread` 创建或
  复用独立 Workspace Entry/Binding 并选中；“编辑后重试”最后才由新 RuntimeController 发送。
  源 RuntimeController 只发起 fork，不得继续在源 Binding 上执行新 thread 的 rename/send。
- 启动时机由 `AgentProviderBootstrapPolicy` 描述；需要项目目录的 provider 不得在获得
  workspace 前启动，也不得参与 eager model preload。
- `AgentProviderRuntimeRegistry` 是应用进程内 Provider 实例和子进程的唯一所有者，也是
  唯一允许调用 `AgentProviderBundleFactory.createBundle` 的对象。`AgentProviderGlobalRuntime` 只借用
  每个 Provider ID 唯一且永不空闲回收的 global runtime；模型、Skill、用量、历史和
  thread 管理等会话前/全局操作不得创建 session runtime。
- Registry `acquire` 必须显式传入 global/session scope，不得提供默认 global 兼容值。
  使用统计面板只能通过 `AgentProviderGlobalRuntime` 读取 bundle 的 quota 端口；不得接受
  raw Provider loader、lease loader 或 shared-provider predicate 等并行生命周期入口。
- 可选 `AgentProviderAcquisitionPreparationPort` 属于中立生命周期机制。Registry 每次 acquire（含复用）返回前等待准备，失败释放该租约，等待后重新校验有效性；端口不暴露凭据或 Provider 协议。准备不能启动会话或扩大权限；运行中的新请求由具体 Provider 再次校验自身认证条件。
- `AgentConversationBindingManager` 按 `draft(providerId, entryId)` 或
  `thread(providerId, threadId)` 唯一映射逻辑会话。草稿拿到真实 threadId 后必须原子晋升；
  目标 key 已存在时 fail-closed。Workspace 只持有 Binding lease，RuntimeController 不得持有
  registry lease、scope、pin 或 runtime identity 缓存。
- `AgentConversationBinding.beginTurn()` 是创建 session runtime 的唯一入口；打开草稿、打开
  thread 和读取历史都不得调用它。cancel、steer、审批/提问回写与 session configuration
  只能通过 `runCurrent` 使用已存在实例，实例已回收时 fail-closed，不得为迟到操作重启 CLI。
- Binding 必须显式发布 `dormant` / `starting` / `attached` / `cleared` runtime 生命周期。
  `starting` 和首次初始化失败不得通过 `currentRuntime == null` 被推断为断连；只有曾进入
  `attached`、且按精确 runtime identity 清除后产生的 `cleared` 才能结算当前 turn 为中断。
- Binding Manager 每分钟执行 single-flight 扫描。session runtime 在没有运行中 turn/RPC 且
  最后活动满 10 分钟后回收，候选必须携带精确 runtime identity 防 ABA；同一 scope 的旧进程
  dispose 完成前，新 acquire 必须等待，禁止新旧 CLI 重叠。配置变化仍会失效该 Provider 的
  global 与全部 session runtime；旧 generation 的事件和权限 apply 必须丢弃。
- 多个 Pane 共享 Provider 时，thread/session 状态必须按 ID 隔离。启动或恢复另一个会话
  不得隐式退订、清空或使其他会话的 reducer 失效；退订只由明确关闭对应会话的调用方发起。
- 桌面窗口关闭必须等待运行时注册表关闭全部 Provider，再 flush 日志并退出，避免遗留
  app-server 或 stdio 孤儿进程。
- Codex app-server 的 JSON-RPC、通知、审批 payload 和历史 JSONL 解析必须留在 agent data 层。
- 权限审批、用户提问和计划审批必须保持独立领域语义：
  `respondToPermission` 只接受 approve/deny/cancel 决策，
  `respondToQuestion` 只接受结构化 answers（空 map 表示 Skip），计划审批继续通过
  `AgentPlanApprovalPort` 回写。三者可以共享 Pending Interaction Dock，但不得复用
  request/decision 模型或 pending registry。
- Plan 回合完成后的“是否执行”属于 Zeta 本地 application 交接，不属于 Provider
  计划审批。它使用独立的 `AgentPlanExecutionRequest`，不调用 approval/permission/question
  端口，不持久化，并在 thread、workspace、provider 或可写性边界变化时清除。
- 本地交接只能由成功的 Plan 终态和非空计划内容触发。执行动作必须通过新的 Default
  `turn/start` 发起；继续规划保持 Plan draft；任何动作都不得预授权后续工具或文件修改。
- 只有支持独立用户提问协议的 Provider 才发布 `questions` 端口；
  permission-only Provider 不得用空 answers、no-op 或权限拒绝伪造提问能力。
- 新 provider 应先评估现有 bundle 端口是否足够；不足时优先扩展可选端口，再在 data 层
  实现具体协议。工厂直接创建原生 `AgentProviderBundle`；旧 `AgentProvider` 大接口已删除，
  不得恢复。静态能力默认值由 data 组合层注入，Shared Domain 不按厂商名称 switch。
- 非所有 provider 都具备的账号能力使用可选端口（例如
  `usageQuota`），不要把可选能力做成所有 provider 的必选实现。
- mapper 文件负责字段兼容、默认值和协议名称转换；不要在 widget 中写散落的 JSON key。
- 模型目录的 Reasoning 和 service tier 在 data mapper 中转为中立领域模型，保留服务端顺序和
  精确 tier id；Fast 等产品语义可在 domain/application 层识别，但不得改写 provider 协议值。
- 需要系统提醒的事件必须先映射为 Provider 中立的 `AgentAttentionSignal`。
  Provider adapter/reducer 决定 identity 来源，workspace 只补齐定位上下文，通知 Store
  只按规范化 identity 去重和清除，不得增加厂商分支。
- 操作系统通知不得包含 prompt、回复、命令、问题、错误原文、完整路径或 raw payload；
  payload 只保留定位与幂等必需的版本、Provider/thread 和 identity。
- 窗口获得焦点、Agent Canvas 可见且当前 thread 一致时必须抑制系统通知并清除
  该 thread 未读。任务栏/Dock 只是内部未读的投影，不是业务唯一依据。
- Conversation mode 通过可选 `conversationModes` 端口和运行时目录发现，不按 provider kind
  或 CLI 版本硬编码。模式是 thread 粘性、逐 turn 提交的状态，由 application controller
  管理 draft / confirmed / pending；不得写入 Provider 全局可变配置。
- 显式 mode 必须冻结进 `AgentTurnConfiguration`。活动 turn 中修改 draft 只影响下一次
  `turn/start`；退出 sticky Plan 必须显式发送 Default。Codex data encoder 负责嵌套
  `collaborationMode.settings`，且 mode 存在时不得再发送冲突的顶层 model / effort。
- experimental 模式目录探测失败时只禁用模式入口，不影响普通 Default 对话。临时 transport
  失败可重试，method-not-found 或损坏目录在当前 runtime generation 内保守降级；重建
  Provider 后重新探测。
- 标准 ACP 的 session update 语法只通过无状态 `AcpSessionUpdateDecoder` 解码；content
  block、permission option 和 session config 继续复用各自 codec/mapper。厂商 source id、
  segment/phase、去重和终态策略必须留在对应 Provider adapter/reducer，不得放回共享层。
- 厂商阻塞请求必须覆盖成功、拒绝/跳过、取消、超时和 provider 清理路径；每条路径都要
  回包、释放 timer 并移除 presentation pending state，未知 request 明确返回 `-32601`。
- 通用 CLI 名称（例如 `agent`）不得只按 basename 判定产品身份；定位器必须
  组合无副作用版本/帮助探测，并在 ACP initialize 的 `agentInfo` 上二次校验。
- workspace-scoped provider 的子进程 cwd 与 session cwd 必须一致；workspace 变化时关闭
  旧 peer、清理待响应请求并重新握手，禁止跨项目复用进程。
- JSON-RPC provider 必须复用 `ProviderRuntimeJsonRpcPeer` 的生命周期 gate。`closing` 后
  禁止新 client RPC；反向请求以 `(runtimeId, connectionEpoch, requestId)` 为权威身份，
  dispose 必须关闭 transport 并等待已入场的 start、RPC 与 handler 排空后才进入 `closed`。
- Provider 事件消费者必须使用 listener generation，并以
  `(runtimeId, connectionEpoch, providerId, threadId, listenerGeneration)` 隔离旧流；旧
  listener 的退出回调不得清理新 generation，Thread/Provider 切换应在首个 `await` 前
  使旧 generation 失效。
- 每个对话事件源必须由 `AgentEventPipeline` 集中持有 subscription、listener scope/gate、
  `CoalescingEventBuffer` 和 `BoundedEventDispatcher`。关闭时先使 scope 失效并停止接收，
  再取消 source；Thread 切换、替换与 dispose 清空旧缓存和 dispatcher 队列，只有当前
  generation 的自然 `onDone` 才会有界 drain 已接收事件。detached runtime 事件仅可在
  scope 仍当前时按既有 critical allowlist 接收，旧 `onDone` 不得释放新 Pipeline。
- Transport 与 Provider mapper 不得丢弃协议事件。`AgentEventCoalescingPolicy` 只定义
  Agent key、merge 与 barrier；通用 `CoalescingEventBuffer` 只实现有界 keyed 合并。
  Application 投影层只允许合并同一
  thread/turn/item/kind 的连续文本或 reasoning delta、token/文件变更最新完整快照和工具 progress；
  item/工具/turn 终态、审批、错误和连接状态必须先 flush 缓冲后立即发布。背压诊断不得包含正文。
- `BoundedEventDispatcher` 保持 FIFO，默认每个 Dart event-loop turn 最多处理 64 个事件，
  continuation 使用 `Timer.run` 让步；名称和职责不得与 Flutter frame 调度混淆。
- 规范化事件必须由 `AgentConversationEventProcessor` 编排。`AgentConversationReducer`
  只能同步产生 typed state、`AgentTimelineMutation`、ThreadSnapshot、
  `AgentUiUpdateRequest` 与 `AgentConversationEffect`；不得导入 Flutter scheduler、创建
  Timer、执行 Future 或调用外部端口。live/history/replay 必须使用隔离的 reducer/context，
  不得共享可变 identity、错误去重或 deprecation 状态。
- Processor 只登记 ThreadSnapshot 刷新；实际 listenable 写入必须与 typed UI state 共用
  presentation scheduler 的安全发布回调，不得在 Flutter build phase 同步通知 Shell。
- TimelineStore 可以继续执行增量 mutation，但不得决定 UI urgency、读取 Provider raw 字段
  或增加 Codex/Grok 分支。外部回调、模型目录持久化和结构化错误日志由 EffectRunner 执行，
  且执行前必须校验 listener generation、runtime/epoch 与必要 thread scope。
- Provider Thread 操作必须复用 `ProviderOperationScheduler`。同一 Thread 的变更使用
  `exclusive` 并保持 FIFO，list/read 使用 Project/Thread `sharedRead`；禁止同键重入，
  dispose 必须拒绝未入场任务并等待已入场任务释放资源键。
- JSON-RPC transport 与 ignored-message 日志不得记录 prompt、文件内容、文件变更 evidence、
  raw payload、认证参数或 stderr 原文；只允许 method/type/reason/count 等白名单诊断。
- 默认审批策略保持保守，不自动授权命令执行或文件写入。Plan 执行交接只可恢复进入
  Plan 前由用户明确选择、且同 Binding/thread/runtime generation 仍有效的策略；否则回落
  到 Provider catalog 默认。卡片上的本次覆盖不调用 Provider apply、不持久化，也不携带
  命令、文件或网络白名单。
- Codex app-server 协议以 `third_party/codex_app_server_schema` 的 pinned
  快照为准；升级 CLI 时先用 `tool/gen_codex_schema.*` 导出并 diff，再改
  适配层。流程见 `docs/zh/protocols/codex_app_server_protocol.md`。

### 管理运行事实边界

管理运行状态只统计本 Workbench 的 session Binding，按精确配置实例 `providerId` 聚合所有前后台 entry，并保留无 entry 但仍有 runtime 的 Binding。默认 Provider 与 Canvas 选择不参与归属；global 模型预热、连接测试和外部 CLI 进程不计入。`ready` 只证明连接，活跃 turn/等待交互才证明运行；不从历史 active 或短 RPC 计数猜测 turn。禁用是配置策略，现存事实保留至实际 clear/remove。主状态按 running → error → starting → unavailable → idle → disabled → notRunning 投影，`hasErrors` 独立保留。

`WorkspaceAgentRuntimeFactSource` 是 app 层唯一跨 feature 适配器；它借用 BindingManager 与 controller 的无正文观测，不拥有 runtime。controller 的观测与 ThreadSnapshot 共用安全发布边界，live 接线时冻结观测来源 identity/connection scope，避免旧状态被重新标记为新实例或新连接的事实。未取得 runtime 的启动失败用内存 `attemptEpoch` 隔离，重试前递增。source 按 Binding 对象身份管理订阅，回调必须校验 source/handle/subscription 代次并同步全量重读。`AgentManagementSliceNotifier` 是唯一管理 owner，reducer 统一出口投影安全 `AgentManagementAgentView.runtimeState`；初始化、探测、连接测试与 settings ingress 不得各自赋值。运行事实、opaque key 和来源代次不落盘、不写日志。

### 4.1 Agent 流式身份与叙事边界

Agent 时间线必须区分 Provider 原始身份和 Zeta 展示身份：

- `sourceItemId` / `sourceMessageId`（统称 source id）保存 Provider 协议给出的
  message/item/event 身份，用于关联、去重和诊断；它不是 UI 合并键。
- `entryId` 是 Zeta 规范化时间线条目身份，也是 CoalescingPolicy/Buffer、TimelineStore 和 UI
  的唯一合并键。迁移期内 `AgentMessageDeltaEvent.messageId`、
  `AgentMessageUpdatedEvent.messageId` 和 `AgentReasoningDeltaEvent.itemId` 字段名暂时
  保留，但语义均为 entryId。
- 同一连续可见条目的 delta 必须复用 entryId；条目被关闭后不得复用。两个 turn
  即使复用同一个 source id，也必须得到不同 entryId；不得用固定 `unknown` 作为
  message/reasoning entryId。
- Provider 的 completed/snapshot 必须通过 source→entry 关联更新已有条目。若一个
  source message 已被拆成多个 segment 且协议没有 segment 信息，完整 snapshot 不得
  猜测性覆盖任一 segment，只能更新可安全关联的 metadata。

`narrative boundary` 是会改变可见时间线顺序、并关闭当前 message segment 或
reasoning phase 的事件。边界至少包括：source message id 改变、正文与 reasoning
互相切换、首次出现的 tool、plan、permission/user question/plan approval、实际进入
时间线的 warning/system 条目以及 turn terminal。以下情况不额外创建边界：同一 tool id
的状态更新、usage/status/config 更新和重复 raw event。连续 reasoning chunk 属于同一
phase；被正文、tool、plan 或交互打断后的 reasoning 必须使用新 entryId。

身份决策与状态隔离遵循以下边界：

- 当前活跃 Provider 是 Codex、Grok 与 Claude Code。共享 ACP decoder 只能解析协议语法和
  typed 字段，必须无状态；Grok data adapter/reducer 负责解释 ACP source id、segment/phase、
  去重和 lifecycle，Codex mapper 按 app-server item 生命周期确定 entryId，Claude Code
  data identity/mapper 按 stream-json message/tool 与 Zeta 自行 mint 的 turnId 确定边界。
  共享层不得提供带 eventId/turn scope 叙事假设的 identity mapper；Store/RuntimeController/UI
  不得读取 raw payload 推断 identity 或 plan。
- live、replay、history 可以复用同一 reducer 算法和 entry-id builder，但必须使用不同
  实例，不得共享 current segment、seen event/tool、terminal 或 generation 状态。
- live 状态至少按 `(runtimeId, connectionEpoch, providerId, sessionId, turnId)` 隔离；
  新 turn、cancel、prompt 失败、peer close、provider dispose、epoch 变化和 session
  删除/切换必须使旧状态失效。replay/history 在 build、失败或取消后也必须释放状态。
- CoalescingPolicy/Buffer 只允许合并同 entryId、同事件 kind 和同必要 detail 的事件；任一非合并
  事件先 flush。它不得推断“最后一个开放气泡”或替代 Provider boundary 状态机。
- TimelineStore 只执行 dumb merge：同 entryId 更新、异 entryId 新建、同 tool id 原地
  upsert，不读取最后条目猜边界、不改写 id、不分配 segment，也不包含 Provider 分支。
  新增 Provider 只需在 data 层实现 decoder/adapter/reducer 并输出完整 `AgentEvent`，无需
  修改 CoalescingPolicy/Buffer 或 TimelineStore。
- eventId、messageId 稳定性和 delta/snapshot 语义必须由带 Provider/CLI 版本的脱敏
  fixture 证明；缺少真实证据时明确阻塞对应门禁，禁止复制其他 Provider 的假设。
- History parser 只能只读来源文件；Grok 每次解析必须创建 fresh reducer，缺少稳定 turn id
  时使用确定性的 history turn ordinal。live/history canonical regression 必须逐位置比较 turn/entry
  ordinal、entry type、message/reasoning phase、source id、规范化文本和 tool kind/status。

文件变更证据遵循同一身份与状态边界：

- `AgentFileChangeSnapshot` 是单个 tool 或 turn owner 的有序、不可变、完整累计快照。
  owner/change id、动作、顺序、`revision`、`replayability` 与 partial 更新的 last-valid 规则
  全部由 Provider-local mapper/tracker 决定；`null` 表示没有 snapshot，空 `changes` 表示权威清空。
- evidence 只表达 Provider 明确给出的事实：替换前后片段、写入内容或 unified patch；
  `null` evidence 只表示路径/动作摘要。空字符串是合法显式值，不能用来猜新建、删除或缺字段。
- 同一 file-change tool 的后续 status/terminal 事件必须继续携带完整 snapshot。Codex 等协议若同时
  提供 tool-scoped 证据与 turn aggregate，优先级、抑制和 empty clear 必须在对应 Provider
  tracker 中完成；共享 Store/UI 不跨 owner 按路径去重。
- 只有命令执行、审批参数或工作区结果时不得生成文件变更 snapshot；禁止解析命令、读取当前
  文件或运行额外 diff 来补证据。presentation 可以解析 typed unified patch 做高亮与行数统计，
  但不得从 patch header 反推路径、动作、owner 或 identity。
- `replayable` 证据必须由 live/history/replay 的独立 tracker/reducer 重建并做 canonical 回归；
  `liveOnly` 只能明确展示为当前实时降级，不得冒充历史可恢复事实。
- Cursor 已彻底清退，不参与当前 schema、catalog、UI、Provider 组合、live/replay/load、
  ACP 扩展、进程启动、测试或 fixture；不得为未发布数据保留 decode/fallback 兼容值。

### 原始协议与字段重建

`AgentProviderRawPayload` 递归冻结原文，不暴露 `operator []`、keys 或 toMap；唯一内容出口 `toPrettyJson()` 仅供上下文面板。适配层使用内容无关的 `wrapAgentProviderPayload(...)`，不得直接调用底层 wrap。`capturedAt` 必须由具体 Provider envelope mapper 显式提取并传入，共享包装器不得扫描 timestamp/createdAt 等字段推测。

需要业务语义时声明 typed 字段。新增字段必须检查 `AgentConversationTimelineStore._mergeToolCall`、history snapshot 的 enrich/overlay 等逐字段重建位置；默认值会掩盖遗漏，必须以回归覆盖。共享层、日志、指标和持久化不得读取原文。守卫：`agent_core_raw_payload_freeze_test`。

### Provider handler 覆盖

覆盖只在该 Provider 自己的 bundle 中，通过 `defaultAgentHandlerRegistryBuilder()` 上的 `register<E>()` 注册。PR 必须说明共享实现为何不适用；共享 reduction 目录不得加入厂商身份分支。

权限、提问、Plan 审批共六个 requested/resolved handler 在 seal 后禁止覆盖。Plan 执行交接由 turn 完成 effect 触发，其保护在 effect 层：`AgentAutoStartPlanExecutionEffect` 必须 `requireThread: true`、scope 含 turnId，执行前重新校验 listener generation、runtime/epoch。覆盖 `AgentTurnCompletedEvent` handler 时必须验证对执行交接的影响，不放宽权限。

### 4.2 共享适配层纯度门禁

本节中的“共享适配层”包括共享协议 decoder/codec/transport、
`AgentEventPipeline`、`AgentEventCoalescingPolicy`、`CoalescingEventBuffer`、
`BoundedEventDispatcher`、`AgentConversationTimelineStore`、共享 handler 注册表
（`packages/zeta_agent_core/lib/src/application/reduction/`），以及消费中立
`AgentEvent` 的 application/presentation 投影。它们是 Provider 无关的机制层，
厂商兼容逻辑留在各 Provider 自有的 mapper、adapter、reducer 和 history parser 中；这些实现不属于共享适配层。

共享适配层只允许承担以下职责：

- 按公开的通用协议契约做无状态语法解码，并输出 typed protocol update；
- 按中立 domain 字段执行可由类型直接证明的通用行为，例如同 entryId 合并、
  同 tool id upsert、机械替换完整文件变更 snapshot、按事件 kind 维持 flush barrier；
- 执行与 Provider 无关的生命周期、缓冲、存储和 UI 投影，不补充任何协议语义。

以下行为一律禁止：

- import 或依赖 Grok、Codex、已退役 Cursor 等具体 Provider 实现；
- 根据 `providerId`、Provider kind、实现类型、显示名称或 CLI 名称分支；
- 从 raw/extra payload、厂商字段、eventId 或 source id 猜测 entryId、message segment、
  reasoning phase、plan、叙事边界、去重、终态或错误恢复策略；
- 从 rawInput/rawOutput、命令、路径或 patch header 猜测文件变更 identity、动作、证据类型，
  或替某个 Provider 保存 partial update 的 last-valid snapshot；
- 在 CoalescingPolicy/Buffer、TimelineStore、RuntimeController 或 UI 中为某个 Provider
  修复乱序、缺 id、
  delta/snapshot 差异或终态竞态；
- 为接入新 Provider 修改 Store 的合并规则，或在共享层增加以 `unknown`、最后开放条目、
  `#segN` 等启发式生成/修复身份。

如果共享层确实需要新的行为，必须先把它建模为名称和语义均与 Provider 无关的 typed
domain contract，并证明至少是协议级或跨 Provider 的共同语义。仅由单个 Provider 原始字段
驱动的行为不得通过 raw map、魔法字符串或隐藏 flag 穿透到共享层；它应由该 Provider
adapter/reducer 消化后输出语义完整的 `AgentEvent`。共享 decoder 的协议版本兼容也只能基于
通用协议证据，不得以 Provider 名称作为条件。

`AgentConversationTimelineStore` 与共享 reducer 若必须产出 Zeta 自有用户可见文案，
只允许通过构造函数注入不可变、Provider 无关的 `AgentUiTextCatalog`。禁止 import
generated l10n、Flutter `Locale` / `BuildContext`，也不得按 Provider 分支选文案；
entryId、叙事边界和 merge 规则仍不得因语言变化。

该边界是新增 Provider 和流式改动的评审门禁：正常接入只修改 Provider data 层、组合边界和
Provider 契约测试。若 PR 因 Provider 差异修改 CoalescingPolicy/Buffer 或 TimelineStore，
必须先证明这是中立
契约缺口；否则应退回 Provider adapter/reducer。共享层测试应使用 Provider 无关 fixture，
并持续断言无具体 Provider import、kind/id 分支和 raw identity 推断。

## 5. 持久化与恢复

持久化数据必须可演进、可恢复、可容错。

- 生产入口以系统应用文档目录为基址创建 `.zeta`，见 `ZetaUserDirectory.getUserDirectory` 与 `lib/main.dart`；`ZetaDataPaths.fromHomeDirectory` 是通用路径构造器，不能据名称推断生产使用 HOME。以下文件均相对于实际数据目录：
  `config/providers.json`、`config/appearance.json`、`config/general.json`、
  `state/ide_session.json`、`state/usage_statistics_index.json`、
  `logs/zeta-YYYY-MM-DD.log` 与 `cache/agent_models_v1.json`。
- `config/general.json` 当前为 v3，用 `appLanguage` 持久化 `en` / `zh-Hans`。
  只解码当前版本；未知语言回退英语，损坏或不支持版本使用启动编排给出的 fallback。
  localized UI copy 不得进入任何 JSON store。
- HOME 解析、目录布局和安全文本替换属于 `core`；各 feature 的 data store 只接收
  `StorageService` 并负责自身 codec。注入走容器：`ZetaStorageBindings` 由**入口**
  解析一次（生产 `.file(paths)`、测试 `.memory()`），把 `providerOverrides` 展开进
  `ZetaAppComposition.create(overrides:)`，store 由
  `lib/src/app/storage/zeta_store_providers.dart` 的 provider 组装，不把 bindings 或
  `StorageService` 当构造参数向下钻；presentation/application 不拼接数据目录路径。
  存储 provider 的默认值保持 fail-closed：组合根替它装了，调用方就换不掉了。
- Claude 按需 OAuth 刷新可更新其原有 CLI 凭据存储，这是明确的认证维护能力：macOS 只写已选中的 Keychain 条目，文件来源只原位替换已有文件。锁内重读、远端刷新、保留无关字段和写回校验必须完整执行；不得迁移来源、备份 secret、扩大 scope 或把凭据保存到 Zeta 自有目录。其余 Provider 私有数据读取不自动获得写入授权，详见 Claude 协议 §11。
- 当前不读取旧 SharedPreferences，也没有历史文件迁移器或 marker。
- 会话状态使用当前版本 JSON；字段新增时提供默认值。
- `tryDecode` 或等价宽容读取逻辑必须处理空值、损坏 JSON、不支持版本和未知字段。
- 启动恢复失败不能阻断应用进入主界面。
- provider 全局配置和项目级 session/thread 状态必须分开存储。
- provider 模型偏好按 `modelId` 保存为版本化条目；当前 selection 和偏好 map 必须同快照写入，
  宽容解码忽略损坏条目并用最新 capability 重新归一化。
- provider 模型目录由 app 级共享仓储统一读取和缓存。启动预热不得阻塞主界面，只预热
  active provider；普通读取采用 stale-while-revalidate 与 single-flight，显式刷新绕过
  provider 内存缓存。共享仓储是 TTL 的唯一依据；refresh loader 必须读取 Provider 权威
  来源。single-flight identity 必须包含安全配置指纹，并以 generation/version 守卫阻止
  失效配置的旧任务回写。协议分页必须完整拉取，失败不得覆盖最近一次可用目录。
- 相同模型目录的 response 与 runtime event 不得重复持久化；实际内容未变化的主动事件应
  保留现有快照，成功的 TTL 刷新即使目录未变化也必须更新获取时间并持久化。
- 模型目录缓存只持久化规范化 domain 白名单字段、不含密钥的配置指纹与获取时间；不得
  保存 provider raw payload、环境变量值或凭证。损坏、版本不兼容、配置变化和超期均应
  宽容失效。
- 路径不存在、目录不可读、权限失败等文件系统异常应转换为可理解状态或日志。
- Agent 配置保存必须先校验语法、检测外部修改、写入同目录临时文件并保留原文件
  备份；不得直接覆盖符号链接或在失败后破坏原配置。
- Agent 日志在进入 UI 前完成凭证与用户目录脱敏。
- 指标只经 `ZetaMetricsPort` 上报；名称登记在 `ZetaMetric` 白名单，标签仅允许规范化的 `providerId`、`component`、`outcome`。采集在 app 组合，业务默认 no-op；`ProviderObserver` 不读取 provider state 或 family 参数。日志和指标不得记录 prompt、回复正文、工具输出、原始错误、环境变量值、凭据或原始协议。
- 应用根日志同时保留 developer 输出并按本地日期追加到数据目录中的 `logs/`；文件 sink
  必须串行写入、脱敏消息，写入失败不能递归进入根 Logger，并在正常关闭窗口前
  排空待写队列。
- 使用统计派生索引只保存聚合所需元数据；禁止写入 Prompt、回复正文、工具输出、
  session 文件路径和原始错误文本。索引必须版本化并支持损坏后重建。
- 文件变更 snapshot 只存在于内存时间线；替换片段、写入内容和 unified patch 不得进入
  Zeta 配置、状态、缓存、日志、系统通知、thread summary 或使用统计索引。
- Provider 自有 data adapter 可以读取对应 CLI 的配置、会话、日志和账号 metadata；
  application/presentation 不得自行遍历 Provider 私有目录，也不得接收原始文件路径或
  payload。读取权限不自动授权迁移、复制、改写或删除；这些写操作必须有独立产品契约、
  用户动作和失败恢复设计。

## 6. UI 与交互

界面需保持可读的信息密度，支持键盘、文字放大和窄窗口。

- `IdeHome` 是主要页面唯一的 Workbench 组合边界。首页、设置、Agent 管理和使用统计
  必须由同一个常驻 `WindowFrame` + `IdeWorkbenchScaffold` 承载，只切换
  Navigation、Canvas、Inspector slot；Feature 页面不得另建或替换顶层骨架。
- Workbench 负责布局模式、Pane 表面与 Overlay，Feature 负责业务内容、控制器和离开
  确认。设置页应通过 `SettingsNavigationPane` 与 `SettingsPageCanvas` 接入 slot，
  不把设置分区或 Agent 配置规则下沉到共享 Scaffold。
- 跨页面保活的 Canvas 必须保证关键 State、`ScrollController`、输入控制器和当前 Thread
  不被销毁。可能因兄弟 slot 增删而换位的 Flex 子节点必须直接使用稳定 Key；仅给内部
  Widget 加 Key 不足以保证父级 Element 复用。保活实现必须只布局活动页面；禁止用
  `IndexedStack` 保留包含长时间线的页面或会话。
- 连续 resize 只允许按布局语义档位更新业务树。`IdeConstraintBucketBuilder` 的稳定
  callback 不得因父级每像素重建而失效；捕获了新配置的 callback 必须显式改变身份。
- Agent 时间线必须使用 block / activity / footer 粒度的稳定 viewport item 与
  `SliverList.builder`。隐藏会话 layout 增量必须为 0，可见 item 构建数必须受 viewport
  限制，不得随全部历史长度线性增长。
- turn grouping、unified diff 和代码高亮分别使用 render revision cache、projection
  cache 与稳定 `HighlightView` identity；数据未变化的 resize 解析增量必须为 0。
- Footer、Pending interaction 与 Active plan 必须在单次 layout 内定位；禁止
  post-frame 读取高度后 `setState`。
- 设计系统底层是 `shadcn_flutter`（`^0.0.53`）+ Graphite token。语义色/字号
  走 `IdeThemeScope` / `IdeColors` / `IdeTextStyles`；第三方组件走 `sf.*`。
- 统一 `import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;`，禁止旧
  `shadcn_ui` / `Shad*` / `showShadDialog` API。
- 新 pane 或重复项优先复用 `Pane`、`PanelCard`、`IdePopoverPanel`、`IdeTabs` / `IdeTab`、`IdeChip`、
  `IdeContextMenu`、`IdeStatusCard`、`WindowFrame` 和主题常量。
  锚点弹出层（Composer 模型/权限/模式、菜单、选择列表）统一用 `IdePopoverPanel`，
  与 Composer 外卡同色、同描边、同 medium 圆角，并带浮层投影；不要再叠
  `sf.Card` 或 SelectPopup 自带卡片。`IdeSurface.popover` 仅用于用量统计等独立浮层面板。
- IDE 通知统一走 `showIdeToast`，不要在 feature 页散落 `sf.showToast` builder。
- 长项目路径、文件路径、thread 标题、工具调用摘要和 diff 统计必须限制行数并使用 ellipsis。
- 非文本按钮需要 tooltip；重要自定义控件需要语义标签。
- 重复的交互行应使用稳定 `ValueKey`，方便测试和状态保持。
- Popover 中的可选列表应支持 roving focus、禁用项原因、Esc 关闭与焦点恢复；
  展开动画必须遵循 reduce motion，不得在用户滚动时强制自动定位。
- 流式消息、语法高亮代码块、diff 明细等高频或重绘成本高的区域应使用 `RepaintBoundary`。
- 桌面布局优先用 `Expanded`、`Flexible`、`LayoutBuilder`、scroll view 和具有足够最小高度的工具栏避免溢出。
- 统计页等宽数据面板在宽屏可双栏排列，窄屏必须回退为单栏；宽表格使用受限的
  横向滚动，不得挤压文本到不可读宽度。
- 界面语言只有英语与简体中文。生产 Locale 在常规设置加载后冻结为
  `settings.appLanguage`，当前进程不监听设置选择或系统 locale，也不因语言字段
  重挂 `IdeHome`。首次启动只解析系统首选语言第一项：显式简体与无 script/region
  的 `zh` 选简体中文，显式繁体与其他语言回退英语；已有安装保持中文。
- 应用侧 Widget 通过 `context.l10n` 读取 `AppLocalizations`；`zeta_ui` 控件自有文案走注入的 `ZetaUiTextCatalog`。application /
  data / reducer 只注入该 feature 的不可变文本目录 port
  （`AgentUiTextCatalog`、`AgentManagementTextCatalog`、
  `UsageStatisticsTextCatalog`、`DesktopAttentionTextCatalog`），禁止下沉
  Flutter `Locale`、`BuildContext` 或 generated l10n。
- 英文 ARB 是 key / description / placeholder 的模板唯一依据；`app_en.arb` 与
  `app_zh.arb` 必须一一对应。当前禁用 plural / date / number formatter；日期、
  数字、百分比和相对时间继续用语言无关算法，目录只翻译外围静态 token。
  `Agent` / `Provider` / `Thread` / `Token` 等产品术语保持英文。
- `shadcn_flutter` 上游只有英语资源。Zeta 自有 `ZetaShadcnLocalizations` 覆盖
  `en` / `zh-Hans`，把公开抽象 API 接到同一批 ARB；参数化日期/数字格式保持
  现有算法。升级该包前必须重跑适配器契约测试。
- 新增用户可见 Zeta 文案不得写成生产字面量。提交前运行
  `dart run tool/check_localized_ui_strings.dart --check`；品牌、产品术语、
  Provider/user/raw、协议 key 与日志由扫描器跳过，allowlist 不得再登记新的
  zeta_copy 债务。Provider 返回值、用户输入、路径、命令和模型名保持原文。

### 控件尺寸与视觉约束

- 禁止在 feature 中使用裸 `Color(0x...)`、手写 `BoxShadow`、`BorderRadius.circular` 或 Material ThemeData。通知统一 `showIdeToast`。
- Select、Tabs、Button、TextField 的高度由 `controlPaddingYFor`、内容和 `controlMinHeightFor` 决定，不外套固定 height/maxHeight。`controlNaturalHeightFor` 仅用于断言与占位。
- 控件图标使用 `IdeIconBox`。标题栏、列表行、工具栏等容器使用 token 的 minHeight，且不得低于内部控件自然高度。
- feature 使用 Ide 封装，不直接新建 `sf.Button` / `sf.IconButton` / `sf.TextField` / `sf.Select`。缺少封装时先补公共组件；必要例外在调用点说明并对齐 IdeMetrics。
- 新 ARB key 同步中英文、description 和 String placeholder，不使用 plural/date/number formatter。用户文档按[文档维护](../development/documentation.md)写日常语言，不机械保留开发术语。

## 7. 文件系统与工作区

- 文件树保持懒加载：打开项目只读顶层，展开目录再读下一层。
- 不递归扫描整个项目，不跟随符号链接。
- `.git`、`.dart_tool`、`.idea`、`.vscode`、`build`、`node_modules` 等大目录或工具缓存目录应继续忽略。
- 目录排序保持目录优先，并按大小写无关名称排序。
- 文件系统读取失败应记录日志并给 UI 留出降级状态，不能让异常直接冒泡导致崩溃。

## 8. 测试与评审重点

新增或修改代码时，测试层级应贴近风险点：

- domain 模型、codec、mapper 和 JSON 宽容解析用单元测试。
- application controller 的分页、恢复、竞态和错误路径用单元测试。
- 包含多字段配置的 application controller 必须覆盖快速连续更新、过期请求、
  确认态回滚、完整快照重试与损坏持久化输入。
- provider datasource 和 transport 用 fake process、fake storage 或 callback 注入。
- pane、timeline、file tree 等用户可见行为用 widget test。
- resize 相关测试至少覆盖外窗 1197/1196/1195px（`wideBreakpoint` + 工作台左右
  `space8` ± 1）、Agent Canvas 641/640/639px、隐藏
  retained page 的 build/layout 增量、viewport item 构建上界、缓存命中和 transient
  callback 不增长。
- 主要页面切换必须使用实际 `IdeHome` 做集成级 Widget 测试。Agent → Settings → Agent
  与 Agent → Usage → Agent 至少验证常驻骨架、AgentPane Element、当前 Thread、草稿、
  非零滚动位置、Pane 宽度和 Pane 可见状态保持。
- 简单视觉调整可以只运行分析和相关 widget test，但行为变化必须补测试。
- 外部 CLI 的自动化测试不能替代真实平台验收。Beta provider 发布前使用脱敏 smoke，分别
  记录 OS/架构、CLI 版本、Schema/包装器类型和结果；没有设备或凭据时必须标记“待执行/阻塞”，
  不得推断通过。真实 smoke 使用临时 workspace、最小权限和非破坏性 prompt。
- smoke 记录不得包含 Prompt、回复、文件内容、凭证、原始协议 payload、thread/turn id 或
  stderr 原文；实验协议缺少预期事件时必须记录实际差异并返回失败，不能用 stable Schema
  或 fake peer 结果替代。
- Windows resize 性能改动必须用 `flutter run -d windows --profile` 采样，不得以
  Debug、估算或主观手感代替。固定场景记录 UI/Raster p95 与慢帧率；如未达 16.7ms /
  5%，只能在同构基线和结构计数均满足时引用相对改善，缺失基线不得补值。

### 8.1 测试选择与分片

CI 必须覆盖全部分片与内部包；本地按改动风险选测试。

开发循环的默认档是 `bash tool/test_affected.sh`：从 git 变更集出发，沿 import 图
做反向闭包算出受影响的测试，再追加架构守卫。选择逻辑在 `tool/test_select.dart`，
设计上只允许一个方向的误差——**宁可多选，不可漏选**：

- 基础配置文件（`pubspec.yaml`、`dart_test.yaml`、`analysis_options.yaml`、
  `.github/workflows/`、选择器自身）变更直接退化成全量；
- 内部 Package 的 barrel `export` 会把整包展开，改 `zeta_agent_core` 一个文件就
  拉起全部依赖方，这是保守但正确的行为；
- 架构守卫（`test/src/architecture/`，以及改 Agent 代码时的
  `test/src/features/agent/architecture/`）扫全树而不走 import 依赖，import 图
  看不见它们与改动的关系，所以无条件追加；
- import 指令用行扫描而不是 analyzer AST：注释掉的 import 只会让结果**多选**，
  方向安全，而整图解析保持在百毫秒级。

根 `test/` 按 `tool/test_shards.dart` 切成 6 片，CI 每片一个并行 Job，
`fail-fast: false`。分片按语义分组而不是贪心装箱，且清单按目录前缀匹配——新增
测试落进已有目录自动归片。

两条硬性约束：

- **CI 必须跑满全部分片 + `tool/test_packages.sh`。** 分片是并行手段，不是取样
  手段；任何"只在 CI 跑受影响分片"的提议都是把门禁降级。
- **重构必须跑完整门禁。** 重构会搬文件、改 import，import 图本身失真，而
  重构必须保持业务断言不变，并通过完整门禁。

`test/src/architecture/test_shard_coverage_guard_test.dart` 守住这套结构：每个测试
文件恰好属于一片、清单路径真实存在、CI 矩阵与清单一致。新增测试必须恰好属于一个分片，避免遗漏。

评审时优先检查依赖方向、协议泄漏、异步竞态、持久化兼容性、文件系统性能和 UI 溢出风险。
