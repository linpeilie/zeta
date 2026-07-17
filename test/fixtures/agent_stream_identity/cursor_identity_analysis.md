# Cursor stream identity 退役历史分析

> 状态：Cursor 运行实现已删除。本文与 synthetic fixture 仅是退役历史证据，
> 不代表当前支持，也不能作为重新接入的协议契约。

## 结论

删除前仓库没有 Cursor 真实 live 或 `session/load` replay 抓取。现有证据不足以判断：

1. `messageId` 是否在同一消息的所有 chunk 中稳定，以及是否会跨 boundary/turn 重用；
2. `eventId` 是否存在、是否稳定、是否表示消息边界，或仅用于事件去重；
3. `agent_message_chunk.content` 是文本 delta、完整 snapshot，还是两者可能混用。

因此不得把 Grok 的 eventId 假设复制到 Cursor，也不得把本目录的 synthetic fixture
描述成 Cursor CLI 行为。

## 已有证据

| 字段/行为 | live 证据 | replay 证据 | 可得结论 |
|-----------|-----------|-------------|----------|
| `messageId` | fake provider 测试只发送 `message-1` 单 chunk | collector 测试让两个 chunk 复用 `agent-1` | 仅证明当前测试与 mapper 支持该形状；不证明真实稳定性 |
| `eventId` | 现有 Cursor 测试和 fake peer 未提供 | 现有 replay 测试未提供 | 语义完全未知，不得作为 boundary |
| content payload | live provider 测试只有单个 agent chunk | collector 测试使用 `Hi ` + `there` 并期待 append | 测试按 delta 编写；真实 delta/snapshot 未知 |
| tool id/update | fake provider 有单 tool；collector 用同 `tool-1` 做 start/update | 同左 | 仅冻结当前 upsert 基线，不能外推所有 Cursor 版本 |
| live/replay 隔离 | live 与 replay 都走共享 mapper；collector 由 sessionId 临时截流 | `_loadSession` 把 `_notificationMapper` 直接传给 collector | 当前 mapper 是 const，但 Phase 3 引入状态后必须 fresh instance |

证据来源：

- 本机 `cursor-agent --version`：`2026.07.09-a3815c0`；这只证明可执行文件版本。
- `cursor_acp_provider_test.dart` 的 fake `session/update` 与 `session/load` 序列。
- `acp_session_replay_collector_test.dart` 的 synthetic 多 chunk/tool update 序列。
- 删除前 CodeGraph 对 `CursorAcpAgentProvider._handleNotification`、`_loadSession` 与
  `AcpSessionReplayCollector` 的调用链快照。

## 未来重新支持所需输入

需要从目标 Cursor Agent 版本采集并脱敏以下原始 JSON 顺序；只保留协议字段，所有
正文、命令、输出、路径、凭据和用户内容替换为占位符：

1. 一次 live turn：至少两个连续 `agent_message_chunk`、一个
   `tool_call` + 同 id `tool_call_update`、tool 后正文和 turn terminal。
2. 同一 session 的 `session/load`：从请求开始、响应返回前产生的全部
   `session/update`，保留精确顺序和字段的存在/缺失。
3. 连续两个 turn：用于确认 messageId/eventId 是否跨 turn 重用。
4. 每条通知保留 `sessionUpdate`、`messageId`、`toolCallId`、`_meta.eventId`、
   `_meta.promptId` 等 identity 字段的存在/缺失；正文只保留长度无关的占位符。
5. 记录 Cursor Agent 精确版本；若 live 与 replay 来自不同版本，必须分别记录。

## 退役结论

- 该证据缺口转化为 Cursor 退役理由，不再实施 identity adapter。
- Phase 3A 先证明 catalog、UI、恢复、factory 和进程启动均不可达；Phase 3B 再删除实现。
- synthetic fixture 保留，但任何未来重新支持都必须另立方案并采集真实协议 fixture。
