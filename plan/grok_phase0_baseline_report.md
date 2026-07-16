# Grok Phase 0 基线与兼容矩阵

## 1. 目标与边界

本报告对应 [`plan/Zeta_Grok_集成详细设计规格书.md`](./Zeta_Grok_集成详细设计规格书.md) 的 Phase 0，只做三类工作：

1. 固化当前 `initialize` / `session/new` / `session/load` / `session/prompt` / `session/cancel` 行为测试。
2. 为当前本地历史解析建立“损坏输入 + 旧版历史”的脱敏 fixture。
3. 记录本机稳定 Grok CLI 与 `grok-build` 参考源码之间、以及与当前 Zeta 实现之间的能力差异。

Phase 0 不修改生产代码，不改变现有 UI 或 Provider 行为。

## 2. 基线版本

| 项目 | 基线 |
| --- | --- |
| 执行日期 | 2026-07-16 |
| 本机 Grok CLI | `grok 0.2.101 (5bc4b5dfad)` |
| 参考源码 | `OpenSource/grok-build@b189869b7755d2b482969acf6c92da3ecfeffd36` |
| Zeta 当前实现 | `lib/src/features/agent/data/datasources/acp/grok_acp_agent_provider.dart` |

## 3. 新增脱敏 fixtures

### 3.1 ACP / x.ai

- `test/fixtures/grok/acp/initialize_0_2_101_redacted.json`
- `test/fixtures/grok/acp/session_new_0_2_101_redacted.json`
- `test/fixtures/grok/acp/session_load_0_2_101_redacted.json`
- `test/fixtures/grok/acp/xai_turn_completed_notification_redacted.json`
- `test/fixtures/grok/acp/xai_session_updates_response_redacted.json`

### 3.2 本地历史

- `test/fixtures/grok/local_history/updates_malformed_lines_redacted.jsonl`
- `test/fixtures/grok/local_history/updates_unreadable_redacted.jsonl`
- `test/fixtures/grok/local_history/chat_history_legacy_redacted.jsonl`

### 3.3 脱敏约束

- fixture 中不包含真实 token、用户目录、仓库名或会话内容。
- 所有 session id、event id、cwd、消息文本均为合成样本。
- x.ai fixture 仅保留 Zeta 当前 mapper / 后续扩展所需的最小字段。

## 4. 当前能力差异矩阵

| 能力 | grok-build 参考源码 | 当前 Zeta 状态 | 说明 |
| --- | --- | --- | --- |
| `x.ai/session/list` | `src/agent/handlers/session.rs` 路由 `x.ai/session/list` | 未接入，仍走 `GrokSessionHistoryReader.listThreads()` | 当前 thread 列表依赖 `~/.grok/sessions` 只读扫描 |
| `x.ai/session/updates` | `src/extensions/session_updates.rs` 实现分页、tail、turnIndex、rewind 过滤 | 未接入，历史仍走本地 `updates.jsonl` / `chat_history.jsonl` | 协议化历史是 Phase 2 |
| `x.ai/session/rename` | `src/extensions/session_admin.rs` | `renameThread()` 直接 `UnsupportedError` | UI 入口被 capability 关闭 |
| `x.ai/session/delete` | `src/extensions/session_admin.rs` | `deleteThread()` 直接 `UnsupportedError` | 当前不能协议删除 Grok 历史 |
| `x.ai/session/fork` | `src/extensions/session_admin.rs` | `forkThread()` 直接 `UnsupportedError` | 分叉能力尚未接入 |
| `x.ai/compact_conversation` | `src/extensions/memory.rs` | `compactThread()` 直接 `UnsupportedError` | 紧凑会话能力尚未接入 |
| `x.ai/rewind/points` / `execute` | `src/extensions/rewind.rs` | 未接入 | rewind 仍无协议入口 |
| ACP 图片内容块 | `src/agent/mvp_agent/acp_agent.rs` 接收 `ContentBlock::Image` | `sendMessage()` 仍使用 `encodeLocalImagesAsPathText: true` | 本地图片被降级为路径文本 |
| 权限/模式下发 | grok-build 已区分多层权限与扩展模式 | `updatePermissionSelection()` 当前仅记录并忽略 | execution mode / effective state 仍待后续阶段 |

## 5. 当前回归基线

### 5.1 生命周期基线

Phase 0 后，以下行为由测试显式保护：

- `initialize` 握手、`authenticate` 和 `session/new`
- `session/load` 恢复与 replay 抑制
- `session/prompt` 发送与 turn 完结
- `session/cancel` 通知下发与挂起权限取消

### 5.2 本地历史基线

Phase 0 后，以下行为由 fixture 测试显式保护：

- `updates.jsonl` 中混入损坏行时，解析器仍能恢复有效 turn
- `updates.jsonl` 无法恢复 turn 时，reader 会降级到旧版 `chat_history.jsonl`
- 旧版 `chat_history.jsonl` 仍能恢复 user / assistant 历史

## 6. 验证命令

建议最少执行：

```sh
flutter test test/src/features/agent/data/datasources/acp/grok_acp_provider_test.dart
flutter test test/src/features/agent/data/datasources/local_history/grok_history_parser_test.dart
flutter test test/src/features/agent/data/datasources/local_history/grok_session_history_reader_test.dart
flutter analyze
flutter test
```

### 6.1 本次执行结果

| 命令 | 结果 |
| --- | --- |
| `flutter test test/src/features/agent/data/datasources/acp/grok_acp_provider_test.dart` | 通过 |
| `flutter test test/src/features/agent/data/datasources/local_history/grok_history_parser_test.dart` | 通过 |
| `flutter test test/src/features/agent/data/datasources/local_history/grok_session_history_reader_test.dart` | 通过 |
| `flutter analyze` | 通过，无 issue |
| `flutter test` | 通过 |

## 7. 结论

Phase 0 完成后，Zeta 已具备后续演进所需的三项基线资产：

1. 可复用的脱敏协议 / 历史 fixtures；
2. 不改变生产行为的回归测试网；
3. 基于本机 CLI 与 `grok-build` 参考实现的能力差异矩阵。
