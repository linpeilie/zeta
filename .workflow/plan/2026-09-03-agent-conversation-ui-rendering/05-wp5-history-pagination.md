# WP-5 · 历史分页加载

| 项 | 值 |
|----|----|
| 状态 | 未开始 |
| 规模 | 5–8 人天（含 spike） |
| 依赖 | WP-1 完成后启动（分页状态归 runtime controller）；与 WP-2/3/4 解耦 |
| 门禁焦点 | G4（capability 驱动）、G2（Store 不猜身份）、G6 |

---

## 0. 背景与现状代码

**现状**：`readThreadHistory` 一次性返回全量历史（`packages/zeta_agent_core/lib/src/domain/agent_provider_bundle.dart:119-128`）：

```dart
abstract interface class AgentThreadCatalogPort {
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query});

  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  });
}
```

**没有 cursor/分页参数**。对应 capability 位是 `canReadHistory`（`agent_provider_capabilities.dart:56,86`）；bundle 的惯例是「操作是否存在以端口是否非空为单一真源」（该类注释明确）。

**性能上下文**：虚拟化 + markdown 缓存已让 UI 渲染不再是瓶颈（WP 分析结论）；真正的规模风险是**历史归约成本与 TimelineStore 内存**随会话长度线性增长。因此本 WP 的优先级低于 WP-1/2/6，且必须先做 T0 spike 确认收益。

## 1. 目标与非目标

- **目标**：超长会话（>500 turn）首次打开只加载最近 N 个 turn；向上滚动按需加载更早历史；live turn 与 standby 语义不受影响。
- **非目标**：不做 turn 内 entry 级分页；不做历史搜索；不改 Provider 的会话文件格式。

## 2. 任务拆分

### T0 · Spike：能力与收益评估（1 人天，产出决策记录）

**必须回答的四个问题**（逐个写结论 + 证据）：

1. **Provider 协议是否支持分页读历史？** 查 Codex app-server 的 thread/read 或 resume 接口是否有 limit/cursor；Grok ACP 的 session/load；Claude Code 的会话文件读取（本地 JSONL，可自行分页——文件在 Zeta 侧读，天然支持）。结论决定契约形态。
2. **TimelineStore 是否支持 prepend？** 读 `agent_conversation_timeline_store.dart` 的 merge 入口，确认「更早的 turn 插到头部」是否需要新 API（大概率需要 `prependHistoryTurns`）。
3. **虚拟化锚点是否支持头部插入？** 读 `IdeAnchoredDynamicSliverList` / `IdeVirtualListController` 的锚定语义：头部插入 N 项时滚动位置是否自动补偿（这是分页体验的生死点；若不支持，工作量 +2 人天）。
4. **收益量化**：构造 500-turn fixture，测全量归约耗时与内存峰值（Debug 数据不作结论，用 Profile）。

**产出**：`.workflow/plan/2026-09-03-agent-conversation-ui-rendering/` 下追加决策记录 DR-004（做/不做/做什么粒度），并更新 `00-index.md` §3。

### T1 · domain 契约（0.5 人天，依赖 T0 结论）

**推荐形态**（若 T0-1 结论为「至少一个 Provider 支持」）：新增可选 bundle 端口，而不是改 `AgentThreadCatalogPort` 签名——符合「端口非空 = 能力存在」惯例（G4）：

```dart
// packages/zeta_agent_core/lib/src/domain/agent_provider_bundle.dart
final class AgentProviderBundle {
  const AgentProviderBundle({
    // ... 现有 ...
    this.threadHistoryPagination,   // 新增可选端口
  });
  final AgentThreadHistoryPaginationPort? threadHistoryPagination;
}

/// 分页历史读取端口（新文件 domain/agent_thread_history_pagination_port.dart）。
abstract interface class AgentThreadHistoryPaginationPort {
  /// 读一页历史：beforeTurnId 为空 = 最新一页；否则只取早于该 turn 的一页。
  Future<AgentThreadHistoryPage> readThreadHistoryPage({
    required String threadId,
    String? sessionPath,
    String? projectPath,
    String? beforeTurnId,
    required int limit,
  });
}

final class AgentThreadHistoryPage {
  const AgentThreadHistoryPage({
    required this.turns,          // List<AgentConversationTurnGroup> 或协议快照，以 T0 结论为准
    required this.oldestTurnId,   // 本页最早 turn 的稳定 id（下一次分页的 anchor）
    required this.hasMore,
  });
  // ...
}
```

- capability：不加新静态位——端口非空即能力（bundle 惯例）；UI 按 `bundle.threadHistoryPagination != null` 渲染「加载更早」入口。
- 守卫：新端口进 bundle 字段清单测试（`agent_provider_bundle` 相关契约测试补一例）。

### T2 · Provider 实现（1–2 人天/Provider，按 T0 结论裁剪）

- Codex：若协议无分页 → **不实现该端口**（端口留空 = 不支持，UI 不出现入口，G4）；Claude Code：本地 JSONL 按行/turn 边界分页读取（data 层 adapter 内实现，协议细节不出 data 层，G6）。
- 每个实现配契约测试：分页边界（恰好 limit、末页 hasMore=false、空历史）、turn 顺序（时间倒序取页、返回正序）。

### T3 · TimelineStore prepend（1 人天）

```dart
// agent_conversation_timeline_store.dart 新增
/// 把更早的一页历史插到头部。只做 dumb merge（G2）：
/// 同 turnId 忽略（幂等），不排序、不去重 entry——顺序由调用方（history 加载器）保证。
void prependHistoryTurns(List<AgentConversationTurnGroup> olderTurns) {
  // 1. 过滤已存在 turnId（幂等，滚动抖动可能重复触发）
  // 2. _turns.insertAll(0, filtered)
  // 3. 本方法不发任何 UI 通知——TimelineStore 是 dumb store（终审修正：
  //    初版写「走既有 UiUpdateRequest 通道」有误，UiUpdateRequest 由 reducer/
  //    processor 产出，store 不持有该通道）。prepend 后由调用方触发 history
  //    region 刷新：WP-1 后 = SliceStore 直接 dispatch RegionsRefreshed；
  //    WP-1 前 = ViewModel 经 UiUpdatePort 发 history region 请求。
}
```

- **G1 自查**：该方法落在 G1 五文件之一的 TimelineStore——实现里禁止出现任何 providerId/kind 分支或从 raw payload 猜身份，纯 turnId 幂等 + 头部插入。

- 测试：prepend 幂等、与 live turn 追加的交错（live 进行中 prepend 不影响 liveTurnState）、与 `syncLiveTurnBinding` 的交互。
- **review 补充两个必须核对的交互**：① `turnContextStore` 的 history overlay 重建（G2 提到的 enrich/overlay 重建点）在 prepend 后是否需要对更早 turn 重放 overlay——读 history 加载路径确认；② `standbyTurn` 不受分页影响（它是本地回显，不属于历史页），但 `AgentConversationHistoryState.visibleTurns` 的窗口变化要反映到 `_semanticSignature`，否则 selector 不触发重建。

### T4 · UI 窗口化与加载触发（1–2 人天）

1. `AgentConversationHistoryState` 增加 `hasMoreHistory` / `isLoadingMoreHistory` 字段（region state 在 application，字段平移即可，注意 `_semanticSignature` 纳入新字段）。
2. 加载触发：虚拟列表首项进入视口时触发（`IdeVirtualListController` 的可见性回调；**不要**用 scroll offset 阈值——锚点语义下 offset 不可靠）。
3. 「加载更早」入口：首项上方渲染 `IdeStatusCard(compact)` 加载条（复用 WP-4 T1 原语；**WP-4 T1 未合入时用现有 regular 档**，本 WP 不因此阻塞——头部「与 WP-4 解耦」以此为准）；加载中防重入（`isLoadingMoreHistory`）。
4. 锚点保持：prepend 后滚动位置必须停留在原内容（T0-3 的结论决定这里是免费获得还是要补 offset 补偿）。

### T5 · 收尾（0.5 人天）

- [ ] 500-turn fixture 的 widget 测试：首屏只渲染最近 N turn、上滚触发加载、加载后锚点不跳。
- [ ] `tool/test_full.sh` 绿；`docs/guides/developer_guide.md` 补「历史分页」小节；登记 `00-index.md` §6「开发记录」。

## 3. 风险与回滚

| 风险 | 缓解 |
|------|------|
| T0 结论为「收益不足」 | 整个 WP 关闭，DR-004 记录原因——这是合法产出 |
| 锚点补偿复杂 | T0-3 提前暴露；不支持则缩小范围（只做「打开时只加载最近 N 页 + 显式按钮加载」，不做无限滚动） |
| Provider 间行为不一致 | 端口可选 + capability 驱动 UI；不支持的 Provider 保持现状全量加载 |

## 4. 完成定义（DoD）

- [ ] DR-004 决策记录归档；若实施：500-turn 会话首屏加载时间可测地下降（Profile 数据入 PR 描述）。
- [ ] 不支持的 Provider 行为零变化；`tool/test_full.sh` 绿。
