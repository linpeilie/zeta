# Codex app-server 协议版本锁定

最后更新：2026-08-12

## 1. 目的

Zeta 的默认 Agent provider（`CodexAppServerAgentProvider`）按 Codex CLI
`app-server` 的 JSON-RPC 协议适配。协议随 CLI 版本演进，字段名、通知方法和
请求 schema 都可能静默变化。

本仓库用 **pinned schema 快照** 固定适配基准：升级 Codex 时先 diff schema，
再改适配层，避免“本机 CLI 已升级、代码仍按旧协议解析”的漂移。

## 2. 当前锁定版本

| 项 | 值 |
| --- | --- |
| Pinned Codex CLI | **0.144.5**（见 `third_party/codex_app_server_schema/PINNED_VERSION`） |
| 导出命令 | `codex app-server generate-json-schema --out <dir>` |
| Schema 快照目录 | [`third_party/codex_app_server_schema/`](../../third_party/codex_app_server_schema/) |
| 生成脚本 | [`tool/gen_codex_schema.sh`](../../tool/gen_codex_schema.sh)、[`tool/gen_codex_schema.ps1`](../../tool/gen_codex_schema.ps1) |
| 适配计划 | `plan/codex_app_server_adaptation_plan.md`（已随 `plan/` 目录移除，仅存于 Git 历史） |

> 说明：本次快照直接取自 `codex-rust-v0.144.5` release 源码中已生成的
> stable JSON Schema；未纳入实验性 API，也继续排除键序不稳定的 v2 聚合文件。

运行时仍通过 PATH / 安装目录解析 `codex`；**运行时 CLI 版本不必与 pin
完全一致**，但升级前应先做 schema diff，确认适配层仍覆盖关键方法。

Plan 模式目录、`turn/start.collaborationMode`、`thread/settings/updated`、
`item/plan/delta` 和 `item/tool/requestUserInput` 属于 experimental surface；
`turn/plan/updated` 是既有通知。稳定快照与实验验证采用双基线：

| 基线 | 版本 / 模式 | 用途 |
| --- | --- | --- |
| 仓库契约 | `0.144.5` stable | 代码评审、稳定方法 diff，不包含实验字段 |
| 真实运行验证 | 实际 CLI 生成的 experimental Schema + smoke | 运行时探测 Plan 能力，记录实际版本与结果 |

低于 pin 的本机 experimental Schema 只能作为兼容性证据，**不得**覆盖
`third_party/codex_app_server_schema` 的 stable pin。

## 3. Schema 快照内容

生成结果主要包括：

- 四个联合类型：`ClientRequest.json`、`ClientNotification.json`、
  `ServerNotification.json`、`ServerRequest.json`
- 聚合文件：`codex_app_server_protocol.schemas.json`
- 逐方法 schema：`v1/`、`v2/` 目录
- 元数据：`PINNED_VERSION`、`GENERATED.json`

> 注：CLI 导出的 `codex_app_server_protocol.v2.schemas.json` 的
> `definitions` 键序不稳定，脚本会主动排除；同等信息已在 `v2/*.json`
> 中按方法拆分保存。

不要手工编辑 JSON；一律通过生成脚本覆盖。

## 4. 重新生成

### macOS / Linux / Git Bash

```sh
./tool/gen_codex_schema.sh
```

### Windows PowerShell

```powershell
./tool/gen_codex_schema.ps1
```

常用选项：

| 选项 | 作用 |
| --- | --- |
| `--diff` / `-Diff` | 只对比当前 CLI 导出与已提交快照，不写入 |
| `--force` / `-Force` | 允许 CLI 版本与 `PINNED_VERSION` 不一致时覆盖快照 |
| `--experimental` / `-Experimental` | 附带实验性方法/字段 |
| `CODEX_BIN` / `-CodexBin` | 指定 Codex 可执行文件路径 |

Windows 上若 PATH 里的 npm 全局 `codex` 偏旧，脚本会优先尝试
`%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe`；也可显式传入：

```powershell
./tool/gen_codex_schema.ps1 -CodexBin "$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe"
```

## 5. 升级 Codex 协议的推荐流程

1. 安装目标版本 Codex CLI，确认 `codex --version`。
2. 运行生成脚本（版本变化时加 `--force` / `-Force`）。
3. `git diff --stat third_party/codex_app_server_schema`，重点看：
   - 四个联合类型的 method 增减
   - 已适配方法的 params / notification 字段变更
   - 服务端请求响应 schema（避免非法应答）
4. 按 diff 更新 `lib/src/features/agent` 适配层与测试。
5. 更新本文件的 pinned 版本说明，以及
   `plan/codex_app_server_adaptation_plan.md` 中的协议基准段落。
6. 用真实 `codex app-server --stdio` 做冒烟：
   - 核心链路：`python tool/smoke_codex_app_server.py --expected-version 0.144.5`
   - Plan 实验链路：`python tool/smoke_codex_plan_mode.py --expected-version 0.144.5`
7. 若本机版本不是目标版本，可省略 `--expected-version` 做兼容性诊断，但结果不能
   代替目标版本发布门禁，且不得据此覆盖 stable Schema。

## 6. 0.142.5 → 0.144.5 适配结论

- `turn/steer` 必须发送活动回合的 `expectedTurnId`，不得发送 `cwd`。
- `thread/read` 只发送 `threadId` 与 `includeTurns`，不再夹带 `itemsView`。
- `thread/rollback` 不再作为 Zeta 产品能力；编辑重试使用
  `thread/fork.lastTurnId` 创建新分支。
- `on-failure` 不再下发，旧持久化值迁移为 `on-request`。
- Permission Profile 的稳定能力仅声明发现，不承诺实验性的运行时选择。
- `initialize` 返回值被映射为运行时版本、兼容状态与动态能力，未知或旧版本
  采用保守降级。
- `account/rateLimits/read.rateLimitResetCredits.availableCount` 映射为中立配额快照中的
  可用重置卡数量。该总数可能大于 `credits` 明细长度，统计 UI 不得用明细条数推算；
  当前仅作只读展示，不接入 `account/rateLimitResetCredit/consume`。

## 7. 与适配层的关系

- UI / domain 只消费中立 `AgentEvent` 等模型，不直接读 schema JSON。
- Schema 快照是 **人工与 CI 可 diff 的协议真相源**，不是运行时依赖。
- 未匹配通知的 fine 日志与诊断计数（A7）用于发现 pin 之外的新方法；
  一旦确认需要适配，应同步更新快照与 mapper。

## 8. Plan experimental 协议与降级

Plan 能力只能在唯一一次 `initialize` 中通过 `experimentalApi: true` 协商。
握手后调用无分页、空参数的 `collaborationMode/list`，目录至少包含 Default / Plan
时才向 UI 暴露选择器。显式模式随每个新 `turn/start` 发送；发送
`collaborationMode.settings` 时不再发送冲突的顶层 model / effort。退出 sticky
Plan 必须显式发送 Default，不能用省略字段代替。

降级规则：

- `initialize` 拒绝 experimental capability、目录方法返回 method-not-found、响应损坏或
  缺少内置模式：本次 runtime generation 将模式端口视为不可用，隐藏选择器，沿用原有
  Default 发送路径；普通对话、模型选择和历史读取继续可用。
- transport / timeout 属于临时不可用，可由用户重试；Provider 或进程重建后重新探测，
  不把旧 generation 的失败写成永久能力。
- 已进入 Plan 但未收到 `turn/plan/updated` 时，时间线仍可使用
  `item/plan/delta` / completed Plan item；不得伪造结构化步骤。
- collaboration mode 是 Zeta 本地 thread 快照的粘性状态。`thread/read` 不回放该设置时，
  重启后先恢复本地快照，再由下一次 `turn/start` 和
  `thread/settings/updated` 收敛服务端确认态。

### 8.1 用户提问响应语义

`item/tool/requestUserInput` 是独立的用户提问请求，不属于权限审批：

- data 层通过 question mapper 映射为 `AgentQuestionRequest`，并保存在独立 pending
  question registry；不得放入 approval mapper 或 permission registry。
- 客户端响应固定为 `{answers: {questionId: {answers: [...]}}}`；空 `answers` 表示
  Skip。该协议没有 approve、deny 或 cancel turn 响应变体。
- `serverRequest/resolved` 和连接关闭必须按请求所属 registry 清理提问状态，避免
  回写已由其他客户端解决的请求。
- 计划审批继续使用独立的 `AgentPlanApprovalRequest/Decision`，不与用户提问互转。

### 8.2 Plan 完成后的本地执行交接

当前 App Server 协议没有“Plan 回合完成后请求用户确认是否执行”的 server request。
Zeta 在 application 层根据成功的 Plan turn 和已归一化的 Plan 内容创建本地
`AgentPlanExecutionRequest`；该请求不进入 JSON-RPC、JSONL 历史或 Provider pending
registry。

- Run plan：先把下一回合 draft 切到 Default，再通过正常 `turn/start` 发送本地交接提示。
- Keep planning：清除交接卡、保持 Plan，并返回 Composer；不会产生 RPC。
- Dismiss：仅清除本地请求；不会向服务端发送 accepted/rejected/cancelled。
- 命令、文件、网络等权限仍由既有审批请求逐项处理，Run plan 不构成预授权。
- `AgentPlanApprovalRequest` 仍只表示 Provider 主动发起的独立计划审批，不能用于本地交接。

### 8.3 真实 smoke 记录

2026-07-23 使用 `tool/smoke_codex_plan_mode.py` 完成一次脱敏兼容性运行：

| 项 | 结果 |
| --- | --- |
| OS / 架构 | Windows / AMD64 |
| 实际 Codex CLI | `0.144.1` |
| 仓库 stable pin | `0.144.5` |
| Schema 模式 | experimental（由实际 CLI 生成并核对） |
| 结果 | 18/19 通过；`turn/plan/updated` 未出现，严格 smoke 返回失败 |
| 已验证 | experimental initialize、Default/Plan 目录、Plan/Default settings、Plan delta、用户提问应答、下一 turn 才切模式、重启 resume、本地 mode 恢复与 settings 收敛 |
| 未替代的门禁 | `0.144.5` experimental 真实运行仍需在具备对应 CLI 的环境执行 |

smoke 只输出平台、版本、Schema 模式、检查项、方法名和计数；不输出或持久化
Prompt、回复、文件内容、凭证、原始 JSONL、thread/turn id 或 stderr 原文。脚本使用临时
空 workspace、只读 sandbox，并默认归档自己创建的 thread。

### 8.4 Skills

Zeta 将 Codex Skills 映射为中立 domain 模型与 Composer token：

| Codex | Zeta |
| --- | --- |
| `skills/list` | `AgentSkillsPort.listSkills` → `AgentSkillsCatalog` |
| `skills/changed` | `AgentSkillsPort.skillsChanged`（失效信号） |
| `UserInput` `{ type: "skill", name, path }` | `AgentUserInput.skill` |
| 文本 marker `$<name>` | Composer chip / 序列化文本；Codex 用户消息常呈现为 `[$name](path)`；历史展平为 `$name` |

发送回合时同时携带文本 `$name` 与结构化 `skill` item（Codex 推荐路径）。
`skills/extraRoots/set` 尚未接入。

### 8.5 文件变更证据

Codex 文件变更分为 App-Server 结构化 tool、本地 JSONL `patch_apply_end`、turn 实时 fallback
与 command-only 四条互不冒充的路径。`CodexFileChangeTracker` 在 data 层完成 identity、
累计快照和优先级；共享 TimelineStore 与 UI 不读取 App Server 或 session JSONL raw 字段。

| App Server 输入 | Zeta 映射 |
| --- | --- |
| `fileChange` ThreadItem、`item/fileChange/patchUpdated.changes[]` | `path`、`kind.type`、可选 `move_path` 与 `diff` → replayable tool-scoped `AgentFileChangeSnapshot` + unified patch evidence |
| 本地 session JSONL `patch_apply_end.changes` | 以 map key 作为 Provider 明示路径；`update.unified_diff` → unified patch，`add.content` → written content，`delete` 无合适 evidence 时只保留动作摘要，非空 `move_path` → moved；结果是 replayable tool snapshot |
| `item/fileChange/outputDelta` 或缺少合法 `changes` | 只保留普通工具进度；已有合法 snapshot 可继续携带，不从文本制造 evidence |
| `turn/diff/updated` | 在 Codex data 层拆成 per-file typed `liveOnly` turn snapshot，仅作为 tool 证据缺失时的实时 fallback |
| `commandExecution` | 普通 execute tool；不解析 command、`commandActions`、审批参数或工作区结果，不生成文件变更 snapshot |

同一 turn 已有结构化 tool snapshot 时，后到的 turn aggregate 被抑制；若 turn fallback 先可见，
后到的 tool snapshot 会先产生 empty turn snapshot 清除 fallback。Store/UI 不按路径跨 owner
去重，也不从 unified patch header 反推文件 identity 或动作。`thread/read` 能恢复的结构化
fileChange 使用独立 history tracker 重建。本地 JSONL 优先时，`patch_apply_end` 的 call id 作为
独立 Apply patch owner；它不必与外层 `custom_tool_call(name: exec)` 相同。缺失或损坏的
`changes` 保持普通工具降级，不解析 exec input、stdout 或 raw 补证据。turn fallback 明确不可
作为历史完整性证据。

当前环境若只观察到 `commandExecution`，正确降级就是保留命令卡而不显示文件变更卡。
schema fixture 只证明结构化兼容路径，不能冒充当前运行时实测。所有 malformed/ignored 诊断
只记录 method/type/reason/count，不记录命令、路径、patch、raw payload 或 stderr 原文。
