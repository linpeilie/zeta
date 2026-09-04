# WP-7 · 卫生清扫

| 项 | 值 |
|----|----|
| 状态 | 已完成 |
| 规模 | 2–3 人天，每任务独立小 PR |
| 依赖 | 无（T1/T2 与 WP-2 的 styles 原地转换有先后关系，见任务内说明） |
| 门禁焦点 | G6 / G7 / G8 |

> 五个任务互相独立，可任意顺序、任意人并行。每个任务的「现状」代码均为 2026-09-03 逐字摘录。

---

## T1 · 5 处英文字面量接入 l10n（0.5 人天）

- [x] 5 个函数接入 l10n；导航轨同源短标签一并走 `agentTurnTokenUsage`。

**现状**（`agent_pane_styles.dart:365-440`，5 个函数含英文字面量）：

```dart
String? _threadOpenStatusText(AgentHeaderState state) {
  return switch (state.threadOpenPhase) {
    AgentThreadOpenPhase.loadingHistory => 'Loading thread history...',
    AgentThreadOpenPhase.openFailed => 'Thread open failed. Click this thread again to retry.',
    AgentThreadOpenPhase.idle => state.systemNoticeLabel,
  };
}
String? _turnTokenUsageLabel(AgentTokenUsage? usage) => ... '${usage!.displayTotalTokens!} tokens';
String? _threadTotalTokenUsageLabel(AgentTokenUsage? usage) => ... 同上
String _contextWindowTokenUsageTooltip(AgentTokenUsage? usage) => ... 'Usage: $percent%' / 'Used: ...' / 'Total: ...'
String _tokenUsageTooltip(AgentTokenUsage? usage) => ... 'Total: $value' / 'Context window: $value' / 'Input: $value' / 'Cached: $value' / 'Output: $value'
```

**步骤**：

1. ARB 新增（`app_en.arb` / `app_zh.arb` 同步，key 带 description，placeholder 一律 String）：

```json
"agentThreadLoadingHistory": "Loading thread history...",
"@agentThreadLoadingHistory": { "description": "头栏状态：正在加载 thread 历史" },
"agentThreadOpenFailedRetry": "Thread open failed. Click this thread again to retry.",
"@agentThreadOpenFailedRetry": { "description": "头栏状态：thread 打开失败，点击重试" },
"agentTurnTokenUsage": "{count} tokens",
"@agentTurnTokenUsage": { "description": "单个 turn 的 token 用量短标签", "placeholders": { "count": { "type": "String" } } },
"agentTokenUsageContextTooltip": "Usage: {percent}%\nUsed: {used}\nTotal: {total}",
"...": "（percent/used/total 均 String placeholder；多行用 \\n）",
"agentTokenUsageDetailTooltip": "..."
```

2. 函数签名加 `AppLocalizations l10n` 参数（如 `threadOpenStatusText(AgentHeaderState state, AppLocalizations l10n)`），调用点传 `context.l10n`。已知调用点：`threadOpenStatusText` ← `agent_pane_header.dart`；token 相关四个 ← header / messages / composer；导航轨同源短标签 `agentConversationNavigationTokenLabel` 也走同一 `agentTurnTokenUsage` key。
3. 若 WP-2 已合入：这些函数在转换后的 `agent_pane_styles.dart`（或二分出的 `agent_pane_text.dart`），改一处即可；否则改 part 时代的 `agent_pane_styles.dart`。
4. 跑 `dart run tool/check_localized_ui_strings.dart --check` 确认无新增违规。

**验收**：5 函数无英文字面量；两份 ARB key 对齐；中文界面下头栏/token tooltip 显示中文。

## T2 · alpha 魔法数 token 化（0.5 人天）

- [x] 命名常量落地：`0.68` / `0.12` / `0.65` / `0.98×2`。`0.88` 的 item 文本样式已随 WP-2/WP-4 删除，不再补常量。`0.65` 随 WP-4 T4 迁到 `agent_timeline_group_card.dart`。

**现状与范围圈定**（2026-09-04 对照仓库回写）：裸 alpha 比初版清单多——本任务**只圈** styles / text / 从 cards 抽出的折叠组：`0.68`（`agentSummaryTextStyle`）、`0.12`（`agentHoverBackground`）、`0.65`（`agent_timeline_group_card.dart`，WP-4 T4 从 cards 迁出）、`0.98` ×2（`fileEditGroupSummarySpan`，WP-2 迁到 `agent_pane_text.dart`）。`0.88` 的 item 文本样式已不存在，不再补常量。**明确不圈**（避免任务边界模糊，列为后续候选）：model_config 的 `0.1`（WP-4 T1 已处理）、navigation_rail 的 `0.94/0.85/0.8/0.14`、file_change_evidence_views 的 `0.08/0.12`、cards.dart 现役 `0.12`、header 的 `0.65`。

**设计**：不做「alpha 常量表」过度设计——在 styles 文件顶部命名，语义化：

```dart
/// 折叠摘要文字的不透明度：弱于正文但可辨认。
const double kAgentSummaryTextAlpha = 0.68;
/// 列表项文字的不透明度。
const double kAgentItemTextAlpha = 0.88;
/// hover 背景的不透明度（border 色稀释）。
const double kAgentHoverBackgroundAlpha = 0.12;
/// 卡片内次要图标的不透明度。
const double kAgentSecondaryIconAlpha = 0.65;
/// diff 增删统计文字的不透明度。
const double kAgentDiffStatTextAlpha = 0.98;
```

**步骤**：逐处替换为常量引用；**数值不变**（纯命名，零视觉变化）；`grep -n "withValues(alpha: 0\." lib/src/features/agent/presentation` 复核无遗漏（WP-4 T1 管辖的 0.1 除外）。

**验收**：替换点全部走常量；`tool/test_affected.sh` 绿（纯重构）。

## T3 · 切除 presentation → providers import（0.5 人天，**WP-1 的解锁条件，优先做**）

- [x] scheduler 的 `AgentMetricLabels.forProviderId` 改为构造注入；ViewModel 透传；组合层绑定保持 `AgentMetricLabels.forProviderId`。

**现状**（`agent_ui_update_scheduler.dart:3` + `:119`）：

```dart
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
// ...
_metricTags = metrics.isEnabled && providerId != null
    ? ZetaMetricTags(providerId: AgentMetricLabels.forProviderId(providerId))
    : ZetaMetricTags.none;
```

**设计**：标签函数改构造注入（与 ViewModel 已有的 `providerMetricLabel = ZetaMetricLabel.hashed` 参数同模式）：

```dart
// 改后
AgentUiUpdateScheduler(
  this._onPublish, {
  AgentFrameScheduler? frameScheduler,
  ZetaMetricsPort metrics = noopZetaMetricsPort,
  String? providerId,
  ZetaMetricLabel Function(String providerId) providerMetricLabel = ZetaMetricLabel.hashed,
}) : ...
     _metricTags = metrics.isEnabled && providerId != null
         ? ZetaMetricTags(providerId: providerMetricLabel(providerId))
         : ZetaMetricTags.none;
```

**接线**：唯一构造点在 ViewModel（`agent_conversation_view_model.dart:117-122`）——ViewModel 构造已有 `providerMetricLabel` 参数，直接透传；`AgentMetricLabels.forProviderId` 的绑定上移到 app 组合层（`agent_conversation_workspace_store.dart` 创建 ViewModel 处）。

**验收**：`grep -rn "zeta_agent_providers" lib/src/features/agent/presentation` 零命中；`feature_layering_guard_test` 绿；指标标签行为不变（scheduler 诊断测试绿）。

## T4 · `sf.` 控件基线对齐（0.5 人天）

- [x] 基线 9 处 `sf.IconButton.ghost`（WP-4 T5 已 −1）+ 设置页 2 处 `sf.Select`；9 处调用点均注明 IdeIconButton 缺 iconDense。

**背景**：G8 基线 = 10 处内嵌 `sf.IconButton.ghost` + 设置页 2 处 `sf.Select`；规则是「只减不增」。

**步骤**：

1. 跑基线命令记录当前值：

```powershell
grep -rnE "sf\.(IconButton|TextField|Button)\." lib/src/features | Measure-Object -Line
```

2. 超出基线的逐个处理：能换 `IdeButton`/`IdeSelect` 的换；换不了的（如 WP-4 T5 的圆形按钮）在调用点写注释说明「为什么 Ide 封装不满足 + 内边距如何对齐 `IdeMetrics`」，等 WP-4 原语落地后回收。
3. WP-4 T5（`IdeSubmitButton`）合入后回来把 composer 的 `sf.IconButton.ghost` 删掉（基线 −1）。

**验收**：基线数值不增；每个保留点有注释或对应 WP-4 任务引用。

## T5 · Plan 预览正则剥壳评估（0.5 人天）

- [x] 保留正则；补契约注释；单测覆盖 `## 标题` 与空输入兜底。

**现状**（`agent_pane_styles.dart:75-88`）：`_planPreviewText` 用三条正则剥 markdown 标记（`#` 头 / 列表符号 / 反引号），取首个非空行做导航目录预览。

**评估结论先行**：**保留正则，不引入解析器**。理由：输入是单行标题级文本，正则失败的最坏结果是预览带 `#` 字符——无害；引入 `zeta_markdown` 的 plain text serializer（`MarkdownPlainTextSerializer`，`markdown_controller.dart:38` 的 `plainText` getter 用它）意味着为导航目录的一次性字符串解析跑完整 parser，成本不对等。

**动作**（仅健壮性）：三条正则合并为一个循环内的顺序替换（现状已是），补一条注释说明「输入为单行、失败无害」的契约；加 2 条单测（`## 标题` → `标题`；空输入 → `'Plan'` 兜底）。

**验收**：单测绿；无行为变化。

---

## 完成定义（DoD）

- [x] 5 个任务落地（T3 此前已合入；T1/T2/T4/T5 同分支收口）。`dart format . && flutter analyze && tool/test_affected.sh` 绿。
- [x] T1/T9（WP-6）后 `check_localized_ui_strings --check` 无违规。
- [x] T1 中文文案补全写入 CHANGELOG `[未发布]` 修复一条。
