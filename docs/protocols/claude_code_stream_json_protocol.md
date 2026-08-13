# Claude Code stream-json 协议基线

最后更新：2026-08-12

本文记录 Zeta 当前 Claude Code Provider 的实际协议边界、已验证帧形状和升级门禁。
它是实现与维护时的事实基线；早期取舍和未落地设想见
[Claude Code Provider 接入适配文档（历史提案）](./claude_code_provider_adapter.md)。

## 1. 基线与适用范围

| 项目 | 基线 |
| --- | --- |
| 对话取样 | Windows 10 / x64，CLI `2.1.224`，`system.init` 自报 `2.1.220` |
| metadata 实测取样 | macOS / arm64，CLI `2.1.228` |
| 核心链路冒烟 | macOS / x86_64，CLI `2.1.227` |
| 取样日期 | 2026-08-11—2026-08-12 |
| 传输 | stdin/stdout 行分隔 JSON（stream-json） |
| fixture | `test/src/features/agent/data/datasources/claude_code/fixtures/` |

CLI 自报版本与 `system.init` 版本可能不同。Zeta 分别保留二者的诊断语义，不把其中
一个改写成另一个，也不据此推断协议兼容。

当前基线覆盖：新建与恢复会话、连续多回合、文本/思考/工具时间线、Edit/Write 文件变更证据、取消、权限审批、
Plan 审批与本地执行交接、只读历史、从 Zeta 列表隐藏记录、CLI 有效模型选项、套餐名称、
可选额度详情、下一回合模型切换和 `/compact`。模型与套餐 metadata 边界见 §7 和 §11。

## 2. 进程启动

固定参数前缀：

```text
claude --print --input-format stream-json --output-format stream-json --verbose
```

Zeta 按以下稳定顺序追加参数：

1. 新会话使用 `--session-id <id>`；恢复使用 `--resume <id>`，两者互斥。
2. 选定模型时追加 `--model <model>`。
3. 选定推理档位时追加 `--effort <level>`。
4. 交互审批追加 `--permission-prompt-tool stdio`。
5. 追加 `--permission-mode <mode>`。
6. 仅显式启用时追加 `--include-partial-messages` 或
   `--no-session-persistence`。
7. 最后追加用户配置的额外参数。

默认实时路径不启用 partial messages。进程以当前项目为 working directory；Zeta 不把
prompt、文件内容或凭证写入启动日志。

模型、套餐名称和显式连接测试使用独立的短生命周期 metadata 进程，不复用会话 peer：

```text
claude --print --input-format stream-json --output-format stream-json --verbose \
  --no-session-persistence --setting-sources user
```

该进程只接收 `control_request.initialize`，不发送 `type:user` 或 Prompt。Zeta 不创建
Claude session 文件；但 Claude CLI 仍可能维护自己的认证、bootstrap 或缓存状态，因此这里
不承诺 CLI 进程对其自有目录绝对零写入。

## 3. transport 约束

`StreamJsonPeer` 把每个换行分隔的 JSON object 视为独立事件，不实现 JSON-RPC
request/result 配对。

- stdout 半行可跨 chunk 拼接；损坏 UTF-8 以替换字符继续解码。
- 单行默认上限为 4 MiB。超限或非法 JSON 进入无原文的协议诊断，后续行继续处理。
- stdin 写入严格串行，避免并发帧交错。
- `close` 先等待已入队写入，再关闭 stdin、终止进程；超时后强制终止。
- 日志只记录帧长度、类型和计数，不记录帧正文或 stderr 原文。

实测 `--print` + stream-json 进程在一个 `result` 后保持存活，可以继续接收下一条
user 帧；关闭 stdin 才结束进程。每回合可能重复发送同 session 的 `system.init`，mapper
必须幂等。

## 4. Zeta → Claude Code

### 4.1 用户回合

```json
{
  "type": "user",
  "session_id": "<session-id>",
  "parent_tool_use_id": null,
  "message": {
    "role": "user",
    "content": [
      {"type": "text", "text": "<prompt>"}
    ]
  }
}
```

Provider 在写入前自行 mint 中立 `turnId`，并让该 id 在整个回合内稳定。Claude Code
wire 没有宿主侧 turn id，因此这个责任不能下沉给共享 TimelineStore。

### 4.2 中断

```json
{"type":"control","subtype":"interrupt"}
```

取消、需要终止回合的权限拒绝和 Plan 取消都可写出 interrupt，但各自的领域决策和
pending registry 保持隔离。

### 4.3 权限与 Plan 响应

`control_request.request_id` 只用于对应的 `control_response`。工具审批按
`request.tool_use_id` 配对工具，Plan 审批只接管已观察到的 `ExitPlanMode` tool id。
具体 allow/deny payload 由各自 adapter 编码；未知、缺字段或冲突请求一律 fail-closed。

## 5. Claude Code → Zeta

| `type` / `subtype` | 当前处理 |
| --- | --- |
| `system.init` | 校验 session，产出 session started + idle；同 session 重复 init 幂等 |
| `assistant` text | 映射为 message update；同 message 的连续块由 Provider identity 分段 |
| `assistant` thinking | 映射为 reasoning delta；text/tool 边界关闭当前 phase |
| `assistant` tool_use | 按 tool id 原位创建/更新工具卡；Edit/Write 等由 Claude-local tracker 产生文件变更快照，`ExitPlanMode` 交给 Plan adapter |
| `user` tool_result | 按 `tool_use_id` 更新为 completed/failed；缺 `is_error` 视为成功，并携带对应 tool_use 已记录的完整快照 |
| `control_request` / `can_use_tool` | Provider 路由到权限或 Plan pending registry |
| `result` | first-terminal-wins；映射回合终态及本回合 usage |
| 未识别 type | 只增加诊断计数并丢弃，不抛异常、不阻断后续帧 |

当前已见但故意忽略的帧包括 `rate_limit_event` 和
`system/thinking_tokens`。它们不能伪装成 reasoning、用量或终态事件。

`result.usage` 是本回合绝对用量，映射时
`isSessionCumulative: false`。已取样字段为 `input_tokens`、`output_tokens`、
`cache_creation_input_tokens` 和 `cache_read_input_tokens`。

## 6. 身份、终态与作用域

Claude Code 的 source message/tool id 仅是 Provider metadata。entryId、message segment、
reasoning phase、去重、迟到事件和终态竞态全部由
`ClaudeCodeStreamIdentity` 在 data 层决定。

- 写 user 帧之前 `beginTurn`，同一 turn 的所有事件使用同一个 Zeta turnId。
- message、reasoning 与 tool 边界由 Provider identity 明确关闭。
- terminal first-wins；终态后的新正文丢弃，已知工具的迟到 terminal update 仍可收口。
- runtime/session/turn 不匹配的事件 fail-closed。
- live 与 history 使用独立 identity/reducer 实例，只用 canonical signature 做逐位置回归。
- diagnostics 与 runtime 诊断快照只含计数和白名单状态，不含 source id、正文或原始 payload；
  本节不指内存中的 typed 文件变更 snapshot。

### 6.1 文件变更证据

Claude Code 的结构化文件证据来自 `assistant.tool_use.input`，不是普通字符串
`user.tool_result`。`ClaudeCodeFileChangeTracker` 按 runtime/session/turn/toolUseId 隔离，
在 tool_use 记录 typed snapshot，在 tool_result 原位更新终态时重新携带同一 snapshot：

| Claude Code tool | Zeta evidence |
| --- | --- |
| `Edit` | `file_path + old_string + new_string + replace_all` → modified replacement snippets；片段不代表完整文件 |
| `Write` | `file_path + content` → written content；没有协议保证时动作保持 unknown，不按文件是否存在猜 created/modified |
| `NotebookEdit` / `MultiEdit` | 只映射已确认路径与 unknown 摘要；未取得真实结构化 fixture 前不解析未知正文 |
| 其他 tool | 不生成 file-change snapshot |

成功、失败工具都保留“尝试执行时 Provider 给出的证据”，实际结果由 tool status 表达；不能把
tool_use 的写入请求直接描述成已经落盘。turn 完成、session/runtime 失效和 dispose 都清理
tracker。live 与 history 使用独立 mapper/tracker，并对 replayable snapshot 的 owner、change
id、顺序、动作、evidence 与终态做逐位置回归。

presentation 只消费 typed snapshot，不读取 `file_path`、`old_string`、`new_string`、`content`
等 wire key；这些正文也不得进入日志、缓存、通知、thread summary 或 Zeta 持久化 JSON。

## 7. Session init、恢复、模型目录与切换

首个 `system.init.session_id` 必须匹配请求的新建/恢复 session。若不匹配，Provider 产出
错误并拒绝把该 runtime 绑定到意外会话；同 runtime 后续 init 也不会重新放行。

`ClaudeCodeCliMetadataProbe` 向独立进程发送带随机 request id 的
`control_request.initialize`，只接受同 id 的成功 `control_response`。模型目录来自
`response.models`，保留 CLI 顺序，以 `value` 作为稳定 id 和 `--model` 参数；旧形状缺少
`value` 时才读取 `name`。Claude 专属的 `value=default` 别名不进入 Composer；
`resolvedModel` 只投影为中立 `AgentModelInfo.model`，用于把历史中的实际模型名归一化回
稳定 `value`，不会保留原始模型 payload。模型声明 `supportsEffort=true` 时，
`supportedEffortLevels` 按 CLI 顺序映射为中立 `supportedReasoningEfforts`；选中值在下一回合
作为 `--effort` 参数。账号身份字段、未知字段，以及尚未接入中立契约的 Fast/auto 能力
均不会上浮或落盘。

这份目录表示**当前 CLI 在当前配置下给出的有效选项快照**。initialize 可能受 Claude CLI
自身 bootstrap、账号权限与缓存影响；它不是 Zeta 直接同步调用的实时远端 API，也不保证
列出 Anthropic 的全部模型。Zeta 不再调用 `/v1/models`，也不维护内置静态 Claude 目录。

应用级 `AgentModelCatalogRepository` 是唯一 TTL 真源：新鲜缓存保留 1 小时，失败时最多
保留 7 天 stale snapshot；刷新成功才覆盖 `agent_models_v1.json`。首次读取失败或 CLI 返回
空目录时不写空缓存，Composer 显示模型加载失败。Provider-local coordinator 只合并并发中的
metadata 探测，不用已完成快照挡住显式刷新。

打开历史时若缓存目录还没有可匹配的 resolved model，Zeta 强制刷新一次模型目录；刷新后
仍不可匹配则保留当前有效模型，不把已下架的历史模型写成 Composer 的孤儿选中值。

模型或推理档位切换不打断运行中的 turn：选择只影响下一回合；下一回合前，Provider 在
空闲边界关闭 peer，以原 session `--resume` 并携带新的 `--model` / `--effort` 恢复。
若新 peer 启动失败，会尝试恢复上一组模型配置，且不会静默吞掉原失败。

## 8. 权限与 Plan

权限模式的稳定映射：

| Zeta optionId | `--permission-mode` |
| --- | --- |
| `:ask` | `default` |
| `:accept-edits` | `acceptEdits` |
| `:plan` | `plan` |
| `:bypass` | `bypassPermissions` |

未知或空值一律回落 `:ask`，绝不默认到 bypass。空闲时切换权限会以同 session 重启并
恢复 peer；运行中切换被拒绝。会话级 remembered decision 只允许保存 tool name 与
allow/deny 白名单字段。

Plan 审批与普通权限审批使用不同 registry、request/decision 模型和回写路径。
`ExitPlanMode` 获批后的执行确认属于 Zeta 本地工作流：成功终态后新建显式 Default
回合，不 steer 当前回合、不调用 Plan 审批端口，也不预授权计划中的命令、文件或网络。

## 9. 本地历史与隐藏列表

Claude Code 项目历史目录为：

```text
~/.claude/projects/<encoded-project-path>/*.jsonl
```

路径编码规则已由 Windows fixture 冻结：

```dart
absolutePath.replaceAll(RegExp(r'[\\/:]'), '-')
```

列表只读取每个文件的有界头尾窗口，跳过损坏行并计数，不跟随符号链接，也不改写
Claude Code 文件。完整 history 有自己的 parser/identity/reducer；磁盘 JSONL 不能当作
live stream 原样送入 mapper。

“从列表移除”只把 project-scoped thread key 写入 Zeta 自有、版本化且宽容解码的
hidden list；原始 Claude history 保留不动。

## 10. Compact 与连接检测

Claude Code 没有独立 compact 控制帧。Zeta 把 `/compact` 作为普通 user turn 发送，
等待该回合终态后才释放当前 Binding 活动租约。Composer 入口仅在 capability 开启且
当前会话可写、空闲时显示；后续普通回合继续使用原 session。

Agent 管理的自动 detect 不发送 Prompt，也不做连接握手，只做：

- `claude --version`；
- `claude auth status --json` 的白名单投影；
- 日志路径枚举，不读取日志正文。

合法 `loggedIn=false` 是明确的未登录证据；命令缺失、输出损坏或探测失败是“认证证据不可用”，
不能通过 `.credentials.json`、`oauth.json` 等文件名猜成 loggedOut。认证证据与 CLI 可用性
相互独立：即使 `loggedIn=false`，用户仍可显式测试当前自定义 Provider/API key 路径。

只有用户显式点击“测试连接”才启动短生命周期 metadata peer，使用临时目录和
`--no-session-persistence`，只等待匹配 id 的 initialize response。它不创建 session、不发送
Prompt、不等待模型 result；但 Claude CLI 可能访问网络并维护自己的认证/bootstrap 缓存，
UI 必须如实说明这一边界。登录指引使用 `claude auth login`。

## 11. 套餐名称与可选额度详情

套餐展示名来自同一 initialize payload 的 `account.subscriptionType`，由 Claude-local mapper
归一化为 `Claude Pro`、`Claude Max`、`Claude Team` 或 `Claude Enterprise`。它不依赖
`claudeCode.accountDataEnrichment`；关闭额度详情增强时，模型目录和套餐名称仍可读取。

额度窗口是独立、可关闭的只读增强：

- 仅在 `claudeCode.accountDataEnrichment=true`、非 API key 模式、OAuth token 未过期，且
  scopes 同时含 `user:inference` 与 `user:profile` 时请求 `GET /api/oauth/usage`。
- HTTP 超时为 5 秒，不重试；Provider 实例内并发 single-flight，并对成功或失败尝试节流
  60 秒。401、429、超时、损坏响应或网络失败都降级为 plan-only snapshot。
- 映射 `five_hour`、`seven_day`、可选 `seven_day_sonnet` / `seven_day_opus` 和
  `extra_usage`。`monthly_limit=null` 只表示 unlimited；不得猜币种、余额或绝对 Token 总额。
- macOS 优先通过参数化 `security find-generic-password` 读取 Claude Code Keychain 条目，
  miss、拒绝、损坏或超时后才回退 Claude 自有 credentials 文件；Windows 使用 Claude 自有
  credentials 文件。凭据只在一次请求期间存在于内存，不进入 Zeta 配置、缓存或日志。

配置 key 为兼容旧数据继续保留，但 UI 名称是“额度详情增强”。它只控制上述凭据读取和
usage REST，不控制 initialize 模型或套餐名称。Zeta 不刷新、迁移、改写或删除 Claude
凭据；与此同时，也不能把“Zeta 不持久化 token”扩大解释为 Claude CLI 自己绝对不写状态。

## 12. 升级与验证

Claude Code stream-json 没有仓库内可生成的官方 schema pin。升级 CLI 时：

1. 在临时、最小权限、只读 workspace 复采脱敏帧。
2. 比较固定参数、user/control wire、init、assistant、tool、result/usage、
   `control_response.initialize`、`auth status --json` 与 usage schema。
3. 更新 Provider 自有 fixture；不得把 Claude fixture 放进共享层测试。
4. 跑 Provider mapper/identity/peer、live-history parity、权限、Plan、metadata、auth、额度、
   模型缓存与 compact 测试。
5. 跑共享层 purity guard，确认 Pipeline、Coalescing、TimelineStore 与 Provider 端口无
   Claude 专属改动。
6. 分别执行 `tool/smoke_claude_code_metadata.py` 与
   `tool/smoke_claude_code_stream_json.py` 的真实平台冒烟；若设备或凭据不可用，明确标记
   “待执行/阻塞”，不得推断通过。fixture 与 smoke 只输出版本、OS/架构、模型计数、套餐
   展示名和成败，不输出模型原始 payload、账号身份、路径、凭据、正文或 stderr。

### 12.1 真实兼容性冒烟记录

2026-08-11 使用 `tool/smoke_claude_code_stream_json.py` 完成一次脱敏真机运行：

| 项目 | 结果 |
| --- | --- |
| OS / 架构 | Darwin / x86_64 |
| Claude Code CLI | `2.1.227` |
| Schema / 包装器 | stream-json 行协议 |
| 结果 | `PASS (init+assistant+result)` |

该记录验证 2.1.227 对本基线核心 init / assistant / result 链路的兼容性，不把取样基线
2.1.224 静默改写成新的最低支持版本，也不替代其他声明平台的真实验收。输出未包含
prompt、回复、文件内容、路径、session/turn id、stderr 或原始 payload。

2026-08-12 的 metadata 契约另以 macOS / arm64、CLI 2.1.228 的脱敏真实形状，以及
Claude Code 2.8.4 逆向源码构造形状固定。它们共同覆盖 `value`、可选 `resolvedModel`、
未知字段和 `subscriptionType`，但 fixture 不能替代 Windows 与 macOS 的双平台真机冒烟。
