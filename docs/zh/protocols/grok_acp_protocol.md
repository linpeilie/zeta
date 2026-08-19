# Grok ACP 协议基线

中文 ｜ [English](../../en/protocols/grok_acp_protocol.md)

最后更新：2026-08-20

本文记录 Zeta Grok Provider 的实际协议边界、已验证消息形状和升级门禁。它是
`packages/grok_acp_client` 的实现与维护基线。

> **来源说明**：旧仓库没有 Grok 协议文档，本文由迁移基线 `bfd4241` 的实现代码
> 反向固化——`grok_acp_agent_provider.dart`（2,574 行）、`acp_session_update_decoder.dart`、
> `grok_session_update_mapper.dart`、`grok_acp_notification_mapper.dart`、
> `grok_process_starter.dart`、`grok_session_history_reader.dart`、
> `grok_billing_quota_mapper.dart`、`grok_permission_mode_codec.dart`、
> `grok_skills_mapper.dart` 与 `tool/smoke_grok_acp.py`。凡本文与上述代码冲突，
> 以代码为准并回头修订本文；迁移完成后本文升级为唯一基线。

## 1. 基线与适用范围

| 项目 | 基线 |
| --- | --- |
| 传输 | stdio JSON-RPC 2.0（标准 ACP） |
| 启动命令 | `grok agent [flags] stdio` |
| 协议族 | Agent Client Protocol（ACP）+ xAI `_x.ai/` 扩展 |
| 冒烟脚本 | `tool/smoke_grok_acp.py`（会话级独立进程 / 回收后恢复） |
| 本地历史 | `~/.grok/sessions`（`GROK_HOME` 可覆盖） |
| 实测平台 | Windows 11 10.0.26100，Grok CLI 1.0.5 (`5115b46bc9`)，2026-08-20 |

当前基线覆盖：新建与恢复会话、连续多回合、文本/思考/工具时间线、结构化 diff 文件变更证据、
取消、权限审批、Plan 模式与计划审批、结构化用户提问、只读历史、重命名与删除、模型目录、
推理档位、Skill 目录与套餐额度。

**ACP 当前只有 Grok 一个消费者**，因此不抽公共 ACP 包；`acp_session_update_decoder`
与 `acp_content_codec` 作为 `grok_acp_client` 的内部实现迁入
（见[迁移任务清单 步骤 14](../architecture/migration_tasks.md)）。

## 2. 进程启动

`GrokCliLocator` 在**每次启动前**重新解析 CLI，不复用持久化的旧路径——避免用户升级或
移动 Grok 后旧路径永久阻断初始化。定位失败抛 `ProcessException`，不静默降级。

参数规范化为 `agent [flags] stdio`：

| 配置形态 | 规范化结果 |
| --- | --- |
| 空参数 | `agent` + 模型 flags + `stdio` |
| 已含 `agent` … `stdio` | 在 `agent` 与 `stdio` 之间注入模型 flags |
| 其它自定义参数 | 原样保留，由调用方保证可启动 ACP |

模型 flags 按当前 Composer 选择动态解析（闭包读取，不在构造时冻结）：

- 选定模型时追加 `-m <model>`。
- 选定推理档位时追加 `--effort <level>`。

环境变量为 `Platform.environment` 叠加 `config.environment`。Zeta 不把 prompt、
文件内容或凭据写入启动日志。

## 3. 会话生命周期

标准 ACP 方法：

| 方法 | 用途 |
| --- | --- |
| `initialize` | 协议握手；返回 `authMethods` 时执行 best-effort 认证 |
| `session/new` | 新建会话 |
| `session/load` | 恢复会话；不支持时降级为本地历史重放 |
| `session/prompt` | 发起回合 |
| `session/cancel` | 取消当前回合 |
| `session/set_model` | 切换模型 |
| `session/request_permission` | **服务端→客户端**权限审批请求 |
| `fs/read_text_file` / `fs/write_text_file` | 服务端→客户端文件访问 |

`session/load` 不被支持时置 `_loadSupported = false`，后续恢复走本地历史重放；重放期间
`_suppressingSessionLoadReplay` 抑制重复事件，避免历史被当作 live 正文二次入库。

## 4. xAI 扩展方法

`_x.ai/` 是当前前缀，`x.ai/`（无下划线）是兼容前缀。两者必须同时接受，**不得**只认一个。

| 扩展方法 | 方向 | 用途 |
| --- | --- | --- |
| `_x.ai/session/update` | 服务端→客户端 | 与标准 `session/update` 同构的会话更新 |
| `_x.ai/session_notification` | 服务端→客户端 | 会话通知包装 |
| `_x.ai/session/prompt_complete` | 服务端→客户端 | 回合完成信号 |
| `_x.ai/session/rename` | 客户端→服务端 | 重命名会话 |
| `_x.ai/session/delete` | 客户端→服务端 | 删除会话 |
| `_x.ai/ask_user_question` | 服务端→客户端 | **结构化用户提问**，非权限审批 |
| `_x.ai/exit_plan_mode` | 服务端→客户端 | 计划审批请求 |
| `_x.ai/billing` | 客户端→服务端 | 账号套餐与额度快照 |
| `_x.ai/skills/list` | 客户端→服务端 | Skill 目录（本地 `SKILL.md` 扫描） |
| `_x.ai/yolo_mode_changed` | 客户端→服务端 | 权限模式变更通知 |

## 5. session/update 解码

`AcpSessionUpdateDecoder` 把每个 update 解码为 typed 值对象。缺 `sessionId` 一律
`AcpUnknownUpdate('missing_session_id')`，不抛异常。

| `sessionUpdate` kind | typed 结果 | 必需字段（缺失即 invalid） |
| --- | --- | --- |
| `user_message_chunk` | `AcpUserMessageChunk` | `content`；`_meta.hideFromScrollback` 控制是否入时间线 |
| `agent_message_chunk` | `AcpAgentMessageChunk` | `content` |
| `agent_thought_chunk` | `AcpAgentThoughtChunk` | `content` |
| `tool_call` / `tool_call_update` | `AcpToolCallUpdate` | `toolCallId` |
| `plan` | `AcpPlanUpdate` | 无（`entries` 可空） |
| `usage_update` | `AcpUsageUpdate` | `used` |
| `turn_completed` | `AcpTurnCompletedUpdate` | 无；`stop_reason` 缺失回落 `end_turn` |
| `current_mode_update` | `AcpCurrentModeUpdate` | `currentModeId` |
| `retry_state` | `AcpRetryStateUpdate` | 无；`type` 缺失回落 `unknown` |
| `session_info_update` | `AcpSessionInfoUpdate` | 无；携带实时 `title` 与 `modelId` |
| `session_summary_generated` | `AcpSessionSummaryGenerated` | 无；`session_summary` 常与正式标题同文 |
| 未知 kind | `AcpUnknownUpdate('unknown_kind')` | 只计诊断，不阻断后续帧 |

身份字段解析顺序固定，snake_case 与 camelCase 都接受：

- `promptId`：`update._meta.promptId` → `params._meta.promptId` → `update.promptId` → `update.prompt_id`
- `eventId`：`update._meta.eventId` → `params._meta.eventId`

`retry_state` 的 `type == 'exhausted'` 或 `is_rate_limited == true` 视为终态失败。

## 6. 权限模式

Grok 的权限模式经 `GrokPermissionModeCodec` 双向编解码，`clientIdentifier` 固定为 `zeta`：

| Zeta 模式 | wire id | 展示名 | 通知 flags |
| --- | --- | --- | --- |
| `ask` | `ask` | Ask | `permission_mode: ask`，`yolo_mode: false`，`auto_mode: false` |
| `auto` | `auto` | Auto | `autoMode: true` / `auto_mode: true` |
| `alwaysApprove` | `always-approve` | Always approve | `yoloMode: true` / `yolo_mode: true` |

解析时容忍的别名：`default`→`ask`；`always_approve`、`alwaysapprove`、`yolo`、
`bypasspermissions`、`bypass_permissions`→`alwaysApprove`。**未知或空值一律回落 `ask`，
绝不默认到 always-approve。** 模式变更经 `_x.ai/yolo_mode_changed` 通知服务端。

## 7. 用户提问与计划审批

三种语义使用**独立的 pending registry、请求/决策模型和回写路径**，互不转换：

| 语义 | 协议入口 | 中立模型 | 回写端口 |
| --- | --- | --- | --- |
| 权限审批 | `session/request_permission` | `AgentPermissionRequest/Decision` | `AgentPermissionResponsePort` |
| 用户提问 | `_x.ai/ask_user_question` | `AgentQuestionRequest/Response` | `AgentQuestionResponsePort` |
| 计划审批 | `_x.ai/exit_plan_mode` | `AgentPlanApprovalRequest/Decision` | `AgentPlanApprovalPort` |

`_x.ai/ask_user_question` **不是**权限审批：`GrokQuestionMapper` 在权限 handler 之前接管，
park 到 UI 并经 `respondToQuestion` 回写。它不得进入会话级 allow/deny 缓存。

未知、缺字段或冲突的 server request 一律 **fail-closed**——拒绝而不是放行。

## 8. 模型目录与推理档位

ACP 握手不提供模型列表，因此模型目录走**独立子进程降级路径**：

```text
grok models
```

`GrokModelsCli` 解析其文本输出为中立 `AgentModelList`；定位失败返回空列表并记 warning，
不伪造目录。上下文窗口经 `ContextWindowCodec` 解析，非正值丢弃。

模型切换有两条路径：会话内经 `session/set_model`；进程级经下次启动的 `-m` flag。
`updateModelSelection` 只更新内存选择，由 peer 工厂闭包在下次启动时读取。

## 9. Skill 目录

`_x.ai/skills/list` 返回本地 `SKILL.md` 扫描结果。响应可能带 ACP `ExtMethodResult`
envelope（`{"result": {"skills": [...]}}`），也可能直接是 `{"skills": [...]}`——
`GrokSkillsMapping` 两者都容忍，并分别计数：

- `entries`：该 cwd 下成功映射的 skill。
- 无法解析的响应/条目数。
- 因缺关键字段或处于禁用态被丢弃的 skill 数。

发送时以 `$name` 文本 marker 调用（Grok 无结构化 skill item 通道，这点与 Codex 不同）。

## 10. 文件变更证据

Grok 的结构化文件证据来自 tool content 中的 `diff` block，**不是**普通文本：

- 普通 content block 继续形成工具正文。
- `diff` block 单独保留为结构化 `AgentFileChangeSnapshot` 证据，不再生成
  `diff: <path>` 占位文本。
- `GrokFileChangeTracker` 按 runtime/session/turn/tool 隔离累计；新 turn 开始时释放同
  session 的旧累计状态。

Presentation 只消费 typed snapshot，不读 `rawInput` / `rawOutput` wire key；这些正文
也不得进入日志、缓存、通知、thread summary 或 Zeta 持久化 JSON。

## 11. 本地历史

Grok ACP **未实现 `session/list`**，因此项目 thread 列表依赖本地存储扫描。

家目录解析优先级固定：`GROK_HOME` → 注入路径（仅测试）→ `~/.grok`；都不可用时回落
相对路径 `.grok`。

```text
<grok-home>/sessions/
```

历史解析优先 `updates.jsonl`（与 `session/load` 回放同构），降级 `chat_history.jsonl`。
两个 parser 与 live mapper 使用**独立 identity/reducer 实例**——磁盘 JSONL 不能当作 live
stream 原样送入 mapper。

Grok 异步写 `generated_title`，因此首轮结束后按预设间隔轮询本地 `summary.json`；轮询有
上限，不无限重试。

## 12. 套餐额度

`_x.ai/billing` 响应经 `mapGrokBillingQuota` 映射为中立 `AgentUsageQuotaSnapshot`：

- `subscription_tier`（顶层或 `config` 内）→ `planType`；同时作为 `limitName`。
- `config` → primary window 与 on-demand window。
- credits 明细单独映射。
- 三者全空时返回 `null`，**不构造空快照**。

窗口标签与 Codex 共用时长文案（「1 周」/「5 小时」），不用「周额度」。**只使用协议实际
返回的字段**；不推算绝对 Token 总额或未提供的窗口。

## 13. 能力声明

Grok 的静态能力集（初始化前的保守声明，握手后以 `runtime.capabilities` 为准）：

| 开启 | 关闭及原因 |
| --- | --- |
| `canCreateSession`、`canResumeSession`、`canListThreads`、`canReadHistory`、`canDeleteThread`、`canRenameThread` | `canArchiveThread` / `canUnarchiveThread`：归档无协议支持 |
| `canPrompt`、`canCancelTurn` | `canSteerTurn`：ACP 无活动回合追加指令 |
| `supportsResourceInput`、`supportsSkillInput` | `supportsLocalImageInput`：本地图片当前只退化为路径文本 |
| `supportsPermissionRequests`、`supportsUserQuestions`、`supportsPlanApproval` | `canForkThread` / `canForkThreadAtTurn` / `canCompactThread`：无对应协议方法 |
| `supportsModelSelection`、`supportsModeSelection`、`supportsReasoningOptions`、`supportsUsage` | `supportsServiceTierSelection`：Grok 无服务档位概念 |

能力语义是**保守**的：只有能真实完成操作时才为 `true`。UI 用它隐藏入口，Bloc 与
Provider 在执行前仍需再次校验（见[迁移任务清单 步骤 33](../architecture/migration_tasks.md)）。

## 14. 升级与验证

Grok ACP 没有仓库内可生成的官方 schema pin。升级 Grok CLI 时：

1. 在临时、最小权限、只读 workspace 复采脱敏帧。
2. 比较启动参数、`initialize` 返回、`session/*` 方法、全部 `sessionUpdate` kind、
   `_x.ai/` 扩展方法名与前缀兼容性、billing 与 skills 响应形状。
3. 更新 `grok_acp_client` 自有 fixture；**不得**把 Grok fixture 放进
   `agent_provider_contracts` 或 `agent_conversation_repository` 的测试。
4. 跑 decoder / mapper / identity / peer、live-history parity、权限、Plan、提问、
   billing、skills 与模型目录测试。
5. 跑架构门禁，确认 `agent_conversation_repository` 与 `agent_provider_contracts`
   无 Grok 专属改动。
6. 执行 `tool/smoke_grok_acp.py` 真实冒烟。设备或凭据不可用时明确标记
   「待执行/阻塞」，**不得推断通过**。

### 14.1 冒烟脚本约束

`tool/smoke_grok_acp.py` 验证会话级独立进程与回收后恢复：起两个完全独立的
`grok agent stdio` 子进程（各自 initialize → authenticate → session/new），并发各发一条
消息，校验两条 `session/prompt` 都返回终态；随后关闭其中一个，用新进程 `session/load`
同一逻辑会话并再次发送。

隔离约束：临时隔离 workspace（每 session 一个空目录，不含真实项目文件，交互只读）；默认 `ask` 模式，
任何 `session/request_permission` 或其它服务端请求一律拒绝，保持非破坏性；prompt 极简且
不触发工具调用。

记录约束：只记录「哪个阶段成功/失败」，**不记录** prompt/回复原文、原始 payload、
sessionId、stderr 原文或凭据。

## 15. 实测补充基线

2026-08-20 在 Windows 11 / Grok CLI 1.0.5 上，以临时空目录和脱敏 smoke 取样：

- [x] `initialize.authMethods` 是对象数组；当前对象字段为 `id`、`name`、`description`。
  `cached_token` best-effort 认证成功；认证失败继续初始化的分支由注入故障 contract test 固定。
- [x] 当前 CLI 实际下发 `_x.ai/` 前缀；`x.ai/` 仅作为历史/兼容前缀继续由 decoder 接受。
- [x] `grok models` 形状为登录状态行、`Default model: <id>`、空行、`Available models:`，
  随后以 `* <id> (default)` 和 `- <id>` 列表展示。实测 default 为 `grok-4.6`，另有
  `grok-4.5`；模型集合本身不作为静态 pin。
- [x] `_x.ai/billing.config` 当前字段为 `creditUsagePercent`、`currentPeriod`、
  `onDemandCap`、`onDemandUsed`、`prepaidBalance`、`isUnifiedBillingUser`、
  `billingPeriodStart`、`billingPeriodEnd`。fixture 仅保留脱敏值。

真实 smoke 最终为 5/5：两个独立进程并发 prompt、AC1 隔离、新进程 `session/load` 恢复和
只记录字段名的协议 metadata 取样全部通过。首次运行在终态后立即回收时发生恢复超时；加入
2 秒有界异步持久化窗口后连续复跑通过，详见迁移执行决策日志。
