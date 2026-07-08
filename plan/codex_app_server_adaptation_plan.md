# Codex app-server 适配清单与适配计划

最后更新:2026-07-08

## 0. 文档目的与协议基准

本文档回答一个问题:**当前 `features/agent` 适配层相对 Codex app-server 完整协议,还有哪些功能没有适配,以及按什么顺序补齐。**

- 协议基准:本机 `codex-cli 0.142.3`,通过 `codex app-server generate-json-schema --out <dir>` 导出的官方 JSON Schema(`ClientRequest` / `ClientNotification` / `ServerNotification` / `ServerRequest` 四个联合类型 + v2 逐方法 schema)。
- 代码基准:`lib/src/features/agent/` 下的 Codex 适配层,入口为
  `data/datasources/app_server/codex_app_server_agent_provider.dart`(library,
  通过 `part` 聚合 client、mapper、parser)。
- 协议规模 vs 当前覆盖:

| 协议面 | 协议总数 | 已适配 | 部分适配/漂移 | 未适配 |
| --- | --- | --- | --- | --- |
| 客户端请求(client → server,带 id) | 87 | 6 | 3(`thread/list`、`turn/start`、`initialize` 参数不完整) | 78 |
| 客户端通知(client → server) | 1 | 1 | 0 | 0 |
| 服务端通知(server → client) | 68 | 11 | 5(`error`、`turn/completed`、`item/started`、`item/completed` 结构消费不全;`mcpServer/startupStatus/updated` 被显式忽略) | 52 |
| 服务端请求(server → client,需应答) | 10 | 5 | 3(`item/tool/requestUserInput`、`mcpServer/elicitation/request` 默认应答;`item/tool/call` 走危险兜底) | 2 |

> 注意:适配层还在监听 3 个当前协议中**已不存在**的通知名(`turn/tokenCount`、`item/tokenCount`、`tokenCount`),详见第 2 节审计项。

---

## 1. 已适配能力清单(现状)

### 1.1 客户端请求(9 个)

| 方法 | 位置 | 备注 |
| --- | --- | --- |
| `initialize` | `codex_app_server_agent_provider.dart` | 发送 `clientInfo` + 显式 `capabilities`(A6 已完成,含 P4~P5 通知 opt-out 清单) |
| `model/list` | `codex_app_server_client.dart` | 握手后自动拉取并缓存 |
| `thread/start` | 同上 | 仅传 `cwd`/`model`/`approvalPolicy: on-request` |
| `thread/resume` | 同上 | 同上 |
| `thread/list` | 同上 | 固定 `archived: false`,未用 `searchTerm`/`modelProviders` |
| `thread/read` | 同上 | 作为本地 JSONL 解析失败后的 fallback |
| `turn/start` | 同上 | 仅 `text` 输入;推理力度按协议字段 `effort` 发送(A4 已修复) |
| `turn/steer` | 同上 | 运行中追加指令 |
| `turn/interrupt` | 同上 | 取消回合 |

### 1.2 服务端通知(显式处理 16 个 case,其中 3 个为失效方法名)

已映射:`thread/started`、`turn/started`、`turn/completed`、`item/agentMessage/delta`、`turn/plan/updated`、`item/started`、`item/completed`、`item/commandExecution/outputDelta`、`command/exec/outputDelta`、`item/fileChange/outputDelta`、`item/fileChange/patchUpdated`、`error`、`warning`、`guardianWarning`、`configWarning`;显式忽略:`mcpServer/startupStatus/updated`;其余 **default 分支静默丢弃**。

### 1.3 服务端请求(审批,5 个显式 + 泛化 fallback)

`item/commandExecution/requestApproval`、`item/fileChange/requestApproval`、`item/permissions/requestApproval`、`execCommandApproval`(legacy)、`applyPatchApproval`(legacy)已完整走 UI 审批;`item/tool/requestUserInput`、`mcpServer/elicitation/request` 走"默认应答"降级(空答案 / action 变体,表单 UI 见 3.8);`item/tool/call`、`account/chatgptAuthTokens/refresh`、`attestation/generate` 与其余未知方法立即回 `-32601` JSON-RPC error(A5 已完成)。

### 1.4 本地 JSONL 历史

`codex_jsonl_history_parser.dart` 已解析 `session_meta`/`event_msg`/`turn_context`/`response_item` 主要子类型,`thread/read` 的 turn item 已覆盖 `userMessage`/`agentMessage`/`plan`/`reasoning`/`commandExecution`/`fileChange`/`mcpToolCall`/`dynamicToolCall`。

---

## 2. 协议漂移审计项(P0,建议先于新功能修复)

这些不是"缺功能",而是**当前实现与 0.142.3 协议不一致、可能已经静默失效**的点。

### A1. Token 用量通知已失效 ⚠️ 高优 —— ✅ 已完成(2026-07-08)

- 现状:`codex_notification_mapper.dart` 监听 `turn/tokenCount` / `item/tokenCount` / `tokenCount`,并按 snake_case(`total_token_usage.input_tokens`)解析。
- 协议现实:0.142.3 的通知是 **`thread/tokenUsage/updated`**,结构为
  `{ threadId, turnId, tokenUsage: { total: TokenUsageBreakdown, last: TokenUsageBreakdown, modelContextWindow } }`,字段为 camelCase(`inputTokens`、`cachedInputTokens`、`outputTokens`、`reasoningOutputTokens`、`totalTokens`)。
- 后果:实时 token 统计(上下文窗口占用、用量气泡)大概率收不到任何数据,只能靠 JSONL 历史回填。
- 修复:新增 `thread/tokenUsage/updated` case,camelCase 解析,保留旧 case 作为容错;`modelContextWindow` 应传给 UI 用于上下文占用比例。

### A2. `error` 通知结构漂移 —— ✅ 已完成(2026-07-08)

- 现状:读取 `params['message']` / `params['details']`。
- 协议现实:`ErrorNotification = { threadId, turnId, willRetry, error: TurnError }`,`TurnError = { message, codexErrorInfo, additionalDetails }`,`codexErrorInfo` 是可判别枚举(`contextWindowExceeded`、`usageLimitExceeded`、`serverOverloaded`、`unauthorized`、`sandboxError`、`httpConnectionFailed{...}` 等)。
- 后果:错误卡片显示的是方法名而非真实错误;无法区分"会自动重试"与"终态失败";无法针对 `contextWindowExceeded` 引导用户 compact、针对 `unauthorized` 引导登录。
- 修复:解析 `error.message` + `codexErrorInfo` + `willRetry`,domain 层为 `AgentErrorEvent` 增加错误码与可重试标记。

### A3. `turn/completed` 未消费 `turn.status` 与 `turn.error` —— ✅ 已完成(2026-07-08)

- 协议现实:`Turn = { id, items, status: completed|interrupted|failed|inProgress, error?, startedAt, completedAt, durationMs }`。
- 后果:被打断(interrupted)和失败(failed)的回合在 UI 上与正常完成无区分;`durationMs` 等元数据丢弃。
- 修复:domain 增加 turn 终态枚举,时间线尾部展示"已中断/失败(原因)"。

### A4. `turn/start` 参数名 `reasoningEffort` vs 协议 `effort` —— ✅ 已完成(2026-07-08)

- `TurnStartParams` 的字段是 `effort`(`ReasoningEffort` 枚举)与 `summary`(`ReasoningSummary`);当前代码发送 `reasoningEffort`,推理力度选择可能根本没有生效(取决于服务端是否保留 serde 别名)。
- 修复:改为发送 `effort`;验证方式:启动真实 app-server,发送带 `effort` 的 turn 并比对 `thread/settings/updated` 或 turn_context。
- 已用真实 app-server(0.142.3)验证:`effort` 传非法类型会报反序列化错误(字段被识别),`reasoningEffort` 传非法类型被静默忽略(字段不被识别,无 serde 别名),证实旧参数名从未生效。

### A5. 未知服务端请求的兜底应答不安全 —— ✅ 已完成(2026-07-08)

- 现状:未知 method 一律 `approved → {}`、`denied → null`。
- 风险:`item/tool/call`(动态工具调用)与 `account/chatgptAuthTokens/refresh` 的响应有严格 schema,`{}`/`null` 属于非法应答,可能让服务端 turn 卡住或报协议错误。
- 修复:对未识别的服务端请求返回 JSON-RPC error(如 `-32601 method not found`),而不是伪造成功;为已知但暂不支持的请求返回结构化拒绝。
- 实施记录:
  - `_CodexApprovalMapper.rejectionFor` 对服务端请求分类:7 个可交互方法(5 个审批 + `item/tool/requestUserInput` + `mcpServer/elicitation/request`)进 UI 卡片;`item/tool/call`、`account/chatgptAuthTokens/refresh`、`attestation/generate` 与未知方法立即回 `-32601` JSON-RPC error(带定制 message),不再产生审批卡片,`_handleServerRequest` 记 warning 日志。
  - 修复输入类响应结构:`item/tool/requestUserInput` 统一回 `{answers: {}}`(schema 必填、协议无拒绝变体,表单收集 UI 属 3.8);`mcpServer/elicitation/request` 按决定回 `{action: accept, content: {}}` / `{action: decline}` / `{action: cancel}`。
  - `approvalResponse` 兜底分支不再返回 `null`,保留 `{}` 作为最后防线(分类改造后正常不可达)。
  - transport 无需改动:`JsonRpcPeer.sendResponse` 本就支持 `error: JsonRpcError`。
  - 测试:fake peer 新增 `errorResponses` 记录;覆盖未知方法/动态工具/token 刷新自动拒绝(无审批事件)、requestUserInput 空答案、elicitation 三种 action。

### A6. `initialize` 未声明 capabilities —— ✅ 已完成(2026-07-08)

- `InitializeParams.capabilities` 支持 `experimentalApi`、`optOutNotificationMethods`、`requestAttestation`、`mcpServerOpenaiFormElicitation`。
- 建议:显式声明 capabilities;用 `optOutNotificationMethods` 屏蔽当前不消费的高频通知(如 `thread/realtime/*`),减少 stdio 流量与解析开销;部分新 API(如动态工具)可能需要 `experimentalApi: true` 才会下发。
- 实施记录:
  - `initialize` 现在显式发送 `capabilities`:`experimentalApi: false`、`requestAttestation: false`、`mcpServerOpenaiFormElicitation: false`(表单渲染见 3.8),以及 `optOutNotificationMethods` 清单。
  - opt-out 清单只含近期路线图之外(P4~P5)的通知:`thread/realtime/*` 全部 8 个、`remoteControl/status/changed`、`app/list/updated`、`windows/worldWritableWarning`、`windowsSandbox/setupCompleted`、`model/safetyBuffering/updated`、`model/verification`、`turn/moderationMetadata`。Phase 1~3 计划消费的通知(reasoning/plan/diff、account、mcp、skills 等)不屏蔽;适配对应功能时需同步维护该清单(常量在 `codex_app_server_agent_provider.dart`)。
  - 已用真实 app-server(0.142.3)验证:完整 capabilities 握手成功;`capabilities`/`optOutNotificationMethods` 传非法类型报反序列化错误(字段被识别);功能对比实验确认 opt-out 后 `remoteControl/status/changed`、`thread/started` 等通知不再下发。
  - 测试:新增 `declares client capabilities during initialize`,断言三个布尔能力与 opt-out 清单,并守护已消费通知(`thread/tokenUsage/updated`、`turn/completed` 等)不得出现在清单中。

### A7. 未匹配通知静默丢弃,无可观测性

- default 分支直接丢弃,协议演进时无法感知遗漏。
- 修复:对未匹配 method 记 `fine` 级日志(带 method 名去重),开发期可开启"未知通知计数"诊断。

---

## 3. 未适配功能清单(按功能域分组)

图例:优先级 P0(正确性)/ P1(核心体验)/ P2(会话管理)/ P3(账户配置生态)/ P4(高级能力)/ P5(暂缓)。
"落点"指主要修改文件;domain 事件均指 `lib/src/features/agent/domain/agent_event_models.dart` 及相邻模型文件。

### 3.1 Turn 级流式体验(P1)

| 能力 | 协议方法/通知 | 结构要点 | 建议落点与做法 | 优先级 |
| --- | --- | --- | --- | --- |
| 实时推理流(思考过程) | `item/reasoning/textDelta`、`item/reasoning/summaryTextDelta`、`item/reasoning/summaryPartAdded` | `{ threadId, turnId, itemId, delta }`;summary 分段 | 新增 `AgentReasoningDeltaEvent`;timeline store 将 delta 聚合到 reasoning 卡片(现在 reasoning 只有历史回放,实时全丢) | P1 |
| Plan 文本流式 | `item/plan/delta` | plan item 的增量文本 | 复用消息 delta 通道,`plan` item 支持流式渲染 | P1 |
| Turn 级聚合 diff | `turn/diff/updated` | `{ threadId, turnId, diff }` 全 turn 统一 diff | 新增 `AgentTurnDiffEvent`;Agent pane 增加"本回合改动"折叠 diff 视图 | P1 |
| 线程运行状态细化 | `thread/status/changed` | `ThreadStatus = notLoaded/idle/active{waitingOnApproval, waitingOnUserInput}/systemError` | 映射到 `AgentThreadRuntimeStatus`(已有枚举,补 waiting 标志);状态胶囊展示"等待审批/等待输入" | P1 |
| 审批请求被他端解决 | `serverRequest/resolved` | `{ requestId, threadId }` | provider 移除 `_pendingApprovals[requestId]` 并发事件让 UI 关闭审批卡(多客户端/daemon 场景必备) | P1 |
| MCP 工具进度 | `item/mcpToolCall/progress` | 进度消息 | 更新对应工具卡片 content | P1 |
| 模型改道提醒 | `model/rerouted` | 模型被服务端切换 | 以系统事件插入时间线 + 状态栏提示 | P1 |
| 弃用警告 | `deprecationNotice` | API 弃用信息 | 记日志 + 一次性系统提示,提示升级适配层 | P1 |
| item 类型全覆盖 | `item/started` / `item/completed` 中的 `ThreadItem` | 协议共 18 种:已识别 8 种;缺 `webSearch`、`imageGeneration`、`imageView`、`collabAgentToolCall`、`subAgentActivity`、`enteredReviewMode`、`exitedReviewMode`、`contextCompaction`、`hookPrompt`、`sleep` | 扩展 `_normalizedAgentItemType` 与 `_toolKind`;`webSearch → AgentToolKind.search`、`imageGeneration/imageView → fetch/other`、review/compaction → 系统事件条目 | P1 |
| 命令输出终端交互 | `item/commandExecution/terminalInteraction` | 命令要求终端交互 | 至少映射为工具卡片提示"命令等待终端输入",配合 P4 终端能力完善 | P2 |
| 自动审批评审指示 | `item/autoApprovalReview/started` / `completed` | guardian 自动评审状态 | 审批卡片显示"自动评审中/结果" | P2 |

### 3.2 输入能力(多模态与富输入,P1~P2)

`turn/start.input: UserInput[]` 协议支持 5 种,当前只发 `text`:

| 输入类型 | 协议结构 | 建议做法 | 优先级 |
| --- | --- | --- | --- |
| `localImage` | `{ type: localImage, path, detail? }` | 输入框支持粘贴/拖拽图片,落盘临时文件后随 turn 发送 | P1 |
| `image` | `{ type: image, url, detail? }` | 支持粘贴远程图片 URL | P2 |
| `mention` | `{ type: mention, name, path }` | @文件引用;可先用本地文件树实现选择器,后续接 `fuzzyFileSearch` | P2 |
| `skill` | `{ type: skill, name, path }` | 依赖 `skills/list`(见 3.8) | P4 |
| `text.text_elements` | 文本内嵌特殊 span(mention 渲染元数据) | 与 mention 一起做 | P2 |

`turn/start` 其余未用参数:

| 参数 | 用途 | 优先级 |
| --- | --- | --- |
| `effort` / `summary` | 推理力度与推理摘要模式覆盖(A4 修复后自然获得) | P0 |
| `clientUserMessageId` | 客户端幂等 id,防重发 | P2 |
| `sandboxPolicy` / `approvalPolicy` | 每回合沙箱/审批策略(UI 提供模式切换:只读/工作区可写/全权限) | P2 |
| `personality` | 回复风格 | P4 |
| `outputSchema` | 最后一条消息的 JSON Schema 约束(自动化场景) | P4 |
| `approvalsReviewer` | 审批评审者(guardian 集成) | P4 |

`thread/start` / `thread/resume` 未用参数:`developerInstructions`、`baseInstructions`、`config`(每线程 config 覆盖)、`ephemeral`(临时会话不落盘)、`sandbox`、`personality`、`modelProvider`、`threadSource`。建议 P2 起在"新建会话"入口暴露 sandbox/approval 预设,其余按需。

### 3.3 Thread 生命周期管理(P2)

当前 `AgentProvider` 接口完全没有这些能力,需同步扩展 domain 接口 + UI(thread 列表右键菜单/详情页):

| 能力 | 请求 | 配套通知 | 说明 | 优先级 |
| --- | --- | --- | --- | --- |
| 重命名 | `thread/name/set { threadId, name }` | `thread/name/updated` | 列表内联重命名 | P2 |
| 归档/取消归档 | `thread/archive` / `thread/unarchive` | `thread/archived` / `thread/unarchived` | `thread/list` 增加 archived 视图切换 | P2 |
| 删除 | `thread/delete` | `thread/deleted` | 危险操作需确认对话框 | P2 |
| 分叉 | `thread/fork { threadId, ... }` | — | 从既有会话分叉出新会话(与 UI"从此处新开分支"结合) | P2 |
| 回滚 | `thread/rollback { threadId, numTurns }` | — | 支撑"编辑上一条消息/重试"体验的基础 | P2 |
| 压缩上下文 | `thread/compact/start { threadId }` | `thread/compacted` | 上下文接近上限时(配合 A1 的 `modelContextWindow`)提示一键压缩 | P2 |
| 设置变更同步 | — | `thread/settings/updated` | 服务端/他端修改 model、approvalPolicy 后同步 UI 选择器 | P2 |
| 线程被关闭 | — | `thread/closed` | 释放本地运行状态 | P2 |
| 取消订阅 | `thread/unsubscribe { threadId }` | — | 切换会话时取消旧订阅,减少无关通知(当前切换后旧 thread 通知仍会到达) | P1 |
| 已加载线程列表 | `thread/loaded/list` | — | daemon/多窗口场景查询服务端已加载线程 | P3 |
| 元数据更新 | `thread/metadata/update` | — | 写入自定义元数据 | P3 |
| 列表增强 | `thread/list` 的 `searchTerm`、`archived`、`modelProviders`、`useStateDbOnly` | — | thread 面板搜索框、归档筛选 | P2 |
| Guardian 放行 | `thread/approveGuardianDeniedAction` | — | guardian 拒绝后的人工放行入口 | P3 |

### 3.4 审批与用户输入深化(P2)

| 能力 | 协议 | 现状与差距 | 优先级 |
| --- | --- | --- | --- |
| 结构化用户提问表单 | `item/tool/requestUserInput`(服务端请求) | 现在直接回默认空答案;协议里有 questions 列表(id/header/question/options),应渲染成表单卡片并回传答案 | P2 |
| MCP elicitation 表单 | `mcpServer/elicitation/request` | 同上,协议携带 JSON Schema 表单定义(`requestedSchema`),需动态表单渲染 | P3 |
| 审批策略预设 | `permissionProfile/list` | 未接;可用来渲染标准的审批/沙箱组合选择器(与 codex TUI 一致) | P2 |
| 细粒度审批策略 | `AskForApproval` 的 `granular` 变体 | 当前只发 `on-request` 字符串;granular 支持 mcp_elicitations/rules/sandbox_approval/skill_approval 独立开关 | P4 |
| 命令审批的完整上下文 | `CommandExecutionRequestApprovalParams` | 协议含 `commandActions`(解析后的命令语义)、`proposedExecpolicyAmendment`(建议的白名单规则,回应时可带 `execpolicy_amendment` 持久化"总是允许") | P2 |

### 3.5 账户与认证(P3)

当前完全未适配,依赖用户预先在终端 `codex login`。落点:新增 `features/agent/data` 的 account 客户端 + `settings` 类 UI。

| 能力 | 协议 | 说明 |
| --- | --- | --- |
| 读取账户状态 | `account/read` | 启动后检测未登录 → 引导登录,而不是报一堆 stderr |
| 登录 | `account/login/start`(`apiKey` / `chatgpt` / `chatgptDeviceCode` 变体)、`account/login/cancel`、通知 `account/login/completed` | ChatGPT 登录会返回授权 URL,需要打开浏览器并等待完成通知 |
| 登出 | `account/logout` | — |
| 账户变化 | `account/updated`(通知) | 计划类型/登录方式变化时刷新 |
| 限额 | `account/rateLimits/read` + `account/rateLimits/updated`(通知) | 状态栏用量表(5h/周限额、重置时间) |
| 用量 | `account/usage/read` | 用量明细页 |
| ChatGPT token 刷新 | `account/chatgptAuthTokens/refresh`(服务端请求) | 服务端主动要求客户端提供新 token 的场景,先按结构化拒绝处理并记日志,接入托管登录后实现 |
| 暂缓 | `account/rateLimitResetCredit/consume`、`account/sendAddCreditsNudgeEmail`、`account/workspaceMessages/read` | 第一方商业化功能,对 Zeta 价值低 |

### 3.6 配置与模型能力(P3)

| 能力 | 协议 | 说明 |
| --- | --- | --- |
| 读全局配置 | `config/read`(含 effective config 分层) | 设置页展示生效配置及来源 |
| 写配置 | `config/value/write`、`config/batchWrite` | 设置页编辑 `~/.codex/config.toml`(模型默认值、审批默认值等) |
| 配置要求 | `configRequirements/read` | 企业托管约束,设置页只读展示 |
| 模型 provider 能力 | `modelProvider/capabilities/read` | 决定是否显示 reasoning effort/serviceTier 选择器,替代现在的硬编码 |
| 配置告警 | `configWarning` 已接,但建议区分启动期一次性告警与运行期告警 | — |

### 3.7 MCP 生态(P3)

| 能力 | 协议 | 说明 |
| --- | --- | --- |
| MCP 服务器状态面板 | `mcpServerStatus/list` + 通知 `mcpServer/startupStatus/updated`(现在被显式忽略) | 展示每个 MCP server 启动状态/工具数;失败给出重载入口 |
| 重载 MCP 配置 | `config/mcpServer/reload` | 修改配置后热重载 |
| MCP OAuth 登录 | `mcpServer/oauth/login` + 通知 `mcpServer/oauthLogin/completed` | 需要浏览器跳转的 MCP 鉴权 |
| 直接调用 MCP 工具 | `mcpServer/tool/call` | 调试面板用,非核心 |
| 读取 MCP 资源 | `mcpServer/resource/read` | 同上 |

### 3.8 Review 模式与代码评审(P4)

| 能力 | 协议 | 说明 |
| --- | --- | --- |
| 发起评审 | `review/start { threadId, target, delivery }`;`ReviewTarget` 支持 `uncommittedChanges` / `baseBranch{branch}` / `commit{sha}` / 自由指令 | UI:在 thread 内提供"Review 未提交改动/对比分支"入口 |
| 评审过程渲染 | thread item `enteredReviewMode` / `exitedReviewMode`(含结构化 findings) | 时间线渲染评审区块与 finding 列表 |

### 3.9 终端与进程(P4)

独立于 turn 的命令执行通道(为"IDE 内终端"预留):

- 请求:`command/exec`(启动)、`command/exec/write`(stdin)、`command/exec/resize`、`command/exec/terminate`;
- 通知:`command/exec/outputDelta`(已作为 turn 内进度复用)、`process/outputDelta`、`process/exited`;
- `thread/shellCommand`:在 thread 的沙箱/审批上下文中由用户直接执行命令(输出会进入会话历史)。

### 3.10 文件系统与搜索(P4,仅远程场景必要)

`fs/readFile`、`fs/writeFile`、`fs/readDirectory`、`fs/getMetadata`、`fs/copy`、`fs/remove`、`fs/createDirectory`、`fs/watch`、`fs/unwatch` + 通知 `fs/changed`;`fuzzyFileSearch` + `fuzzyFileSearch/sessionUpdated` / `sessionCompleted`。

- Zeta 当前文件树是本地直读,单机 stdio 场景无需 fs/*;
- 一旦支持 `--listen ws://`/daemon 远程连接(见 3.12),文件树与 @mention 搜索应切换到这组 RPC;
- `fuzzyFileSearch` 短期也可用于 @mention(即使本地场景,复用服务端 fuzzy 排序)。

### 3.11 Skills / Hooks / 动态工具(P4)

| 能力 | 协议 | 说明 |
| --- | --- | --- |
| Skills 列表与注入 | `skills/list`、`skills/config/write`、`skills/extraRoots/set`、通知 `skills/changed`;输入类型 `skill` | 输入框 "/skill" 选择器 |
| Hooks | `hooks/list`、通知 `hook/started` / `hook/completed`;item `hookPrompt` | 时间线显示 hook 执行状态 |
| 动态工具(客户端注册工具) | 服务端请求 `item/tool/call`(`DynamicToolCallParams { tool, arguments, callId }`);item `dynamicToolCall` | 允许 Zeta 向模型暴露 IDE 能力(打开文件、跳转等);需调研注册方式(疑似 `thread/start.config` 或 experimental capability);A5 已完成,未注册时收到 `item/tool/call` 会回 `-32601` 拒绝 |

### 3.12 运行形态与其他(P4~P5)

| 能力 | 协议 | 建议 |
| --- | --- | --- |
| daemon / 远程连接 | CLI `codex app-server daemon`、`--listen ws://`、`unix://`;通知 `remoteControl/status/changed` | 传输层已抽象 `JsonRpcPeer`,可加 WebSocket transport;P4 调研 |
| 会话目标(goal) | `thread/goal/set` / `get` / `clear` + 通知 `thread/goal/updated` / `cleared` | 会话目标横幅;P4 |
| 注入历史条目 | `thread/inject_items` | 把 IDE 侧上下文(如诊断信息)注入会话;P4 |
| 外部 agent 配置导入 | `externalAgentConfig/detect` / `import` / `import/readHistories` + 进度通知 | 从 Claude Code 等导入配置/历史;P5 |
| 实时语音 | `thread/realtime/*`(8 个通知) | 桌面语音会话;P5,建议 `optOutNotificationMethods` 屏蔽 |
| Windows 沙箱安装 | `windowsSandbox/readiness` / `setupStart` + 完成通知、`windows/worldWritableWarning` | 项目支持 windows 目标,发布 Windows 版前做;P5 |
| Apps / 插件 / 市场 | `app/list`(+`app/list/updated`)、`plugin/*`(10 个)、`marketplace/*`(3 个) | Codex 插件生态,待其稳定后评估;P5 |
| 反馈上传 | `feedback/upload` | P5 |
| 实验特性开关 | `experimentalFeature/list` / `enablement/set` | 开发者设置页;P5 |
| 证明/攻击面 | `attestation/generate`(服务端请求,需 capability opt-in) | 不 opt-in 即不会收到;P5 |
| 安全缓冲/验证通知 | `model/safetyBuffering/updated`、`model/verification`、`turn/moderationMetadata` | 记日志即可;P5 |

---

## 4. 分阶段适配计划

每个阶段保持"domain 契约 → data 适配 → application/presentation 消费 → 测试"同步推进;所有新增通知映射必须带 fixture 单测(参考 `test/src/features/agent/data/datasources/app_server/codex_app_server_provider_test.dart` 的 fake peer 模式)。

### Phase 0:协议对齐审计(约 3~5 个工作日)

目标:**修复静默失效,建立协议同步机制。**不新增用户可见功能。

| # | 任务 | 落点 |
| --- | --- | --- |
| 0.1 ✅ | `thread/tokenUsage/updated` 适配,camelCase 解析,携带 `modelContextWindow`;旧 tokenCount case 保留为容错(已完成,含 `thread/read` 嵌套结构兼容与新增单测) | `codex_notification_mapper.dart`、`agent_turn_history_models.dart`(补 `modelContextWindow` 字段) |
| 0.2 ✅ | `error` 通知按 `{error: TurnError, willRetry}` 解析;`AgentErrorEvent` 增加 `code`(codexErrorInfo)与 `willRetry`(已完成,顺带修复 `configWarning` 读 `summary` 字段,view model 对 willRetry 附加自动重试提示) | mapper + `agent_event_models.dart` + timeline store 错误卡片 |
| 0.3 ✅ | `turn/completed` 消费 `turn.status` / `turn.error` / `durationMs`;区分 completed/interrupted/failed(已完成:`AgentHistoryTurnStatus` 增加 interrupted/failed 终态,分隔线展示 `Interrupted/Failed · 耗时`,失败原因插入回合分组并与 error 通知去重) | mapper + `AgentTurnCompletedEvent` 扩展 + UI 终态样式 |
| 0.4 ✅ | `turn/start` 参数 `reasoningEffort` → `effort`,补发 `summary`(可选)(已完成:改发 `effort` 并经真实 app-server 验证;`summary` 暂无 UI 来源,不发送) | `codex_app_server_client.dart` |
| 0.5 ✅ | 未知服务端请求返回 JSON-RPC error 而非 `{}`/`null`;`item/tool/call`、`account/chatgptAuthTokens/refresh` 显式结构化拒绝(已完成:`rejectionFor` 分类 + `-32601` 应答,顺带修复 requestUserInput/elicitation 响应结构;transport 的 `sendResponse(error:)` 原生支持,无需改动) | `codex_approval_mapper.dart`、`codex_app_server_agent_provider.dart` |
| 0.6 ✅ | `initialize` 声明 capabilities;`optOutNotificationMethods` 屏蔽 `thread/realtime/*` 等(已完成:显式声明三个布尔能力为 false + 15 个 P4~P5 通知 opt-out,经真实 app-server 验证通知确实被抑制) | provider |
| 0.7 | 未匹配通知记录日志(去重);新增开发诊断计数 | provider |
| 0.8 | 建立协议同步机制:`tool/` 下加脚本调用 `codex app-server generate-json-schema`,在 `docs/` 记录 pinned codex 版本;协议升级时 diff schema | 新增 `tool/gen_codex_schema.sh` + 文档 |

验收标准:真实 `codex app-server` 冒烟(发一条消息)可看到 token 用量更新;人为断网可看到带错误码的错误卡片;`turn/interrupt` 后时间线显示"已中断";全部现有测试通过 + 新增 fixture 测试。

### Phase 1:核心流式体验(约 1.5~2 周)

目标:**与 codex TUI 对齐的实时观感。**

| # | 任务 | 落点 |
| --- | --- | --- |
| 1.1 | reasoning 三通知 → `AgentReasoningDeltaEvent`;timeline"思考中"卡片流式展开 | mapper、domain、timeline store、agent pane |
| 1.2 | `item/plan/delta` 流式 plan | 同上 |
| 1.3 | `turn/diff/updated` → 回合级 diff 视图 | 新 `AgentTurnDiffEvent`;复用现有 diff 渲染组件 |
| 1.4 | `thread/status/changed` → 状态胶囊(等待审批/等待输入) | mapper、`agent_thread_models.dart`、状态胶囊组件 |
| 1.5 | `serverRequest/resolved` → 自动撤销审批卡片 | provider(`_pendingApprovals` 清理)+ 新事件 + timeline store |
| 1.6 | `item/mcpToolCall/progress` 工具卡进度 | mapper |
| 1.7 | `model/rerouted`、`deprecationNotice` 系统提示 | mapper + 系统事件条目 |
| 1.8 | `item/started|completed` 覆盖全部 18 种 ThreadItem(webSearch/imageGeneration/review/compaction 等) | `codex_app_server_helpers.dart`(类型归一化、工具分类)+ 历史 reader 同步 |
| 1.9 | 切换会话时调用 `thread/unsubscribe` | client、provider、view model |
| 1.10 | 输入框支持本地图片(`localImage`)发送 | `AgentProvider.sendMessage` 签名扩展(输入项列表)、client、composer UI |

验收标准:真实会话中可见流式思考、流式 plan、回合 diff;审批在另一客户端处理后本端卡片自动消失;粘贴图片可发送并出现在历史里。

### Phase 2:Thread 管理与审批深化(约 2 周)

| # | 任务 | 落点 |
| --- | --- | --- |
| 2.1 | `AgentProvider` 接口扩展:rename/archive/unarchive/delete/fork/rollback/compact | `agent_provider.dart` + client + provider |
| 2.2 | thread 列表右键菜单与归档视图(`thread/list archived:true`、`searchTerm` 搜索框) | `project_threads` feature + agent feature |
| 2.3 | 配套通知(`thread/archived|unarchived|deleted|closed|name/updated|compacted|settings/updated`)→ 列表与会话状态同步 | mapper + threads controller |
| 2.4 | 基于 `thread/rollback` + `thread/fork` 实现"编辑消息重试 / 从此处分叉" | conversation view model + UI |
| 2.5 | 上下文用量接近 `modelContextWindow` 时提示 `thread/compact/start` | timeline store + 状态条 |
| 2.6 | `item/tool/requestUserInput` 表单卡片(问题列表 + 选项 + 自由文本),答案结构化回传 | approval mapper(响应编码)、新表单组件 |
| 2.7 | `permissionProfile/list` 驱动审批/沙箱预设选择器;`turn/start` 携带所选 `approvalPolicy`/`sandboxPolicy` | client、model selection controller 同级新 controller、composer 设置弹层 |
| 2.8 | 命令审批卡片增强:展示 `commandActions` 语义、支持 `execpolicy_amendment`("总是允许此命令") | approval mapper、审批卡片 |
| 2.9 | `item/autoApprovalReview/*` 指示器;`thread/approveGuardianDeniedAction` 放行入口 | mapper + UI |
| 2.10 | `clientUserMessageId` 幂等、mention 输入(`mention` + `text_elements`,选择器先用本地文件树) | client、composer |

验收标准:可在 UI 完成重命名/归档/删除/分叉/回滚全流程;`request_user_input` 出表单且回答被模型接收;审批模式切换后新 turn 生效。

### Phase 3:账户、配置与 MCP 生态(约 2 周)

| # | 任务 | 落点 |
| --- | --- | --- |
| 3.1 | `account/read` 启动检测;未登录时引导页 | 新 `features/agent` account 子模块或独立 feature |
| 3.2 | `account/login/start`(chatgpt: 打开浏览器等 `account/login/completed`;apiKey:表单)+ cancel/logout + `account/updated` | 同上 |
| 3.3 | `account/rateLimits/read` + `updated` → 状态栏用量表;`account/usage/read` 用量页 | 同上 + 状态栏 |
| 3.4 | `account/chatgptAuthTokens/refresh` 服务端请求实现(托管 token 场景) | approval mapper 旁新增 account request handler |
| 3.5 | `config/read` / `config/value/write` / `config/batchWrite` 设置页;`configRequirements/read` 只读展示 | 新 settings feature |
| 3.6 | `modelProvider/capabilities/read` 驱动模型选择器能力开关 | model selection controller |
| 3.7 | MCP 面板:`mcpServerStatus/list`、启用 `mcpServer/startupStatus/updated`(撤销显式忽略)、`config/mcpServer/reload`、`mcpServer/oauth/login` + completed 通知 | 新 MCP 状态面板 |
| 3.8 | `mcpServer/elicitation/request` 按 `requestedSchema` 动态渲染表单 | 复用 2.6 的表单基建 |
| 3.9 | `thread/loaded/list`、`thread/metadata/update` | client |

验收标准:全新机器上不用终端即可完成登录并开始对话;设置页可改默认模型/审批策略并立即生效;MCP server 状态可见且可重载。

### Phase 4:高级能力(按需排期)

- Review 模式:`review/start` + `enteredReviewMode`/`exitedReviewMode` 渲染(评审 findings 列表)。
- 终端套件:`command/exec` 四件套 + `process/*` + `item/commandExecution/terminalInteraction`;`thread/shellCommand`。
- `fuzzyFileSearch`(+ 两个通知)接管 @mention 搜索。
- Skills:`skills/list` + `skill` 输入 + `skills/changed`;Hooks:`hooks/list` + `hook/*` 通知 + `hookPrompt` item。
- 动态工具:调研注册途径(疑似需 `experimentalApi`),实现 `item/tool/call` 应答,把 IDE 能力(打开文件、读取诊断)暴露给模型。
- `thread/goal/*`、`thread/inject_items`。
- WebSocket/daemon transport(`--listen ws://` + `codex app-server daemon`),为远程与多窗口铺路;届时补 `fs/*` 与 `fs/changed`。

### Phase 5:暂缓项(明确不做,直到有真实需求)

`thread/realtime/*`(语音)、`windowsSandbox/*` 与 `windows/worldWritableWarning`(Windows 发布前)、`plugin/*`、`marketplace/*`、`app/list`、`externalAgentConfig/*`、`feedback/upload`、`attestation/generate`、`account/rateLimitResetCredit/consume`、`account/sendAddCreditsNudgeEmail`、`account/workspaceMessages/read`、`experimentalFeature/*`、`remoteControl/status/changed`、`model/safetyBuffering/updated`、`model/verification`、`turn/moderationMetadata`。

理由:或属第一方商业化/实验功能,或依赖尚未规划的运行形态(语音、远程、Windows 发布、插件生态)。统一先做到"收到即记日志、不误应答"(Phase 0.5/0.7 覆盖)。

---

## 5. 横切工程事项

1. **协议版本锁定**:适配层按 `codex-cli 0.142.3` schema 开发;`tool/gen_codex_schema.sh` 输出纳入 review 流程,升级 codex 时先 diff schema 再动代码。
2. **domain 事件演进**:新增事件一律走 `agent_event_models.dart` 的 sealed 层次,禁止在 presentation 里读 raw 协议字段;raw payload 仅存 `raw` 字段用于诊断。
3. **测试策略**:
   - 每个新通知/请求映射:fixture JSON → mapper 单测(Arrange-Act-Assert);
   - provider 级:fake `JsonRpcPeer` 集成测试(复用现有 `codex_app_server_provider_test.dart` 基建);
   - 阶段收尾:真实 `codex app-server --stdio` 冒烟清单(手动或 integration test)。
4. **历史与实时一致性**:每次新增实时 item 类型,同步检查 `codex_jsonl_history_parser.dart` 与 `thread/read` 映射,保证刷新/重开会话后渲染一致。
5. **文档同步**:每阶段完成后更新 `docs/design_document.md`(Agent 设计节)与本计划的状态标记。

## 6. 附录:决策快查

- 想知道某个方法当前状态 → 第 1 节(已适配)/ 第 3 节(未适配,含优先级)。
- 想知道"为什么 token/错误显示不对" → 第 2 节审计项 A1/A2/A3。
- 想排期 → 第 4 节 Phase 0~5,建议顺序执行 Phase 0 → 1 → 2,Phase 3 起可按产品优先级调整。
