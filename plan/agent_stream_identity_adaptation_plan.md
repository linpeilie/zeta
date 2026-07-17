# Agent 流式身份与 Provider 适配层边界整改实施方案

> 状态：Phase 0–5 实现与自动化门禁已完成；Phase 4 记录中的未复测手工项保持原状
> 版本：2.4
> 编制日期：2026-07-17
> 目标版本：当前主干；Codex app-server 以本机 `0.144.1` stable schema 为实现基线
> 关联问题：Grok 实时时间线操作沉底、思考按 eventId 碎片化、共享层承担 Provider 叙事策略
> 核心约束：Cursor 必须先从运行时软下线、再删除实现；Phase 3 全部门禁完成前，禁止删除 TimelineStore 现有兜底

---

## 1. 执行摘要

### 1.1 一句话目标

**活跃 Provider 的流式身份由 Grok、Codex 各自的数据适配层决定；Cursor 因缺少可验证的稳定协议契约而退役，application/presentation 只按规范化身份合并。**

### 1.2 本次确定的架构决策

| ID | 决策 | 结果 |
|----|------|------|
| ADR-1 | 区分 Provider 原始身份与 UI 合并身份 | `sourceItemId` 保存原始协议身份；`entryId` 是规范化时间线身份 |
| ADR-2 | 保留现有字段名降低改动面 | `AgentMessageDeltaEvent.messageId` 暂不重命名，但语义改为 `entryId`；新增 `sourceMessageId` |
| ADR-3 | ACP 共享层只解析协议语法 | 无状态 `AcpSessionUpdateDecoder` 只负责 typed 解码；叙事边界由活跃 Provider adapter/reducer 决定 |
| ADR-4 | 状态按运行资源隔离 | 活跃 Provider 的 live、replay、history 复用算法时必须使用不同实例和状态 |
| ADR-5 | 推理按连续 phase 聚合 | 不按 eventId 拆卡；被正文、工具、计划或交互打断后，新 reasoning phase 使用新 `itemId` |
| ADR-6 | 所有活跃 Provider 准备完成后再简化 Store | Grok identity 已通过门禁、Cursor 完成退役、Codex 契约测试通过后，才删除 open/`#segN` |
| ADR-7 | 不使用 raw payload 控制统一层兼容逻辑 | 禁止 `raw['_legacyStreamSegment']`；回滚以 PR revert 或 app 组合层 typed 配置完成 |
| ADR-8 | plan 等展示语义必须显式进入 domain event | 新增中立 `AgentMessageKind`，Store/ViewModel 不再从 provider raw 猜 plan |
| ADR-9 | Cursor 采用两阶段退役 | 先从目录、UI、组合与进程启动路径软下线，再删除实现；保留旧配置容错，不删除任何用户 Cursor 数据 |

### 1.3 最终数据流

```text
Raw ACP notification
        ↓
AcpSessionUpdateDecoder（共享、无状态、只解析协议）
        ↓
GrokEventAdapter / GrokStreamIdentity
        ↓ 语义完整 AgentEvent（entryId 已确定）
AgentEventStreamBuffer（同 entryId 批内合并，不猜边界）
        ↓
AgentConversationTimelineStore（同 id 更新、异 id 新建）
        ↓
ViewModel / UI grouping（只改变展示组合，不改变事件顺序）

Codex app-server notification
        ↓
CodexNotificationMapper（itemId → entryId，维持 item 生命周期）
        ↓
同一条统一链路

Legacy Cursor config / selected provider
        ↓
CursorRetirementPolicy（容错读取、明确 unavailable、安全回退）
        ↓
不创建 provider、不启动 cursor-agent、不读取或改写 Cursor 会话数据
```

### 1.4 实施总顺序

```text
Phase 0  契约、fixture 与基线 ✅
   ↓
Phase 1  Domain 事件补全 + 无状态 ACP decoder ✅
   ↓
Phase 2  Grok live identity ✅
   ↓
Phase 3A Cursor 软下线 ✅
   ↓
Phase 3B Cursor 实现删除
   ↓ Cursor 退役门禁通过
Phase 4  原子性简化 EventBuffer/TimelineStore + Codex 回归
   ↓
Phase 5  Grok history 对齐 + 共享层清理 + 文档同步
   ↓
Phase 6  全量回归、观测与发布验收
```

---

## 2. 背景与根因

### 2.1 用户可见问题

1. Grok 输出“说明 → 工具 → 总结”时，工具最终落在所有正文之后。
2. 使用 eventId 作为每个正文 chunk 的 id 后，正文交错改善，但 reasoning 被拆成多张卡。
3. 同一套共享 Store 启发式作用于 Grok、Cursor、Codex，使 Provider 兼容依赖事件顺序碰巧满足假设。
4. Grok live 与本地 history 使用不同 identity 规则，重开会话后的条目数量和顺序可能与实时态不同。

### 2.2 当前根因链

```text
ACP agent_message_chunk 可能没有稳定 messageId
  → 共享 mapper 使用 messageId/eventId/turn scope 兜底
  → TimelineStore 再根据“当前 turn 最后一条条目”执行 open merge
  → preferredId 被占用时由 Store 生成 #segN
  → Provider 事件仍是半成品，统一层承担了叙事判断
  → Codex/Cursor 被动继承 Grok 向规则
```

### 2.3 当前实现中的边界泄漏

| 位置 | 当前职责 | 问题 |
|------|----------|------|
| `acp_session_update_mapper.dart` | ACP kind 映射、content/tool/usage 映射、message/thought id 决策 | 共享协议层包含 Grok 向叙事策略 |
| `grok_acp_notification_mapper.dart` | 委托共享 mapper、处理少量 xAI 扩展 | 名为厂商 mapper，但不拥有核心 identity |
| `cursor_acp_agent_provider.dart` | 直接持有共享 mapper | Cursor 无独立契约，replay 也复用同一 mapper |
| `agent_conversation_timeline_store.dart` | open message 检测、跨 id 合并、`#segN` 分配 | application 层猜 Provider 叙事结构 |
| `agent_event_stream_buffer.dart` | 按 id 批内合并 | 本身中立，但未被纳入现有迁移测试矩阵 |
| `grok_updates_history_parser.dart` | 独立使用 messageId/eventId 生成历史身份 | live/history 分段规则不一致 |
| Store / ViewModel plan 检测 | 从 raw payload 猜 `type=plan` | 原始 Provider 语义泄漏到统一层 |

---

## 3. 范围与非目标

### 3.1 纳入范围

- Agent 正文、reasoning、tool、plan 和交互条目的身份与叙事边界。
- `AgentMessageDeltaEvent` / `AgentMessageUpdatedEvent` 的规范化身份和显式消息 kind。
- ACP 原始通知的无状态解码与 Grok 厂商投影。
- Grok live identity，以及 Cursor 软下线、旧配置兼容和实现删除。
- Grok updates history 与 live 的语义对齐。
- `AgentEventStreamBuffer` 的顺序与合并契约。
- `AgentConversationTimelineStore` open/`#segN` 启发式删除。
- cancel、失败、断连、重连、迟到事件和重复事件的状态生命周期。
- 单元测试、provider 测试、Store 测试、Widget 回归、手测和文档门禁。
- Cursor provider 目录/UI/组合/进程入口清理，以及退役后的兼容回归。

### 3.2 有限纳入的用户消息

- 保留 live ViewModel 乐观插入用户消息的现有行为。
- live `user_message_chunk` 仍不得重复插入同一用户消息。
- replay/history 中 user chunk 的文字与附件合并继续由对应 replay/history adapter 负责。
- 本方案不重做 composer、附件上传或乐观消息撤销流程。

### 3.3 不纳入范围

- 命令组、文件编辑组的视觉样式重做。
- 审批 dock、用户问题弹层或计划审批交互重做。
- token、context window、model selection 的业务语义调整。
- JSON-RPC transport、进程启动、认证或权限协议重写。
- Claude Code Provider 实现；但其未来接入必须遵守本方案的 identity 契约。
- 大规模目录迁移或第三方状态管理引入。
- Cursor 协议继续适配、真实 fixture 补采或未来重新启用；重新支持必须另立方案并重新完成协议门禁。
- 删除、迁移或重写 `~/.cursor`、项目 `.cursor`、`~/.zeta/state/cursor_sessions.json` 或用户已有 Cursor 配置。

### 3.4 依赖与前置输入

| 输入 | 必需时间 | 说明 |
|------|----------|------|
| Grok 真实/脱敏 `session/update` 序列 | Phase 0 | 至少覆盖 text/tool/text、thought、turn_completed |
| Cursor synthetic fixture 与 blocker 记录 | 已具备 | 作为退役决策证据保留，不再作为活跃 Provider 实现门禁 |
| Cursor 运行入口与旧配置引用清单 | Phase 3A | 覆盖 provider catalog、UI、app 组合、bootstrap、持久化配置与 fallback |
| Cursor 实现引用/用户数据边界清单 | Phase 3B | CodeGraph/`rg` 审计删除范围，并证明不触碰外部 Cursor 数据 |
| Codex 0.144.1 stable schema | 已具备 | 作为当前实现基线，不读取 experimental API |
| 现有关键测试清单 | Phase 0 | 记录迁移前通过状态和预期行为 |

Cursor 真实 fixture 缺失不再阻塞 identity 实现，因为 Cursor 不再作为活跃 Provider；它转化为 ADR-9 的退役理由。Phase 4 仍必须等待 Phase 3A、3B 全部门禁完成，确保不存在可受 Store 简化影响的 Cursor 运行路径。

---

## 4. 成功标准

| ID | 验收标准 |
|----|----------|
| S1 | Grok `text → tool → text` 最终条目顺序严格为 `Message, Tool, Message` |
| S2 | Grok 连续 reasoning chunk 不因 eventId 不同而碎卡 |
| S3 | `thought → tool → thought` 保留两个连续 reasoning phase 的真实顺序，不回填到 tool 之前 |
| S4 | Cursor 不再出现在可选 Provider 中，任何运行路径都不能实例化 provider 或启动 `cursor-agent` |
| S5 | TimelineStore 不再读取最后一条 entry 推断流边界，不再生成 `#segN` |
| S6 | EventBuffer 只按规范化 id 合并，不能跨 tool/reasoning/plan/interaction 合并已关闭条目 |
| S7 | Codex 同一 itemId 的 delta 顺序拼接；不同 itemId 永不粘连；completed 更新同一条目 |
| S8 | 两个 turn 复用同一 raw messageId 时，不发生跨 turn 覆盖 |
| S9 | cancel、失败、断连和 connection epoch 变化后，不复用旧 identity 状态 |
| S10 | Grok live/history 的条目类型、相对顺序、文本和 phase 分段一致 |
| S11 | Store/ViewModel 不再从 raw payload 识别 plan 或决定 identity |
| S12 | `flutter analyze`、相关定向测试和最终 `flutter test` 全部通过 |
| S13 | 旧 Cursor 配置可容错读取并安全回退；外部 `.cursor` 与 `cursor_sessions.json` 保持原样 |
| S14 | Cursor 专属运行实现与测试删除完成，仓库只保留必要的 legacy 配置兼容和退役决策证据 |

---

## 5. 目标分层与代码归属

### 5.1 分层职责

| 层 | 允许职责 | 禁止职责 |
|----|----------|----------|
| transport / JSON-RPC peer | 分帧、请求响应关联、通知转发、连接生命周期 | 消息气泡、reasoning phase、UI 分段 |
| ACP decoder（共享 data） | 解析标准 ACP 字段，生成 typed decoded update，宽容未知字段 | 决定 message/reasoning entryId |
| Provider adapter/reducer（厂商 data） | source id 解释、segment/phase、扩展通知、生命周期与诊断 | 修改通用 UI 状态 |
| domain event | 暴露规范化 id、kind、role、status、source id | 暴露必须由 UI 解码的 Provider raw 语义 |
| EventBuffer（application） | 同规范化 id 的高频事件批内合并、非合并事件前 flush | 推断“当前开放气泡” |
| TimelineStore（application） | 同 id create/update、tool upsert、turn 分组、展开态 | 改写 id、分配 segment、判断 Provider |
| ViewModel / UI | 路由、刷新、可视 grouping | 从 raw 推断 plan/identity/厂商规则 |

### 5.2 推荐文件布局

```text
lib/src/features/agent/
  domain/
    agent_message_models.dart                 # AgentMessageKind
    agent_event_models.dart                   # entryId/sourceId 契约
    agent_turn_history_models.dart            # history message kind/sourceId
  data/mappers/
    acp_content_codec.dart                    # 保留
    acp_session_update_decoder.dart           # 新增：typed、无状态
    acp_session_update_mapper.dart            # 迁移期兼容，最终删除或降级
    grok_stream_identity.dart                 # 新增：Grok reducer/state
    grok_session_update_mapper.dart           # 新增或由 notification mapper 承担
    grok_acp_notification_mapper.dart         # xAI + Grok adapter 门面
    codex_notification_mapper.dart            # 保持 Codex 私有协议映射
  data/datasources/acp/
    grok_acp_agent_provider.dart               # 生命周期、交互 boundary 接线
  data/datasources/local_history/
    grok_updates_history_parser.dart           # 使用独立 history reducer
  application/
    agent_event_stream_buffer.dart             # 只按规范化 id 合并
    agent_conversation_timeline_store.dart     # dumb merge
```

Phase 3B 应删除 Cursor 专属 provider、mapper、进程启动、session locator/index、诊断和测试；
`acp_session_replay_collector.dart` 等共享命名文件只有在引用审计证明仅服务 Cursor 时才删除，
不得误删 Grok 或其他活跃 Provider 仍依赖的 ACP 能力。

### 5.3 为什么不采用“每个厂商复制一份完整 ACP switch”

标准 ACP kind、content、tool status、usage 等语法解析仍有共享价值。完整复制会导致：

- 活跃 ACP Provider 对标准字段的兼容修复漂移。
- 未知 kind、宽容解码和 tool 映射需要重复维护。
- Provider 差异与协议语法纠缠，难以单测。

因此本方案采用“两段式”：

```text
共享无状态 decoder：Raw JSON → typed ACP update
厂商有状态 adapter：typed ACP update → AgentEvent
```

### 5.4 ACP decoded update 最小模型

decoder 输出采用 sealed typed update；所有类型保留脱敏前的 `raw` 供 mapper 附带，但业务判断只读取显式字段：

| 类型 | 必需字段 | 可选字段 |
|------|----------|----------|
| `AcpUserMessageChunk` | sessionId、content | sourceMessageId、eventId、promptId |
| `AcpAgentMessageChunk` | sessionId、content | sourceMessageId、eventId、promptId |
| `AcpAgentThoughtChunk` | sessionId、content | sourceItemId、eventId、promptId |
| `AcpToolCallUpdate` | sessionId、toolCallId、status/kind/content | promptId、locations、rawInput/rawOutput |
| `AcpPlanUpdate` | sessionId、entries | promptId、eventId |
| `AcpUsageUpdate` | sessionId、usage | promptId |
| `AcpTurnCompletedUpdate` | sessionId、stopReason | promptId、usage、duration |
| `AcpUnknownUpdate` | sessionId、kind | raw |

实现约束：

- decoded 类型不得依赖 Flutter/application/presentation。
- decoder 不保存 current turn、segment、seen event 等 mutable state。
- 缺失必需字段时返回 `AcpUnknownUpdate` 或明确的 decode failure 结果，不抛出未处理异常。
- 本方案使用 Dart 内建类型，不新增 runtime 或 dev dependency。

---

## 6. Domain 事件与身份契约

### 6.1 两类身份

| 名称 | 含义 | 是否为 UI 合并键 | 生命周期 |
|------|------|------------------|----------|
| `sourceItemId` | Provider 原始 message/item/event 身份 | 否 | 按 Provider 协议定义 |
| `entryId` | Zeta 规范化时间线条目身份 | 是 | 单个连续可见条目，关闭后不得复用 |

第一阶段为控制改动面，不直接重命名所有 API：

| 事件/模型 | 现有字段 | 新语义/新增字段 |
|-----------|----------|-----------------|
| `AgentMessageDeltaEvent` | `messageId` | 语义改为 `entryId`；新增 `sourceMessageId`、`kind` |
| `AgentMessageUpdatedEvent` | `messageId` | 必须指向同一规范化 `entryId`；新增 `sourceMessageId`、`kind` |
| `AgentReasoningDeltaEvent` | `itemId` | 语义为 reasoning entryId；新增 `sourceItemId` |
| `AgentToolCall` | `id` | tool entryId/upsert key；若 raw id 非会话唯一，由 adapter 规范化 |
| `AgentHistoryMessageEntry` | `id` | 与 live entryId 相同语义；新增显式 `kind`、可选 source id |

### 6.2 `AgentMessageKind`

新增中立枚举：

```dart
enum AgentMessageKind {
  regular,
  plan,
}
```

约束：

1. Codex `item/plan/delta` 与 completed plan item 映射为 `plan`。
2. ACP `plan` update 映射为 `AgentPlanUpdatedEvent` 或显式 `kind=plan` 的消息，不能依赖 raw 检测。
3. Store 和 ViewModel 删除 `_messageKindFromRaw` / `_rawLooksLikePlan` 等 Provider raw 推断。
4. `raw` 仅用于上下文面板和诊断展示，不参与主业务分支。

### 6.3 entryId 唯一性

`entryId` 必须在当前已加载 conversation 中唯一。Provider adapter 必须满足：

1. 同一连续条目的 delta 使用同一 entryId。
2. 条目被可见 boundary 关闭后，后续内容必须使用新 entryId。
3. 两个 turn 即使复用相同 raw id，也必须生成不同 entryId。
4. 不允许使用固定 `unknown` 作为 message/reasoning entryId。
5. connection epoch 只参与状态隔离，不进入稳定 entryId，避免 live/history 因重连产生不同 UI key。

ACP synthetic id 建议格式：

```text
acp:<providerId>:<encodedSessionId>:<encodedTurnScope>:<entryKind>:<encodedSourceOrAnon>:<ordinal>
```

实现要求：

- 使用 `Uri.encodeComponent` 处理组成部分，不引入新依赖。
- `turnScope` 优先使用 promptId/本地 runningTurnId；replay/history 缺失时使用解析器生成的确定性 turn ordinal。
- `ordinal` 在同一 turn、同一 entry kind 内单调递增。
- raw source id 仅作为组成信息，不能绕过 segment ordinal。

### 6.4 无法解析 turn scope 时的行为

live agent/reasoning 内容必须能关联到有效 session 与 turn：

1. 若通知携带 promptId/turnId，使用协议值。
2. 否则使用该 session 唯一的 provider-local runningTurnId。
3. 若 session 下不存在或存在多个无法区分的 active turn，丢弃该内容事件并记录脱敏诊断。
4. 禁止回退为全局 `unknown`，避免跨 turn/跨 session 合并。

### 6.5 delta 与 snapshot 语义

| 输入语义 | Domain 事件 | Store 行为 |
|----------|-------------|------------|
| 纯文本增量 | `AgentMessageDeltaEvent` | append |
| 完整权威文本 | `AgentMessageUpdatedEvent(text: fullText)` | replace |
| 仅状态/耗时终态 | `AgentMessageUpdatedEvent(text: null)` | metadata update |
| 重复 raw eventId | adapter 丢弃并记计数 | Store 不感知 |

Provider adapter 必须先判断输入是 delta 还是完整 snapshot，禁止把完整 snapshot 当 delta 重复追加。

### 6.6 跨 segment completed 规则

同一 source message 可能因工具/交互被规范化为多个 entryId。adapter 应维护：

```text
sourceMessageId → [entryId1, entryId2, ...]
```

当 completed snapshot 到达：

- 只有一个 entryId：允许用完整文本 replace，并更新终态。
- 有多个 entryId且协议没有 segment 信息：不得用完整文本覆盖任一 segment；对已存在 segment 只更新 status/duration。
- 协议能明确对应最后一个 segment：只更新该 segment。
- 无法关联任何 entryId：记录诊断，不创建迟到的新消息。

Codex item 生命周期是一对一 itemId，因此不触发多 segment 歧义。

---

## 7. Provider-local identity reducer 规格

### 7.1 状态作用域

live identity 状态键：

```text
(runtimeId, connectionEpoch, providerId, sessionId, turnId)
```

稳定 entryId 不包含 runtimeId/epoch；两者只用于阻止旧连接状态进入新连接。

每个 turn state 至少包含：

```text
messageSegmentOrdinal
reasoningPhaseOrdinal
currentMessageEntryId
currentMessageSourceId
currentReasoningEntryId
currentReasoningSourceId
seenToolCallIds
seenVisibleBoundaryKeys
recentRawEventIds（每 turn 最多 512 个 `(kind, eventId)`）
sourceMessageEntryIds
terminalState
```

### 7.2 建议接口

接口位于 data 层，不暴露给 application/UI：

```dart
abstract interface class AcpStreamIdentityReducer {
  void beginTurn(AcpStreamTurnScope scope);

  AcpResolvedMessageIdentity resolveMessage(
    AcpAgentMessageChunk update,
  );

  AcpResolvedReasoningIdentity resolveReasoning(
    AcpAgentThoughtChunk update,
  );

  void noteBoundary(AcpNarrativeBoundary boundary);

  void completeTurn({required AcpTurnEndReason reason});

  void invalidate({required AcpIdentityInvalidation reason});
}
```

允许活跃 ACP Provider 实现各自策略；不提供带叙事假设的默认实现。Cursor 退役后不得
为了保留其运行路径而新增 reducer 实现。

mapper factory 最小接口：

```dart
abstract interface class AcpProviderEventMapperFactory {
  AcpProviderEventMapper createLive({
    required String sessionId,
    required AgentRuntimeScope runtimeScope,
  });

  AcpProviderEventMapper createReplay({required String sessionId});

  AcpProviderEventMapper createHistory({required String sessionId});
}
```

`createReplay` / `createHistory` 每次必须返回 fresh instance；不得缓存到 live session map。

### 7.3 Narrative boundary 规则

| 输入 | message phase | reasoning phase | 说明 |
|------|---------------|-----------------|------|
| 连续相同 source 的 text chunk | 保持 | 若正在 reasoning，则先关闭 reasoning | 正文连续追加 |
| source messageId 改变 | 关闭并新建 | 关闭 | 即使中间没有 tool，也必须尊重新 source |
| 首次见到某 toolCallId | 关闭 | 关闭 | tool update 重复到达不重复 bump |
| 已见 toolCallId 的 update | 不额外关闭 | 不额外关闭 | 原地更新工具卡 |
| reasoning 首 chunk | 关闭 message | 新建 reasoning phase | 不使用每 chunk eventId 分卡 |
| 连续 reasoning chunk | 保持关闭 | 保持当前 phase | 同一逻辑思考卡 |
| plan 条目开始 | 关闭 | 关闭 | plan 是可见 boundary |
| permission / user question / plan approval | 关闭 | 关闭 | 由 provider server-request 路径显式通知 reducer |
| 可见 warning/system history event | 关闭 | 关闭 | 仅当它实际进入时间线 |
| usage/status/config update | 不变 | 不变 | 非叙事条目 |
| turn terminal | 关闭 | 关闭 | turn state 进入 terminal |

### 7.4 reasoning phase 决策

本方案不采用“整 turn 永远一张思考卡”，而采用“连续 reasoning phase 一张卡”：

```text
thought(a), thought(b)
  → 同一个 reasoning entryId

thought(a), tool, thought(b)
  → reasoning-1, tool, reasoning-2

text(a), thought(b), text(c)
  → message-1, reasoning-1, message-2
```

这样同时满足：

- 不因 Grok 每个 thought chunk 的 eventId 不同而碎卡。
- 不把 tool 后的 reasoning 回填到 tool 前。
- 时间线顺序可由 dumb Store 直接保持。

### 7.5 Grok 规则

1. `messageId` 是 source id，不直接保证等于 entryId。
2. `_meta.eventId` 默认只用于去重和诊断，不作为一 chunk 一气泡的依据。
3. 无 source messageId 时，连续 text chunk 使用当前 message segment。
4. tool、reasoning、plan、交互 boundary 关闭当前 message segment。
5. thought chunk 的 eventId 不参与 reasoning phase identity。
6. `_x.ai/session/update` 与标准 `session/update` 进入同一 session/turn reducer。
7. `session/prompt` RPC 完成与 `_x.ai` turn_completed 采用“首个终态生效”规则。

### 7.6 Cursor 退役规则

1. 不再解释 Cursor `messageId`、`eventId`、delta 或 snapshot 语义，也不新增协议适配。
2. 先从 provider catalog、UI、app 组合、bootstrap 与进程启动路径软下线，确认不可达后再删除实现。
3. 旧配置仍可容错解码；若最后选择的是 Cursor，必须显示 unavailable 状态并安全回退到可用 Provider，
   不得静默删改用户配置。
4. 退役过程不得读取、迁移、清空或重写 `~/.cursor`、项目 `.cursor` 与
   `~/.zeta/state/cursor_sessions.json`。
5. Phase 3A 门禁通过后，删除 Cursor 专属 provider、mapper、replay/load、进程、诊断及对应运行测试；
   只保留必要的旧配置兼容测试和退役决策证据。
6. synthetic fixture 与缺少真实 fixture 的分析作为历史证据保留，但不再作为运行实现或 Phase 4 的协议门禁。

### 7.7 Codex 规则

Codex app-server 以本机 `0.144.1` stable schema 为基线：

- `item/started → item-specific deltas → item/completed` 是单 item 生命周期。
- `item/agentMessage/delta` 使用 `itemId`，同 itemId 的 delta 按顺序拼接。
- `item/completed` 是权威终态，必须更新同一 itemId 对应的 entry。
- reasoning 使用协议 reasoning itemId、contentIndex、summaryIndex。
- Codex 不引入 ACP segment reducer；只补充 domain kind/source 字段和回归测试。

官方最新 release `0.144.5` 高于本机版本，但本方案不自动升级 CLI，也不使用 experimental schema。

---

## 8. 生命周期、迟到事件与错误策略

### 8.1 turn 生命周期

```text
idle
  → beginTurn(generation + 1)
  → running
  → completing（收到首个终态）
  → terminal
  → disposed / 下一 turn 新 generation
```

### 8.2 首个终态生效

活跃 ACP Provider（当前为 Grok）可能同时从通知与 `session/prompt` RPC 响应得到终态：

1. 第一个可关联当前 turn generation 的终态负责完成 turn。
2. 后续相同终态视为幂等重复，不再次 emit `AgentTurnCompletedEvent`。
3. 后续冲突终态记录脱敏诊断，但不覆盖首个终态。
4. terminal 后不再创建新的 message/reasoning/tool 条目。
5. terminal 后允许已存在 tool/message 的幂等终态 metadata 更新；禁止新增正文。

### 8.3 必须 invalidation 的场景

| 场景 | 动作 |
|------|------|
| 新 turn 开始 | 为该 session 创建新 generation，关闭旧 active state |
| cancel 被接受 | 标记当前 generation cancelling/terminal，关闭开放 segment |
| `session/prompt` 抛错 | complete failed + invalidate turn state |
| peer closed | 清空该 connection epoch 下全部 live identity state |
| provider dispose | dispose factory、live states、recent event caches |
| runtime/connection epoch 改变 | 旧 epoch state 全部失效 |
| session 删除/切换 | 删除对应 session identity state |
| replay collector build/失败 | 无条件 dispose replay state |

### 8.4 迟到事件

| 迟到事件 | 处理 |
|----------|------|
| terminal 后新 message/reasoning chunk | 丢弃，增加 `lateContentDropped` |
| terminal 后已知 tool 的 completed update | 允许更新已存在 tool，不创建新 tool |
| 新 turn 开始后无法区分属于哪个 turn 的通知 | 丢弃并告警，禁止使用 `_lastTurnId` 猜测 |
| 旧 connection epoch 事件 | 由 runtime scope/gate 拒绝 |
| 重复 eventId | adapter 有界去重，不进入 EventBuffer |

如 Provider 协议确实保证 turn_completed 之后仍会发送合法内容，必须在对应厂商 adapter 中以 fixture 和单测证明，不得把宽松规则加回统一层。

---

## 9. Live、Replay 与 History 一致性

### 9.1 复用原则

| 可复用 | 不可复用 |
|--------|----------|
| reducer 实现、entry id builder、boundary 规则 | mutable reducer 实例、seen tool/event 集合、当前 segment |
| typed decoded update | live runningTurn map |
| golden fixture 断言工具 | connection epoch state |

### 9.2 Cursor 退役与数据保留

Cursor 软下线后不再创建 live/replay mapper，也不再执行 `session/load`。Phase 3B 通过
CodeGraph 与 `rg` 审计 `AcpSessionReplayCollector`：若它只被 Cursor 使用则一并删除；若仍被
活跃 Provider 使用，则保留其共享能力，但不得含 Cursor 分支。

退役不是数据迁移。`~/.zeta/state/cursor_sessions.json` 以及 Cursor 自有目录只作为用户数据边界
保留，Zeta 不应为完成退役而读取、重写或删除这些内容。

### 9.3 Grok history 对齐

`grok_updates_history_parser.dart` 必须使用新的独立 history reducer：

- messageId/eventId 先解码为 source metadata。
- 正文按 narrative boundary 生成 segment ordinal。
- reasoning 按连续 phase 聚合。
- tool update 按 source tool id upsert。
- turn 缺少稳定 id 时，以解析顺序生成确定性 history turn id。

### 9.4 一致性比较方式

live 与 history 不强制 runtime 状态相同，但必须比较以下 canonical signature：

```text
turn ordinal
entry ordinal
entry type
message/reasoning phase ordinal
source id（若存在）
normalized text
tool kind/status
```

golden 测试不得只比较条目总数；必须比较完整相对顺序。

---

## 10. 分阶段开发任务

本节每个 `Pn-m` 条目都应在任务系统中建立独立子任务，登记负责人、估时和对应 PR。表中仅写文件名时，完整路径按 §5.2 的推荐布局解析。

### Phase 0：契约、fixture 与基线（1–1.5 人日）

目标：在任何行为修改前冻结输入和预期结果。

| 任务 | 文件/产物 | 实施内容 | 完成标准 |
|------|-----------|----------|----------|
| P0-1 | `test/fixtures/agent_stream_identity/` | 增加脱敏 Grok live、Grok history、Cursor live、Cursor replay、Codex 通知 fixture | 每个 fixture 有来源版本和场景说明 |
| P0-2 | 本方案 + `docs/engineering_standards.md` | 写入 sourceId/entryId、boundary、状态隔离契约 | 文档评审通过 |
| P0-3 | 现有测试报告 | 运行并记录 mapper/Store/provider/EventBuffer 迁移前结果 | 基线无未知失败 |
| P0-4 | Cursor fixture 分析记录 | 记录 messageId/eventId 与 delta/snapshot 缺少真实证据的 blocker | 作为 ADR-9 退役决策证据，不假设协议语义 |
| P0-5 | Codex 协议证据记录 | 记录 0.144.1 stable item 生命周期、delta 和 completed 字段 | 不依赖实验 API |

Phase 0 门禁：

- [x] Grok `text/tool/text` 与 thought fixture 已入库。
- [x] Cursor 当前只有从现有 fake/test 构造的 synthetic baseline；真实 live/replay fixture
  缺失及其影响已记录，因此不再实施 Cursor identity，转入两阶段退役。
- [x] Codex delta/completed fixture 已入库。
- [x] 所有 fixture 不包含 prompt 正文、token、真实路径或凭据等敏感信息。

Phase 0 执行记录（2026-07-17）：

- [x] P0-1：已在 `test/fixtures/agent_stream_identity/` 增加 Grok live/history、
  Cursor live/replay synthetic、Codex stable 通知 fixture；每个文件记录版本、场景、
  provenance 和隐私约束。Cursor synthetic fixture 仅作为历史基线和退役决策证据。
- [x] P0-2：`docs/engineering_standards.md` 已同步 sourceId/entryId、narrative
  boundary、Provider adapter、EventBuffer/TimelineStore 和状态隔离契约。
- [x] P0-3：迁移前 6 组定向测试共 189 个用例全部通过，记录见
  `test/fixtures/agent_stream_identity/baseline_report.md`。
- [x] P0-4：Cursor messageId/eventId 稳定性和 delta/snapshot 语义缺少真实 fixture
  证据；blocker、所需输入与影响已记录，且没有假设 eventId 语义。该缺口已转化为
  ADR-9 的退役依据，不再阻塞退役任务。
- [x] P0-5：已按本机 Codex `0.144.1` stable schema 记录 item lifecycle、
  agentMessage delta 与 item/completed 字段；未使用 experimental API。

Phase 0 总状态：**已完成**。Phase 1/2 已完成；Phase 3 改为 Cursor 两阶段退役。
Phase 4 仍须等待 Phase 3A、3B 全部门禁通过。

### Phase 1：Domain 补全与无状态 ACP decoder（已完成，1–2 人日）

目标：先建立不含叙事策略的稳定输入/输出契约，不改变 Store 行为。

| 任务 | 文件 | 实施内容 | 测试 |
|------|------|----------|------|
| [x] P1-1 | `agent_message_models.dart` | 新增 `AgentMessageKind` | domain model test |
| [x] P1-2 | `agent_event_models.dart` | message delta/updated 增加 kind/source id；reasoning 增加 source item id；更新文档注释 | constructor/copy/event tests |
| [x] P1-3 | `agent_turn_history_models.dart` | history message 增加显式 kind/source id，默认兼容旧调用方 | history parser tests |
| [x] P1-4 | `acp_session_update_decoder.dart` | 定义 typed decoded update；宽容未知 kind/字段 | decoder fixture tests |
| [x] P1-5 | `acp_session_update_mapper.dart` | 暂时改为兼容 wrapper，内部调用 decoder；不得新增叙事逻辑 | 现有 mapper tests 继续通过 |
| [x] P1-6 | Codex mapper | 显式设置 kind/source id，delta/completed id 保持 itemId | app-server provider tests |

Phase 1 门禁：

- [x] decoder 是无状态类，可使用 `const` 或纯函数。
- [x] decoder 不生成 message/reasoning entryId。
- [x] 未知 ACP kind 返回 typed unknown/diagnostic，不抛出导致 Provider 断连。
- [x] Store 仍保持现状，避免尚未迁移的 Provider 回归。

### Phase 2：Grok identity 下沉（已完成，1.5–2.5 人日）

目标：Grok 对外产出的事件已经具备最终 entryId；Store 兜底暂留但不再是 Grok 正确性的来源。

| 任务 | 文件 | 实施内容 | 测试 |
|------|------|----------|------|
| [x] P2-1 | `grok_stream_identity.dart` | 实现 session/turn reducer、message segment、reasoning phase、seen tool/event、source→entry 映射 | reducer unit tests |
| [x] P2-2 | `grok_session_update_mapper.dart` | typed ACP update → AgentEvent；使用 reducer 决定 identity | mapper sequence tests |
| [x] P2-3 | `grok_acp_notification_mapper.dart` | 标准 ACP 与 `_x.ai` 扩展进入同一 Grok adapter | notification tests |
| [x] P2-4 | `grok_acp_agent_provider.dart` | begin/complete/cancel/error/peer close/dispose 接线；permission/question boundary 接线 | provider lifecycle tests |
| [x] P2-5 | Grok 诊断 | 增加 synthetic id、duplicate、late drop、missing scope 计数，不记录正文 | diagnostic assertions |
| [x] P2-6 | 手测 | H1–H5 | 记录截图/结果，不作为自动测试替代 |

Grok reducer 必测序列：

| ID | 输入 | 期望 |
|----|------|------|
| G1 | text(a), text(b) | 同 entryId，文本 `ab` |
| G2 | text, new tool, text | Message-1, Tool, Message-2 |
| G3 | text(source=A), tool, text(source=A) | 两个 entryId，共用 sourceMessageId=A |
| G4 | text(source=A), text(source=B) | 两个 entryId，即使无 tool |
| G5 | thought(event1), thought(event2) | 同 reasoning entryId |
| G6 | thought, tool, thought | Reasoning-1, Tool, Reasoning-2 |
| G7 | text, permission, text | Message-1, Permission, Message-2 |
| G8 | tool_call, tool_call_update(同 id), text | tool update 不重复增加 segment ordinal |
| G9 | turn completed 后 text | text 被丢弃并记 late counter |
| G10 | cancel/peer close 后新 turn | 新 state，不复用旧 segment |

Phase 2 门禁：

- [x] adapter 级测试在不经过 Store 的情况下已输出正确 entryId 序列。
- [x] Grok provider 不直接调用共享叙事 mapper。
- [x] `_x.ai` 和标准通知不会创建两套 turn state。
- [x] 现有 Store 即使暂时可能吞并连续不同 id，Phase 2 不宣称最终 UI 契约已完成；最终 UI 验收在 Phase 4。

Phase 2 执行记录（2026-07-17）：

- 应用基线 commit：`1d8b686f` + 当前 Phase 2 working tree；Provider/CLI：
  `grok 0.2.102 (ab5ebf69ac)`；模型：`grok-4.5`。
- H1：通过；真实 live signature 为
  `Reasoning, Message, Tool, Reasoning, Message`，其中 required
  `Message, Tool, Message` 顺序成立。
- H2：通过；长连续思考的 live signature 为 `Reasoning, Message`，只生成一个
  reasoning phase。
- H3：通过；live signature 为
  `Reasoning, Message, Tool, Reasoning, Message`，工具前后 reasoning entryId
  不同。
- H4：通过；live signature 为
  `Reasoning, Tool, Tool, Reasoning, Message`，两个不同 tool id 各一张卡，
  同 id 更新未新增工具卡。
- H5：通过（本次一回合样本）；重开后 history signature 与 live 均为
  `Reasoning, Message, Tool, Reasoning, Message`。这只是 Phase 2 手测记录，
  不替代 Phase 5 的 live/history canonical golden 门禁。
- 全部 H1–H5 smoke 的异常诊断：`duplicate=0`、`late=0`、`missing=0`、
  `collision=0`；`synthetic` 仅记录缺少 source id 时按预期生成的 entryId。
  手测记录未保存 prompt 正文、正文输出或完整 raw payload。

### Phase 3：Cursor 两阶段退役（1.5–3 人日）

目标：先使 Cursor 在产品和运行时中不可选择、不可实例化、不可启动，再删除其专属实现；
全过程保留旧配置容错，且不触碰任何用户 Cursor 数据。真实 Cursor fixture 不再是本阶段输入。

#### Phase 3A：软下线

| 任务 | 范围 | 实施内容 | 测试 |
|------|------|----------|------|
| [x] P3A-1 | provider catalog / 设置 UI / Agent 管理 | 移除 Cursor 可选项、安装/检测/配置入口和支持声明 | catalog、widget、management tests |
| [x] P3A-2 | `app.dart` / bootstrap / provider factory | 停止创建 `CursorAcpAgentProvider`、`FileCursorSessionIndexStore`、CLI locator 与进程 starter | composition/bootstrap tests |
| [x] P3A-3 | 持久化 Provider 配置 | 旧配置仍可解码；最后选择 Cursor 时明确 unavailable，并安全回退到可用 Provider | legacy decode/fallback tests |
| [x] P3A-4 | 用户数据边界 | 对 `~/.cursor`、项目 `.cursor`、`~/.zeta/state/cursor_sessions.json` 建立只读前后快照，退役代码不得读写或删除 | data-boundary regression |
| [x] P3A-5 | 运行时不可达性 | 验证 UI、deep link/恢复、历史入口和启动流程均不能创建 Cursor provider 或启动 `cursor-agent` | negative path/process-spy tests |

Phase 3A 门禁：

- [x] Cursor 不出现在 provider catalog、设置、创建会话和 Agent 管理入口。
- [x] app 组合与 bootstrap 不实例化 Cursor provider/index/locator，也不启动 `cursor-agent`。
- [x] 旧 Cursor 配置不会阻塞启动，用户可见 unavailable 原因并回退到可用 Provider。
- [x] Cursor 外部目录、会话索引和旧配置内容在软下线前后保持原样。
- [x] 相关定向测试与 `flutter analyze` 通过。

Phase 3A 执行记录（2026-07-17）：

- 产品入口：默认 Provider catalog 仅保留 Codex/Grok；创建 Thread 选择器与 Agent 管理页对旧 Cursor
  配置做二次过滤，Cursor 安装、检测、配置、日志和 Beta 支持入口均不可见。
- 组合断开：`app.dart`、默认 factory、Agent 管理组合和 bootstrap 迁移不再构造或引用 Cursor
  provider、session index、CLI locator、process starter 或 management repository；Phase 3B 实现文件仍保留。
- 兼容与数据：旧 Cursor 配置和最后选择值继续容错解码；运行时仅内存回退并展示 unavailable 原因，
  不自动保存；临时目录回归证明用户 Cursor 目录、项目 `.cursor`、Cursor session index 和旧 Provider
  配置内容前后不变，legacy Cursor index preference 也不会被读取或迁移。
- 不可达性：Provider 选择、Agent 管理自动检测、旧配置启动、deep link、工作区恢复、历史入口和
  Provider 聚合均有 negative/process-spy 断言，Cursor provider 创建、CLI locator、进程启动和
  session-index 写入计数均为 0；H6、H7、H8 的软下线场景可自动验证。
- 验证：`dart format .`、`flutter analyze`（0 issues）、11 个相关测试文件（141 tests）通过；
  Phase 3B 前保留的 Cursor provider/locator/starter/index/management 实现测试（47 tests）通过；
  完整 `flutter test` 的非 golden 测试通过，8 个既有 Workbench/AgentPane golden 在当前 Windows
  渲染环境存在 0.09%–0.62% 像素差异，单独串行复跑可复现，未更新与本阶段无关的 golden 基线。

#### Phase 3B：删除实现

必须在 Phase 3A 全部门禁通过后开始。

| 任务 | 范围 | 实施内容 | 测试/审计 |
|------|------|----------|-----------|
| [x] P3B-1 | CodeGraph + `rg` 引用清单 | 审计 Cursor 生产引用、测试引用、共享 ACP 调用方和用户数据边界 | 删除前 blast-radius 记录 |
| [x] P3B-2 | Cursor 运行实现 | 删除 provider、CLI locator、process starter、extension mapper、diagnostics store、session index store 与 management repository | 编译 + 引用审计 |
| [x] P3B-3 | Cursor replay/load | 删除 Cursor 的 live/replay/load 路径；`AcpSessionReplayCollector` 仅在确认无其他调用方时删除 | ACP provider tests |
| [x] P3B-4 | Cursor 专属测试与 fake | 删除运行实现测试；保留旧配置 decode/fallback、不可达性和数据未改写回归 | retirement compatibility tests |
| [x] P3B-5 | fixture 与文档 | synthetic fixture、identity analysis 作为历史证据保留；更新支持列表和设计文档 | docs/fixture review |

Phase 3B 门禁：

- [x] 生产代码不再引用 Cursor provider、CLI、ACP 扩展、诊断、session index 或 management repository。
- [x] 仓库不存在 `cursor-agent`/Cursor ACP 进程启动路径；provider catalog 与 UI 仍无 Cursor。
- [x] 只允许保留明确列入白名单的 legacy 配置兼容标识，以及 fixture/分析等退役证据。
- [x] 共享 ACP 文件经调用图证明仍被活跃 Provider 使用，或已随最后一个调用方安全删除。
- [x] 旧配置 fallback、运行时不可达和用户数据未改写测试通过；`flutter analyze` 通过。

Phase 3B 执行记录（2026-07-17）：

- 删除 Cursor provider、CLI locator、process starter、extension mapper、diagnostics store、
  session index store、management repository 和真实 CLI smoke 工具；删除 8 个只验证这些
  运行实现的测试文件。
- CodeGraph 与 `rg` 证明 `AcpSessionReplayCollector` 的生产调用方只有 Cursor，因此随最后
  调用方及其测试删除；`AcpSessionUpdateDecoder`、content/permission mapper、JSON-RPC
  runtime peer/stdio transport 仍由 Grok 使用，runtime peer/stdio transport 也由 Codex 使用。
- 保留旧 Cursor id/kind/default config、退役策略、unavailable 展示、旧配置 decode/fallback、
  process-spy/运行时不可达、数据未改写测试，以及明确标为退役历史证据的 synthetic fixture。
- 验证：`dart format .`、`flutter analyze`（0 issues）；兼容/不可达/数据边界/目录与管理
  151 tests、共享 ACP/Grok/transport 89 tests、Codex/local history 93 tests 全部通过。
  完整 `flutter test` 为 579 passed、22 skipped，只有 Phase 3A 已记录的 8 个 Windows golden
  像素差异失败，未更新无关 golden 基线。
- 未修改 TimelineStore/EventBuffer，也未读取、迁移、改写或删除任何真实 Cursor 用户数据。

Phase 3 只有按顺序完成 3A 和 3B 才算通过。Cursor 真实 fixture 缺失不再阻塞 Phase 3；
任何未来重新支持 Cursor 的需求必须另立方案并重新采集真实协议 fixture。

### Phase 4：统一层原子性简化（1–1.5 人日）

依赖：Phase 2 已完成，Phase 3A、3B 全部门禁通过。

目标：删除统一层叙事推断，并一次性验证 Grok/Codex 以及 Cursor 退役兼容路径。

| 任务 | 文件 | 实施内容 | 测试 |
|------|------|----------|------|
| [x] P4-1 | `agent_conversation_timeline_store.dart` | 删除 `_resolveStreamingAgentMessageId`、open stream、segment seq、`#segN` | Store unit tests |
| [x] P4-2 | 同上 | `appendMessageDelta` 只按 `event.messageId` create/append；`updateMessage` 按相同 entryId 更新 | delta/update tests |
| [x] P4-3 | Store/ViewModel | 使用 domain `AgentMessageKind`，删除 raw plan sniff，并移除/替换 application 层重复枚举 | plan tests |
| [x] P4-4 | `agent_event_stream_buffer.dart` | coalescing key 纳入 message kind；merge 必须保留 source id/kind；reasoning merge 保留 source item id | EventBuffer tests |
| [x] P4-5 | Codex mapper/provider | 增加不同 itemId、item/tool/item、delta/completed 测试 | app-server tests |
| [x] P4-6 | ViewModel/Widget | 验证最终 `Message, Tool, Message` 和 reasoning phase 顺序 | view model/widget tests |

禁止事项：

- 不增加任何 `providerId` 特判；Cursor 退役逻辑只存在于配置兼容与组合边界。
- 不读取 `raw['_legacyStreamSegment']`。
- 不保留默认关闭但无人负责删除的 legacy path。
- 不在 EventBuffer 中实现“最后条目是否开放”的替代启发式。

Phase 4 门禁：

- [x] `rg "#seg|_openAgentMessage|_resolveStreamingAgentMessageId" lib/src/features/agent/application` 无生产代码命中。
- [x] Store 同 id 合并、异 id 新建测试通过。
- [x] EventBuffer `Message(seg1), Tool(pending), Message(seg2)` 顺序测试通过。
- [x] Grok、Codex provider 定向测试与 Cursor 退役兼容测试全部通过。
- [ ] H1、H3、H6、H7、H8、H9 手测通过。

Phase 4 执行记录（2026-07-17）：

- 前置门禁：Phase 2、Phase 3A、Phase 3B 的执行记录与门禁均为通过；生产代码审计未发现
  Cursor live/replay/ACP、`cursor-agent` 或 Cursor provider 实例化路径，因此才删除 Store 兜底。
- Store 只按 normalized entryId create/append/update，删除 open message、last-entry、segment seq 和
  `#segN`；未知 completed snapshot 不创建新消息。Store/ViewModel 使用 domain
  `AgentMessageKind`，raw payload 不再控制 identity 或 plan kind。
- EventBuffer 的 message key 包含 `AgentMessageKind`，message/reasoning merge 保留 source id、
  kind、phase、status、duration 与 index；不同 normalized entryId 不合并。
- Codex 基线为本机 `codex-cli 0.144.1` stable schema，schema 与已安装版本匹配；验证了
  `item/agentMessage/delta`、`item/completed`、reasoning text/summary/index 和未知未来 item type，
  未升级 CLI、未使用 experimental API。
- `dart format .`、`flutter analyze` 和 §11.5 全部定向测试通过；额外通过页面切换状态测试及
  Cursor 退役兼容 147 tests。精确 `rg` 审计无禁用符号命中。
- H1/H3、H6–H9 均有自动化等价回归覆盖，Phase 2/3 记录也包含此前 smoke 证据；但当前环境
  未重新执行真实外部 Provider/桌面手测，因此本轮 Phase 4 手测门禁保持未勾选，不以自动化冒充手测。

### Phase 5：History 对齐与共享层收口（1–2 人日）

目标：重开会话与 live 保持语义一致，并移除迁移期共享 mapper。

| 任务 | 文件 | 实施内容 | 测试 |
|------|------|----------|------|
| [x] P5-1 | `grok_updates_history_parser.dart` | 使用 fresh history reducer；正文/reasoning/tool 顺序对齐 live | history fixture tests |
| [x] P5-2 | golden comparator | 比较 canonical signature，而非只比较数量 | live/history golden tests |
| [x] P5-3 | `acp_session_update_mapper.dart` | 删除或降级为无状态 decoder facade；移除 eventId/turn scope identity 代码 | mapper references audit |
| [x] P5-4 | docs | 更新 engineering standards、developer guide、design document | 文档 review |
| [x] P5-5 | 注释/命名 | 修正 `messageId`、Store、replay 的旧语义注释 | `rg` 审计 |

Phase 5 门禁：

- [x] Grok live/history canonical signature 一致。
- [x] 生产代码不包含 Cursor live/replay/ACP 运行引用。
- [x] 共享 ACP 文件不包含 Grok/Cursor eventId 叙事假设，也不含已退役 Cursor 分支。
- [x] 新增 Provider 文档说明只需实现 adapter/reducer，无需修改 Store。

Phase 5 执行记录（2026-07-17）：

- Grok `updates.jsonl` parser 每次 `parse` 内创建 fresh `GrokSessionUpdateMapper` / reducer；
  live 与 history 复用 boundary 算法但不共享 mutable state。messageId/eventId 不再生成 history
  entryId；缺少稳定 turn id 时使用 `grok-history:<thread>:turn:<ordinal>` 确定性顺序 id。
  正文按 boundary 分段，连续 reasoning 聚合为 phase，tool start/progress/completed 按 tool id
  在原位置 upsert；reader 只读回归证明来源 `updates.jsonl` 字节不变。
- 新增完整 canonical comparator 与脱敏 golden。它逐位置比较 turn ordinal、entry ordinal、
  entry type、message/reasoning phase ordinal、存在时的 source id、normalized text、tool
  kind/status；覆盖 text→tool→text、thought→tool→thought 和同 tool id 三次更新。live 使用
  epoch 73、history 使用 parser 私有 epoch 0，最终类型顺序严格为
  `T1: Message, Tool, Message; T2: Reasoning, Tool, Reasoning`，两侧均与 golden 完全一致。
- CodeGraph 与 `rg` 证明迁移期 `AcpSessionUpdateMapper` 无生产调用方，唯一调用方是其自身
  兼容测试，因此文件与测试一并删除。保留的 `AcpSessionUpdateDecoder` 仍为无状态语法
  decoder；content、permission、session config、runtime peer 与 stdio transport 仍由 Grok
  或其他活跃链路使用，未误删。
- Cursor 运行残留精确审计无 `CursorAcpAgentProvider`、replay/load collector、Cursor ACP
  extension、CLI locator/process starter 或 `cursor-agent` 命中。白名单仅保留旧 `cursor` id /
  `cursorAcp` kind/default config 的宽容 decode、`CursorRetirementPolicy` fallback/unavailable、
  factory fail-closed、受保护 `cursor_sessions.json` 路径、UI 退役展示、兼容测试和 synthetic
  退役证据；未读取或改写真实 Cursor 用户数据。
- 同步 `engineering_standards.md`、`developer_guide.md`、`design_document.md`、`AGENTS.md`
  与 `product_requirements.md`：明确 sourceId/entryId、Provider adapter/reducer 边界、Store
  dumb merge、live/history 状态隔离、Codex/Grok 活跃列表、Cursor 不参与运行时，以及新增
  Provider 无需修改 Store。
- `dart format .` 与 `flutter analyze`（0 issues）通过；PR-E 定向矩阵 184 tests 与共享
  transport 21 tests 全部通过，其中包含 decoder/Grok mapper/provider、history
  parser/reader/golden、TimelineStore、旧配置 fallback、运行时不可达和用户数据未改写。
  H5 的当前 canonical reopen 自动化等价门禁通过，
  并保留 Phase 2 已记录的真实 Grok H5 smoke 结果。本轮完整 `flutter test` 为 584 passed、
  22 skipped；仅前序报告已记录的 8 个 Windows golden 像素差异失败，未更新无关基线。

### Phase 6：全量回归与发布验收（0.5–1 人日）

| 任务 | 内容 | 完成标准 |
|------|------|----------|
| P6-1 | `dart format .` | 无未格式化 Dart 文件 |
| P6-2 | `flutter analyze` | 0 error；新增 warning 必须处理 |
| P6-3 | 全量 `flutter test` | 全绿 |
| P6-4 | H1–H10 手测 | 记录 provider/version/结果 |
| P6-5 | 诊断检查 | 无 identity collision、missing scope、late drop 异常增长 |
| P6-6 | 变更报告 | 记录 PR、测试、已知限制与回滚点 |

---

## 11. 测试策略

### 11.1 测试分层

| 层 | 重点 | 不应测试 |
|----|------|----------|
| decoder unit | raw → typed update、未知字段、空字段 | UI 气泡 |
| reducer unit | source→entry、boundary、generation、去重 | transport |
| mapper sequence | typed update 序列 → AgentEvent 序列 | Widget 样式 |
| provider test | live/replay 接线、终态竞态、断连、server request boundary | 页面布局 |
| EventBuffer test | 批内合并与 barrier 顺序 | Provider raw |
| Store test | 同 id/异 id、metadata update、无启发式 | 厂商策略 |
| ViewModel/Widget | 最终 entry 类型和顺序、展开态/滚动回归 | 协议字段解析 |
| history golden | live/history canonical signature | runtime epoch |
| retirement compatibility | 旧 Provider 配置回退、运行时不可达、用户数据未改写 | 已退役 Provider 协议语义 |

### 11.2 必须覆盖的交错矩阵

| 场景 | 期望条目 |
|------|----------|
| text, text | Message |
| text, tool, text | Message, Tool, Message |
| text(A), tool, text(A) | Message(entry1/sourceA), Tool, Message(entry2/sourceA) |
| text(A), text(B) | Message(A), Message(B) |
| text, thought, text | Message, Reasoning, Message |
| thought, thought | Reasoning |
| thought, tool, thought | Reasoning, Tool, Reasoning |
| text, permission, text | Message, Permission, Message |
| text, plan, text | Message, Plan, Message |
| tool pending, tool progress, tool completed | 单 Tool 原地更新 |
| terminal, late text | 无新增条目，diagnostic +1 |
| turn1 source=A, turn2 source=A | 两个不同 entryId |

### 11.3 隔离与 Cursor 退役兼容矩阵

| 场景 | 断言 |
|------|------|
| 旧配置最后选择 Cursor | 可容错读取，显示 unavailable，并安全回退；不创建 provider |
| 应用启动与 Provider 探测 | 不调用 Cursor CLI locator，不启动 `cursor-agent` |
| 软下线与删除实现前后 | `~/.cursor`、项目 `.cursor`、`cursor_sessions.json` 内容不变 |
| connection epoch 1 关闭后 epoch 2 | epoch 1 事件被拒绝 |
| turn generation 1 terminal 后 generation 2 | generation 1 迟到内容不能进入 generation 2 |

### 11.4 Codex 回归矩阵

| 场景 | 断言 |
|------|------|
| 同 itemId 两个 agentMessage delta | 顺序拼接为一条 |
| 不同 itemId 连续 agentMessage | 两条，不被 open merge |
| itemA, toolItem, itemB | Message, Tool, Message |
| delta(itemA), completed(itemA) | completed 更新 itemA，不重复创建 |
| reasoning text/summary delta | 按 reasoning itemId 与 index 聚合 |
| 未知未来 item type | 宽容忽略/诊断，不破坏连接 |

### 11.5 建议测试命令

每个 Dart 行为 PR：

```sh
dart format .
flutter analyze
```

定向门禁：

```sh
flutter test test/src/features/agent/domain/
flutter test test/src/features/agent/data/mappers/
flutter test test/src/features/agent/data/datasources/acp/
flutter test test/src/features/agent/data/datasources/app_server/
flutter test test/src/features/agent/data/datasources/local_history/
flutter test test/src/features/agent/application/agent_event_stream_buffer_test.dart
flutter test test/src/features/agent/application/agent_conversation_timeline_store_test.dart
flutter test test/src/features/agent/presentation/agent_conversation_view_model_test.dart
flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart
```

最终门禁：

```sh
flutter test
```

---

## 12. 手工验收清单

| ID | Provider | 场景 | 期望 |
|----|----------|------|------|
| H1 | Grok | 先说明、读取文件、再总结 | Message, Tool, Message |
| H2 | Grok | 长连续思考 | 单个连续 reasoning phase，不按 eventId 碎卡 |
| H3 | Grok | 思考、工具、继续思考 | Reasoning, Tool, Reasoning |
| H4 | Grok | 多工具连续更新 | 每个 tool id 一张卡，状态原地更新 |
| H5 | Grok | turn 结束后重开会话 | 与 live canonical 顺序一致 |
| H6 | Cursor 退役 | 打开 Provider 选择、设置和 Agent 管理 | 不显示 Cursor 可选项或安装/配置入口 |
| H7 | Cursor 退役 | 使用最后选择 Cursor 的旧配置启动 | 显示 unavailable 原因并安全回退，不创建 Cursor provider |
| H8 | Cursor 退役 | 启动、恢复工作区并退出应用 | 不启动 `cursor-agent`；Cursor 目录与本地 session index 未改写 |
| H9 | Codex | item→tool→item | Message, Tool, Message |
| H10 | Codex | 多 agentMessage item + completed | 不粘连、不重复、终态正确 |

手测记录必须包含：应用 commit、Provider/CLI 版本、场景 ID、结果、异常诊断计数；不得保存用户 prompt 正文。

---

## 13. 观测与诊断

### 13.1 建议计数器

| 名称 | 触发条件 | 严重度 |
|------|----------|--------|
| `syntheticEntryIdCreated` | Provider 缺少 source id，adapter 合成 entryId | info |
| `duplicateRawEventDropped` | 重复 eventId 被丢弃 | fine/info |
| `lateContentDropped` | terminal/旧 generation 内容被丢弃 | warning |
| `missingTurnScopeDropped` | 无法安全解析 turn scope | warning |
| `identityCollisionDetected` | 新 entryId 与已关闭/其他 turn 冲突 | error |
| `conflictingTerminalIgnored` | 第二终态与首个终态冲突 | warning |
| `historyStateLeakPrevented` | history/live 实例误复用被 assert/guard 拒绝 | error |

### 13.2 隐私约束

- 日志只记录 providerId、脱敏 session/turn 标识、事件 kind 和计数。
- 不记录 message/reasoning 文本、完整 raw payload、命令、文件内容或凭据。
- source id 如可能包含敏感信息，只记录 hash/截断后的诊断值；不得使用 Dart `hashCode` 作为持久稳定 id。

### 13.3 Debug 断言

开发模式建议断言：

- closed entryId 不再接收 delta。
- history mapper/reducer 与 live mapper/reducer 不为同一实例。
- active turn state 的 connection epoch 与当前 peer 一致。
- completed update 能解析到现有 source→entry 映射。

release 模式不得因断言条件导致崩溃，应降级为诊断和安全丢弃。

---

## 14. 风险与缓解

| ID | 风险 | 影响 | 缓解 |
|----|------|------|------|
| R1 | 旧配置最后选择 Cursor，软下线后启动失败 | 用户无法进入应用或配置丢失 | 宽容解码、明确 unavailable、安全回退，保留原配置 |
| R2 | 只隐藏 UI，Cursor 仍可从组合/恢复路径启动 | 已退役进程仍运行 | catalog、factory、bootstrap、deep link/恢复入口联合审计与 process-spy 测试 |
| R3 | 显式 source id 在 tool 前后复用 | 更新旧气泡 | sourceId/entryId 分离，segment ordinal |
| R4 | turn_completed 与 RPC 返回竞态 | 重复完成、状态丢失 | first-terminal-wins + generation guard |
| R5 | terminal 后迟到内容 | 写入下一 turn | terminal tombstone + late drop |
| R6 | 完整 snapshot 跨多个 segment | 文本重复或顺序扁平化 | 多 segment 时只更新 metadata，禁止盲 replace |
| R7 | 退役时删除或重写 Cursor 用户数据 | 会话索引或用户配置丢失 | 明确禁止迁移/删除，受保护路径前后快照回归 |
| R8 | 删除 Cursor 时误删 Grok 仍使用的共享 ACP 代码 | 活跃 Provider 回归 | CodeGraph 调用图 + `rg` 引用审计，只删除 Cursor 专属或已无调用方的代码 |
| R9 | legacy 开关长期残留 | 双轨不可维护 | 不使用 raw 开关；回滚以 PR revert 为主 |
| R10 | 新 kind/source 字段改动面扩大 | 编译和测试成本 | 默认值兼容旧构造，分 PR 迁移 |

---

## 15. 回滚策略

### 15.1 原则

- 不在 raw payload 中加入兼容开关。
- 不在 TimelineStore 保留长期双轨。
- 每个 PR 保持可单独 revert。
- Phase 4 是统一层行为切换点；发现跨 Provider 回归时优先整体 revert Phase 4。

### 15.2 分阶段回滚

| PR/阶段 | 回滚方式 | 数据影响 |
|---------|----------|----------|
| Phase 1 Domain/decoder | revert 对应 PR；字段有默认值时可单独保留 | 无持久数据迁移 |
| Phase 2 Grok | revert Grok adapter 接线，恢复迁移期 mapper | 仅 live 展示变化 |
| Phase 3A Cursor 软下线 | revert 软下线 PR，恢复原目录/组合入口；不得借回滚改写用户数据 | 无数据迁移，Cursor session index 保持原样 |
| Phase 3B Cursor 删除 | revert 删除实现 PR；如需重新启用，必须先恢复完整实现和测试，再恢复入口 | 无数据迁移，外部 Cursor 数据保持原样 |
| Phase 4 Store | 整体 revert Store/EventBuffer PR | 恢复 open/`#segN`；不得只恢复一半 |
| Phase 5 history | revert parser；保留 live adapter | 不重写用户原始 history 文件 |

### 15.3 可选 typed 开关

只有无法通过测试环境覆盖 Provider 版本差异时，才允许在 app 组合层增加：

```dart
enum ProviderStreamIdentityMode { legacy, normalized }
```

要求：

- 按 provider 配置，不通过 raw 事件传递。
- 默认 `normalized` 前必须完成全部门禁。
- 创建时同时登记删除日期和负责人。
- Store 仍不得包含 provider-specific 分支；legacy 逻辑留在对应 provider adapter。
- 该开关不得用于重新启用 Cursor；Cursor 只能通过新的、具备真实协议证据的独立方案恢复支持。

---

## 16. PR 拆分与排期建议

### 16.1 PR 划分

| PR | 内容 | 依赖 | 可并行 | 合并条件 |
|----|------|------|--------|----------|
| PR-A | Phase 0 + Domain kind/source 字段 + ACP decoder（已完成） | 无 | 否 | 基线 fixture、domain/decoder tests |
| PR-B | Grok reducer/mapper/provider lifecycle（已完成） | PR-A | 否 | Phase 2 门禁 |
| PR-C1 | Cursor 软下线：目录/UI/组合/启动/旧配置回退 | PR-B | 否 | Phase 3A 门禁 |
| PR-C2 | Cursor 实现与专属测试删除 | PR-C1 | 否 | Phase 3B 门禁 |
| PR-D | Store/EventBuffer dumb merge + Codex/ViewModel 回归 | PR-B、PR-C2 | 否 | Phase 4 全部门禁 |
| PR-E | Grok history golden、共享 mapper 清理、工程文档 | PR-D；部分 history 工作可提前 | 部分 | Phase 5 门禁 |
| PR-F | 全量回归和必要的小修 | PR-E | 否 | Phase 6 发布验收 |

### 16.2 工作量

| Phase | 估时 |
|-------|------|
| Phase 0（已完成） | 1–1.5 人日 |
| Phase 1（已完成） | 1–2 人日 |
| Phase 2（已完成） | 1.5–2.5 人日 |
| Phase 3 | 1.5–3 人日 |
| Phase 4 | 1–1.5 人日 |
| Phase 5 | 1–2 人日 |
| Phase 6 | 0.5–1 人日 |
| 总计 | 约 7.5–13.5 人日 |
| 剩余 Phase 3–6 | 约 4–7.5 人日 |

PR-C2 必须等待 PR-C1 的软下线门禁通过；PR-D 必须等待 PR-C2 完成，不能把运行入口删除和
Store 行为切换放进同一个不可独立回滚的 PR。

### 16.3 排期登记表

实际排期时复制并填写：

| PR | 开发负责人 | 评审负责人 | 计划开始 | 计划完成 | 状态 |
|----|------------|------------|----------|----------|------|
| PR-A | 已完成 | 已完成 | 2026-07-17 | 2026-07-17 | 已完成 |
| PR-B | 已完成 | 已完成 | 2026-07-17 | 2026-07-17 | 已完成 |
| PR-C1 | 已完成 | 已完成 | 2026-07-17 | 2026-07-17 | 已完成 |
| PR-C2 | 已完成 | 已完成 | 2026-07-17 | 2026-07-17 | 已完成 |
| PR-D | 已完成 | 已完成 | 2026-07-17 | 2026-07-17 | 已完成 |
| PR-E | 已完成 | 已完成 | 2026-07-17 | 2026-07-17 | 已完成 |
| PR-F | 待分配 | 待分配 | 待定 | 待定 | 未开始 |

### 16.4 Definition of Ready

任务进入开发前必须满足：

- [ ] 对应 fixture 已脱敏并入库。
- [ ] 输入字段与预期 boundary 已写清。
- [ ] 涉及的 Provider/CLI 版本已记录。
- [ ] 测试文件和验收场景已指定。
- [ ] 活跃 Provider 无未决的“eventId 是否表示消息边界”等协议问题；已退役 Provider 的协议未知项不构成门禁。

### 16.5 Definition of Done

- [ ] 代码与 feature-sliced 目录归属一致。
- [ ] 新公共 API 有中文 `///` 注释。
- [ ] 无 Provider raw 语义泄漏到 Store/ViewModel/UI。
- [ ] 活跃 Provider 的 live/replay/history mutable state 隔离。
- [ ] 已退役 Provider 不可从 UI、配置恢复或组合路径进入运行时，且用户数据未改写。
- [ ] 定向测试、`flutter analyze`、最终 `flutter test` 通过。
- [ ] 手测记录包含版本和诊断结果。
- [ ] 对应工程文档同步。
- [ ] PR 描述包含回滚点和已知限制。

---

## 17. 文档同步清单

| 文档 | 必须更新的内容 |
|------|----------------|
| `docs/engineering_standards.md` | sourceId/entryId、Provider adapter 边界、Store dumb merge、state isolation、Cursor 退役边界 |
| `docs/developer_guide.md` | 活跃 Provider 列表、新增 Provider 的 decoder/adapter/reducer 接入步骤和测试要求 |
| `docs/design_document.md` | AgentEvent 流、EventBuffer、TimelineStore 的目标架构及 Cursor 不再参与运行时组合 |
| `AGENTS.md` | 简短规则：厂商 quirks 留在 data adapter；统一层不得猜 identity |
| 本方案 | PR 合并后勾选任务、记录偏差和最终结果 |

---

## 18. 最终实施检查清单

### 契约与共享层

- [x] `AgentMessageKind` 已加入 domain。
- [x] message delta/updated 已区分 entryId 与 sourceMessageId。
- [x] reasoning 已区分 entry itemId 与 sourceItemId。
- [x] ACP decoder 无状态且不决定叙事边界。
- [x] Store/ViewModel 不从 raw 判断 plan/identity。

### Grok

- [x] Grok reducer 按 session/turn/epoch 隔离。
- [x] text/tool/text 输出两个 message entryId。
- [x] 连续 thought 不按 eventId 碎卡。
- [x] thought/tool/thought 输出两个 reasoning phase。
- [x] 标准 ACP 与 xAI 终态 first-terminal-wins。
- [x] cancel/error/peer close/dispose 正确 invalidate。

### Cursor 退役

- [x] Provider 目录、设置、创建会话和 Agent 管理 UI 不再显示 Cursor。
- [x] app 组合、bootstrap、恢复路径不创建 Cursor provider 或启动 `cursor-agent`。
- [x] 旧 Cursor 配置可容错读取、明确 unavailable 并安全回退。
- [x] Cursor 专属运行实现与测试已删除，只保留必要兼容和退役证据。
- [x] `~/.cursor`、项目 `.cursor`、`cursor_sessions.json` 与用户旧配置未被改写。

### Codex

- [x] 同 itemId delta 正确拼接。
- [x] 不同 itemId 不粘连。
- [x] delta/completed 更新同一 entry。
- [x] reasoning index 行为无回归。
- [x] 基线明确为本机 0.144.1 stable schema。

### 统一层与 UI

- [x] TimelineStore 无 open/`#segN`。
- [x] EventBuffer 不跨 normalized entryId 合并。
- [x] `Message, Tool, Message` Widget/VM 测试通过。
- [x] reasoning phase 顺序测试通过。
- [x] 页面切换、草稿、滚动和展开态无回归。

### History、质量与发布

- [x] Grok live/history canonical golden 一致。
- [x] 诊断不记录敏感正文/raw payload。
- [x] `dart format .` 已执行。
- [x] `flutter analyze` 已通过。
- [ ] 定向测试与 `flutter test` 已通过。
- [ ] H1–H10 手测已记录。
- [x] 文档同步完成。
- [ ] 回滚点已写入 PR 描述。

---

## 19. 术语

| 术语 | 定义 |
|------|------|
| source id | Provider 原始协议身份，不直接作为 UI 合并依据 |
| entryId | Zeta 规范化时间线条目身份，也是统一层合并键 |
| message segment | 两个 narrative boundary 之间的连续正文条目 |
| reasoning phase | 两个 narrative boundary 之间的连续 reasoning 条目 |
| narrative boundary | 会改变时间线叙事顺序并关闭当前 message/reasoning 的可见事件 |
| reducer | Provider-local、有状态的 identity 状态机 |
| decoder | 共享、无状态的 ACP 原始字段解析器 |
| dumb merge | 同 id 更新、异 id 新建，不推测 Provider 叙事结构 |
| generation | 同一 session 内区分连续 turn、取消和迟到事件的本地代数 |
| canonical signature | 用于比较 live/history 语义一致性的稳定条目签名 |

---

## 20. 变更记录

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-07-17 | 1.0 | 初版：提出 Grok identity 下沉和 Store dumb merge |
| 2026-07-17 | 2.0 | 补齐 source/entry 身份、typed decoder、Cursor 先迁移、replay 隔离、reasoning phase、生命周期、EventBuffer、测试门禁、排期与回滚，升级为可直接安排开发的实施规格 |
| 2026-07-17 | 2.1 | 标记 Phase 0–2 已完成；Cursor 改为 Phase 3A 软下线、Phase 3B 删除实现，并同步后续门禁、测试、风险和回滚 |
| 2026-07-17 | 2.2 | 完成 Phase 3A/3B Cursor 退役，记录实现删除、兼容白名单、共享 ACP 调用图与验证结果 |
| 2026-07-17 | 2.3 | 完成 Phase 4 P4-1 至 P4-6 与自动化门禁；保留未重新执行的 H1/H3/H6/H7/H8/H9 手测项未勾选 |
| 2026-07-17 | 2.4 | 完成 Phase 5 P5-1 至 P5-5：Grok live/history canonical golden、fresh history reducer、共享 mapper 删除、Cursor 残留审计与文档收口 |
