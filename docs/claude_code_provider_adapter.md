# Claude Code Provider 接入适配文档

> 目的：将 Anthropic 的 Claude Code CLI 作为 **第三个** Agent Provider 接入
> Zeta（与 Codex app-server、Grok ACP 并列），复用 `~/.claude` 已登录态，覆盖
> 基础对话 / 工具时间线 / 权限审批 / Plan 审批 / 会话历史 / 模型目录 /
> MCP·hooks 透传等能力。本文档同时作为落地任务清单与评审基线。
>
> **约束基线**：本文档不重复 `CLAUDE.md`、`AGENTS.md`、
> `docs/developer_guide.md` 已固化的规则。凡涉及事件管线、共享适配层、feature
> 目录约束、Git 提交格式的部分，仍以那三份文档为准。发生冲突时，本文档服从
> 上述权威文档，同时在此登记差异并触发同步修订。

## 0. 决策速览

| 决策项 | 结论 | 依据 |
| --- | --- | --- |
| 接入形态 | Claude Code CLI 常驻子进程，`--print --input-format stream-json --output-format stream-json --verbose` | 与现有 Codex/Grok stdio 模型同构；零 SDK/Node 依赖；官方稳定支持（备选方案对比见 §0.1） |
| 认证 | 复用 `claude` 已登录态（`~/.claude/.credentials.json` / OAuth cache），Zeta 只做检测 | 与 Codex/Grok 一致；避免重复实现 login |
| 上架方式 | 独立第 3 个 Provider（`AgentProviderKind.claudeCode`） | 骨架已预留：枚举、`defaultsFor`、`DefaultAgentProviderFactory` 均已留分支 |
| MVP 能力 | 对话/工具 + 权限审批 + Plan 审批 + 会话历史/resume + 模型目录 + MCP/hooks 透传 | 与用户澄清结论一致 |
| Default provider | 保持 Codex 为默认，Claude Code 与 Grok 一样是可选项 | 降低回滚风险；`AgentDefinition.all` 追加即可 |
| 数据边界 | 严禁读写 `~/.claude` 之外的 Claude 状态；Zeta 自有数据仍在 `~/.zeta/` | 与 CLAUDE.md「持久化」条款一致 |

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
| supportsUsage | ✅ | ✅ | ✅（stream-json 的 `usage` 字段） |

> 未列出的字段（如 `supportsTextInput`）沿用 Codex 相同默认。

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
> `docs/codex_app_server_protocol.md` 的版本锁定流程，为 Claude Code 建立
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
    + claude_code_model_catalog.dart           # 静态目录 + fallback
    + claude_code_session_history_reader.dart  # 读 ~/.claude/projects/<encoded-cwd>/*.jsonl
+ src/features/agent/data/mappers/
    + claude_code_permission_mode_codec.dart   # 中立 optionId ↔ CLI --permission-mode
    + claude_code_message_content_codec.dart   # content block ↔ AgentMessage segment
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
+ test/src/features/agent_management/data/
    + claude_code_agent_management_repository_test.dart
+ test/src/features/agent/data/
    + default_agent_provider_factory_test.dart        # 追加 claudeCode 分支断言
+ tool/smoke_claude_code_stream_json.py               # 真实 CLI 冒烟（可选，二期）
```

### 3.7 文档

```
+ docs/claude_code_stream_json_protocol.md    # 协议版本锁定（对齐 codex_app_server_protocol.md）
~ docs/developer_guide.md                     # 追加 CC 特有的启动/权限章节；§7 的 16 条清单以 CC 为例补充
~ docs/design_document.md                     # 更新 Provider 表
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
  `modelCatalog`，Provider 需要实现 `listModels`（走 §4.6）。

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

- Claude Code 无 `model/list` 端点。静态目录：

  | optionId | 展示名 | 场景 |
    | --- | --- | --- |
  | `claude-opus-4-7` | Opus 4.7 | 默认高性能 |
  | `claude-sonnet-4-6` | Sonnet 4.6 | 主力性价比 |
  | `claude-haiku-4-5-20251001` | Haiku 4.5 | 低延迟 |
  | `opus` / `sonnet` / `haiku` | 别名 | 兼容 `--model` 短写 |

- `AgentModelCatalogRepository`（app 级）继续做 SWR + 单飞，但
  `Provider.listModels` 直接返回静态列表——`config` 指纹变化时也不打网络。
- `AgentModelPreference` 沿用：Zeta 侧记住用户选择；Fast/reasoning effort
  MVP 不暴露（CC 用 `thinkingBudget` 数值，展示上属另一个交互模型，二期做）。
- **禁止**读取 `~/.claude` 下的 model 缓存（数据边界）。

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
5. **modelList**：直接返回静态目录（无网络调用）。

**日志路径**：`discoverLogPaths` 返回 `~/.claude/logs/*.log`（若存在）。

### 7.2 认证策略

| 用户场景 | Zeta 行为 |
| --- | --- |
| 已 `claude login` | 直接跑，不注入 env |
| 未登录 | 详情页显示「运行 `claude login` 后重试」，Zeta 不代跑 |
| 设置页填 API Key（可选） | 值放入子进程 env `ANTHROPIC_API_KEY`；**Zeta 落盘时脱敏**（`extra` 里只存 `hasApiKey=true` 与 masked 后 4 位）；真值由 OS keychain 存（沿用现有 secure storage；如无现成通路则 MVP 不做，只显式提示不落盘） |
| Bedrock / Vertex | 二期；MVP 不做，UI 明确标注 |

**硬性约束**（对齐 CLAUDE.md）：

- 不读、不写 `~/.claude/.credentials.json` 内容；
- Zeta 侧配置文件 `~/.zeta/config/agent_providers.json` 不落原始 key、不落
  prompt/回复/tool output/环境变量原文；
- 会话 hidden list、tool allow-list 白名单字段可持久化。

## 8. 分阶段落地计划

| 阶段 | 交付物 | 完成判据 |
| --- | --- | --- |
| **M0 · 骨架** | `AgentDefinition.claudeCode` + `defaultsFor` 真实能力 + `DefaultAgentProviderFactory` 分支替换为**空 provider**（返回错误的 initialize） | `default_agent_provider_factory_test.dart` claude_code 分支不再 throw；`AgentProviderIcon` 出图；设置页出现 Claude Code 条目 |
| **M1 · 联通** | StreamJsonPeer + ProcessStarter + Provider.initialize + mapper 覆盖 `system.init`/`assistant.text`/`user.tool_result`/`result` | 手工新建一条 thread，能发一句话拿到回复；`flutter analyze` + 新 mapper 单测通过 |
| **M2 · 工具时间线** | mapper 覆盖 `thinking`/`tool_use` 完整生命周期 + `AgentTokenUsageEvent` + turn 状态归一化 | 工具卡片、reasoning phase、usage 全部出；`agent_event_storm_fixture_test.dart` 追加 CC fixture |
| **M3 · 权限 + Plan** | ControlRequestHandler + PermissionPolicyAdapter + PlanApprovalAdapter + 4 选项 catalog + 显式 Default 执行回合 | 权限模式条可切；plan → 审批 → 执行链路手工通；单测覆盖所有 4 个 optionId |
| **M4 · 历史 / resume** | SessionHistoryReader + `--resume` 参数拼装 + hidden list | 重启 Zeta 后能看到历史 thread、点开恢复；损坏 jsonl 不阻断启动 |
| **M5 · 打磨** | CLI 检测四阶段 + 日志页 + 详情页文案 + 图标 + 文档 | detect 完整跑通；`docs/claude_code_stream_json_protocol.md` 归档 schema；`docs/design_document.md` 更新 |
| **M6+ · 二期** | fork、skills（`~/.claude/agents/`）、MCP config 透传、thinkingBudget、Bedrock/Vertex | 独立 PR，按需排 |

每个阶段结束：`dart format .` → `flutter analyze` → `flutter test`（对齐
CLAUDE.md「每次代码修改后」章节）。

## 9. 测试策略

对齐 `docs/engineering_standards.md` 与 CLAUDE.md：

1. **共享层守卫**：新增 fixture-based 架构测试，断言
   `agent_event_coalescing_policy.dart`、`agent_event_pipeline.dart`、
   `agent_conversation_timeline_store.dart` 不 import 任何
   `datasources/claude_code/` 路径。
2. **契约测试（provider 无关）**：mapper 用 golden fixtures
   （`test/src/features/agent/data/datasources/claude_code/fixtures/*.jsonl`）
   驱动，断言 → `AgentEvent` 序列匹配预期。fixture 从真实 CLI 生成一次
   后冻结，schema 演进时同步 `docs/claude_code_stream_json_protocol.md`。
3. **单元测试**：permission adapter / plan adapter / session history reader
   各自 A/A/A，用 fake `StreamJsonPeer`；不 mock。
4. **AgentEvent 16 条清单**：新增/改动 event 时逐项回答
   `docs/developer_guide.md §7`；MVP 若不新增 event，只需在 PR
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

## 11. 明确不做（MVP 边界）

- MCP server 透传给 CC（`--mcp-config`）
- Hooks（Zeta 尚无 hook 抽象；不新增）
- Custom slash commands 目录（`~/.claude/commands/`）
- Skills / subagents（`~/.claude/agents/`）
- `--fork-session` 分叉
- thinkingBudget 数值调档 UI
- Bedrock / Vertex 后端
- Cursor 类共享 session；Cursor 已退役，不打通 CC ↔ Cursor 历史

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
- [ ] `~/.claude/**` 除 stat / list 外未读、未写
- [ ] `dart format .` / `flutter analyze` / `flutter test` 干净
- [ ] Git 提交格式：Conventional Commits，摘要 ≤50 字符，`sh` 代码块提供

---

**下一步动作建议**：先做 §8 M0（骨架），产出一份能通过 analyze / test 的
最小改动 PR；再进入 M1（一次能跑起来的 hello turn）；之后按 M2-M4 顺序
迭代，每个阶段独立 PR 便于回滚。