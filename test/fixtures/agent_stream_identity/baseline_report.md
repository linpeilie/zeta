# Phase 0 迁移前测试基线

## 运行上下文

- 日期：2026-07-17（Asia/Shanghai）
- 基线 commit：`f33b14f00ea67de922b3655666a4b07a07861d37`
- 工作区初始状态：`plan/agent_stream_identity_adaptation_plan.md` 为用户已有
  `AM` 修改；基线运行前未改动生产代码或测试代码。
- Flutter 输出中的镜像提示不是失败；所有命令退出码均为 `0`。

## 定向测试结果

| 范围 | 命令 | 结果 | 用例数 | 用时 |
|------|------|------|--------|------|
| ACP / Cursor mapper | `flutter test test/src/features/agent/data/mappers/` | PASS | 15 | 4.6s |
| Grok/Cursor provider + replay collector | `flutter test test/src/features/agent/data/datasources/acp/` | PASS | 59 | 5.5s |
| Codex app-server provider | `flutter test test/src/features/agent/data/datasources/app_server/` | PASS | 71 | 4.9s |
| Grok/Codex local history | `flutter test test/src/features/agent/data/datasources/local_history/` | PASS | 22 | 4.6s |
| EventBuffer | `flutter test test/src/features/agent/application/agent_event_stream_buffer_test.dart` | PASS | 7 | 4.0s |
| TimelineStore | `flutter test test/src/features/agent/application/agent_conversation_timeline_store_test.dart` | PASS | 15 | 4.3s |
| 合计 | 上述六个定向门禁 | PASS | 189 | — |

未知失败：无。

## 冻结的当前行为

### ACP mapper

- agent 正文 id 优先级为 `messageId → eventId → promptId/runningTurnId/session`。
- 无 `messageId` 的正文若有 eventId，当前 mapper 生成
  `acp-agent_message_chunk-event-<eventId>`。
- thought 不使用 eventId；优先显式 `messageId`，否则按
  prompt/turn/session 作用域聚合。
- tool 以 `toolCallId` 映射，`tool_call_update` 由下游按同 id upsert。

### Grok provider/history

- 标准 `session/update` 和 `_x.ai/session/update` 都委托共享 ACP mapper。
- live provider 会抑制 `session/load`/`isReplay` 通知进入实时线。
- updates history 独立解析 messageId/eventId，并按 id 合并；其身份规则尚未与
  live 共用 reducer。

### Cursor provider/replay

- live `session/update` 直接使用共享 `AcpSessionUpdateMapper`。
- `session/load` 请求期间，按 sessionId 将通知送入
  `AcpSessionReplayCollector`；collector 当前接收 provider 的同一个
  `_notificationMapper` 实例。
- collector 对文本使用重复、后缀和前缀启发式 `_mergeText`，因此当前实现本身
  不能证明输入是 delta 还是 snapshot。

### EventBuffer

- 文本/reasoning 只在同 `(kind, sessionId, turnId, itemId, detail)` key 内批次合并。
- token/diff 只保留同 turn 最新快照；非合并事件先 flush，再立即发布。
- terminal tool 不并入 progress，listener generation 失效时丢弃未发布增量。

### TimelineStore

- 当前 Store 会把同 turn 末尾仍开放的普通 agent 消息跨 preferred id 合并。
- tool 打断后若基础 id 已存在，会生成 `<baseId>#segN`。
- 现有测试明确冻结：连续不同 eventId chunk 在 tool 前合并；tool 后新建消息；复用
  turn-scoped id 时 tool 后产生 `#seg2`。

### Codex mapper

- `item/agentMessage/delta.params.itemId` 直接作为
  `AgentMessageDeltaEvent.messageId`。
- `item/started` / `item/completed` 的 agentMessage item 映射为同 item id 的
  `AgentMessageUpdatedEvent`，不会创建 tool 卡。
- reasoning 以协议 itemId、contentIndex、summaryIndex 聚合。

这些行为是 Phase 0 基线，不代表 Phase 1–4 的目标行为。特别是 TimelineStore 的
open/`#segN` 兜底在 Grok 与 Cursor identity 门禁完成前必须保留。

## Phase 0 产物验证

- 8 个 JSON 文件均通过 PowerShell `ConvertFrom-Json` 解析。
- 敏感模式扫描未发现真实 Windows/Unix home 路径、私钥、Bearer、`sk-` 凭据。
- `flutter analyze`：PASS，`No issues found`。
- `git diff --check`：PASS。
- 未修改任何 `lib/` Dart 运行时代码或现有测试代码，因此未运行全量
  `flutter test`，符合 Phase 0 的纯文档/fixture 范围。
