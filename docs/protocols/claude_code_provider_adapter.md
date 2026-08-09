# Claude Code Provider 接入适配文档

> 目的：将 Anthropic 的 Claude Code CLI 作为 **第三个** Agent Provider 接入
> Zeta（与 Codex app-server、Grok ACP 并列），复用 `~/.claude` 已登录态，覆盖
> 基础对话 / 工具时间线 / 权限审批 / Plan 审批 / 会话历史 / 模型目录 /
> MCP·hooks 透传等能力。本文档同时作为落地任务清单与评审基线。
>
> **约束基线**：本文档不重复 `CLAUDE.md`、`AGENTS.md`、
> `docs/guides/developer_guide.md` 已固化的规则。凡涉及事件管线、共享适配层、feature
> 目录约束、Git 提交格式的部分，仍以那三份文档为准。发生冲突时，本文档服从
> 上述权威文档，同时在此登记差异并触发同步修订。

## 0. 决策速览

| 决策项 | 结论 | 依据 |
| --- | --- | --- |
| 接入形态 | Claude Code CLI 常驻子进程，`--print --input-format stream-json --output-format stream-json --verbose` | 与现有 Codex/Grok stdio 模型同构；零 SDK/Node 依赖；官方稳定支持（备选方案对比见 §0.1） |
| 认证 | 复用 `claude` 已登录态（`~/.claude/.credentials.json` / OAuth cache），Zeta 只做检测 | 与 Codex/Grok 一致；避免重复实现 login |
| 上架方式 | 独立第 3 个 Provider（`AgentProviderKind.claudeCode`） | 骨架已预留：枚举、`defaultsFor`、`DefaultAgentProviderFactory` 均已留分支 |
| MVP 能力 | 对话/工具 + 权限审批 + Plan 审批 + 会话历史/resume + 模型目录 + 账号套餐用量 + MCP/hooks 透传 | 与用户澄清结论一致 |
| Default provider | 保持 Codex 为默认，Claude Code 与 Grok 一样是可选项 | 降低回滚风险；`AgentDefinition.all` 追加即可 |
| 数据边界 | 严禁读写 `~/.claude` 之外的 Claude 状态；Zeta 自有数据仍在 `~/.zeta/` | 与 CLAUDE.md「持久化」条款一致 |
| 模型列表数据源 | 动态优先：`GET /v1/models`（本机 OAuth accessToken）；失败/关闭增强开关时静态目录兜底 | Claude Code 无 `model list` 子命令，stream-json 也不带结构化 catalog；直接 REST 是唯一结构化来源（§2.4、§4.10） |
| 套餐用量数据源 | `GET /api/oauth/usage`（同一 accessToken），实现既有 `AgentUsageQuotaProvider` 接口 | 五小时/周限额无法从 stream-json 拿到；接口对高频调用敏感需节流（§4.11） |
| 账号数据增强开关 | 默认开启，设置页可关闭；关闭后模型目录回退静态、套餐面板隐藏 | 这是本文档唯一「绕开 CLI 子进程、直接用本机 OAuth 凭证发 REST」的路径，需可关闭以降低合规/风控顾虑（§7.2、§10） |

### 0.1 备选接入方式全景对比（本次评审新增）

> 为便于评审追溯上表「接入形态」一行的取舍依据，本节列出基于 Claude Code
> 现行文档体系（CLI / Agent SDK / 第三方 ACP 桥接 / 云端托管面）调研过的全部
> 接入路径，逐项给出优缺点。除方式 A 外均为**不采用**，供二期重估时参考；
> 结论不改变 §0 决策速览的既定结果。

| 接入方式 | 技术形态摘要 | 结论 |
| --- | --- | --- |
| A. CLI 常驻子进程 + stream-json 交互输入 | `claude --print --input-format stream-json --output-format stream-json`，进程常驻，双向行分隔 JSON | **已选**（见 §0 决策速览） |
| B. CLI 单次调用 / headless 非交互模式 | 每次 `-p`/`--print` 单条 prompt，靠 `--continue`/`--resume` 续接磁盘 session，无常驻管道 | 不适用于交互式会话；二期可评估批处理场景 |
| C. Claude Agent SDK（TypeScript / Python） | 官方 SDK，底层仍是「spawn 一个 claude 子进程走 stdio」，SDK 包自带原生 CLI 二进制 | 不采用，违反零 Node/Python 依赖判据 |
| D. 社区 ACP 桥接（如 `claude-code-acp` / `claude-agent-acp`） | Zed 团队维护，封装官方 TS SDK，对外暴露标准 Agent Client Protocol | 不采用，非 Anthropic 官方维护 + 额外 Node 依赖 |
| E. Claude Code 作为 MCP Server（反向集成） | 让 Claude Code 反过来给 Codex/其他 Agent 提供工具，而非作为独立 Provider | 不适用，集成方向相反 |
| F. 云端 / CI 托管面（Claude Code on the web、GitHub/GitLab CI、Slack、Claude Tag） | 会话跑在 Anthropic 云端或 CI runner 上，状态不落在本机 `~/.claude` | 不适用，交互模型与数据边界都对不上 |

#### A. CLI 常驻子进程 + stream-json（已选）

优点：

- 与 Codex app-server、Grok ACP 现有 stdio 架构同构，只需新增
  `StreamJsonPeer` 这一层 transport（§4.1），不用改共享管线；
- 复用 `~/.claude` 已登录态，不强制切到 API Key；
- 官方文档把「持续会话 + 消息排队 + 实时中断 + 权限/Plan 反向请求」的模式
  列为推荐用法，覆盖 MVP 能力清单最完整；
- 不引入 Node.js / Python 运行时依赖。

缺点：

- stream-json 是 Claude Code 私有协议，官方未做版本承诺，CLI 升级可能
  变更事件形状（已登记在 §10 风险表，靠 mapper 对未知 `type` 兜底丢弃缓解）；
- 要求用户本机已安装并登录 Claude Code CLI，Zeta 不能代为登录；
- 新协议能力（比如新版本才有的 hook/事件类型）需要自行跟进 mapper，无法
  像官方 SDK 那样随版本自动继承。

#### B. CLI 单次调用 / headless 非交互模式

优点：

- 实现最简单，不用管理长生命周期子进程和 stdin 写队列；
- 适合「一次性任务」场景，比如未来的批处理式代码审查；
- `--bare` 参数可跳过 hooks/skills/plugins/MCP/CLAUDE.md 的自动发现，
  启动更快，适合不需要完整上下文加载的轻量调用。

缺点：

- 不支持消息排队、实时中断、图片直传等——这些正是官方文档中明确写出
  「Single Message 模式不具备」的能力，MVP 要求的实时工具时间线体验做不到；
- 权限反向询问机制依赖长连接会话；单次调用场景基本只能预先固定
  `--permission-mode`，实现不了「每次弹审批弹窗」（Ask 模式）；
- 多轮对话退化成「重启进程 + 磁盘续接」（`--continue`/`--resume`），
  时延和资源开销都比常驻进程高；
- `--bare` 快速模式不读订阅登录态、也不读 OAuth 凭证或系统 keychain，
  必须显式配置 `ANTHROPIC_API_KEY`，与 §7.2 认证策略「复用已登录态优先」
  的姿态冲突。

#### C. Claude Agent SDK（TypeScript / Python）

优点：

- 官方维护，类型化消息、Hook 回调（`canUseTool`）、Subagent、Skills、
  Session 持久化（`SessionStore` 适配器）等能力比裸协议更完整，且随官方
  版本自动演进；
- SDK 包自带绑定的原生 Claude Code 二进制，理论上不需要用户机器单独装 CLI。

缺点：

- 只有 TS / Python 两种语言绑定，Zeta 是 Dart/Flutter 技术栈，接入必须
  额外内嵌 Node.js 或 Python 运行时并做跨语言桥接（FFI/IPC），直接违反
  决策速览「零 SDK/Node 依赖」的既定判据，且与 Codex/Grok 的 stdio 架构
  不同构，等于第三套技术栈；
- 官方明确建议第三方产品走 API Key 认证，而不是复用交互式 `claude login`
  的订阅态登录，这与「检测并复用 `~/.claude` 已登录态」的现有策略存在
  潜在冲突，需要额外合规确认；
- 底层本质仍是「spawn 子进程走 stdio」，并没有绕开协议稳定性问题，只是
  把风险转移给了 SDK 维护方。

#### D. 社区 ACP 桥接（如 `claude-code-acp` / `claude-agent-acp`）

优点：

- 协议本身是有版本号的标准 Agent Client Protocol，比 Claude 私有
  stream-json 的「无版本承诺」更可控；
- 理论上可以直接复用 Zeta 现有 Grok Provider 的 `JsonRpcPeer` 传输层和
  部分权限模型代码，新增代码量可能是几种方案里最小的。

缺点：

- 不是 Anthropic 官方产品，是 Zed 团队基于官方 TS SDK 封装的开源桥接，
  功能对齐落后于 Claude Code 原生 CLI（官方博客明确提到不少内置 slash
  command 尚未被适配层覆盖）；
- 底层仍要跑 Node.js + npm 包，同样违反零 Node 依赖判据；
- 多一跳中间进程（Zeta → 桥接进程 → SDK → CLI 子进程），增加延迟和故障
  面；桥接层的修复节奏不受 Anthropic 控制；
- 认证方式由桥接层自行处理（自带登录/计费），与 Zeta 现有「仅 stat
  `~/.claude` 凭证文件」的探测逻辑（§7.1）不一定兼容。

#### E. Claude Code 作为 MCP Server（反向集成）

优点：让已接入的 Codex/Grok Provider 需要借用 Claude Code 能力时可以把它
当工具调用，不用新增 Provider 抽象。

缺点：与本文档目标——让用户在 UI 里把 Claude Code 选作一个独立的、拥有
自己对话时间线/权限/Plan/历史的 Agent Provider——方向相反，无法满足核心
诉求。

结论：不适用；可作为 §11「MCP 透传」二期方向的延伸，单独立项评估，不
影响本次接入。

#### F. 云端 / CI 托管面

Claude Code on the web、GitHub Actions、GitLab CI/CD、Slack、Claude Tag
等都是官方支持的「离开终端也能跑」接入面，但会话状态在 Anthropic 云端或
CI runner 上，不落在本机 `~/.claude`，认证、数据边界、「本地文件系统直接
读写」的交互模型都要整套重做，且做不到 Zeta 需要的实时权限/Plan 审批体验。
不适用，超出本次接入范围。

## 1. 当前 Provider 全景

### 1.1 已接入 Provider 能力对齐表

| 能力 (`AgentProviderCapabilities`) | Codex app-server | Grok ACP | Claude Code（目标） |
| --- | :-: | :-: | :-: |
| canCreateSession | ✅ | ✅ | ✅ |
| canResumeSession | ✅ | ✅ | ✅（`--resume <session-id>`） |
| canListThreads / canReadHistory | ✅ | ✅ | ✅（读 `~/.claude/projects/<encoded-cwd>/*.jsonl`） |
| canRenameThread | ✅ | ✅ | ⚠️ 本地重命名（只写 Zeta 侧索引，不改 Claude 文件） |
| canArchiveThread / canUnarchiveThread | ✅ | ❌ | ❌（Claude Code 无归档语义） |
| canDeleteThread | ✅ | ✅ | ⚠️ 仅 `removeThreadFromList`（不删 Claude jsonl；UI 明示保留） |
| canForkThread / canForkThreadAtTurn | ✅ / 动态 | ❌ | ⚠️ MVP 关闭（可用 `--resume + --fork-session`，二期开） |
| canCompactThread | ✅ | ❌ | ✅（透传 `/compact` slash 或 `compact`/`clear` 事件） |
| canSteerTurn | ✅ | ❌ | ❌（CLI 无 mid-turn interject） |
| canPrompt / canCancelTurn | ✅ / ✅ | ✅ / ✅ | ✅ / ✅（写 `{"type":"control","subtype":"interrupt"}`） |
| supportsLocalImageInput | ✅ | ❌ | ✅（`content` 数组里携带 image block；工具调用与 attachments 遵循 SDK 契约） |
| supportsResourceInput | ✅ | ✅ | ✅（`@file` mention 直接进 user message） |
| supportsSkillInput | ✅ | ✅ | ⚠️ MVP 关闭；二期读 `~/.claude/agents/` |
| supportsPermissionRequests | ✅ | ✅ | ✅（`can_use_tool` server request） |
| supportsUserQuestions | ✅ | ✅ | ❌（Claude Code 无独立 ask_user_question 语义） |
| supportsPlanApproval | ❌ | ✅ | ✅（ExitPlanMode 工具输出 → 独立审批） |
| supportsModelSelection | ✅ | ✅ | ✅（Opus/Sonnet/Haiku + fallback） |
| supportsReasoningOptions | ✅ | ✅ | ⚠️ 仅 `thinkingBudget`（数值化，非枚举 low/med/high） |
| supportsServiceTierSelection | ✅ | ❌ | ⚠️ MVP 关闭（Claude 无对等档位；Bedrock/Vertex 走 kind 而非 tier） |
| supportsUsage | ✅ | ✅ | ✅（stream-json 的 `usage` 字段，本回合 token 计数） |
| 账号套餐/限额查询（`AgentUsageQuotaProvider`，非 `AgentProviderCapabilities` 字段，见 §1.2 说明） | ✅ | ✅（`_x.ai/billing`） | ✅（`GET /api/oauth/usage`，见 §4.11；API Key 模式下不适用，返回 `null`） |

> 未列出的字段（如 `supportsTextInput`）沿用 Codex 相同默认。
>
> `AgentUsageQuotaProvider` 不是 `AgentProviderCapabilities` 里的字段，也不经过
> `AgentProviderBundle.adapt` 的 switch；UI 用量面板直接对 `AgentProvider` 实例做
> `provider is AgentUsageQuotaProvider` 判断（`provider_agent_usage_panel_repository.dart:190`
> 的 `_readQuota` 已是这个姿态），Claude Code 只需实现该接口即可接入，无需改共享层。

### 1.2 事件管线与端口地图（Zeta 侧现状）

```
CLI 子进程 stdout (行分隔 JSON)
   │
   ▼
[peer / transport]  ── JsonRpcPeer 抽象（Codex/Grok 复用；Claude Code 需新增 StreamJsonPeer）
   │                   • lib/src/features/agent/data/datasources/transport/*
   ▼
[provider adapter]  ── AgentProvider 实现（每种 CLI 一个）
   │                   • codex_app_server_agent_provider.dart
   │                   • grok_acp_agent_provider.dart
   │                   • claude_code_agent_provider.dart  ← 新增
   │                   通过 mixin 组合 AgentPlanApprovalProvider /
   │                   AgentPermissionPolicyProvider / AgentSkillsCatalogProvider /
   │                   AgentLocalThreadListProvider / AgentSessionConfigProvider
   ▼
[event mapper]      ── 每个 provider 私有；输出中立 AgentEvent（domain/agent_event_models.dart）
   ▼
[AgentEventPipeline] ── listener gate → coalescing → dispatcher（共享，禁 provider 分支）
   ▼
[AgentConversationEventProcessor] ── 纯同步 reducer（live/history/replay 各自独立实例）
   ▼
[AgentConversationTimelineStore] ── dumb merge，按规范化 id
   ▼
[AgentUiUpdatePort] ── 类型化 UI 更新
```

`AgentProviderBundle.adapt(provider)` 按 provider 是否实现可选接口自动挂载
可选端口（见 `domain/agent_provider_bundle.dart:26-95`）。**这是 Claude Code
新增能力的唯一装配途径**——不要在 registry / bundle / capabilities 里加
`switch (kind)` 分支。

### 1.3 已装配现状

- Provider 工厂：`lib/src/features/agent/data/default_agent_provider_factory.dart`
  第 25-27 行的 `claudeCode` 分支目前直接 `throw UnsupportedError`。**这是插入
  实例化的位置**。
- 枚举与 capabilities：
    - `AgentProviderKind.claudeCode` 已存在
      （`domain/agent_provider_models.dart:9`）
    - `AgentProviderCapabilities.defaultsFor(claudeCode)` 目前落到
      `unsupported`（`domain/agent_provider_capabilities.dart:237-244`）
- `AgentDefinition.all` 目前只有 `codex, grok`
  （`features/agent_management/domain/agent_management_models.dart:115`）。
- Repository map：`agent_management_controller.dart` 的构造函数接受
  `Map<String, AgentCliManagementRepository>`；应用组合层在
  `lib/src/app/app.dart` 组装（`DefaultAgentProviderFactory` 有 2 个 caller
  都在 `app.dart`）。

## 2. Claude Code 接入契约

### 2.1 启动命令（MVP）

```
claude \
  --print \
  --input-format stream-json \
  --output-format stream-json \
  --verbose \
  [--session-id <uuid>]                 # 首次会话固定我们自己的 uuid
  [--resume <session-id>]               # 恢复
  [--fork-session]                      # 二期：resume 时分叉出新 session
  [--model <id>]                        # opus / sonnet / haiku / 明确 id
  [--permission-mode default|acceptEdits|plan|bypassPermissions]
  [--allowed-tools <csv>] [--disallowed-tools <csv>]
  [--append-system-prompt <text>]
  [--mcp-config <path>]                 # 二期：透传 Zeta 组装的 MCP 配置
  [--add-dir <path>]                    # 追加允许访问的路径（thread cwd 之外）
  [--dangerously-skip-permissions]      # 仅当权限模式选 bypass 时使用
  [--permission-prompt-tool <tool>]     # 转发权限询问到我们自己的 tool
```

- 工作目录：`AgentSession.workingDirectory`（Zeta 侧 thread 的 cwd）。
- 环境：不显式注入 `ANTHROPIC_API_KEY` —— 依赖用户 `claude login`；仅在设置
  页显式启用 API key 模式时把值放到子进程 env（**不落盘**，见 §7）。

### 2.2 stream-json IO 帧

**发送（stdin，每行一个 JSON）**：

```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"...","content":"..."}]}}
{"type":"control","subtype":"interrupt"}
```

**接收（stdout，每行一个 JSON）**：常见 `type`：

| type | subtype | 语义 | 映射到 AgentEvent |
| --- | --- | --- | --- |
| `system` | `init` | 会话就绪，携带 session_id / cwd / model | `AgentSessionStartedEvent` + `AgentThreadStatusChangedEvent(running=false)` |
| `assistant` |  | 一段模型输出（文本 / thinking / tool_use） | `AgentMessageAppendedEvent` / `AgentReasoningStreamedEvent` / `AgentToolCallStartedEvent` |
| `user` |  | 模型回读的 tool_result 或用户消息回显 | `AgentToolCallCompletedEvent`（tool_result 分支）；用户回显通常静默丢弃 |
| `result` | `success` / `error_max_turns` / `error_during_execution` | 一次 turn 结束 | `AgentTurnCompletedEvent`（映射 status）+ `AgentTokenUsageEvent`（读 `usage`） |
| `control_request` |  | permission 询问、plan 审批等反向请求（携带 `request_id`） | 交给对应 adapter（§5、§6），最终产出 `AgentPermissionRequest` / `AgentPlanApprovalRequest` |
| `control_response` |  | 我们回写 control 的确认（我们不消费，只做诊断） | 忽略 |

> stream-json schema 会随 CLI 版本演进。参照
> `docs/protocols/codex_app_server_protocol.md` 的版本锁定流程，为 Claude Code 建立
> 独立的 `docs/claude_code_stream_json_protocol.md` 与
> `third_party/claude_code_stream_schema/`（后续任务，非 MVP 必须）。

### 2.3 反向 control request（权限 / plan）

CLI 端通过 `control_request` 让宿主决策：

```json
{"type":"control_request","request_id":"req_1","request":{"type":"can_use_tool","tool_name":"Bash","input":{...}}}
```

宿主回写：

```json
{"type":"control_response","request_id":"req_1","response":{"behavior":"allow","updatedInput":{...}}}
{"type":"control_response","request_id":"req_1","response":{"behavior":"deny","message":"..."}}
```

Plan 审批走 `ExitPlanMode` 工具（assistant tool_use）+ Zeta 侧独立
Application 工作流（§6），不复用 permission 决策模型。

### 2.4 模型列表 / 套餐用量的 REST 旁路（非 stream-json）

Codex 的 `model/list`、Grok 的 `_x.ai/billing` 都是「CLI 子进程代理鉴权请求」——
Zeta 从不接触 Codex/Grok 自己的凭证文件，只通过既有的 JSON-RPC/ACP 连接发请求，
由子进程本身完成鉴权。Claude Code 的 stream-json 协议**没有等价通道**：

- 没有稳定的 `claude model list` 子命令，`--output-format json` / `stream-json`
  也只是外壳，模型 catalog 不在结构化字段里；
- `/usage` 的 `json` / `stream-json` 输出里，五小时/周限额仍是 `result` 字符串
  里的自由文本段落，没有对应的结构化字段。

因此模型列表（§4.7）与套餐用量（§4.11）**不经过** `StreamJsonPeer` 或子进程，
而是 Zeta 直接以 `dart:io HttpClient` 向 Anthropic REST API 发 HTTPS 请求，复用
本机 `claude login` 落地的 OAuth accessToken 作 Bearer 凭证：

```
GET https://api.anthropic.com/v1/models?limit=100
GET https://api.anthropic.com/api/oauth/usage
```

这不是新模式——Zeta 已有 `CodexAgentManagementRepository._latestVersion()` 用同
样的 `dart:io HttpClient`（可注入 `httpClientFactory`，无需新增 `package:http` /
`dio` 依赖）直连 `registry.npmjs.org` 做版本检查
（`codex_agent_management_repository.dart:650-683`）。这里只是把同一模式套到
Anthropic 官方 API 上，唯一的新变量是请求头带上了本机 OAuth accessToken。

这是本文档相对 Codex/Grok「子进程代理鉴权」范式的**唯一例外**，其只读边界、
关闭开关、失败降级与合规提示见 §4.10、§7.2、§10。

## 3. 新增/修改文件清单

> 路径以 `lib/` 为根，除非另行注明。**新增**用 `+`，**修改**用 `~`。

### 3.1 Data 层（Provider 与协议）

```
+ src/features/agent/data/datasources/claude_code/
    + stream_json_peer.dart                    # 行分隔 JSON transport（新 peer，不复用 JsonRpcPeer）
    + claude_code_process_starter.dart         # PATH 探测 / bootstrap 参数拼装
    + claude_code_agent_provider.dart          # AgentProvider 实现（组合 AgentPlanApprovalProvider / ...）
    + claude_code_event_mapper.dart            # stream-json → AgentEvent
    + claude_code_control_request_handler.dart # can_use_tool / ExitPlanMode 反向请求分发
    + claude_code_permission_policy_adapter.dart
    + claude_code_plan_approval_adapter.dart
    + claude_code_model_catalog.dart           # 动态 GET /v1/models 优先 + 静态 fallback（§4.7）
    + claude_code_session_history_reader.dart  # 读 ~/.claude/projects/<encoded-cwd>/*.jsonl
    + claude_code_usage_quota_adapter.dart     # AgentUsageQuotaProvider 实现（§4.11）
    + claude_code_anthropic_api_client.dart    # /v1/models·/api/oauth/usage 共享 HTTP 客户端（§4.10）
    + claude_code_oauth_credentials_reader.dart # 只读 accessToken 到内存；不刷新、不落盘（§4.10）
+ src/features/agent/data/mappers/
    + claude_code_permission_mode_codec.dart   # 中立 optionId ↔ CLI --permission-mode
    + claude_code_message_content_codec.dart   # content block ↔ AgentMessage segment
    + claude_code_model_catalog_mapper.dart    # GET /v1/models 响应 → AgentModelList（§4.7）
    + claude_code_usage_quota_mapper.dart      # GET /api/oauth/usage 响应 → AgentUsageQuotaSnapshot（§4.11）
+ src/features/agent/data/agent_provider_permission_migration.dart
    # 追加 ClaudeCodePermissionPreferenceMigrator（若引入 legacy 字段迁移；否则不必）
```

### 3.2 Domain 层

```
~ src/features/agent/domain/agent_provider_capabilities.dart
    # defaultsFor(claudeCode) 返回真实静态能力（见 §1.1 目标列）
~ src/features/agent/domain/agent_provider_models.dart
    # 追加 defaultClaudeCodeProviderId 常量与 AgentProviderConfig.defaultClaudeCode
+ src/features/agent/domain/claude_code_models.dart      # 若有 CC 专属只读模型（可选，避免污染共享 domain）
```

### 3.3 CLI 管理与设置

```
+ src/features/agent_management/data/claude_code_agent_management_repository.dart
    # 实现 AgentCliManagementRepository：detect / testConnection / readConfiguration / discoverLogPaths
~ src/features/agent_management/domain/agent_management_models.dart
    # 追加 AgentDefinition.claudeCode 并把 all = [codex, grok, claudeCode]
~ src/features/agent_management/application/agent_management_controller.dart
    # _sanitizeProviderConfig / _configForAgent / _pathBelongsToAgent 扩展分支
```

### 3.4 装配层（composition root）

```
~ src/features/agent/data/default_agent_provider_factory.dart
    # AgentProviderKind.claudeCode => ClaudeCodeAgentProvider(config: config)
~ src/app/app.dart
    # 组装 Map<String, AgentCliManagementRepository> 时加入 claude_code 条目
```

### 3.5 UI（capability-driven，不按 kind 分支）

```
~ src/features/agent/presentation/widgets/agent_provider_icon.dart
    # 追加 Claude Code 图标（AgentProviderKind.claudeCode 分支——图标是唯一允许的 kind 分支之一）
~ src/features/agent_management/presentation/agent_management_page.dart
    # 详情页文案：安装/登录/文档链接
```

其余 UI（新建 thread 选择器、模型选择器、权限模式条、Plan 卡片、消息渲
染、工具时间线）**无需改动**——它们全部 capability 驱动，只要 §3.2 的
`defaultsFor(claudeCode)` 声明真实能力，UI 会自动出现。

### 3.6 测试

```
+ test/src/features/agent/data/datasources/claude_code/
    + stream_json_peer_test.dart
    + claude_code_event_mapper_test.dart              # fixture-based, provider 无关 shape check
    + claude_code_permission_policy_adapter_test.dart
    + claude_code_plan_approval_adapter_test.dart
    + claude_code_session_history_reader_test.dart
    + claude_code_anthropic_api_client_test.dart      # 鉴权矩阵/401/429/超时/非法 JSON，fake HttpClient
    + claude_code_oauth_credentials_reader_test.dart  # 缺失/损坏/过期文件降级；toString 不含 token
    + claude_code_usage_quota_adapter_test.dart        # 节流、API Key 模式短路、增强开关关闭
+ test/src/features/agent/data/mappers/
    + claude_code_model_catalog_mapper_test.dart
    + claude_code_usage_quota_mapper_test.dart
+ test/src/features/agent_management/data/
    + claude_code_agent_management_repository_test.dart
+ test/src/features/agent/data/
    + default_agent_provider_factory_test.dart        # 追加 claudeCode 分支断言
+ tool/smoke_claude_code_stream_json.py               # 真实 CLI 冒烟（可选，二期）
```

### 3.7 文档

```
+ docs/claude_code_stream_json_protocol.md    # 协议版本锁定（对齐 codex_app_server_protocol.md）
~ docs/guides/developer_guide.md                     # 追加 CC 特有的启动/权限章节；§7 的 16 条清单以 CC 为例补充
~ docs/architecture/design_document.md                     # 更新 Provider 表
~ CLAUDE.md                                   # 若 Zeta 默认 provider 或 default model 有变更再改
```

## 4. Data 层设计要点

### 4.1 `StreamJsonPeer`（新增）

**为什么不能复用 `JsonRpcPeer`**：JsonRpc peer 用 `id/method/params` 与
`id/result|error` 的严格帧匹配；Claude Code stream-json 每行都是一个
`type` 事件，没有请求—响应 id 相关性，`control_response` 是我们主动
写的独立行。强行复用会污染共享 transport 的语义并产生大量假 pending。

**接口草案（放在 `stream_json_peer.dart`）**：

```dart
abstract class StreamJsonPeer {
  Stream<StreamJsonEvent> get events;
  Stream<String> get stderrLines;
  Stream<StreamJsonProtocolException> get protocolErrors;

  Future<void> start();
  Future<void> sendUserMessage(Map<String, Object?> message);
  Future<void> sendControl(Map<String, Object?> control);           // interrupt / permission response / ...
  Future<void> close();
}

class StreamJsonEvent {
  const StreamJsonEvent({required this.type, this.subtype, required this.raw});
  final String type;
  final String? subtype;
  final Map<String, Object?> raw;
}
```

**实现要点**（与 `JsonRpcStdioTransport` 一致的实现纪律）：

- Dart `Process.start`，UTF-8 with `allowMalformed`（沿用 Codex 已验证选择）。
- 严格串行化 stdin 写队列，`writeln` + `flush`；关闭时 kill + `SIGKILL`
  兜底（沿用 `json_rpc_stdio_transport.dart:404-418`）。
- 每次 `sendControl` 生成 `request_id`，但**不等待响应**——事件流里出现
  同 `request_id` 的 `control_response` 才落诊断 log。
- 单行 payload 大小超阈值（比如 4 MB）拒收并触发 `protocolErrors`，避免
  被极端 tool_result 撑爆内存。

### 4.2 `ClaudeCodeProcessStarter`

- 从 `AgentProviderConfig.command` 读 CLI 路径（默认 `claude`）。
- 组装参数（§2.1）；args 顺序稳定，便于日志比对与冒烟脚本复现。
- Windows 用 `where.exe` / macOS+Linux 用 `command -v` 解析；实测 CLI
  可用性只通过 `AgentCliManagementRepository.detect` 做，不在 starter 里
  提前失败（沿用 Codex/Grok「实际启动才报错」的现有姿态，见
  `agent_management_controller.dart:117-128`）。

### 4.3 `ClaudeCodeAgentProvider`

组合与 mixin：

```dart
class ClaudeCodeAgentProvider extends AgentProvider
    implements
        AgentPlanApprovalProvider,
        AgentPermissionPolicyProvider,
        AgentLocalThreadListProvider,
        AgentSessionConfigProvider,
        AgentRefreshableModelCatalogProvider,  // 新增：强制刷新动态模型列表（§4.7）
        AgentUsageQuotaProvider,               // 新增：套餐用量（§4.11）
        // MVP 不实现：AgentSkillsCatalogProvider, AgentQuestionResponseProvider,
        //           AgentConversationModeCatalogProvider（Claude 用 --permission-mode plan
        //           就直接切换，不需要独立 mode catalog）
{
  ...
}
```

对齐 `agent_provider_bundle.dart:26-95` 的 switch：

- **实现 `AgentPermissionPolicyProvider`** → bundle 自动挂载 `permissionPolicy`；
- **实现 `AgentPlanApprovalProvider`** → bundle 自动挂载 `planApproval`；
- 通过 `capabilities.canListThreads/canReadHistory=true` → bundle 自动挂载
  `threadCatalog`，Provider 只需实现 `AgentProvider.listThreads/readHistory`。
- 通过 `capabilities.supportsModelSelection=true` → bundle 自动挂载
  `modelCatalog`，Provider 需要实现 `listModels`（走 §4.7）；额外实现
  `AgentRefreshableModelCatalogProvider.refreshModels` 支持强制刷新。
- **实现 `AgentUsageQuotaProvider`** 不经过 bundle——UI 用量面板直接对
  `AgentProvider` 实例做 `is` 判断（对齐 Codex/Grok 现有实现，见 §1.1 脚注），
  实现该接口即可自动出现在 `AgentUsagePanel`，无需碰 bundle/switch。

**运行时纪律**（与 Codex/Grok 对齐，`CLAUDE.md#Agent 事件管线`）：

- provider 原始事件永不透出到共享层；`AgentEvent` 是唯一契约。
- reducer 纯同步；副作用（thread rename 落盘、模型缓存写入等）走
  `AgentConversationEffectRunner` 已有通道，不新造。
- `sourceItemId/sourceMessageId` 只作 metadata；`entryId`、reasoning phase、
  turn 状态归一化都在 `claude_code_event_mapper.dart` 里做。

### 4.4 `ClaudeCodeEventMapper`

映射目标：**永远输出中立 `AgentEvent`；共享层禁止再解析 CC 私有字段**。

- `system.init` → `AgentSessionStartedEvent(AgentSession(id: session_id,
  workingDirectory: cwd, model: model))` + `AgentThreadStatusChangedEvent`。
- `assistant.message.content[]`：按 block type 分派
    - `text` → `AgentMessageAppendedEvent`（增量拼接由 mapper 维护 offset）
    - `thinking` → `AgentReasoningStreamedEvent`（对齐 Codex reasoning phase）
    - `tool_use` → `AgentToolCallStartedEvent`（`toolCallId = tool_use.id`）
- `user.message.content[]`
    - `tool_result` → `AgentToolCallCompletedEvent`（关联 `tool_use_id`）
    - 其他 role=user 消息（回显）：静默丢弃，避免 timeline 重复
- `result` → `AgentTurnCompletedEvent`
    - `subtype=success` → `AgentHistoryTurnStatus.completed`
    - `subtype=error_max_turns` → `interrupted`
    - `subtype=error_during_execution` → `failed`（`errorCode` 用 subtype，
      `errorMessage` 从 payload 提取）
    - `usage` → 另发 `AgentTokenUsageEvent`（`input_tokens` + `output_tokens`
        + `cache_creation_input_tokens` + `cache_read_input_tokens`）
- `control_request` → 交给 `ClaudeCodeControlRequestHandler`
  （不产生 AgentEvent；handler 内部产生 permission/plan 请求事件）

**关键守则**：mapper 对未识别 `type` 一律记录诊断日志并**丢弃**，绝不
throw；这样 CLI 引入新事件类型时不会阻断整个 pipeline。

### 4.5 `ClaudeCodePermissionPolicyAdapter`

- 中立 optionId 目录（由 codec 生成）：

  | Zeta optionId | Claude Code `--permission-mode` | 语义 |
    | --- | --- | --- |
  | `:ask` | `default` | 每个高风险工具都问 |
  | `:accept-edits` | `acceptEdits` | 自动允许编辑类工具，其他仍问 |
  | `:plan` | `plan` | 只允许读、只出 plan（不执行副作用） |
  | `:bypass` | `bypassPermissions` | YOLO（要求二次确认；需检测 root 用户判定） |

- `listPermissionOptions` 返回静态 4 项 catalog，`defaultOptionId=':ask'`。
- `applyPermissionSelection`：
    - 需要重启子进程（`--permission-mode` 是启动参数）→ 返回
      `AgentPermissionApplyScope.nextSession`；由 registry 触发 provider
      重连（沿用 `_persistDetectionSummary` 里 `commandChanged` 的
      `restartProvider` 通路，`agent_management_controller.dart:463-470`）。
    - 如果未来 CLI 暴露 live `permission_mode` control，可切到
      `AgentPermissionApplyScope.runtime`；MVP 不做。
- **不做** legacy 迁移（CC 新入，`AgentProviderPermissionMigrationRegistry`
  不加分支）。
- 反向 `can_use_tool` 询问：
    - 生成中立 `AgentPermissionRequest`（`decisionOptions=[allow_once,
    allow_always, deny_once, deny_always]`）；
    - 用户决策 → `sendControl({type:"control_response",request_id,
    response:{behavior:"allow"|"deny", updatedInput?, message?}})`；
    - `allow_always` / `deny_always` 由 adapter 缓存到当前 session 的
      tool allow-list，并落 `~/.zeta/state/claude_code/session_<id>.json`（
      仅规范化字段：tool_name + 决策；**不存 input/prompt**）。

### 4.6 `ClaudeCodePlanApprovalAdapter`

- 触发路径：assistant 输出 `tool_use.name = "ExitPlanMode"`（`input.plan`
  是 Markdown 文本）。
- Mapper 不把它当普通工具，而是转成 `AgentPlanApprovalRequest`（domain
  已有类型）——**必须**与权限模型完全隔离（`CLAUDE.md#Provider 运行时`
  硬性规则）。
- 用户批准 → adapter 通过 `control_response`（behavior=allow）放行，同时
  在 Zeta application 层 **新建显式 Default 回合**（对齐 CLAUDE.md）：
    1. 保持当前 session；
    2. 新回合的 permission snapshot 强制为 `:accept-edits`（或用户可选
       `:ask`），不预授权具体命令；
    3. UI 明示这是「执行确认」，与协议层 approval 分离。
- 拒绝 → `control_response(deny, message)`；Claude 会在下一 assistant turn
  收到 reason。

### 4.7 `ClaudeCodeModelCatalog`

Claude Code CLI 本身无 `model list` 端点（§2.4），因此 `Provider.listModels()`
按「动态优先、静态兜底」两层实现：

1. **动态（首选，需账号数据增强开关开启，见 §4.10）**：调
   `ClaudeCodeAnthropicApiClient.listModels()` → `GET /v1/models?limit=100`，把
   `data[]` 映射为 `AgentModelList`（新 mapper
   `claude_code_model_catalog_mapper.dart`）：
     - `id`/`model` = `id`；`displayName` = `display_name`；
     - `contextWindowTokens` = `max_input_tokens`；
     - `raw` 保留完整 `capabilities` 节点（`effort`/`thinking`/`image_input` 等），
       当前不强解析未声明字段，留给后续 UI 消费；
     - `isDefault`：匹配首个 id 以 `sonnet` 开头的条目（接口不提供官方"默认模型"
       字段，`sonnet` 是 Claude Code CLI 自身的默认别名）。
2. **静态兜底**（未登录 / accessToken 过期 / 401 / 429 / 网络失败 / 增强开关关闭时）：

   | optionId | 展示名 | 场景 |
     | --- | --- | --- |
   | `claude-opus-4-7` | Opus 4.7 | 默认高性能 |
   | `claude-sonnet-4-6` | Sonnet 4.6 | 主力性价比 |
   | `claude-haiku-4-5-20251001` | Haiku 4.5 | 低延迟 |
   | `opus` / `sonnet` / `haiku` | 别名 | 兼容 `--model` 短写 |

- Provider 内存缓存命中直接返回；未命中 → 动态优先 → 失败静态兜底 → 写入内存
  缓存（不落盘）。`AgentModelCatalogRepository`（app 级）继续在其上层做 SWR +
  单飞；静态兜底路径本身不发请求，指纹变化时最多只打一次 `/v1/models`。
- 实现 `AgentRefreshableModelCatalogProvider.refreshModels()`：绕过内存缓存强制
  重新走动态源（用户点"刷新模型列表"），失败仍以静态目录兜底，不抛异常。
- `AgentModelPreference` 沿用：Zeta 侧记住用户选择；Fast/reasoning effort
  MVP 不暴露（CC 用 `thinkingBudget` 数值，展示上属另一个交互模型，二期做）。
- **禁止**读取 `~/.claude/cache/model-capabilities.json`——那是官方 CLI 自己的
  缓存，不是本文档的数据源；Zeta 用自己的内存缓存，不与官方缓存混用（数据边界）。
- 账号数据增强关闭时（`claudeCode.accountDataEnrichment=false`，见 §4.10）
  `listModels()`/`refreshModels()` 永远直接返回静态目录，不发起任何网络请求。

### 4.8 `ClaudeCodeSessionHistoryReader`

- Path：`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`。
    - `<encoded-cwd>` = 把 workspace 绝对路径的 `/` 与 `\` 都替换成 `-`，
      Windows 盘符 `C:` 变 `C-`（参照 CC CLI 现行编码；实现前用真实 CLI
      生成一个会话，把编码规则做单测冻结在
      `claude_code_session_history_reader_test.dart`）。
- 读取契约：与 `codex_thread_history_reader.dart` 对齐：
    - **只读**，绝不改写；
    - 宽容 `tryDecode`：损坏行跳过并计数上报诊断；
    - 输出 `AgentThreadDescriptor` 列表（title 用首条 user message 前 60 字符
      生成，与 Codex/Grok 一致）。
- 与 `AgentLocalThreadListProvider.removeThreadFromList` 的配合：
    - Zeta 只维护自己的隐藏 list（`~/.zeta/state/claude_code/hidden_threads.json`），
      hide 时把 `<encoded-cwd>/<session-id>` 加进去；
    - UI 明示「远端会话文件仍保留在 `~/.claude/projects/...`，如需彻底删除
      请手动」。**符合数据边界规则**。

### 4.9 归档 / 删除 / fork（MVP 关闭）

- `canArchiveThread=false`，`canDeleteThread=false`（协议不支持）。
- `canRemoveThreadFromList=true`（走 §4.8 的 hidden list）。
- 二期：`--fork-session` + 复制 jsonl 到新 session-id 可以实现本地 fork，
  仍不动 Claude 内部 index。

### 4.10 `ClaudeCodeAnthropicApiClient` 与 `ClaudeCodeOAuthCredentialsReader`

模型列表（§4.7）与套餐用量（§4.11）共享的基础设施；这是本 Provider 唯一绕开
`StreamJsonPeer` 子进程、直接对 Anthropic REST API 发 HTTPS 请求的通道（背景
见 §2.4）。

**`ClaudeCodeOAuthCredentialsReader`**：

- 只读 `~/.claude/.credentials.json`（Windows：
  `%USERPROFILE%\.claude\.credentials.json`），解析
  `claudeAiOauth.{accessToken,expiresAt,subscriptionType}` 到瞬时值对象
  `ClaudeCodeOAuthCredentials`；
- `expiresAt <= now`（本机常见 Unix 毫秒）→ 视为不可用，返回 `null`。**不做**
  刷新（不调用 `POST /v1/oauth/token`）——续期完全交给用户重新运行 `claude` 或
  `claude login`，Zeta 不接管，避免与 CLI 自身的目录锁续期逻辑竞态，也避免落入
  需要写回凭证文件的合规灰区（对齐 §11「明确不做」）；
- 文件缺失 / 损坏 / JSON 解析失败 → 返回 `null`，不抛异常，调用方按「未登录」
  路径降级；
- `ClaudeCodeOAuthCredentials.toString()` **不含** token 原文；诊断日志只允许
  记录 `hasCredentials: bool` 与 `expired: bool` 两个布尔字段，不记录前缀或全文；
- 结果**不缓存到磁盘、不缓存到长生命周期内存**——每次调用重新读文件（成本可
  忽略），避免"内存缓存到期后仍在用"的隐患。

**`ClaudeCodeAnthropicApiClient`**：

- 复用 Zeta 既有的 `dart:io HttpClient` 直连模式，与
  `CodexAgentManagementRepository._latestVersion()` 调 `registry.npmjs.org`
  完全同构（`codex_agent_management_repository.dart:650-683`）：可注入
  `httpClientFactory`、固定超时、`try/finally { client.close(force: true) }`，
  不引入 `package:http` / `dio` 等新依赖。

  ```dart
  class ClaudeCodeAnthropicApiClient {
    ClaudeCodeAnthropicApiClient({HttpClient Function()? httpClientFactory})
        : _httpClientFactory = httpClientFactory ?? HttpClient.new;

    final HttpClient Function() _httpClientFactory;

    /// GET /v1/models；订阅 OAuth 走 Bearer + oauth beta，API Key 模式走 x-api-key。
    Future<Map<String, Object?>?> listModels({
      required String accessToken,
      required bool isSubscriptionOAuth,
    }) => _get(
      Uri.parse('https://api.anthropic.com/v1/models?limit=100'),
      accessToken: accessToken,
      isSubscriptionOAuth: isSubscriptionOAuth,
      extraHeaders: isSubscriptionOAuth
          ? const {'anthropic-beta': 'oauth-2025-04-20'}
          : const {},
    );

    /// GET /api/oauth/usage；仅订阅 OAuth 语义存在，调用方须自行拦截 API Key 模式。
    Future<Map<String, Object?>?> readUsageQuota({
      required String accessToken,
      required String? claudeCodeVersion,
    }) => _get(
      Uri.parse('https://api.anthropic.com/api/oauth/usage'),
      accessToken: accessToken,
      isSubscriptionOAuth: true,
      extraHeaders: {
        'anthropic-beta': 'oauth-2025-04-20',
        if (claudeCodeVersion != null)
          HttpHeaders.userAgentHeader: 'claude-code/$claudeCodeVersion',
      },
    );

    Future<Map<String, Object?>?> _get(
      Uri uri, {
      required String accessToken,
      required bool isSubscriptionOAuth,
      Map<String, String> extraHeaders = const {},
    }) async {
      final client = _httpClientFactory();
      try {
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 10));
        request.headers.set('anthropic-version', '2023-06-01');
        if (isSubscriptionOAuth) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $accessToken',
          );
        } else {
          request.headers.set('x-api-key', accessToken);
        }
        extraHeaders.forEach(request.headers.set);
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        // 401/429/其他非 200 一律静默降级，不重试——调用方各自决定兜底策略。
        if (response.statusCode != HttpStatus.ok) {
          return null;
        }
        final body = await response
            .transform(const Utf8Decoder())
            .join()
            .timeout(const Duration(seconds: 10));
        final decoded = jsonDecode(body);
        return decoded is Map
            ? decoded.map((key, value) => MapEntry(key.toString(), value))
            : null;
      } catch (_) {
        return null;
      } finally {
        client.close(force: true);
      }
    }
  }
  ```

- **鉴权矩阵**（实测冻结自参考调研，写进单测防回归）：`x-api-key` 绝不能与
  `anthropic-beta: oauth-2025-04-20` 同时出现（会 401 `invalid x-api-key`）；
  订阅 OAuth 模式必须用 `Authorization: Bearer`。
- 两个方法都是 **best-effort**：401 / 429 / 超时 / 网络错误 / 非法 JSON 一律
  返回 `null`；客户端自己不抛出、不重试、不把响应体内容写入日志（只记录
  status code），调用方（§4.7、§4.11）各自决定降级策略。
- `claudeCodeVersion` 来自 detect 阶段缓存的
  `config.extra['detectedCurrentVersion']`（沿用 Codex 已有模式，见
  `codex_app_server_agent_provider.dart:299`）；缺失时不带 `User-Agent` 头
  （参考调研确认裸调用仍可 200，只是更易触发限流）。
- **账号数据增强开关**：`AgentProviderConfig.extra['claudeCode.accountDataEnrichment']`
  （布尔，缺省视为 `true`）。设置页详情页提供开关（§5）；关闭后 §4.7/§4.11
  永远不构造 `ClaudeCodeAnthropicApiClient` 请求，直接走各自的静态/空兜底。
  这是本文档相对 Codex/Grok 唯一「直接用本机凭证发 REST」的路径，默认开启但
  必须可关闭，降低合规/风控顾虑（参考调研的合规提示：Anthropic 条款建议第三
  方产品优先走 Console API Key；Zeta 场景是本机复用用户自己已登录的 CLI 凭证
  做只读诊断展示，不做刷新、不落盘、不外传，风险显著低于托管代理场景，但仍
  需要可关闭的显式开关兜底）。

### 4.11 `ClaudeCodeUsageQuotaAdapter`（套餐用量，`AgentUsageQuotaProvider`）

`ClaudeCodeAgentProvider.readUsageQuota()` 实现步骤：

1. 账号数据增强被关闭，或当前认证模式为 Console API Key（§7.2）→ 直接返回
   `null`（`/api/oauth/usage` 对 API Key **不适用/非此语义**）；用量面板降级
   为"暂无统计"，与 Codex/Grok 未开通套餐时行为一致。
2. 节流：与上次调用（无论成功失败）间隔 < 60s → 直接复用上次内存结果，不重
   复打这个对高频调用敏感、易 429 的接口。
3. 读 §4.10 `ClaudeCodeOAuthCredentialsReader`；无有效凭证（未登录/已过期）→
   返回 `null`。
4. 调 `ClaudeCodeAnthropicApiClient.readUsageQuota()`；返回 `null` → 原样返回
   `null`。
5. 成功 → 用新 mapper `claude_code_usage_quota_mapper.dart`（类比
   `grok_billing_quota_mapper.dart`，纯函数、无副作用）转换为
   `AgentUsageQuotaSnapshot`：
     - `windows`：`five_hour` → `AgentUsageWindow(label: '五小时会话额度',
       usedPercent: five_hour.utilization.round(), resetsAt: five_hour.resets_at)`；
       `seven_day` → `AgentUsageWindow(label: '1 周',
       usedPercent: seven_day.utilization.round(), resetsAt: seven_day.resets_at)`；
       `resets_at` 为 `null`（窗口未激活，对应 `limits[].is_active=false`）时省
       略该字段，不臆造重置时间；
     - `planType`：来自 §4.10 凭证读取顺带拿到的 `subscriptionType`（如
       `pro`/`max`），不为此额外发请求；
     - `credits`：`extra_usage.is_enabled=true` 时映射
       `AgentUsageCredits(hasCredits:…, unlimited: false, balance:…)`；否则为
       `null`；
     - `limitName`：固定 `'Claude Code 订阅额度'`（接口未提供 Grok 那样的
       period type 语义字段）。
6. 全流程任一步失败即返回 `null`，不向上抛出——`provider_agent_usage_panel_repository.dart`
   的 `_readQuota` 已有 `catch (_) => null` 兜底，Provider 侧无需重复防御，但
   mapper 内部仍应保守处理，避免把网络异常伪装成"套餐是 0%"。
- **不做**：不解析 `/usage` slash 的自由文本；不做 `/cost`（API Key 花费，语义
  不同）；不做本地 JSONL token 历史聚合（"今日 Token" 沿用 stream-json
  `result.usage` 走既有 `AgentTokenUsageEvent`，见 §4.4，与本 adapter 完全独立）。

## 5. Application / UI 影响清单

绝大多数改动**只需**开启 capability。列出的都是必须动的地方：

1. `agent_management_controller.dart`
    - `_sanitizeProviderConfig` / `_pathBelongsToAgent` / `_configForAgent`
      追加 `claudeCode` 分支（沿用 Codex/Grok 的 sanitization 姿态）；
    - `_persistDetectionSummary` 已 provider 无关，不必改；
    - repository map 由 `app.dart` 传入，添加一项即可（§3.4）。
2. `AgentProviderIcon`：新增 CC 图标资源与分支（UI 允许的少数 kind 分支之一）。
3. 新 thread 选择器：`availableThreadProviders` 依赖 `providerController`
   与 repository map，无需改。
4. Provider 设置页：capability 驱动，无需改；只在**详情页**加安装 / 登录
   / 文档指引文案（数据来自 `AgentDefinition.claudeCode`）。
5. `agent_conversation_view_model.dart`：**禁止**为 CC 加任何 kind 分支；
   任何看似需要「因为是 CC 所以特殊处理」的场景都要重新想能力抽象。
6. 详情页新增「账号数据增强」开关（对应 `claudeCode.accountDataEnrichment`，
   默认开）：控制 §4.10 是否发起 REST 调用；关闭时模型目录回退静态列表、
   套餐用量面板自动隐藏（`readUsageQuota()` 返回 `null`，非 unsupported）。
   文案需说明该开关会读取本机 `claude login` 的 OAuth 凭证发起只读查询。

## 6. Plan / Permission / History 语义映射详解

### 6.1 权限映射决策表

| Zeta UI 术语 | Zeta optionId | CC 启动参数 | can_use_tool 反向询问处理 |
| --- | --- | --- | --- |
| Ask（默认） | `:ask` | `default` | 每次弹审批弹窗 |
| Accept edits | `:accept-edits` | `acceptEdits` | 编辑类自动 allow；其他弹 |
| Plan only | `:plan` | `plan` | 只允许 read 类；写类一律 deny + 提示 |
| Always approve | `:bypass` | `bypassPermissions` | 不发反向询问（CC 侧不 emit）；UI 二次确认后启动 |

### 6.2 Plan 审批完整流程

```
用户选 :plan → 启动 (--permission-mode plan)
      │
      ▼
assistant.tool_use = ExitPlanMode(input.plan="...")
      │  (mapper 转 AgentPlanApprovalRequest；不产生 tool_call 时间线卡)
      ▼
UI 展示 plan Markdown → 用户 approve
      │
      ├── adapter.respondToPlanApproval(approved=true)
      │       → sendControl(control_response{allow})   # 让 CLI 退出 plan mode
      │       → 【关键】新建 Default 回合（Zeta application 工作流）
      │            • 权限 = :accept-edits（用户可选覆盖为 :ask）
      │            • 不预授权具体命令/文件/网络
      │       → CLI 下个 turn 开始执行
      │
      └── 拒绝 → sendControl(deny, message=用户理由)
```

### 6.3 History 恢复

- List：读 `~/.claude/projects/<cwd>/*.jsonl` 头 + 尾数行，输出
  descriptor（title/时间/model/消息数）。
- Read：整文件流式解析，同 mapper（关键）→ `AgentEvent` → `history`
  reducer（**独立实例**，`CLAUDE.md#Agent 事件管线`）→ TimelineStore。
- Resume：启动子进程时携带 `--resume <session-id>`；CLI 首个 `system.init`
  会带来 session_id / cwd，验证是否与预期一致，否则视为 provider 拒绝
  恢复（弹错，不静默）。
- Compact：Claude Code 有 `/compact` slash command（触发方式：给 CLI 一条
  `user` message with `{"type":"text","text":"/compact"}`）；`canCompactThread=true`，
  Provider 侧实现 `compactThread` 即可，UI 无需改。

## 7. CLI 检测与配置

### 7.1 `ClaudeCodeAgentManagementRepository.detect`

对齐 `codex_agent_management_repository.dart` 与
`grok_agent_management_repository.dart` 的分阶段结构：

1. **install**：`claude --version`（`AgentInstallationState.installed`）
2. **account**：探测 `~/.claude/.credentials.json` 或 `~/.claude/oauth.json`
   是否存在且未过期；**不读凭证内容**，只 stat 与 mtime。
    - 存在 → `AgentAccountState.loggedIn`
    - 缺失 → `loggedOut`（详情页给出 `claude login` 指引）
3. **version**：解析 `--version`，与 `npm view` 或本地 `~/.claude/version` 对比
   （沿用 Codex/Grok 的 `isNewerVersion` 已有逻辑；不引新增依赖）
4. **runtime handshake**（testConnection）：短生命周期启动子进程，发一条
   ping user message，等 `system.init` + `result`，超时 20s 取消。
5. **modelList**：detect 阶段本身仍不打网络——直接返回静态目录。真正的动态
   `GET /v1/models` 发生在 §4.7/§4.10 描述的独立运行时路径（用户实际打开模型
   选择器 / 点刷新时才触发），不阻塞 detect 流程，也不与 detect 共用实现。

**日志路径**：`discoverLogPaths` 返回 `~/.claude/logs/*.log`（若存在）。

> `account` 阶段的「不读凭证内容」与 §4.10 的 accessToken 读取是两条独立
> 路径，语义不同：前者只判断登录态（stat/mtime）用于设置页图标展示；后者是
> 用户主动触发模型列表/套餐用量时的运行时读取，范围、频率、限制见 §4.10、
> §7.2。二者不合并实现，避免把"content 读取"需求越权带入轻量 detect 流程。

### 7.2 认证策略

| 用户场景 | Zeta 行为 |
| --- | --- |
| 已 `claude login` | 直接跑，不注入 env |
| 未登录 | 详情页显示「运行 `claude login` 后重试」，Zeta 不代跑 |
| 设置页填 API Key（可选） | 值放入子进程 env `ANTHROPIC_API_KEY`；**Zeta 落盘时脱敏**（`extra` 里只存 `hasApiKey=true` 与 masked 后 4 位）；真值由 OS keychain 存（沿用现有 secure storage；如无现成通路则 MVP 不做，只显式提示不落盘）；此模式下 §4.10/§4.11 的 `/api/oauth/usage` 不适用，`readUsageQuota()` 直接返回 `null` |
| Bedrock / Vertex | 二期；MVP 不做，UI 明确标注 |
| 账号数据增强（模型列表/套餐用量，默认开） | §4.10 在需要时把 `claudeAiOauth.accessToken` 解析进内存，仅用于拼装 `GET /v1/models` 与 `GET /api/oauth/usage` 的请求头；用户可在详情页关闭（§5 item 6），关闭后完全不触碰凭证文件 |

**硬性约束**（对齐 CLAUDE.md）：

- **detect / testConnection 阶段**（§7.1）不读 `~/.claude/.credentials.json`
  内容，只 stat / mtime；
- **§4.10 的模型列表 / 套餐用量通道**是唯一允许读取该文件内容的路径，且仅限
  把 `accessToken`（连同 `expiresAt`/`subscriptionType`）解析进内存用于拼装
  两个只读 GET 请求；**不做**刷新（不调用 `POST /v1/oauth/token`）、不写回
  文件、不落盘、不写入日志（诊断日志只允许记录 `hasCredentials`/`expired`
  两个布尔值，不得记录 token 前缀或全文）；该通道可被用户在详情页整体关闭；
- Zeta 侧配置文件 `~/.zeta/config/agent_providers.json` 不落原始 key/token、
  不落 prompt/回复/tool output/环境变量原文；
- 会话 hidden list、tool allow-list 白名单字段可持久化。

## 8. 分阶段落地计划

| 阶段 | 交付物 | 完成判据 |
| --- | --- | --- |
| **M0 · 骨架** | `AgentDefinition.claudeCode` + `defaultsFor` 真实能力 + `DefaultAgentProviderFactory` 分支替换为**空 provider**（返回错误的 initialize） | `default_agent_provider_factory_test.dart` claude_code 分支不再 throw；`AgentProviderIcon` 出图；设置页出现 Claude Code 条目 |
| **M1 · 联通** | StreamJsonPeer + ProcessStarter + Provider.initialize + mapper 覆盖 `system.init`/`assistant.text`/`user.tool_result`/`result` | 手工新建一条 thread，能发一句话拿到回复；`flutter analyze` + 新 mapper 单测通过 |
| **M2 · 工具时间线** | mapper 覆盖 `thinking`/`tool_use` 完整生命周期 + `AgentTokenUsageEvent` + turn 状态归一化 | 工具卡片、reasoning phase、usage 全部出；`agent_event_storm_fixture_test.dart` 追加 CC fixture |
| **M3 · 权限 + Plan** | ControlRequestHandler + PermissionPolicyAdapter + PlanApprovalAdapter + 4 选项 catalog + 显式 Default 执行回合 | 权限模式条可切；plan → 审批 → 执行链路手工通；单测覆盖所有 4 个 optionId |
| **M4 · 历史 / resume** | SessionHistoryReader + `--resume` 参数拼装 + hidden list | 重启 Zeta 后能看到历史 thread、点开恢复；损坏 jsonl 不阻断启动 |
| **M5 · 打磨** | CLI 检测四阶段 + 日志页 + 详情页文案 + 图标 + 账号数据增强（动态模型列表 §4.7 + 套餐用量 §4.11，含详情页开关）+ 文档 | detect 完整跑通；`GET /v1/models`/`GET /api/oauth/usage` 手工冒烟通过（含未登录/401/429 降级、增强开关关闭三条路径）；`docs/claude_code_stream_json_protocol.md` 归档 schema；`docs/architecture/design_document.md` 更新 |
| **M6+ · 二期** | fork、skills（`~/.claude/agents/`）、MCP config 透传、thinkingBudget、Bedrock/Vertex | 独立 PR，按需排 |

每个阶段结束：`dart format .` → `flutter analyze` → `flutter test`（对齐
CLAUDE.md「每次代码修改后」章节）。

## 9. 测试策略

对齐 `docs/architecture/engineering_standards.md` 与 CLAUDE.md：

1. **共享层守卫**：新增 fixture-based 架构测试，断言
   `agent_event_coalescing_policy.dart`、`agent_event_pipeline.dart`、
   `agent_conversation_timeline_store.dart` 不 import 任何
   `datasources/claude_code/` 路径。
2. **契约测试（provider 无关）**：mapper 用 golden fixtures
   （`test/src/features/agent/data/datasources/claude_code/fixtures/*.jsonl`）
   驱动，断言 → `AgentEvent` 序列匹配预期。fixture 从真实 CLI 生成一次
   后冻结，schema 演进时同步 `docs/claude_code_stream_json_protocol.md`。
3. **单元测试**：permission adapter / plan adapter / session history reader
   各自 A/A/A，用 fake `StreamJsonPeer`；不 mock。`ClaudeCodeAnthropicApiClient`
   / `ClaudeCodeOAuthCredentialsReader` / `ClaudeCodeUsageQuotaAdapter` 走同一
   姿态但注入 fake `HttpClient`/fake 文件系统（对齐
   `CodexAgentManagementRepository` 的 `httpClientFactory` 测试模式），断言
   401/429/超时/凭证过期/增强开关关闭都落到 `null` 而非异常。
4. **AgentEvent 16 条清单**：新增/改动 event 时逐项回答
   `docs/guides/developer_guide.md §7`；MVP 若不新增 event，只需在 PR
   描述中明示「未新增 AgentEvent」。
5. **冒烟脚本**：`tool/smoke_claude_code_stream_json.py`，参照
   `tool/smoke_codex_app_server.py` 模式；CI 不跑（需真实 CLI），发布
   前手动执行。
6. **回归**：`test/src/features/agent/domain/agent_provider_capabilities_test.dart`
   追加 `defaultsFor(claudeCode)` 真实能力断言；`agent_provider_bundle_test.dart`
   追加 CC provider fake 覆盖新挂载的 optional 端口。

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| stream-json schema 无版本承诺 | CLI 升级后事件形状变化，UI 空白/崩溃 | mapper 对未识别 `type` 一律记诊断并丢弃；fixture 冻结 + 冒烟脚本 + 独立协议 doc |
| `<encoded-cwd>` 编码规则未文档化 | 历史读取错文件 / 空目录 | 首次接入时用真实 CLI 打样，把编码规则冻在单测里；后续 CLI 版本升级时冒烟 |
| Plan 审批语义与 permission 混淆 | 用户被过度授权 | 硬性隔离 domain 类型（`AgentPlanApprovalRequest` vs `AgentPermissionRequest`）；文档反复强调「新建显式 Default 回合」 |
| API key 落盘 | 凭证泄漏 | MVP 只做「已登录 CLI」；API key 通路默认关闭；开启需 secure storage |
| Bedrock/Vertex 覆盖不到 | 企业内网用户不可用 | UI 显式标注 unsupported，走二期 |
| 长 tool_result 阻塞 stdin | 子进程 hang | Peer 层 payload 上限 + `--dangerously-suppress-output` 兜底 kill |
| Claude Code CLI 不在 PATH（Windows） | 启动失败但错误信息不友好 | detect 用 `where.exe` 明确报错并给安装 URL；provider initialize 失败时错误映射为「未安装」而非「协议错」 |
| 直接用本机 OAuth accessToken 调用 Anthropic REST（§4.10），非 Codex/Grok 那种「CLI 子进程代理鉴权」范式 | Anthropic 条款建议第三方产品优先走 Console API Key，长期被视为不合规使用可能招致账号侧风控关注 | 只读不刷新、不落盘、不外传，且仅用于用户自己账号的本机诊断展示；详情页提供可关闭的「账号数据增强」开关（默认开，§5 item 6）；文档登记合规提示，二期视 Anthropic 官方立场调整默认值 |
| `GET /api/oauth/usage` 对高频调用敏感，易 429 | 套餐面板刷新失败/被限流 | 客户端内存节流（与上次调用间隔 < 60s 直接复用结果，§4.11）；失败静默降级为「暂无统计」，不重试风暴；带 `User-Agent: claude-code/<version>` 降低 429 概率 |
| `GET /v1/models` 动态 catalog 与静态 fallback 目录字段不完全一致（新增/下线模型不同步） | 模型选择器展示与实际账号权限不符 | 动态结果优先，静态仅在动态失败/关闭时兜底；`AgentModelInfo.raw` 保留原始 capabilities 字段供排障；两套目录都走同一 `AgentModelInfo` 形状，UI 无感知差异 |

## 11. 明确不做（MVP 边界）

- MCP server 透传给 CC（`--mcp-config`）
- Hooks（Zeta 尚无 hook 抽象；不新增）
- Custom slash commands 目录（`~/.claude/commands/`）
- Skills / subagents（`~/.claude/agents/`）
- `--fork-session` 分叉
- thinkingBudget 数值调档 UI
- Bedrock / Vertex 后端
- Cursor 类共享 session；Cursor 已退役，不打通 CC ↔ Cursor 历史
- accessToken 主动刷新（`POST /v1/oauth/token`）——续期完全由用户重新运行
  `claude` 或 `claude login` 完成（§4.10）；若后续要接，需专项评估与 CLI 自身
  续期逻辑的文件锁竞态及合规边界，不能顺手夹带
- 本地 usage 历史聚合 / 导出（`ccusage` 类工具形态）——§4.11 只做当前快照
  展示，不做跨会话统计
- Bedrock/Vertex、`statusline rate_limits` 通道等其他余量获取方式（§4.10 只做
  `GET /api/oauth/usage` 一条路径）

上述项目全部走 §8 M6+ 独立 PR，不塞进本次接入。

## 12. Checklist（PR 提交前）

- [ ] `AgentProviderKind.claudeCode` 分支在 `DefaultAgentProviderFactory` /
  `defaultsFor` / `AgentProviderIcon` / `_sanitizeProviderConfig` 全部覆盖
- [ ] `AgentDefinition.all` 追加 `claudeCode`
- [ ] `agent_provider_bundle.dart` **未新增** `switch(kind)` 分支
- [ ] 共享 pipeline / coalescing / timeline store **未 import**
  `datasources/claude_code/` 任何文件（架构测试通过）
- [ ] `permissionPolicy` / `planApproval` / `threadCatalog` / `modelCatalog`
  / `localThreadList` 端口通过 mixin 挂载
- [ ] Plan 审批链路：`AgentPlanApprovalRequest` ↔ 显式 Default 回合
  新建，权限与 plan 决策模型隔离
- [ ] 未持久化任何 prompt / 回复 / tool output / env / API key 原文
- [ ] `~/.claude/**` 除 stat / list 外，仅 §4.10 的 accessToken 内存读取一条
  例外路径，未读、未写其余内容
- [ ] 模型列表：动态 `GET /v1/models` 失败（401/429/超时/网络错误）时静态
  目录兜底路径手工验证过
- [ ] 套餐用量：`readUsageQuota()` 在未登录 / API Key 模式 / 401 / 429 /
  增强开关关闭下均返回 `null` 且不抛出未捕获异常
- [ ] `ClaudeCodeAnthropicApiClient` / `ClaudeCodeOAuthCredentialsReader` 未被
  日志、诊断、`agent_providers.json` 持久化 accessToken 原文或前缀
- [ ] 详情页「账号数据增强」开关关闭后，模型目录/套餐面板完全回退到静态/
  空状态，不再发起任何 REST 请求
- [ ] `dart format .` / `flutter analyze` / `flutter test` 干净
- [ ] Git 提交格式：Conventional Commits，摘要 ≤50 字符，`sh` 代码块提供

---

**下一步动作建议**：先做 §8 M0（骨架），产出一份能通过 analyze / test 的
最小改动 PR；再进入 M1（一次能跑起来的 hello turn）；之后按 M2-M4 顺序
迭代，每个阶段独立 PR 便于回滚。