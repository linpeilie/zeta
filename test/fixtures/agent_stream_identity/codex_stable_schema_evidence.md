# Codex 0.144.1 stable schema 证据

## 版本与证据层级

- 本机版本：`codex-cli 0.144.1`。
- skill cache 同步：`status=updated`、`schema_matches_installed=true`、无 warning。
- stable schema 生成版本：`0.144.1`，生成时间 `2026-07-10T10:06:04.499782Z`。
- stable schema SHA-256：
  `dccfd1613ab9393fb2f5287686f74cc5961c22b3a4542d37983047cc622cefa2`。
- 官方最新 release 为 `0.144.5`，高于本机；本阶段未升级 CLI，仍严格采用本机
  `0.144.1` schema。
- 未读取或使用 experimental schema/API。stable schema 内带有 EXPERIMENTAL 标记的
  plan 流接口也不作为本阶段证据。

证据文件：

- `.agents/skills/codex-app-server-docs/references/cache-manifest.json`
- `.agents/skills/codex-app-server-docs/references/cached-app-server.md`
- `.agents/skills/codex-app-server-docs/references/app-server-api.stable.schema.json`

## Stable 通知形状

| method | stable 必需字段 | 身份结论 |
|--------|-----------------|----------|
| `item/started` | `threadId`, `turnId`, `startedAtMs`, `item` | `item.id` 开始一个 ThreadItem 生命周期 |
| `item/agentMessage/delta` | `threadId`, `turnId`, `itemId`, `delta` | `itemId` 关联 agentMessage item；`delta` 是追加字段 |
| `item/completed` | `threadId`, `turnId`, `completedAtMs`, `item` | `item.id` 结束/更新同一个 ThreadItem 生命周期 |

stable `AgentMessageThreadItem` 必须包含 `id`、`type=agentMessage`、`text`；`phase`
可选。由此冻结的 Zeta 契约是：

- 同一个 `itemId` 的 agentMessage delta 按通知顺序进入同一 entry。
- completed 的 `item.id` 与 delta `itemId` 相同，更新同一 entry，不创建 tool。
- 不同 item id 始终是不同 entry；commandExecution 等 tool item 保持自己的 item id，
  因而 `itemA → toolItem → itemB` 的源顺序可被保留。

官方缓存文档补充了 schema 未展开的运行语义：每个 item 的生命周期固定为
`item/started → zero or more item-specific deltas → item/completed`；started 的
`item.id` 与 delta `itemId` 相同；completed 是最终权威 item；agentMessage 的
`delta` 需要按同 itemId 的到达顺序拼接。上述语义与 `0.144.1` stable schema 的字段
形状一致，因此本阶段采用文档语义、以版本匹配 schema 约束线上的精确字段。

## 当前实现与测试基线

- 当前 app-server mapper 将 delta 的 `itemId` 直接映射为
  `AgentMessageDeltaEvent.messageId`。
- `item/started` 与 `item/completed` 先识别 agentMessage，并生成同 id 的
  `AgentMessageUpdatedEvent`；只有非消息 ThreadItem 才继续映射为 tool/system item。
- app-server provider 定向测试 71/71 通过，其中覆盖 agentMessage delta、completed
  agentMessage、reasoning index 和多种 ThreadItem。

本目录的 `codex_agent_message_lifecycle.json` 和 `codex_item_tool_item.json` 只使用
上述 stable 字段，并补齐 stable schema 要求的 `startedAtMs`/`completedAtMs`。
