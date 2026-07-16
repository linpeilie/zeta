# Zeta Grok 集成详细设计规格书

> 文档简称：Zeta Grok 集成详设书  
> 文档状态：设计草案，待架构评审  
> 目标读者：Zeta 架构师、Agent 数据层开发者、Flutter 客户端开发者、测试与发布负责人  
> 设计基线：Zeta 当前工作区与 grok-build 提交 b189869b7755d2b482969acf6c92da3ecfeffd36  
> 目标平台：Windows、macOS、Linux

## 目录

- [1. 文档信息](#1-文档信息)
- [2. 概述与目标](#2-概述与目标)
- [3. 当前状态分析](#3-当前状态分析)
- [4. 架构原则与设计决策](#4-架构原则与设计决策)
- [5. 高价值能力补齐清单](#5-高价值能力补齐清单)
- [6. 详细设计](#6-详细设计)
- [7. 实施路线图](#7-实施路线图)
- [8. 不建议事项与风险规避](#8-不建议事项与风险规避)
- [9. 接口与数据结构定义](#9-接口与数据结构定义)
- [10. 附录](#10-附录)

---

## 1. 文档信息

### 1.1 基本信息

| 项目 | 内容 |
| --- | --- |
| 文档标题 | Zeta Grok 集成详细设计规格书 |
| 文档版本 | V1.0-draft |
| 编制日期 | 2026-07-16 |
| 作者 | Codex（架构分析草案） |
| 审批人 | 待定 |
| 所属项目 | Zeta |
| 关联组件 | Agent、Project Threads、Workspace、Agent Management |
| 参考实现 | grok-build |
| grok-build 快照 | commit b189869b7755d2b482969acf6c92da3ecfeffd36；关键 crate 版本 0.1.220-alpha.4 |
| 设计目标版本 | 待产品与发布计划确认 |

### 1.2 修订历史

| 版本 | 日期 | 修订人 | 修订内容 | 状态 |
| --- | --- | --- | --- | --- |
| V1.0-draft | 2026-07-16 | Codex | 基于 Zeta 与 grok-build 源码对照形成首次完整详设 | 待评审 |

### 1.3 术语与缩写

| 术语 | 说明 |
| --- | --- |
| ACP | Agent Client Protocol，Agent 客户端与 Agent 进程之间的标准协议 |
| Grok Extension | grok-build 在标准 ACP 之外提供的 x.ai/* 扩展协议 |
| Provider | Zeta 对 Codex、Grok、Cursor 等 Agent 后端的中立抽象 |
| Capability | Provider、CLI 版本或当前会话实际支持的能力 |
| Replay | 从持久化历史或事件流重新构建会话状态 |
| Event Cursor | 用于断线续传、增量读取和事件去重的稳定游标 |
| Workspace Backend | Zeta 对本地或远程文件、搜索、Git 等工作区操作的中立抽象 |
| Tool Call | Agent 发起的文件、命令、搜索、MCP 等工具调用 |
| JSONL | 每行一个 JSON 对象的追加式存储格式 |
| TUI | Terminal User Interface，终端用户界面 |

### 1.4 文档约束

1. 本文以当前 grok-build 源码为参考，不假设用户安装的 Grok CLI 一定与源码提交完全一致。
2. 所有 x.ai/* 能力必须经过运行时协商或安全探测，不能只依赖编译期常量或版本字符串。
3. 本文定义的是 Zeta 客户端集成架构，不改变 Grok、Codex、Cursor 自有配置和历史文件。
4. 代码示例为设计伪代码，最终命名可在实现评审中调整，但分层边界和降级语义不得弱化。

---

## 2. 概述与目标

### 2.1 项目背景

grok-build 已公开 Grok 编码 Agent 的主要运行时实现，包括：

- Grok Agent TUI 与 headless/stdio 入口；
- 标准 ACP 生命周期；
- x.ai/* 会话、工作区、Git、终端、搜索和扩展通知；
- 会话持久化、回放、压缩与 rewind；
- 类型化工具运行时；
- 权限规则、能力模式和沙箱协作；
- Skills、Plugins、Hooks、MCP、子 Agent 与后台任务。

从代码边界看，grok-build 更接近“Grok 编码 Agent 运行时与参考客户端”，而不是适合直接移植到 Flutter 的桌面编辑器 UI。对 Zeta 最有价值的部分是其公开协议、领域划分、状态管理和恢复机制。

Zeta 当前已经通过 Grok ACP stdio 完成基本接入。后续工作不是重新接入 Grok，而是将现有实现从：

> 标准 ACP 主链路 + Grok 私有本地历史兼容

升级为：

> 标准 ACP + 类型化 Grok 扩展适配 + 动态能力协商 + 协议化历史恢复

最终使 Zeta 从“基础 ACP 客户端”演进为“充分理解 Grok 扩展能力的通用 Agent IDE”。

### 2.2 设计目标

#### 2.2.1 Grok 集成目标

1. 完整利用 grok-build 已公开且适合 IDE 的会话扩展能力。
2. 将会话列表和历史读取从私有磁盘结构迁移到协议优先。
3. 补齐会话重命名、删除、派生、压缩和 rewind 等操作。
4. 映射 Grok 的高价值扩展事件，改善长任务、Diff、模型变化和后台任务体验。
5. 使用 ACP 原生内容块发送图片，不再将图片仅编码为路径文本。
6. 根据实际 CLI 版本和会话响应动态呈现能力，避免无效按钮和静默 no-op。

#### 2.2.2 通用 Agent IDE 目标

1. 保持 UI、应用层和领域层不依赖 x.ai/* 私有字段。
2. 建立可复用于 Codex、Cursor 和未来 Provider 的动态能力机制。
3. 建立本地/远程统一的 Workspace Backend 抽象。
4. 增强工具调用模型，使其支持类型化内容、增量进度和唯一终态。
5. 建立 Provider 中立的权限选择模型，并区分审批策略、执行模式与 OS 沙箱。
6. 为断线恢复、多窗口和远程 Agent 预留事件游标与追加式缓存能力。

### 2.3 核心价值

| 价值 | 说明 |
| --- | --- |
| 稳定性 | 减少对 ~/.grok/sessions 私有格式的主路径依赖 |
| 完整性 | 展示 Grok 已提供但当前被丢弃的会话和任务状态 |
| 兼容性 | 老版本 CLI 继续通过 session/load 或本地只读历史降级 |
| 可扩展性 | x.ai/* 被隔离在数据层，不污染通用 UI |
| 可诊断性 | 能区分不支持、版本不匹配、协议损坏和传输失败 |
| 远程就绪 | 会话、历史和工作区不再天然绑定当前机器文件系统 |
| 多 Provider 一致性 | 能力、权限、工具、事件采用统一领域语义 |

### 2.4 非目标

本设计明确不包含以下工作：

1. 不移植 grok-build 的 Rust TUI、主题或终端 Markdown 渲染器。
2. 不把 grok-build 通过 Rust FFI 或动态库嵌入 Flutter 进程。
3. 不在 Zeta 中重新实现 Grok 的模型执行、记忆检索、Sandbox 或 Hooks 引擎。
4. 不修改、迁移或重写 ~/.grok、~/.codex、~/.cursor 下的配置和历史。
5. 不让 presentation 层直接识别 x.ai/* 方法名或 Grok 原始 JSON。
6. 不为旧版本 Grok CLI 伪造不存在的扩展能力。
7. 不把 Grok 专有能力强行定义为所有 Provider 必须实现的接口。
8. 不直接复用 grok-build 的代码图实现作为 Dart/Flutter 索引器；当前实现不覆盖 Dart。
9. 首批实施不引入 Grok leader/WebSocket 共享进程，除非基础 stdio 方案已完成并验证。

### 2.5 成功判定

满足以下条件时，可认为本设计的核心目标完成：

- 新版本 Grok CLI 可通过协议列出、搜索、分页和恢复会话；
- 老版本 CLI 仍可安全降级到现有本地历史读取；
- UI 仅在能力确认支持时展示 rename、delete、fork、compact、rewind 等操作；
- 扩展事件不会丢失关键状态，未知事件可诊断但不会导致会话失败；
- 图片通过 ACP ImageContent 发送，并正确处理压缩或丢弃通知；
- 断线或重复回放不会产生重复消息、重复工具终态或重复标题更新；
- Grok 私有 JSON 不越过 data mapper 进入 presentation；
- 所有新增行为具有单元测试，核心协议流程具有假 Agent 集成测试。

---

## 3. 当前状态分析

### 3.1 当前架构

~~~mermaid
flowchart TD
    UI["Flutter UI / ViewModel"] --> Provider["AgentProvider 中立接口"]
    Provider --> Codex["CodexAppServerAgentProvider"]
    Provider --> Grok["GrokAcpAgentProvider"]
    Provider --> Cursor["CursorAcpAgentProvider"]
    Grok --> Mapper["ACP / Grok Notification Mapper"]
    Grok --> Transport["JsonRpcStdioTransport"]
    Transport --> CLI["grok agent stdio"]
    Grok --> LocalHistory["GrokSessionHistoryReader"]
    LocalHistory --> Disk["~/.grok/sessions JSONL"]
~~~

现有分层方向正确：UI 依赖中立 AgentProvider，Grok 的进程启动、ACP 传输、通知映射和本地历史位于 data 层。

### 3.2 已完成的 Grok 接入能力

当前 Grok Provider 已实现以下能力：

| 分类 | 已有能力 | 主要位置 |
| --- | --- | --- |
| 进程 | 定位 Grok CLI，构造 agent stdio 参数并启动 | grok_process_starter.dart |
| 初始化 | ACP v1 initialize、客户端能力声明、认证 | grok_acp_agent_provider.dart |
| 会话 | session/new、session/load、session/prompt、session/cancel | grok_acp_agent_provider.dart |
| 模型 | 从 initialize/session/CLI 获取模型，调用 session/set_model | grok_acp_agent_provider.dart |
| 流式事件 | 消息、思考、工具、计划、用量、turn completed | acp_session_update_mapper.dart、grok_acp_notification_mapper.dart |
| 权限 | 处理 session/request_permission 和文件读取请求 | grok_acp_agent_provider.dart、acp_permission_mapper.dart |
| 历史 | 扫描 ~/.grok/sessions，解析 updates.jsonl 和 chat_history.jsonl | grok_session_history_reader.dart 及相关 parser |
| 标题 | 轮询 Grok 本地 summary 等待生成标题 | grok_session_history_reader.dart |
| 管理 | CLI 检测、版本、登录状态、配置、日志和模型探测 | grok_agent_management_repository.dart |
| UI 能力门控 | 通过 AgentProviderCapabilities 隐藏部分不支持操作 | agent_provider_capabilities.dart |

关键文件：

- lib/src/features/agent/data/datasources/acp/grok_acp_agent_provider.dart
- lib/src/features/agent/data/datasources/acp/grok_process_starter.dart
- lib/src/features/agent/data/mappers/acp_session_update_mapper.dart
- lib/src/features/agent/data/mappers/grok_acp_notification_mapper.dart
- lib/src/features/agent/data/datasources/local_history/grok_session_history_reader.dart
- lib/src/features/agent/domain/agent_provider.dart
- lib/src/features/agent/domain/agent_provider_capabilities.dart
- lib/src/features/agent/domain/agent_event_models.dart
- lib/src/features/agent/domain/agent_tool_models.dart
- lib/src/features/agent_management/data/grok_agent_management_repository.dart

### 3.3 现有架构优势

1. AgentProvider 已隔离 UI 与 Provider 协议，适合继续扩展。
2. JSON-RPC stdio 传输层已经可复用，不需要重新建设传输协议。
3. ACP 标准通知已经集中映射，Grok 与 Cursor 可共享标准部分。
4. 领域层已有 AgentTurnDiffEvent、AgentThreadNameUpdatedEvent、AgentThreadStatusChangedEvent 等可复用事件。
5. AgentToolCall 已具备中立类型、生命周期状态和原始输入输出。
6. Project Threads 已根据 capability 对部分操作进行门控。
7. Provider 配置、管理、时间线和权限已经按 feature 划分，符合当前项目架构规范。
8. Grok 本地历史读取可作为旧 CLI 和协议异常时的兼容降级方案。

### 3.4 现有局限

#### 3.4.1 私有磁盘格式仍是主要历史来源

当前 Grok 会话列表和历史依赖 ~/.grok/sessions 的目录编码、summary.json、updates.jsonl 和 chat_history.jsonl。该方案存在以下问题：

- 私有格式可能随 CLI 版本调整；
- 无法天然支持远程 Agent 或 relay；
- 客户端需要维护多套解析器和损坏容错；
- 标题必须通过磁盘轮询获取；
- rewind、压缩和事件分支过滤容易与 Agent 权威状态不一致。

#### 3.4.2 x.ai 扩展事件大量丢失

当前 Grok mapper 仅对 x.ai/session/update 中的 turn_completed 做补充映射。Diff Review、Retry、自动压缩、模型变化、标题、子 Agent、后台任务、Goal 和待交互状态均未进入领域层。

#### 3.4.3 会话管理能力被静态判定为不支持

当前 Grok capability 对 rename、delete、fork、rollback、compact、steer 等能力返回 false，但 grok-build 已实现其中多数 x.ai 扩展方法。静态能力无法处理不同 Grok CLI 版本之间的差异。

#### 3.4.4 图片未使用标准内容块

grok-build 的 ACP prompt 支持 ImageContent。Zeta 当前 Grok 路径仍将本地图片表示为文本路径，导致 Agent 不能稳定获得图片二进制内容，也无法准确处理图片压缩、大小限制和丢弃状态。

#### 3.4.5 权限选择没有完整下发

Zeta 已有 approvalPolicy、sandboxPolicy、permissionProfileId，但 Grok Provider 当前忽略部分 permission selection。Grok 的 Default、Accept Edits、Plan、Auto、Don't Ask、Bypass 等执行模式与 OS 沙箱也尚未形成清晰映射。

#### 3.4.6 远程和重连能力不足

当前实现以单个 stdio 子进程和单个活动会话为中心，没有稳定事件游标、自动重连和跨进程回放。对于长任务、多窗口或未来 WebSocket relay，可能出现状态丢失或重复。

#### 3.4.7 工作区仍主要是本地目录视图

当前 Workspace feature 通过 Dart 本地 Directory 构建文件树，尚未抽象本地/远程 Workspace Backend。即使 Grok Agent 可以提供远程 fs/git/search，UI 也没有统一消费边界。

---

## 4. 架构原则与设计决策

### 4.1 决策总览

| 决策编号 | 决策 | 结论 |
| --- | --- | --- |
| ADR-GROK-001 | Grok 集成边界 | 继续使用外部 CLI + ACP，不嵌入 Rust |
| ADR-GROK-002 | 历史权威来源 | 协议优先，session/load 次之，本地磁盘只读降级 |
| ADR-GROK-003 | 扩展协议位置 | x.ai/* 仅存在于 Grok data adapter |
| ADR-GROK-004 | 能力表达 | 内部使用三态能力，领域/UI 只暴露已确认支持能力 |
| ADR-GROK-005 | 事件模型 | Provider 原始事件必须映射到中立 AgentEvent |
| ADR-GROK-006 | 权限 | 审批、执行模式、规则和 OS 沙箱分层表达 |
| ADR-GROK-007 | 工作区 | 通过 WorkspaceBackend 统一本地与远程 |
| ADR-GROK-008 | 工具生命周期 | 进度可多次，终态必须唯一且不可回退 |
| ADR-GROK-009 | 客户端缓存 | 只写 ~/.zeta，采用版本化追加式事件结构 |
| ADR-GROK-010 | 兼容策略 | 未知字段宽容读取，未知方法显式降级，危险操作不自动重试 |

### 4.2 协议优先、磁盘降级

会话读取顺序固定为：

~~~text
x.ai/session/list、x.ai/session/updates
              ↓ 方法不支持或版本不兼容
标准 ACP session/load replay
              ↓ 无回放或回放损坏
~/.grok/sessions 只读解析
              ↓ 仍失败
返回可诊断错误，不伪造空会话
~~~

约束：

1. 协议返回的数据为当前 Agent 的权威结果。
2. 本地历史 reader 不得覆盖协议中更新的标题、状态或模型。
3. 只有明确的 method-not-found、能力不支持或协议不可用才进入下一层降级。
4. 认证失败、权限失败和数据损坏必须向上返回对应错误，不能误判为“不支持”。
5. 本地历史继续保持只读，不创建、不删除、不重写 Grok 文件。

### 4.3 中立 Provider 接口与扩展机制

x.ai/* 不直接加入 AgentProvider 的必选方法。采用“通用能力进入中立接口，Provider 私有协议留在适配器”的策略：

- rename/delete/fork/compact/rollback 已有或具有明确通用语义：映射到 AgentProvider。
- session updates、模型变化、Diff、后台任务：映射为 AgentEvent。
- Grok 专属但暂时没有通用 UI 的元数据：留在 data 层 raw/diagnostics。
- 未来被两个以上 Provider 支持且语义稳定的能力，再提升为可选领域接口。

建议新增 GrokExtensionClient 作为 grok_acp_agent_provider.dart 的内部依赖，禁止 ViewModel 和 Widget 直接调用该客户端。

### 4.4 动态能力协商

动态能力由四层合成：

~~~mermaid
flowchart LR
    Static["标准 ACP 静态基线"] --> Merge["能力合成器"]
    Init["initialize / session payload"] --> Merge
    Version["CLI 版本兼容规则"] --> Merge
    Probe["方法懒探测结果"] --> Merge
    Merge --> Snapshot["AgentProviderCapabilities 快照"]
    Snapshot --> UI["Controller / UI capability gate"]
~~~

内部能力状态采用：

- unknown：尚未确认，UI 按不支持处理；
- supported：已由响应、版本证据或成功调用确认；
- unsupported：明确未声明或返回 method-not-found；
- temporarilyUnavailable：传输或认证暂时失败，不永久缓存为不支持。

规则：

1. 成功调用的证据高于版本表。
2. method-not-found 可将单项能力标记为 unsupported。
3. 超时、进程退出和认证错误不能将能力永久降级。
4. CLI 路径、版本或 agentVersion 变化时清空探测缓存。
5. 危险或有副作用的方法不得仅为探测而调用；应在用户真实操作时懒确认。

### 4.5 分层权限模型

权限至少分为四层：

| 层 | 作用 | 示例 |
| --- | --- | --- |
| 交互审批策略 | 是否向用户询问 | on-request、never |
| Agent 执行模式 | Agent 可主动执行到什么程度 | Plan、Accept Edits、Auto、Bypass |
| 工具规则 | 对命令、路径、MCP、网络的 allow/ask/deny | deny 优先于 ask，ask 优先于 allow |
| OS 沙箱 | 进程最终可访问的资源 | readOnly、workspaceWrite、dangerFullAccess |

架构要求：

- 不能将“不询问”自动等价为“绕过沙箱”。
- UI 必须区分“请求的模式”和“Agent 实际生效的模式”。
- Bypass/dangerFullAccess 必须由用户显式选择，不能因兼容回退而自动升级。
- Provider 不支持某一层时，必须显示降级说明，不得静默忽略。

### 4.6 本地/远程统一的 Workspace Backend

Workspace UI 只依赖中立 WorkspaceBackend。后端可为：

- LocalWorkspaceBackend：Dart dart:io、本地 Git/搜索；
- GrokWorkspaceBackend：x.ai/fs、git、search、code navigation 等代理操作；
- 未来 Codex 或其他远程后端。

WorkspaceBackend 必须声明 capability，文件写入、命令和 Git 修改仍需通过权限系统。首期只设计抽象，不要求立即替换现有文件树。

### 4.7 类型化、可流式的工具模型

借鉴 grok-build Tool runtime 的生命周期约束：

~~~text
零到多条 progress
        ↓
恰好一个 completed / failed / cancelled
        ↓
后续迟到 progress 被忽略并记录诊断
~~~

工具模型区分：

- 输入参数 rawInput；
- 面向模型/协议的结构化输出；
- 面向 UI 的内容块；
- 进度消息；
- 终态结果；
- 图片、文本、资源引用等富内容。

为控制改造风险，现有 AgentToolCall 继续作为 UI read model，新类型先在 mapper 和 timeline store 内部逐步接入。

### 4.8 追加式事件历史

Zeta 若建立自己的会话缓存，应遵循：

1. 原始事件追加，不原地重写历史；
2. 摘要和会话列表是可重建的派生索引；
3. 使用 schemaVersion；
4. 使用 providerId + sessionId + eventId 作为去重边界；
5. rewind 通过 marker/branch 表达，不删除旧事件；
6. compaction checkpoint 与原始事件分离；
7. 所有 Zeta 自有文件仅写入 ~/.zeta。

首期可只在内存实现事件合并和游标；持久化缓存应在协议链路稳定后单独实施。

### 4.9 进程隔离与生命周期

保留 grok agent stdio 子进程边界：

- CLI 更新不需要重新编译 Flutter；
- 崩溃与内存隔离更清晰；
- stderr 可独立采集；
- 不引入 Rust FFI 的构建和 ABI 风险。

Leader/WebSocket 模式仅作为后续选项，用于多窗口、远程或长任务重连，不作为首期依赖。

### 4.10 宽容读取、严格写入

- 对响应新增未知字段保持兼容；
- 对缺少关键 id、cursor、sessionId 的数据返回可诊断解析错误；
- 对写请求只发送当前版本明确支持的字段；
- 不声称 Zeta 具备未实现的 fs write、terminal、code navigation 或 MCP Apps 能力；
- 变更型请求不因网络超时盲目自动重试。

### 4.11 单写者状态与不可变快照

借鉴 grok-build ChatStateActor 的串行状态变更思想，Zeta 中同一会话的状态更新必须经由单一应用层入口：

- Provider notification 只产生领域事件，不直接修改 Widget 或多个 Controller；
- AgentConversationTimelineStore 作为时间线聚合的单写者；
- ProjectThreadsController 作为项目会话列表的单写者；
- UI 只消费不可变快照；
- history/replay、live notification、用户操作通过命令或事件排队合并；
- 可被后续请求取代的异步加载继续使用 token/version guard；
- Controller dispose 后不再发布通知。

该原则用于避免 session/load、历史分页、实时通知和 rename/delete 同时发生时出现竞态。它不是要求引入新的第三方状态管理库，现有 ChangeNotifier、ValueNotifier 和应用层 Controller 足以实现。

### 4.12 Agent Profile 与扩展目录分离

grok-build 将 Agent definition、Skills、Plugins、Hooks、MCP 和工具配置分开。Zeta 应保持相同的职责分离：

- Agent Profile：模型、提示词、允许工具、权限模式和完成约束的可选配置视图；
- Skills：供 Agent 加载的知识/流程包；
- Plugins：可能聚合 Skills、Commands、Agents、Hooks 和 MCP；
- Hooks：Agent 生命周期中的受控执行点；
- MCP：外部工具与应用连接。

首期只消费 initialize、availableCommands 和 Provider 提供的只读目录信息，不在 Zeta 内重新执行 Grok Plugin/Hook。未知 profile 字段宽容保留在 data 层；只有跨 Provider 语义稳定的字段才进入领域模型。

---

## 5. 高价值能力补齐清单

优先级定义：

- P0：直接影响当前 Grok 集成正确性或稳定性；
- P1：显著提升完整性和可用性；
- P2：通用 Agent IDE 架构增强；
- P3：远期或需更多产品设计。

| 能力 | Zeta 当前状态 | grok-build 已公开能力 | 建议实现方案 | 优先级 |
| --- | --- | --- | --- | --- |
| 会话列表 | 扫描 ~/.grok/sessions | x.ai/session/list，支持 cwd、query、limit、cursor、facets、partial | GrokExtensionClient 协议优先；本地 reader 降级 | P0 |
| 会话历史 | 解析 updates/chat_history JSONL | x.ai/session/updates，支持 offset、limit、tail、turnIndex、stream、chunk | 建立分页历史读取器与事件游标 | P0 |
| session/load replay | 恢复时抑制回放并依赖本地历史 | 标准 ACP load session 与回放 | 作为 updates 不支持时的第二级来源 | P0 |
| 动态 capability | Grok capability 静态常量 | initialize meta、agentVersion、方法实际响应 | 三态能力注册表 + 可观察快照 | P0 |
| 标题更新 | 轮询本地 summary | SessionSummaryGenerated | 映射为 AgentThreadNameUpdatedEvent，磁盘轮询仅降级 | P0 |
| 模型变化 | 初始化和主动 set_model 可见，被动变化不足 | ModelChanged、ModelAutoSwitched | 更新 session config；产生中立模型变化事件 | P0 |
| Diff Review | x.ai 事件被忽略 | DiffReview | 映射到现有 AgentTurnDiffEvent；保留 review 状态 | P0 |
| Retry 状态 | 缺少清晰反馈 | RetryState | 新增 AgentRetryStateChangedEvent | P1 |
| 自动压缩 | 仅能表达最终 compact 或完全不可见 | AutoCompactStarted/Completed/Failed/Cancelled | 新增压缩状态事件，完成时复用 AgentThreadCompactedEvent | P1 |
| rename | Grok 标记不支持 | x.ai/session/rename | 调用扩展、更新列表缓存、发名称事件 | P0 |
| delete | Grok 标记不支持 | x.ai/session/delete | 用户确认后调用；成功后移除快照与缓存 | P0 |
| fork | Grok 标记不支持 | x.ai/session/fork | 映射 sourceSessionId/sourceCwd/newCwd/targetPromptIndex | P1 |
| compact | Grok 标记不支持 | x.ai/compact_conversation | 映射 AgentProvider.compactThread，显示进度 | P1 |
| rewind/rollback | Grok 标记不支持 | x.ai/rewind/points、x.ai/rewind/execute | 先列点再执行；支持 force/mode 的受控映射 | P1 |
| 图片输入 | 本地路径文本 | ACP ImageContent；图片压缩/丢弃事件 | base64 + MIME 内容块，能力门控和大小提示 | P0 |
| Pending Interaction | 缺少 Grok 专属等待状态 | PendingInteraction、InteractionResolved | 映射 AgentThreadStatusChangedEvent | P1 |
| 子 Agent | 未显示 | SubagentSpawned/Progress/Finished | 新增中立子任务事件和折叠式时间线 | P2 |
| 后台任务 | 未显示 | TaskBackgrounded、TaskCompleted、MonitorEvent | 新增中立后台任务状态 | P2 |
| Goal | 未显示 | GoalUpdated | 映射为中立 Goal/Plan 状态 | P2 |
| Hooks/Plugins | 扩展通知被忽略 | HookAnnotation、HookExecution、HooksChanged、PluginsChanged | 首期只诊断；后续映射状态和管理页 | P3 |
| 图片处理通知 | 未显示 | ImageCompressed、ImageDropped | 转换为非阻断提示或 warning event | P1 |
| 用量完整性 | 标准 token usage | PromptUsage、cost tick、incomplete 语义 | 扩展 AgentTokenUsage；不估算缺失成本 | P1 |
| 会话搜索 | 仅本地过滤 | x.ai/session/search/list query | 服务端搜索优先，UI 保持现有搜索交互 | P1 |
| MCP 运行态 | 主要依赖本地配置/初始化信息 | MCP servers/apps 与 session update_mcp_servers | 首期只读展示；写入必须单独评审 | P2 |
| 工作区文件 | 本地 Directory | x.ai/fs、fs notify、delta | WorkspaceBackend 后引入 Grok 远程实现 | P2 |
| Git/worktree/hunk | 尚无正式 feature | x.ai/git、worktree、hunk tracker | 先领域抽象，再构建 UI；不直连 presentation | P2 |
| 搜索/code navigation | 本地能力有限 | x.ai/search、code navigation | capability-gated WorkspaceBackend | P3 |
| 断线恢复 | stdio 进程关闭即丢连接 | eventId、isReplay、session updates、leader | 先游标去重，后评估 leader/WebSocket | P2/P3 |
| Session mode | 权限选择未完整映射 | session/set_mode、yolo/auto mode 元数据 | 复用 AgentSessionConfigOption 和权限选择 | P1 |
| 初始化元数据 | 仅基础 clientInfo/capabilities | clientIdentifier、clientType、buffering、interactive trust 等 | 只发送 Zeta 实际支持且有价值的字段 | P1 |
| Session config/mode 更新 | 标准 mapper 当前忽略 available_commands/current_mode/config_option/session_info 更新 | ACP session configuration 与 Grok mode 更新 | 写入 AgentSessionConfigOption 和有效配置状态 | P1 |
| Active turn steer | Grok Provider 明确不支持 | 本次分析未确认稳定、可依赖的 Grok steer 扩展 | 继续隐藏；只有协议明确发布后再能力化 | P3 |
| archive/unarchive | Grok Provider 明确不支持 | 已分析扩展未提供等价的稳定归档语义 | 不用 kind、delete 或本地索引伪造归档 | P3 |
| Session recap | 未映射 | initialize meta 和扩展更新包含 recap 能力 | 先映射为可选系统摘要，不影响权威历史 | P2 |

---

## 6. 详细设计

### 6.1 目标架构

~~~mermaid
flowchart TB
    Presentation["Agent / Project Threads / Workspace UI"]
    Application["Controllers / Timeline Store / Session Coordinator"]
    Domain["AgentProvider + AgentEvent + Capabilities + WorkspaceBackend"]

    subgraph Data["Data Layer"]
        GrokProvider["GrokAcpAgentProvider"]
        ExtClient["GrokExtensionClient"]
        StandardMapper["AcpSessionUpdateMapper"]
        GrokMapper["GrokAcpNotificationMapper"]
        CapabilityResolver["GrokCapabilityResolver"]
        HistorySource["GrokSessionHistorySource"]
        LocalFallback["GrokSessionHistoryReader"]
        Transport["JsonRpcStdioTransport"]
    end

    CLI["grok agent stdio"]
    Disk["~/.grok/sessions 只读"]
    ZetaCache["~/.zeta 可选事件缓存"]

    Presentation --> Application --> Domain
    Domain --> GrokProvider
    GrokProvider --> ExtClient
    GrokProvider --> StandardMapper
    GrokProvider --> GrokMapper
    GrokProvider --> CapabilityResolver
    GrokProvider --> HistorySource
    ExtClient --> Transport
    GrokProvider --> Transport
    Transport --> CLI
    HistorySource --> ExtClient
    HistorySource --> LocalFallback
    LocalFallback --> Disk
    Application -.可选.-> ZetaCache
~~~

### 6.2 GrokExtensionClient

#### 6.2.1 职责

GrokExtensionClient 是 x.ai/* 的唯一调用入口，负责：

1. 方法名与请求字段编码；
2. 响应解码和宽容字段处理；
3. JSON-RPC 错误分类；
4. method-not-found 到 capability 的反馈；
5. 查询类请求的超时和取消；
6. 对变更型请求禁止不安全自动重试；
7. 原始协议日志脱敏。

它不负责：

- UI 状态；
- 会话列表合并策略；
- AgentEvent 渲染；
- 本地磁盘解析；
- 用户确认弹窗。

#### 6.2.2 建议文件

新增：

- lib/src/features/agent/data/datasources/acp/grok_extension_client.dart
- lib/src/features/agent/data/datasources/acp/grok_extension_models.dart
- lib/src/features/agent/data/datasources/acp/grok_capability_resolver.dart
- lib/src/features/agent/data/datasources/acp/grok_session_history_source.dart

修改：

- lib/src/features/agent/data/datasources/acp/grok_acp_agent_provider.dart
- lib/src/features/agent/data/default_agent_provider_factory.dart

#### 6.2.3 方法范围

首批客户端方法：

| 方法 | 类型 | 幂等性与重试 |
| --- | --- | --- |
| x.ai/session/list | 查询 | 可在重连后重试一次 |
| x.ai/session/updates | 查询/流式 | 可按 cursor 续传 |
| x.ai/session/rename | 变更 | 不因超时自动重试；刷新确认结果 |
| x.ai/session/delete | 破坏性变更 | 绝不自动重试 |
| x.ai/session/fork | 变更 | 使用客户端生成 newSessionId 时才可受控重试 |
| x.ai/compact_conversation | 长变更 | 不自动重复触发 |
| x.ai/rewind/points | 查询 | 可重试 |
| x.ai/rewind/execute | 破坏性变更 | 用户确认后执行，不自动重试 |

#### 6.2.4 错误模型

错误必须归一化为：

- unsupported：明确 method-not-found；
- invalidRequest：客户端编码错误；
- invalidResponse：响应缺少关键字段或类型错误；
- authenticationRequired：未认证或 token 失效；
- permissionDenied：Agent/系统拒绝；
- transportUnavailable：进程退出、管道关闭、网络失败；
- timeout：本次调用超时；
- conflict：会话状态不允许当前操作；
- unknown：保留 provider code 和脱敏 details。

只有 unsupported 可以持久影响 capability。transportUnavailable 和 timeout 只能影响当前运行态。

### 6.3 初始化与会话创建元数据

#### 6.3.1 initialize

保留当前标准字段，并在确认 grok-build 支持后增加：

- clientIdentifier: zeta；
- clientVersion；
- clientType: generic 或约定的 Zeta 标识；
- bufferingSettings：仅在 Flutter 流式渲染确有批处理策略时发送；
- interactive trust：仅表达实际交互能力；
- codeNavEnabled、mcpApps：默认不声明，直到 Zeta 真正实现。

禁止虚假声明 fs write、terminal、code navigation 等能力。initialize 响应中的 modelState、agentVersion、availableCommands、session capabilities 和 MCP 信息进入 data 层状态，不直接透传 UI。

认证继续沿用当前 initialize 后优先 cached_token 的 best-effort 流程。除非 Grok 扩展明确要求，不新增 Zeta 自有 token 存储；认证错误与“不支持扩展方法”必须严格区分。

#### 6.3.2 session/new

在 CLI 版本支持时优先通过 session/new._meta 下发：

- clientIdentifier；
- modelId；
- sessionId（仅需要客户端稳定生成时）；
- yoloMode/autoMode 或等价执行模式。

模型在 session/new 时确定，可减少“先创建默认模型，再 set_model”的短暂竞态。若版本不支持，继续使用现有 session/set_model。

Reasoning effort 应优先走 session 级配置，不应只依赖进程启动参数；进程参数仅作为旧版本兼容。

### 6.4 会话管理增强

#### 6.4.1 会话列表

GrokSessionHistorySource 负责选择数据源：

~~~mermaid
flowchart TD
    Request["listThreads(query, cursor, cwd)"] --> Capability{"session/list 已支持?"}
    Capability -->|是| Protocol["GrokExtensionClient.listSessions"]
    Capability -->|unknown| Probe["真实只读调用"]
    Probe -->|成功| Protocol
    Probe -->|method-not-found| Local["GrokSessionHistoryReader"]
    Capability -->|否| Local
    Protocol --> Map["映射 AgentThreadPage"]
    Local --> Map
    Map --> Return["返回 sessions + nextCursor + source"]
~~~

请求字段：

- cwd：当前工作区根目录；
- query：项目线程搜索词；
- limit：沿用当前 Project Threads 分页大小；
- cursor：保持 opaque，不解析、不拼接；
- _meta：只发送版本明确需要的字段。

响应处理：

1. sessions 映射为 AgentThreadSummary/AgentSession。
2. nextCursor 原样保存，禁止假设为数字 offset。
3. partial 为 true 时允许展示已返回结果，同时保留“结果可能不完整”的诊断状态。
4. facets 先保存在 data 层，只有产品需要筛选 UI 时再提升领域模型。
5. cwd 比较使用规范化绝对路径，但不能通过字符串替换推导 Grok 磁盘目录。

协议结果与本地结果不应默认无条件合并，避免重复和状态冲突。只有协议明确返回 partial 且产品确认需要时，才可按 sessionId 去重补充本地条目，并标记 source。

#### 6.4.2 rename

流程：

1. UI 根据 capability 展示入口。
2. Controller 校验非空标题并执行乐观状态或 loading 状态。
3. Provider 调用 x.ai/session/rename。
4. 成功后更新分页缓存并产生 AgentThreadNameUpdatedEvent。
5. 同时收到 SessionSummaryGenerated 时按 eventId/时间顺序去重。
6. 失败时恢复旧标题并展示明确错误。

#### 6.4.3 delete

删除必须二次确认。成功后：

- 从 Project Threads 状态移除；
- 清除 Zeta 自有会话快照和缓存；
- 若删除的是当前会话，关闭当前绑定并回到无会话状态；
- 不主动删除 ~/.grok 内任何文件，删除行为只通过 Grok 官方扩展执行。

#### 6.4.4 fork

请求映射包括：

- sourceSessionId；
- sourceCwd；
- newCwd；
- newSessionId；
- newModelId；
- targetPromptIndex；
- sessionKind/sourceWorkspaceDir（仅版本支持时）。

Zeta 应生成 newSessionId 以便失败后识别是否已创建成功。Fork 成功后新增线程，但不默认切换，是否切换沿用现有 Project Threads 交互。

#### 6.4.5 compact 与 rewind

Compact：

- 使用 x.ai/compact_conversation；
- userContext 仅在 UI 明确提供时发送；
- 映射开始、成功、失败和取消状态；
- 成功后保留原始事件和 checkpoint，不删除 UI 历史。

Rewind：

1. 先通过 x.ai/rewind/points 获取可回滚点；
2. UI 显示目标 prompt/turn；
3. 用户确认后调用 x.ai/rewind/execute；
4. 将后续旧事件标记为非活动分支，不在缓存中物理删除；
5. force 只能在普通执行被拒绝且用户二次确认后使用。

### 6.5 历史、分页、游标与回放

#### 6.5.1 数据源优先级

1. x.ai/session/updates；
2. ACP session/load replay collector；
3. GrokSessionHistoryReader；
4. 明确错误状态。

#### 6.5.2 并发与去重流程

~~~mermaid
sequenceDiagram
    participant UI as Project/Conversation UI
    participant Provider as GrokAcpAgentProvider
    participant Buffer as Replay Buffer
    participant Ext as GrokExtensionClient
    participant Grok as grok agent

    UI->>Provider: readThreadHistory(sessionId)
    Provider->>Buffer: 开启该 session 的 live 暂存
    Provider->>Ext: x.ai/session/updates(sessionId, cursor/limit)
    Ext->>Grok: JSON-RPC request
    Grok-->>Provider: live session/update
    Provider->>Buffer: 暂存 live envelope
    Grok-->>Ext: history page + next cursor/event ids
    Ext-->>Provider: decoded envelopes
    Provider->>Provider: map + sort + deduplicate
    Provider->>Buffer: 合并暂存 live 事件
    Provider->>Provider: 提交最后 event cursor
    Provider-->>UI: AgentTurnHistory snapshot
    Provider->>Buffer: 切换为实时直通
~~~

#### 6.5.3 去重键

优先级：

1. provider eventId；
2. sessionId + turnId + itemId + updateType + sequence；
3. 对缺少稳定 id 的旧事件使用受限指纹。

指纹只用于旧版本降级，不得跨会话共享。工具终态、turn completed 和标题更新必须额外做语义去重。

#### 6.5.4 排序

- 有 provider sequence/event cursor 时按其排序；
- 没有时使用协议数组顺序；
- timestamp 仅用于展示和最后兜底，不能作为唯一顺序依据；
- live 与 replay 相交时，replay 先进入 store，再刷新缓冲的 live 事件。

#### 6.5.5 分页

支持：

- 正向 offset/limit；
- 负 offset 或 tail 读取最新事件；
- turnIndex 定位；
- opaque event cursor；
- chunk/stream 响应。

领域层不暴露 Grok offset 细节，统一使用 AgentHistoryPageRequest 和 AgentHistoryCursor。Cursor 中保留 provider opaque token。

#### 6.5.6 session/load 降级

当 x.ai/session/updates 不支持时：

1. 复用现有 AcpSessionReplayCollector；
2. session/load 同时完成 session 绑定和历史捕获；
3. 避免 readThreadHistory 和 resumeSession 对同一会话重复 load；
4. 只有 load 不提供历史时才进入本地 JSONL；
5. replay 事件不得触发权限弹窗、Toast 或后台任务重复启动。

### 6.6 通知与事件映射

#### 6.6.1 Mapper 分层

~~~text
标准 session/update
    → AcpSessionUpdateMapper

x.ai/session/update 或 _x.ai/session/update
    → GrokAcpNotificationMapper

两者输出
    → List<AgentEvent>
    → AgentConversationTimelineStore
~~~

Grok mapper 先委托标准 mapper；仅在标准 mapper 无匹配或 payload 明确为 x.ai 扩展时解析扩展。未知 update type 记录低级别诊断计数，不产生错误卡片。

#### 6.6.2 事件映射表

| Grok 更新 | 中立事件 | 领域/UI 行为 | 阶段 |
| --- | --- | --- | --- |
| SessionSummaryGenerated | AgentThreadNameUpdatedEvent | 更新列表和标题，替代磁盘轮询 | 第一批 |
| ModelChanged | AgentThreadSettingsUpdatedEvent 或 AgentModelChangedEvent | 更新模型配置和系统提示 | 第一批 |
| ModelAutoSwitched | AgentModelReroutedEvent | 展示 from/to/reason | 第一批 |
| DiffReview | AgentTurnDiffEvent | 复用现有 Diff 卡片；保留 review 元数据 | 第一批 |
| RetryState | AgentRetryStateChangedEvent | 显示重试原因、次数和等待状态 | 第一批 |
| AutoCompactStarted | AgentCompactionStateChangedEvent | 显示压缩中 | 第二批 |
| AutoCompactCompleted | AgentThreadCompactedEvent | 标记 checkpoint 和完成 | 第二批 |
| AutoCompactFailed/Cancelled | AgentCompactionStateChangedEvent | 失败或取消提示 | 第二批 |
| PendingInteraction | AgentThreadStatusChangedEvent | waitingOnUserInput=true | 第一批 |
| InteractionResolved | AgentThreadStatusChangedEvent | 清除 waiting 状态 | 第一批 |
| TaskBackgrounded | AgentBackgroundTaskEvent | 创建后台任务条目 | 第三批 |
| TaskCompleted | AgentBackgroundTaskEvent | 更新任务终态 | 第三批 |
| MonitorEvent | AgentBackgroundTaskEvent | 更新监控摘要 | 第三批 |
| ScheduledTask 更新 | AgentBackgroundTaskEvent | 更新计划任务的下次运行和状态 | 第三批 |
| SubagentSpawned | AgentSubagentEvent | 创建子任务节点 | 第三批 |
| SubagentProgress | AgentSubagentEvent | 更新摘要/进度 | 第三批 |
| SubagentFinished | AgentSubagentEvent | 冻结终态 | 第三批 |
| GoalUpdated | AgentGoalUpdatedEvent | 更新目标/计划区域 | 第三批 |
| available_commands_update | AgentAvailableCommandsChangedEvent 或配置目录刷新 | 更新可用命令/Profile 只读目录 | 第三批 |
| current_mode_update | AgentSessionConfigChangedEvent | 更新 effective execution mode | 第二批 |
| config_option_update | AgentSessionConfigChangedEvent | 更新 AgentSessionConfigOption 当前值 | 第二批 |
| session_info_update | 会话摘要/配置刷新事件 | 更新 title、cwd、model 等中立字段 | 第二批 |
| SessionRecap | AgentSystemEvent/会话摘要 | 作为可选摘要，不替换权威事件历史 | 第三批 |
| HookAnnotation/Execution | AgentSystemEvent 或专用事件 | 首期仅诊断，后续展示 | 远期 |
| HooksChanged/PluginsChanged | 管理状态刷新信号 | 不直接插入消息时间线 | 远期 |
| MemoryFlush/Dream/SessionSaved | 诊断或轻量状态 | 不在 Zeta 重新实现 Grok memory | 远期 |
| ToolCallDeltaChunk | AgentToolCallEvent/AgentToolProgress | 合并工具增量并保持唯一终态 | 第二批 |
| ImageCompressed | AgentSystemEvent | 非阻断提示 | 第二批 |
| ImageDropped | AgentErrorEvent/warning | 明确告知未发送成功 | 第二批 |
| TurnCompleted | AgentTurnCompletedEvent | 保持现有逻辑并补充 stopReason/usage | 第一批 |

#### 6.6.3 Raw 数据边界

AgentEvent 可保留 raw 用于诊断，但：

- presentation 不能按 raw 中的 x.ai 字段分支；
- raw 不得写入普通日志全文；
- token、路径、命令输出和用户消息需要按现有日志策略脱敏；
- 未识别事件只保留类型和安全摘要。

### 6.7 图片内容块

#### 6.7.1 发送流程

1. Composer 根据 capability 决定是否启用图片附件。
2. 读取本地文件并验证 MIME、文件大小和可读性。
3. 编码为 ACP ImageContent，而不是把路径追加到文本。
4. 文本和图片按用户选择顺序构建 ContentBlock 列表。
5. Agent 返回 ImageCompressed/ImageDropped 时映射为可见状态。

~~~json
{
  "sessionId": "session-id",
  "prompt": [
    {
      "type": "text",
      "text": "请分析这张截图"
    },
    {
      "type": "image",
      "mimeType": "image/png",
      "data": "<base64>"
    }
  ]
}
~~~

具体字段名以当前 ACP schema 和已安装 CLI 实际版本为准，编码器应集中在 ACP content mapper 中。

#### 6.7.2 安全与资源控制

- 不在日志中记录 base64；
- 读取失败时不启动 turn；
- 不自动绕过 Agent 的图片大小限制；
- UI 对压缩给出弱提示，对丢弃给出明确警告；
- 历史缓存优先保存引用和 MIME，不重复持久化大体积 base64。

### 6.8 动态能力协商与版本适配

#### 6.8.1 能力来源

| 来源 | 用途 | 可信度 |
| --- | --- | --- |
| 标准 ACP initialize capabilities | 标准能力 | 高 |
| initialize _meta / modelState / agentVersion | Grok 扩展线索 | 中高 |
| session/new、session/load payload | 会话级能力 | 高 |
| 成功调用 | 单项扩展能力确认 | 最高 |
| method-not-found | 单项不支持确认 | 最高 |
| CLI version compatibility table | 初始推断 | 中 |
| 超时或进程退出 | 仅运行态错误 | 不用于永久判定 |

#### 6.8.2 能力快照更新

保持 AgentProviderCapabilities 作为 UI 易用的不可变快照，新增可选接口 AgentDynamicCapabilitiesProvider：

- currentCapabilities；
- capabilityChanges；
- diagnostics/version。

未初始化前只返回标准、安全的最小能力。初始化成功或懒探测完成后发出新快照，Project Threads 和 Composer 重新计算按钮状态。

#### 6.8.3 缓存

第一阶段仅在进程生命周期内缓存。若后续需要持久化，缓存键至少包含：

- Grok CLI 规范化路径；
- CLI version；
- initialize agentVersion/agentId；
- 协议版本。

缓存写入 ~/.zeta，不写 Grok 配置。任何版本变化立即失效。

### 6.9 WorkspaceBackend

#### 6.9.1 分层

~~~mermaid
flowchart LR
    FileTree["File Tree"]
    SearchUI["Search"]
    DiffUI["Diff / Git"]
    Workspace["WorkspaceBackend"]
    Local["LocalWorkspaceBackend"]
    Grok["GrokWorkspaceBackend"]

    FileTree --> Workspace
    SearchUI --> Workspace
    DiffUI --> Workspace
    Workspace --> Local
    Workspace --> Grok
~~~

#### 6.9.2 能力

WorkspaceCapabilities 至少表达：

- list/read/stat；
- watch/index delta；
- write（默认 false，需权限）；
- search；
- git status/diff；
- worktree；
- hunk tracker；
- code navigation；
- terminal。

首期 Grok 集成只要求定义接口和本地实现适配方案，不要求一次性实现全部能力。

有效工作区能力按交集计算：

~~~text
Backend 实际能力
  ∩ Provider/会话声明能力
  ∩ 当前 Agent execution mode
  ∩ 用户权限与 OS sandbox
= 本次操作可用能力
~~~

任何子 Agent、远程 session 或 Plugin 只能缩小能力集合，不能自行扩大父会话或 Backend 的权限。

#### 6.9.3 路径规则

- 领域层使用规范化 workspace-relative path；
- data backend 负责转换为本地绝对路径或远程 URI；
- 禁止通过简单字符串前缀判断目录边界；
- 写操作必须验证 canonical target 位于允许工作区；
- 远程 backend 不得假设本机存在对应绝对路径。

#### 6.9.4 通知

Grok fs index/delta 通知转换为 WorkspaceChange，不直接触发 Widget setState。由 application controller 合并、节流并生成不可变文件树快照。

### 6.10 Tool 模型类型化改造

#### 6.10.1 兼容策略

不立即删除 AgentToolCall。新增内容块和 progress 模型，并在 TimelineStore 中增强合并规则。

如果未来 Zeta 承担工具注册或托管职责，还应保持 grok-build Tool runtime 的以下边界：

- tool id 稳定，不使用展示标题作为调用标识；
- 工具是否可见由当前 workspace、权限和 Provider capability 共同决定；
- description 可以按上下文生成，但不能改变工具语义；
- wire JSON、模型可见内容和 UI 展示内容分别建模；
- 子会话只能获得父会话能力的子集，不能通过工具配置扩大权限。

建议新增：

- AgentToolContentPart；
- AgentToolProgress；
- AgentToolTerminalResult；
- AgentToolInvocationSnapshot。

AgentToolCall 可逐步增加：

- contentParts；
- progress；
- terminalResult；
- sequence；
- parentTaskId/subagentId。

#### 6.10.2 合并规则

1. 以 toolCallId 为主键。
2. informative title 不被 opaque id 或“tool progress”覆盖。
3. inProgress 可追加 progress，但 completed/failed/cancelled 不可回退。
4. 重复终态按 eventId 去重；冲突终态保留首个权威终态并记录诊断。
5. 文本增量按 sequence 拼接；全量 snapshot 覆盖旧增量。
6. 图片和资源引用保持结构化，不转换成不可逆字符串。

#### 6.10.3 UI

- 默认展示现有紧凑工具卡；
- progress 仅显示最新摘要，详细列表折叠；
- rich content 在详情面板渲染；
- RepaintBoundary 保持在高频工具区域；
- 长路径、命令和输出继续有边界和省略。

### 6.11 跨 Provider 权限设计

#### 6.11.1 复用现有模型

现有 AgentPermissionSelection 已包含 approvalPolicy、sandboxPolicy 和 permissionProfileId。建议增加可选 executionMode，而不是另建一套 Grok 专属选择器。

建议中立执行模式：

| 中立模式 | Grok 可能映射 | 行为 |
| --- | --- | --- |
| defaultMode | Default | 按规则决定是否询问 |
| plan | Plan | 只规划或限制变更 |
| acceptEdits | Accept Edits | 文件编辑可自动接受，其他操作仍按规则 |
| auto | Auto | Agent 按能力自动推进 |
| dontAsk | Don't Ask | 不发交互询问，但不等于绕过沙箱 |
| bypass | Bypass/yolo | 高风险，必须显式确认 |

最终 wire 映射按当前 CLI 提供的 session modes/config options 优先；只有旧版本才使用 session/new._meta.yoloMode/autoMode。

#### 6.11.2 有效配置

Controller 同时维护：

- requestedSelection：用户选择；
- effectiveSelection：Provider 返回的实际配置；
- unsupportedFields：未生效字段；
- source：session config、initialize、fallback。

如果 Grok 不支持某字段，UI 显示降级状态，不能假装已经应用。

#### 6.11.3 权限请求

保持现有 session/request_permission 流程，并补充：

- 请求超时后的明确状态；
- 远端或其他客户端已解决时清理本地卡片；
- replay 时不重新弹审批；
- deny > ask > allow 的最终规则解释；
- write/terminal 等 WorkspaceBackend 调用继续经过同一权限边界。

### 6.12 事件历史与缓存

#### 6.12.1 第一阶段：内存事件账本

每个会话维护：

- lastEventCursor；
- seenEventIds 有界集合；
- activeBranch/rewind marker；
- replayInProgress；
- bufferedLiveEvents；
- lastSessionSummary；
- lastModelState。

seenEventIds 必须有上限，可按 checkpoint 或最近窗口淘汰。

#### 6.12.2 可选持久化阶段

建议目录：

~~~text
~/.zeta/
  cache/
    agent_sessions/
      grok/
        <session-id>/
          events.jsonl
          index.json
          checkpoints.jsonl
~~~

约束：

- cache 可删除、可重建，不作为唯一权威来源；
- index target-file-first、原子替换；
- JSON 版本化、宽容读取；
- 禁止复制 Grok token、认证信息和完整环境变量；
- 用户消息与命令输出是否缓存需服从 Zeta 隐私设置。

#### 6.12.3 Rewind

旧分支事件保留，通过 branchId/active=false 过滤。UI 默认只展示活动分支，诊断或历史视图可在后续选择展示已回滚分支。

### 6.13 进程、重连与 Leader

#### 6.13.1 当前阶段

继续复用 JsonRpcStdioTransport。增加：

- 进程意外退出状态；
- capability 暂时失效但不永久降级；
- 当前 sessionId、lastEventCursor 和未完成 turn 的恢复上下文；
- 重新 initialize 后按 cursor 补拉 updates；
- 重复 turn/tool 终态去重。

#### 6.13.2 后续评估

只有出现以下需求时才引入 Grok leader 或 WebSocket serve：

- 多个 Zeta 窗口共享同一 Agent；
- Zeta 关闭后 Agent 继续运行；
- 远程机器 Agent；
- 网络断开后长任务继续并可恢复。

引入前必须单独评审认证、端口、进程所有权、会话归属和升级兼容。

### 6.14 应用层与 UI 调整

#### 6.14.1 Project Threads

修改候选：

- lib/src/features/project_threads/application/project_threads_controller.dart
- lib/src/features/project_threads/presentation/project_threads_view_model.dart

调整内容：

- 支持 opaque cursor；
- capability 更新后刷新操作入口；
- rename/delete/fork 后局部更新分页缓存；
- 协议 partial/remote source 只进入状态模型，不泄漏 x.ai 字段；
- 当前会话被删除时正确清理 snapshot。

#### 6.14.2 Conversation 与 Timeline

修改候选：

- lib/src/features/agent/application/agent_conversation_timeline_store.dart
- lib/src/features/agent/presentation/agent_timeline_grouping.dart
- lib/src/features/agent/presentation/widgets/agent_pane_messages.dart
- lib/src/features/agent/presentation/widgets/agent_pane_composer.dart

调整内容：

- Diff Review、Retry、Compact、Pending Interaction；
- 工具进度和唯一终态；
- 图片内容块；
- 子 Agent/后台任务在后续阶段使用折叠式节点；
- replay 事件不触发即时 Toast。

#### 6.14.3 Agent 管理

修改候选：

- lib/src/features/agent_management/data/grok_agent_management_repository.dart
- lib/src/features/agent_management/presentation/agent_management_page.dart

展示：

- CLI 路径和版本；
- ACP initialize 结果摘要；
- 已确认/未知/不支持扩展能力；
- 最近一次 method-not-found、协议解析错误和进程退出；
- 不展示 token、完整 prompt 或 base64 图片。

### 6.15 可观测性与诊断

建议诊断指标：

| 指标 | 用途 |
| --- | --- |
| grok.extension.call.success/failure | 扩展方法稳定性 |
| grok.extension.unsupported | 版本能力分布 |
| grok.notification.unmatched | 新事件类型发现 |
| grok.replay.duplicate_dropped | 回放去重效果 |
| grok.history.source | protocol/load/local fallback 占比 |
| grok.process.restart | 进程稳定性 |
| grok.image.compressed/dropped | 图片体验 |
| grok.capability.changed | 动态能力变化 |

日志规则：

- 方法名、耗时、错误类型可记录；
- sessionId 可散列或按现有策略处理；
- 不记录 token、base64、完整用户输入、完整命令输出；
- fine 日志可记录未知字段名，但不记录敏感字段值。

### 6.16 测试设计

#### 6.16.1 单元测试

新增建议：

- test/src/features/agent/data/datasources/acp/grok_extension_client_test.dart
- test/src/features/agent/data/datasources/acp/grok_capability_resolver_test.dart
- test/src/features/agent/data/datasources/acp/grok_session_history_source_test.dart
- test/src/features/agent/data/mappers/grok_acp_notification_mapper_test.dart

扩展现有：

- grok_acp_provider_test.dart；
- grok_session_history_reader_test.dart；
- agent_provider_capabilities_test.dart；
- agent_conversation_timeline_store_test.dart；
- project_threads_controller_test.dart。

必须覆盖：

1. method-not-found 只降级单项能力；
2. timeout 不标记 unsupported；
3. protocol → session/load → local 的降级顺序；
4. live/replay 交叠去重；
5. duplicate turn completed、tool terminal、title update；
6. rename/delete/fork 请求字段；
7. unknown update type 不崩溃；
8. 图片 base64 不进入日志；
9. requested/effective 权限差异；
10. CLI 版本变化导致 capability cache 失效。

#### 6.16.2 协议集成测试

使用 fake JSON-RPC peer 或测试进程脚本模拟：

- initialize；
- x.ai/session/list 多页；
- x.ai/session/updates chunk/live；
- session/load replay；
- method-not-found；
- 服务端 request_permission；
- 进程中断后重连和 cursor 补拉。

测试 fixture 必须脱敏，不直接提交真实用户会话。

#### 6.16.3 Widget 测试

- capability 未确认时不展示危险操作；
- 支持后 rename/delete/fork 入口出现；
- Retry/Compact/Pending Interaction 状态可见；
- DiffReview 复用现有 Diff 卡；
- 图片被丢弃时出现明确提示；
- 更大系统字体和窄窗口下无 overflow。

#### 6.16.4 工程门禁

每个实现阶段至少执行：

~~~sh
dart format .
flutter analyze
flutter test
~~~

涉及真实 CLI 的 smoke test 在 Windows、macOS、Linux 分别记录版本、初始化结果和会话恢复证据。

### 6.17 文件改动总览

| 文件 | 动作 | 目的 |
| --- | --- | --- |
| grok_acp_agent_provider.dart | 修改 | 注入扩展客户端、动态能力、协议历史、图片和权限映射 |
| grok_extension_client.dart | 新增 | 隔离 x.ai/* |
| grok_extension_models.dart | 新增 | 扩展请求/响应模型 |
| grok_capability_resolver.dart | 新增 | 能力合成与探测 |
| grok_session_history_source.dart | 新增 | 协议/load/本地降级编排 |
| grok_acp_notification_mapper.dart | 修改 | 扩展事件映射 |
| acp_session_update_mapper.dart | 小幅修改 | 共享标准映射或补齐内容块 |
| grok_session_history_reader.dart | 保留并调整 | 明确只读 fallback，不再作为首选 |
| agent_provider.dart | 按阶段修改 | 增加可选动态能力/历史分页抽象 |
| agent_provider_capabilities.dart | 修改 | 新 Grok 能力和动态快照 |
| agent_event_models.dart | 修改 | Retry、Compact、Subagent、Task、Goal 等中立事件 |
| agent_tool_models.dart | 修改 | 富内容、进度与终态 |
| agent_permission_selection_models.dart | 修改 | 可选 executionMode/effective state |
| agent_session_config_models.dart | 复用/小幅修改 | Grok mode/config option |
| agent_conversation_timeline_store.dart | 修改 | 去重、回放和新事件合并 |
| project_threads_controller.dart | 修改 | opaque cursor、动态能力和管理操作 |
| workspace/domain/* | 新增/修改 | WorkspaceBackend 和 capability |
| workspace/data/* | 新增 | Local/Grok backend |
| grok_agent_management_repository.dart | 修改 | 扩展能力与诊断展示 |
| 对应 test 文件 | 新增/修改 | 单元、协议和 Widget 覆盖 |

### 6.18 Agent Profile、Skills、Plugins、Hooks 与 MCP

该组能力必须采用“Provider 负责执行，Zeta 负责发现、配置和展示”的边界。

#### 6.18.1 首期读取模型

可定义 Provider 中立的只读摘要：

- AgentProfileSummary：id、名称、说明、模型、执行模式、工具限制；
- AgentCommandSummary：稳定 command id、名称、参数提示；
- AgentExtensionSummary：类型为 skill/plugin/hook/mcp，包含启用状态和来源；
- AgentExtensionHealth：ready、disabled、failed、unknown。

数据来源可以是 initialize meta、availableCommands、标准 session config 或 x.ai 扩展，但领域对象不得保留 x.ai 命名。若只有 Grok 支持某字段，放入 data 层 raw。

#### 6.18.2 首期不实施

- 不解析并执行 Grok Agent definition 的 Markdown/YAML；
- 不由 Zeta 运行 Grok Hook；
- 不将 Grok Plugin 文件复制到 ~/.zeta；
- 不擅自修改 Grok MCP、Skills 或 Plugins 配置；
- 不把 Provider 的 memory flush/dream 事件升级为 Zeta 自有记忆系统。

后续若需要写操作，必须分别定义目标配置文件、权限、原子更新、回读验证和版本兼容方案，不能复用会话协议调用作为隐式配置写入。

---

## 7. 实施路线图

### 7.1 阶段总览

| 阶段 | 目标 | 主要交付物 | 前置依赖 | 主要风险 |
| --- | --- | --- | --- | --- |
| Phase 0 | 固化当前行为 | 基线测试、协议 fixtures、版本矩阵 | 无 | 现有用户改动与测试不稳定 |
| Phase 1 | 扩展协议内核 | GrokExtensionClient、错误模型、能力 resolver | Phase 0 | CLI 版本差异 |
| Phase 2 | 协议化会话读取 | session/list、updates、分页、游标、三级降级 | Phase 1 | replay/live 重复 |
| Phase 3 | 会话管理 | rename、delete、fork、compact、rewind | Phase 2 | 破坏性操作和状态竞态 |
| Phase 4 | 高价值事件 | 标题、模型、Diff、Retry、Compact、Pending | Phase 1/2 | 事件顺序与 UI 噪声 |
| Phase 5 | 图片与权限 | ImageContent、模式、effective permission | Phase 1 | 大文件、权限误映射 |
| Phase 6 | 通用工具与工作区 | Tool rich content、WorkspaceBackend 骨架 | Phase 2/4 | 改造面较大 |
| Phase 7 | 高级任务体验 | 子 Agent、后台任务、Goal、MCP/Hook 状态 | Phase 4/6 | 领域模型过度 Grok 化 |
| Phase 8 | 恢复与远程评估 | 游标持久化、重连；leader/WebSocket 决策 | Phase 2/6 | 进程所有权和安全 |

### 7.2 Phase 0：基线与兼容矩阵

任务：

1. 固化当前 initialize/new/load/prompt/cancel 测试。
2. 为当前本地历史解析补充损坏和旧版本 fixture。
3. 记录至少一个当前稳定 Grok CLI 与 grok-build 源码版本的能力差异。
4. 建立 x.ai 响应脱敏 fixtures。

交付物：

- 测试基线；
- CLI 版本/能力矩阵；
- 当前行为回归报告。

验收：

- 不修改生产行为；
- 现有 Grok Provider 测试稳定通过；
- fixture 不包含真实凭据和用户数据。

### 7.3 Phase 1：GrokExtensionClient 与动态能力

任务：

1. 新增扩展客户端和模型。
2. 新增 GrokCapabilityResolver。
3. 接入 initialize agentVersion/modelState/client metadata。
4. 将静态 Grok capability 改为最小初始快照 + 运行时更新。
5. 管理页增加安全诊断。

交付物：

- 可测试的扩展协议边界；
- 三态能力；
- method-not-found 和暂时失败区分。

风险与控制：

- 风险：旧 CLI 不认识扩展方法。
- 控制：只读方法懒探测；unknown 在 UI 按不支持处理。

验收：

- 单个方法不支持不会让整个 Provider 失效；
- CLI 版本变化会重置能力；
- 无 x.ai 字段进入 presentation。

### 7.4 Phase 2：会话列表和历史

建议拆分为四个小迭代：

1. session/list + opaque cursor；
2. session/updates 单页历史；
3. chunk/tail/turnIndex；
4. replay/live 缓冲、去重和三级降级。

交付物：

- GrokSessionHistorySource；
- Project Threads 协议分页；
- history source 诊断；
- 本地 reader 降级。

依赖：Phase 1。

风险与控制：

- 重复事件：eventId + 语义终态去重；
- 顺序错乱：replay gate 暂存 live；
- 协议 partial：标记来源和完整性，不静默伪造完整。

验收：

- 新 CLI 不读取本地磁盘即可完成列表和历史；
- 方法不支持时现有历史功能不回退；
- 切换会话不会重复消息或工具卡。

### 7.5 Phase 3：会话管理操作

建议每个操作独立提交：

1. rename；
2. delete；
3. fork；
4. compact；
5. rewind points；
6. rewind execute。

每个提交必须包含 capability gate、Provider 实现、Controller 状态、错误回滚和测试。

验收：

- 不支持的 CLI 不显示入口；
- 删除和 rewind 有明确确认；
- 超时不会自动重复破坏性请求；
- 成功后当前会话、列表和快照一致。

### 7.6 Phase 4：扩展事件

第一批：

- SessionSummaryGenerated；
- ModelChanged/ModelAutoSwitched；
- DiffReview；
- RetryState；
- PendingInteraction/InteractionResolved；
- TurnCompleted 扩展字段。

第二批：

- 自动压缩全生命周期；
- 图片处理通知；
- usage/cost/incomplete。

交付物：

- 新/复用 AgentEvent；
- mapper 测试；
- TimelineStore 合并规则；
- UI 卡片和状态。

验收：

- 未知事件不崩溃；
- replay 不触发即时副作用；
- 高频事件不会造成明显重绘和滚动抖动。

### 7.7 Phase 5：图片与权限

图片任务：

1. ACP content mapper；
2. MIME/大小验证；
3. Composer capability gate；
4. compressed/dropped 反馈；
5. 日志脱敏测试。

权限任务：

1. executionMode 领域字段；
2. requested/effective 状态；
3. session mode/config option 映射；
4. yolo/auto 旧版本兼容；
5. 高风险模式确认。

验收：

- 图片以原生内容块发送；
- base64 不出现在日志和普通缓存；
- 不支持的权限字段有明确降级；
- 不会自动提升到 bypass/dangerFullAccess。

### 7.8 Phase 6：Tool 与 WorkspaceBackend

先后顺序：

1. Tool progress/terminal 合并规则；
2. rich content；
3. WorkspaceBackend 接口；
4. LocalWorkspaceBackend 适配；
5. Grok read/list/watch/search 只读实现；
6. Git/worktree 等能力在单独产品需求下实现。

验收：

- 现有文件树无功能回退；
- terminal 状态唯一；
- 远程路径不被当作本地路径；
- 写操作仍经过权限层。

### 7.9 Phase 7：子 Agent 与后台任务

任务：

- 中立 AgentSubagentEvent；
- 中立 AgentBackgroundTaskEvent；
- GoalUpdated；
- 时间线层级和折叠；
- 管理页 Hooks/Plugins 只读刷新信号。

控制原则：只有语义可以跨 Provider 时才进入领域层；Grok 特有字段保留在 raw/data 层。

### 7.10 Phase 8：断线恢复与远程模式评估

先实现 stdio 重启后的：

- initialize；
- session 重新绑定；
- lastEventCursor 补拉；
- in-flight turn 状态恢复；
- 重复事件去重。

完成后再提交 leader/WebSocket 的独立 ADR。没有多窗口或远程需求时，不实施该模式。

---

## 8. 不建议事项与风险规避

### 8.1 不建议事项

| 不建议事项 | 原因 | 替代方案 |
| --- | --- | --- |
| 移植 Rust TUI/主题 | 与 Flutter UI、设计 token 和可访问性体系不匹配 | 只复用协议和领域设计 |
| Rust FFI 嵌入 grok-build | ABI、构建、升级、崩溃隔离和三平台发布复杂 | 外部 CLI + ACP |
| 直接依赖私有 JSONL | 格式不稳定、无法远程、需长期维护 parser | 协议优先，本地只读 fallback |
| UI 直接调用 x.ai/* | 破坏 Provider 中立和测试边界 | GrokExtensionClient + mapper |
| 将 Grok raw payload 作为领域模型 | Provider 字段会污染通用 UI | 映射为 AgentEvent/领域对象 |
| 伪造不支持能力 | 导致无效按钮、静默 no-op 和数据风险 | 动态 capability gate |
| 在 Zeta 重写 Grok memory/sandbox/hooks | 与 Agent 运行时职责重复且易产生安全差异 | 配置、展示和编排 |
| 将 Grok 代码图直接用于 Dart | 当前不覆盖 Dart/Flutter | 仅借鉴增量索引架构 |
| 首期引入 leader/WebSocket | 增加认证、生命周期和远程安全复杂度 | 先稳定 stdio + cursor replay |
| 自动重试 delete/rewind/compact | 超时后结果不确定，可能重复产生副作用 | 查询状态、用户确认后恢复 |

### 8.2 主要风险

| 风险 | 概率 | 影响 | 规避措施 |
| --- | --- | --- | --- |
| 开源源码与用户 CLI 版本不一致 | 高 | 高 | 动态探测、版本矩阵、method-not-found 降级 |
| x.ai 扩展未承诺长期兼容 | 中 | 高 | 集中适配、宽容读、严格写、fixture 回归 |
| replay/live 产生重复 | 中 | 高 | replay gate、eventId、语义终态去重 |
| 破坏性操作结果不确定 | 中 | 高 | 禁止盲重试、刷新权威状态、二次确认 |
| 本地 fallback 与协议结果冲突 | 中 | 中 | 协议权威，非 partial 不混合 |
| 动态 capability 导致 UI 抖动 | 中 | 中 | unknown 初始隐藏，批量发布不可变快照 |
| 工具高频进度造成性能下降 | 中 | 中 | 合并、节流、RepaintBoundary、折叠详情 |
| 图片占用大量内存和日志泄漏 | 中 | 高 | 大小检查、流式读取评估、禁止记录 base64 |
| 权限模式错误映射 | 低到中 | 高 | requested/effective 分离，高风险显式确认 |
| 远程路径误当本地路径 | 中 | 高 | Workspace URI/relative path 抽象 |
| Provider 私有字段泄漏 UI | 中 | 中 | mapper 边界测试和代码评审门禁 |
| 缓存含敏感会话数据 | 中 | 高 | ~/.zeta、可关闭、版本化、脱敏和清理策略 |

### 8.3 许可证合规

grok-build 第一方代码整体以 Apache-2.0 为主要许可基线，但仓库中可能包含来自 Codex、OpenCode 或其他项目的移植代码和逐文件声明。

要求：

1. 优先复用公开协议和架构思想，而不是复制实现。
2. 复制任何代码前必须检查目标文件头、仓库 LICENSE、NOTICE 和 third-party 说明。
3. 保留 Apache-2.0 要求的版权和许可声明。
4. 第三方来源代码按其原始许可证单独评估。
5. 不将“仓库可读”误认为“所有文件可无条件复制”。
6. 发布前由项目维护者或法务完成依赖与 NOTICE 审核。

---

## 9. 接口与数据结构定义

> 以下为 Dart 风格设计伪代码，强调边界和语义，不要求逐字实现。

### 9.1 GrokExtensionClient

~~~dart
abstract interface class GrokExtensionClient {
  Future<GrokSessionPage> listSessions(GrokSessionListRequest request);

  Future<GrokSessionUpdatePage> readSessionUpdates(
    GrokSessionUpdatesRequest request,
  );

  Future<void> renameSession({
    required String sessionId,
    required String cwd,
    required String title,
    String? kind,
  });

  Future<void> deleteSession({
    required String sessionId,
    required String cwd,
    String? kind,
  });

  Future<GrokForkSessionResult> forkSession(
    GrokForkSessionRequest request,
  );

  Future<void> compactConversation({
    required String sessionId,
    String? userContext,
  });

  Future<List<GrokRewindPoint>> listRewindPoints({
    required String sessionId,
    required String cwd,
  });

  Future<void> executeRewind(GrokRewindRequest request);
}
~~~

具体实现 JsonRpcGrokExtensionClient 仅依赖 JSON-RPC peer/transport，不依赖 Widget、Controller 或本地文件系统。

### 9.2 会话分页

~~~dart
class GrokSessionListRequest {
  const GrokSessionListRequest({
    required this.cwd,
    this.query,
    this.limit = 50,
    this.cursor,
  });

  final String cwd;
  final String? query;
  final int limit;
  final String? cursor;
}

class GrokSessionPage {
  const GrokSessionPage({
    required this.sessions,
    this.nextCursor,
    this.partial = false,
    this.facets = const <String, Object?>{},
  });

  final List<GrokSessionSummary> sessions;
  final String? nextCursor;
  final bool partial;
  final Map<String, Object?> facets;
}
~~~

nextCursor 必须作为 opaque string 保存；不得转换为 offset。

### 9.3 历史请求和事件包

~~~dart
class GrokSessionUpdatesRequest {
  const GrokSessionUpdatesRequest({
    required this.sessionId,
    required this.cwd,
    this.offset,
    this.limit,
    this.turnIndex,
    this.cursor,
    this.stream = false,
    this.chunkSize,
  });

  final String sessionId;
  final String cwd;
  final int? offset;
  final int? limit;
  final int? turnIndex;
  final String? cursor;
  final bool stream;
  final int? chunkSize;
}

class GrokSessionUpdateEnvelope {
  const GrokSessionUpdateEnvelope({
    required this.sessionId,
    required this.updateType,
    required this.payload,
    this.eventId,
    this.sequence,
    this.isReplay = false,
  });

  final String sessionId;
  final String updateType;
  final Map<String, Object?> payload;
  final String? eventId;
  final int? sequence;
  final bool isReplay;
}
~~~

### 9.4 动态能力

~~~dart
enum AgentFeatureSupport {
  unknown,
  supported,
  unsupported,
  temporarilyUnavailable,
}

enum GrokExtensionFeature {
  sessionList,
  sessionUpdates,
  sessionRename,
  sessionDelete,
  sessionFork,
  compactConversation,
  rewind,
  nativeImagePrompt,
  sessionMode,
  remoteWorkspace,
  backgroundTasks,
  subagents,
}

class GrokRuntimeCapabilities {
  const GrokRuntimeCapabilities({
    required this.features,
    required this.agentVersion,
    required this.protocolVersion,
  });

  final Map<GrokExtensionFeature, AgentFeatureSupport> features;
  final String? agentVersion;
  final String? protocolVersion;
}

abstract interface class AgentDynamicCapabilitiesProvider {
  AgentProviderCapabilities get currentCapabilities;
  Stream<AgentProviderCapabilities> get capabilityChanges;
}
~~~

公共 AgentProviderCapabilities 只将 supported 转换为 true。unknown 和 temporarilyUnavailable 默认不开放危险入口。

### 9.5 能力解析

~~~dart
abstract interface class GrokCapabilityResolver {
  GrokRuntimeCapabilities get current;
  Stream<GrokRuntimeCapabilities> get changes;

  void applyInitializeResult(Map<String, Object?> result);

  void markMethodSucceeded(String method);

  void markMethodUnsupported(String method);

  void markTemporarilyUnavailable(String method, Object error);

  void resetForRuntime({
    required String executablePath,
    required String version,
  });
}
~~~

### 9.6 会话历史源

~~~dart
enum AgentHistorySourceKind {
  providerExtension,
  acpSessionLoad,
  localReadOnlyFallback,
}

class AgentHistoryReadResult {
  const AgentHistoryReadResult({
    required this.turns,
    required this.source,
    this.nextCursor,
    this.isPartial = false,
  });

  final List<AgentTurnHistory> turns;
  final AgentHistorySourceKind source;
  final String? nextCursor;
  final bool isPartial;
}

abstract interface class GrokSessionHistorySource {
  Future<AgentThreadPage> listThreads(AgentThreadPageRequest request);

  Future<AgentHistoryReadResult> readHistory({
    required String sessionId,
    required String cwd,
    AgentHistoryCursor? cursor,
  });
}
~~~

### 9.7 扩展事件

~~~dart
enum AgentRetryPhase { waiting, retrying, recovered, exhausted }

class AgentRetryStateChangedEvent extends AgentEvent {
  const AgentRetryStateChangedEvent({
    required this.sessionId,
    required this.phase,
    this.turnId,
    this.attempt,
    this.reason,
    this.retryAfter,
    this.raw = const <String, Object?>{},
  });

  final String sessionId;
  final String? turnId;
  final AgentRetryPhase phase;
  final int? attempt;
  final String? reason;
  final Duration? retryAfter;
  final Map<String, Object?> raw;
}

enum AgentCompactionPhase {
  started,
  completed,
  failed,
  cancelled,
}

class AgentCompactionStateChangedEvent extends AgentEvent {
  const AgentCompactionStateChangedEvent({
    required this.sessionId,
    required this.phase,
    this.turnId,
    this.checkpointId,
    this.message,
    this.raw = const <String, Object?>{},
  });

  final String sessionId;
  final String? turnId;
  final AgentCompactionPhase phase;
  final String? checkpointId;
  final String? message;
  final Map<String, Object?> raw;
}
~~~

子 Agent、后台任务和 Goal 事件应采用相同模式：稳定 id、sessionId、可选 turnId、领域状态和 raw，不在事件类中出现 x.ai 命名。

### 9.8 WorkspaceBackend

~~~dart
class WorkspaceCapabilities {
  const WorkspaceCapabilities({
    this.canList = true,
    this.canRead = true,
    this.canWatch = false,
    this.canWrite = false,
    this.canSearch = false,
    this.canReadGit = false,
    this.canMutateGit = false,
    this.canManageWorktrees = false,
    this.canNavigateCode = false,
    this.canUseTerminal = false,
  });

  final bool canList;
  final bool canRead;
  final bool canWatch;
  final bool canWrite;
  final bool canSearch;
  final bool canReadGit;
  final bool canMutateGit;
  final bool canManageWorktrees;
  final bool canNavigateCode;
  final bool canUseTerminal;
}

abstract interface class WorkspaceBackend {
  WorkspaceCapabilities get capabilities;

  Future<List<WorkspaceEntry>> list(String relativePath);

  Future<WorkspaceTextFile> readText(String relativePath);

  Stream<WorkspaceChange> watch();

  Future<WorkspaceSearchPage> search(WorkspaceSearchRequest request);
}
~~~

写入、Git 修改和 terminal 可由 capability-gated 可选接口承担，避免让纯只读 backend 实现无意义 no-op。

### 9.9 类型化工具内容

~~~dart
sealed class AgentToolContentPart {
  const AgentToolContentPart();
}

class AgentToolTextPart extends AgentToolContentPart {
  const AgentToolTextPart(this.text);
  final String text;
}

class AgentToolImagePart extends AgentToolContentPart {
  const AgentToolImagePart({
    required this.mimeType,
    this.dataReference,
  });

  final String mimeType;
  final String? dataReference;
}

class AgentToolResourcePart extends AgentToolContentPart {
  const AgentToolResourcePart({
    required this.uri,
    this.title,
  });

  final Uri uri;
  final String? title;
}

class AgentToolProgress {
  const AgentToolProgress({
    required this.sequence,
    required this.parts,
    this.timestamp,
  });

  final int sequence;
  final List<AgentToolContentPart> parts;
  final DateTime? timestamp;
}
~~~

### 9.10 权限选择

~~~dart
enum AgentExecutionMode {
  defaultMode,
  plan,
  acceptEdits,
  auto,
  dontAsk,
  bypass,
}

class AgentPermissionSelection {
  const AgentPermissionSelection({
    this.approvalPolicy = defaultApprovalPolicy,
    this.sandboxPolicy = defaultSandboxPolicy,
    this.permissionProfileId,
    this.executionMode = AgentExecutionMode.defaultMode,
  });

  final String approvalPolicy;
  final String sandboxPolicy;
  final String? permissionProfileId;
  final AgentExecutionMode executionMode;
}

class AgentEffectivePermissionState {
  const AgentEffectivePermissionState({
    required this.requested,
    required this.effective,
    this.unsupportedFields = const <String>[],
    this.source,
  });

  final AgentPermissionSelection requested;
  final AgentPermissionSelection effective;
  final List<String> unsupportedFields;
  final String? source;
}
~~~

### 9.11 追加式缓存事件

~~~json
{
  "schemaVersion": 1,
  "providerId": "grok",
  "sessionId": "session-id",
  "eventId": "opaque-provider-event-id",
  "sequence": 123,
  "branchId": "main",
  "active": true,
  "receivedAt": "2026-07-16T10:00:00.000Z",
  "event": {
    "type": "agentMessageDelta",
    "payload": {}
  }
}
~~~

缓存 codec 必须 tryDecode，损坏单行不能阻止应用启动；不可识别版本跳过并记录诊断。

### 9.12 Provider 调用关系

~~~mermaid
sequenceDiagram
    participant Controller
    participant Provider as GrokAcpAgentProvider
    participant Caps as GrokCapabilityResolver
    participant Ext as GrokExtensionClient
    participant Peer as JSON-RPC Peer

    Controller->>Provider: renameThread(id, title)
    Provider->>Caps: 查询 sessionRename
    alt 已确认不支持
        Provider-->>Controller: AgentUnsupportedOperation
    else supported 或 unknown
        Provider->>Ext: renameSession(...)
        Ext->>Peer: x.ai/session/rename
        alt success
            Peer-->>Ext: result
            Ext-->>Provider: success
            Provider->>Caps: markMethodSucceeded
            Provider-->>Controller: success + name event
        else method-not-found
            Peer-->>Ext: JSON-RPC error
            Ext-->>Provider: unsupported
            Provider->>Caps: markMethodUnsupported
            Provider-->>Controller: AgentUnsupportedOperation
        else transport/timeout
            Ext-->>Provider: temporary failure
            Provider->>Caps: markTemporarilyUnavailable
            Provider-->>Controller: retryable error
        end
    end
~~~

---

## 10. 附录

### 10.1 Zeta 关键文件引用索引

| 文件 | 当前职责 | 本设计影响 |
| --- | --- | --- |
| [grok_acp_agent_provider.dart](../lib/src/features/agent/data/datasources/acp/grok_acp_agent_provider.dart) | Grok ACP 主 Provider | 核心改造入口 |
| [grok_process_starter.dart](../lib/src/features/agent/data/datasources/acp/grok_process_starter.dart) | CLI 参数和进程启动 | 保留 stdio；减少 session 配置对进程参数依赖 |
| [grok_acp_notification_mapper.dart](../lib/src/features/agent/data/mappers/grok_acp_notification_mapper.dart) | Grok 通知映射 | 扩展全部高价值事件 |
| [acp_session_update_mapper.dart](../lib/src/features/agent/data/mappers/acp_session_update_mapper.dart) | 标准 ACP 通知映射 | 保持共享标准层 |
| [grok_session_history_reader.dart](../lib/src/features/agent/data/datasources/local_history/grok_session_history_reader.dart) | 本地 Grok 历史 | 调整为只读 fallback |
| [agent_provider.dart](../lib/src/features/agent/domain/agent_provider.dart) | 中立 Provider 接口 | 可选动态能力和分页历史 |
| [agent_provider_capabilities.dart](../lib/src/features/agent/domain/agent_provider_capabilities.dart) | UI capability gate | 从静态 Grok 常量演进为快照 |
| [agent_event_models.dart](../lib/src/features/agent/domain/agent_event_models.dart) | 中立 Agent 事件 | 新增 Retry/Compact/Task/Subagent/Goal |
| [agent_tool_models.dart](../lib/src/features/agent/domain/agent_tool_models.dart) | 工具 read model | 增加富内容、进度、唯一终态 |
| [agent_permission_selection_models.dart](../lib/src/features/agent/domain/agent_permission_selection_models.dart) | 审批与沙箱选择 | 增加 executionMode/effective state |
| [agent_session_config_models.dart](../lib/src/features/agent/domain/agent_session_config_models.dart) | 动态 session 配置 | 复用 Grok mode/model |
| [agent_conversation_timeline_store.dart](../lib/src/features/agent/application/agent_conversation_timeline_store.dart) | 时间线状态合并 | replay、去重和新事件 |
| [project_threads_controller.dart](../lib/src/features/project_threads/application/project_threads_controller.dart) | 项目会话列表与操作 | opaque cursor、动态能力、管理操作 |
| [grok_agent_management_repository.dart](../lib/src/features/agent_management/data/grok_agent_management_repository.dart) | Grok CLI 管理 | 增加扩展能力诊断 |
| [workspace_tree_builder.dart](../lib/src/features/workspace/application/workspace_tree_builder.dart) | 本地文件树 | 后续接入 WorkspaceBackend |

### 10.2 grok-build 参考索引

| 路径 | 参考内容 |
| --- | --- |
| [README.md](../../OpenSource/grok-build/README.md) | 仓库定位、组件和许可 |
| [15-agent-mode.md](../../OpenSource/grok-build/crates/codegen/xai-grok-pager/docs/user-guide/15-agent-mode.md) | stdio、serve、headless 和扩展概览 |
| [17-sessions.md](../../OpenSource/grok-build/crates/codegen/xai-grok-pager/docs/user-guide/17-sessions.md) | 会话持久化结构 |
| [22-permissions-and-safety.md](../../OpenSource/grok-build/crates/codegen/xai-grok-pager/docs/user-guide/22-permissions-and-safety.md) | 权限与安全模型 |
| [acp_agent.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-shell/src/agent/mvp_agent/acp_agent.rs) | ACP Agent 主实现与 x.ai 路由 |
| [session.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-shell/src/agent/handlers/session.rs) | session list/info/close |
| [session_updates.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-shell/src/extensions/session_updates.rs) | 历史 updates、分页与回放 |
| [session_admin.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-shell/src/extensions/session_admin.rs) | rename/delete/fork |
| [rewind.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-shell/src/extensions/rewind.rs) | rewind points/execute |
| [memory.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-shell/src/extensions/memory.rs) | compact conversation |
| [notification.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-shell/src/extensions/notification.rs) | x.ai 扩展事件枚举 |
| [workspace_ops.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-workspace/src/workspace_ops.rs) | Local/Proxy WorkspaceOps |
| [capability.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-workspace/src/capability.rs) | 工作区能力子集与只读模式 |
| [tool.rs](../../OpenSource/grok-build/crates/common/xai-tool-runtime/src/tool.rs) | 类型化、流式 Tool 接口 |
| [rules.rs](../../OpenSource/grok-build/crates/codegen/xai-grok-workspace/src/permission/rules.rs) | Agent 执行/权限模式 |
| [ChatStateActor](../../OpenSource/grok-build/crates/codegen/xai-chat-state/src/actor/mod.rs) | 会话状态单写者与命令式更新 |
| [xai-grok-agent README](../../OpenSource/grok-build/crates/codegen/xai-grok-agent/README.md) | Agent profile、工具、skills 和配置设计 |

### 10.3 未来扩展方向

以下方向建立在前述基础完成之后，不属于首批交付：

1. Grok leader/WebSocket，多窗口共享和远程 Agent。
2. Provider 中立的后台任务中心和子 Agent 树。
3. WorkspaceBackend 下的远程 Git/worktree/hunk review。
4. MCP、Skills、Plugins、Hooks 的只读统一状态面板。
5. Provider 中立的事件缓存、断线游标和分支历史。
6. 基于 availableCommands/Agent profile 的可配置 Agent 工作流。

### 10.4 评审检查表

- [ ] x.ai/* 是否只存在于 Grok data 层？
- [ ] 是否保留老 CLI 的 session/load 和本地只读 fallback？
- [ ] capability 是否由运行时证据决定？
- [ ] unknown 是否不会开放危险操作？
- [ ] delete/rewind/compact 是否禁止盲目自动重试？
- [ ] replay/live 是否有明确缓冲和去重算法？
- [ ] raw payload 是否不会驱动 presentation 分支？
- [ ] 图片 base64 是否不会进入日志和普通缓存？
- [ ] 权限是否区分审批、执行模式和沙箱？
- [ ] Zeta 缓存是否仅写入 ~/.zeta？
- [ ] 新事件是否有 mapper、store 和 UI 测试？
- [ ] 是否完成 grok-build 文件级许可证核查？

---

## 结论

Zeta 当前 Grok 接入的主方向正确，现有 AgentProvider、ACP transport、事件模型和 capability gate 足以承载后续演进。实施重点应集中在 Grok data 层：

1. 以 GrokExtensionClient 隔离 x.ai/*；
2. 以协议化 list/updates 替换私有磁盘主路径；
3. 以动态 capability 消除版本假设和静默 no-op；
4. 将 Grok 扩展事件映射为 Provider 中立领域事件；
5. 逐步建设可复用于其他 Provider 的权限、工具、工作区和事件恢复机制。

该路线能够在保留现有兼容能力的同时，逐步把 Zeta 从基础 ACP 客户端升级为完整的通用 Agent IDE，而无需移植 grok-build UI、嵌入 Rust 运行时或破坏当前 feature-sliced 架构。
