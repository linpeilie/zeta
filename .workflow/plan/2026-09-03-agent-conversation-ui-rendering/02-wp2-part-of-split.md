# WP-2 · part-of 单体 library 拆分

| 项 | 值 |
|----|----|
| 状态 | 进行中（T1–T5 已完成） |
| 规模 | 2–3 人天，1–2 个 PR |
| 依赖 | 无；**是 WP-3 / WP-4 的地基** |
| 门禁焦点 | G6 |
| 性质 | **纯重构**（零行为变化）：收尾 `bash tool/test_full.sh`；测试断言零修改是唯一正确性证据 |

---

## 0. 背景与机制说明

`agent_pane.dart:43-57` 把 `widgets/` 下 15 个文件声明为 `part of`。**part 的语义**：15 个文件共享同一 library 命名空间，所有 `_` 私有符号跨文件互相可见。后果：

- 改任何一个 `_` 符号，编译器无法告诉你爆炸半径（全 library 都能访问）；
- IDE「查找引用」、codegraph 调用图、review diff 的精度全部被拉低到 1.3 万行粒度；
- 文件看似拆分了，封装实际不存在。

**拆分原理**：把 part 文件变成独立 library = 每个文件自带 `import`，跨文件共享的符号必须**去下划线公开**。所以拆分的核心工作量是 T1 的符号盘点——确定哪些符号真的被跨文件用。

**参照样板**：`agent_file_change_evidence_card.dart` / `agent_provider_icon.dart` 已是独立 library（`agent_pane.dart:40-41` 正常 import），照它们的写法来。

## 1. 目标与非目标

- **目标**：15 个 part 文件全部独立；`agent_pane.dart` 收缩为 <400 行的壳；共享符号集中归属；零行为变化。
- **非目标**：不做视觉/逻辑调整（WP-4）、不做分发插件化（WP-3）、不动 ViewModel（WP-1）、不做 l10n 收编（WP-7）。**本 WP 只搬不改**——任何「顺手优化」都会污染 diff，让「零行为变化」无法自证。

## 2. 任务拆分

### T1 · 共享符号盘点（0.5 人天） · 已完成（2026-09-03）

**目的**：产出每个 `_` 符号的去向表，这是整个 WP 的施工图纸。

盘点范围：`agent_pane.dart` 的 15 个 `part` + 壳本身。方法：列出顶层定义（含 `sealed` / `final class`、`@immutable` 修饰的声明），再在 part/壳 library 内做词边界引用检索。测试文件对 `_` 符号的命中若只是架构守卫的源码字符串匹配（如 `_appendRawSection`），不计入跨文件共享。

**规模**：

| 项 | 数量 |
|---|---|
| part 文件 | 15（另 2 个已是独立 library：`agent_file_change_evidence_card.dart` / `agent_provider_icon.dart`） |
| 顶层 `_` 符号 | 217 |
| 跨文件 → 去下划线 | 75（表 A 全部 + 表 B 的 RawMarkdown + 表 C 除 Layout/Builder 外） |
| 仅定义文件 → 保持私有 | 142（表 D，按文件罗列） |
| 已经公开、拆分后只改 import | 3：`AgentPane`、`AgentModeSelector`、`AgentModeSelectorStatus` |
| 同文件引用但必须连带公开 | 3：`ComposerSelectorPopoverLayout` / `ComposerSelectorPopoverBuilder`（Controller 公开 API）；`AgentMarkdownBody`（T3 与 Raw 同文件抽出） |

**相对原文预判的修正**（以仓库代码为准，无「待定」）：

1. `_AgentMarkdownBody` **没有**被 sections / cards 引用，只在 `agent_pane_messages.dart` 内部使用。cards 用的是 `_AgentRawMarkdownBody`（`:533`）。T3 仍把两者抽到同一文件：它们共享 `_suppressMarkdownContextMenu`，且 WP-6 T9/T10 只改这一处。
2. `agent_pane_styles.dart` 实际 27 个顶层符号，原文清单漏了 code/highlight/history icon/duration/token 文案等 14 个。
3. `AgentModeSelector` / `AgentModeSelectorStatus` 已经公开；`agent_mode_selector_test.dart` 经 `agent_pane.dart` 引用它们，T5 改 import 即可。
4. 壳持有三个 picker 的 `ListController` 以及 `_SlashMenuItem` 族（`agent_pane.dart` 键盘激活走 `switch`），T5 必须公开。
5. **cards 不是叶节点**：依赖 composer 的 `_textAreaHeight` / `_PermissionOptionButton`，以及 model_config 的 `_AgentModelConfig`。原文 T4 先转 cards 会与仍留在壳 library 的 composer 形成 import 环。
6. `agent_timeline_extent_descriptor.dart:410` 对 `_operationGroupOuterPadding` 只是注释对齐，不是调用。
7. WP-1 已删除 `agent_conversation_view_model.dart`，且 AgentPane 已去掉 `dart:io`。T4 示例 import 与 T6 壳职责按现状改。

**T1 决议**：

- T2 **做二分**：视觉函数留 `agent_pane_styles.dart`，文案/摘要函数迁 `agent_pane_text.dart`（WP-7 T1/T2 只动文案文件）。两个文件均为独立 library，符号全部去下划线（本文件 27 个顶层符号全部跨文件，没有可保持私有的）。
- T3 抽出 `_AgentMarkdownBody` + `_AgentRawMarkdownBody`；`_suppressMarkdownContextMenu` / `_AgentMarkdownBodyState` 随迁并保持私有。
- **总转换顺序**（叶序；独立 library 不能 import 仍含自己调用方的壳，否则成环）：

```
T2  styles + text
T3  agent_markdown_body.dart          ← 只依赖 styles
T5  composer_selector_popover         ← 真叶
    agent_model_config                ← 真叶（Trigger/Panel 定义在本文件）
    agent_mode_selector               ← popover + model_config Trigger
    skill / slash / mention picker    ← model_config Panel；Controller 给壳用
    agent_pane_composer               ← model_config + popover + styles + ModeSelector
T4  agent_pane_header                 ← 只依赖 text（可与 T5 并行）
    agent_pane_navigation_rail        ← 真叶（可与 T5 并行）
    agent_pane_cards                  ← styles/text + composer + markdown + model_config
    agent_pane_messages               ← styles/text + cards + markdown
    agent_pane_context_panel          ← styles + cards
    agent_pane_sections               ← cards + messages + composer + navigation_rail + styles
    agent_pane_plan_panel             ← sections（_AgentContentAlign）
T6  壳 import 收口
```

T4 / T5 仍按「L2–L3 文件 / L4 文件」分任务记账，但 **T5 必须在 T4 的 cards/messages/sections 之前做完**。header 与 navigation_rail 可提前。PR 切分改为：T2+T3 一 PR，T5→T4→T6 一 PR（或整 WP 一 PR）；不再按原文「先 L2–L3 后 L4」。

---

#### 表 A · T2 原地转换（`agent_pane_styles.dart` / `agent_pane_text.dart`）

去下划线后的公开名 = 去掉前缀 `_`。WP-7 再改文案字面量，本次原样保留逻辑。

**视觉 → `agent_pane_styles.dart`（T2）**

| 符号 | 定义 | 引用处 | 公开名 |
|---|---|---|---|
| `_agentSummaryTextStyle` | styles:3 | cards×2 | `agentSummaryTextStyle` |
| `_agentItemTextStyle` | styles:13 | cards×2 | `agentItemTextStyle` |
| `_agentMetaTextStyle` | styles:25 | context_panel×1 | `agentMetaTextStyle` |
| `_agentHoverBackground` | styles:33 | cards×3，context_panel×1 | `agentHoverBackground` |
| `_operationGroupOuterPadding` | styles:44 | sections×1 | `operationGroupOuterPadding` |
| `_toolIcon` | styles:143 | cards×1 | `toolIcon` |
| `_historyEventIcon` | styles:157 | cards×1 | `historyEventIcon` |
| `_historyEventAccent` | styles:166 | cards×1 | `historyEventAccent` |
| `_historyEventTone` | styles:175 | cards×1 | `historyEventTone` |
| `_agentMarkdownTheme` | styles:184 | messages×2（T3 后改 markdown 文件） | `agentMarkdownTheme` |
| `_agentUserBubbleMarkdownTheme` | styles:244 | messages×1（T3 后改 markdown 文件） | `agentUserBubbleMarkdownTheme` |
| `_agentCodeTextStyle` | styles:273 | cards×5 | `agentCodeTextStyle` |
| `_agentCodeBlockDecoration` | styles:286 | cards×1 | `agentCodeBlockDecoration` |
| `_agentHighlightTheme` | styles:294 | cards×1 | `agentHighlightTheme` |
| `_contextWindowTokenUsageProgressValue` | styles:393 | composer×1 | `contextWindowTokenUsageProgressValue` |

**文案 / 摘要 → `agent_pane_text.dart`（T2 二分）**

| 符号 | 定义 | 引用处 | 公开名 |
|---|---|---|---|
| `_commandGroupSummary` | styles:54 | cards×1 | `commandGroupSummary` |
| `_planPreviewText` | styles:75 | messages×1 | `planPreviewText` |
| `_fileEditGroupSummarySpan` | styles:90 | cards×1 | `fileEditGroupSummarySpan` |
| `_toolKindLabel` | styles:138 | cards×1（styles 内部也被 summary 调用） | `toolKindLabel` |
| `_formatDuration` | styles:316 | messages×1（text 内部也被 elapsed/live 调用） | `formatDuration` |
| `_liveActivityStatusText` | styles:322 | messages×1 | `liveActivityStatusText` |
| `_toolElapsedLabel` | styles:354 | cards×1 | `toolElapsedLabel` |
| `_threadOpenStatusText` | styles:365 | header×1 | `threadOpenStatusText` |
| `_turnTokenUsageLabel` | styles:376 | messages×1 | `turnTokenUsageLabel` |
| `_threadTotalTokenUsageLabel` | styles:385 | header×1 | `threadTotalTokenUsageLabel` |
| `_contextWindowTokenUsageTooltip` | styles:403 | composer×1 | `contextWindowTokenUsageTooltip` |
| `_tokenUsageTooltip` | styles:419 | header×1，messages×1 | `tokenUsageTooltip` |

---

#### 表 B · T3 独立文件公开（`widgets/agent_markdown_body.dart`）

| 符号 | 定义 | 引用处 | 去向 |
|---|---|---|---|
| `_AgentMarkdownBody` | messages:603 | 仅 messages 内部（`:50/507/594/762/842`） | 新文件公开为 `AgentMarkdownBody` |
| `_AgentRawMarkdownBody` | messages:706 | cards×1（`:533`）+ messages 自身 | 新文件公开为 `AgentRawMarkdownBody` |
| `_AgentMarkdownBodyState` | messages:622 | 仅 messages | 随迁，保持私有 |
| `_suppressMarkdownContextMenu` | messages:730 | 仅 messages（两个 markdown widget 共用） | 随迁，保持私有 |

引用点在 T3 之后只有 messages 与 cards（**不是** sections）。右键菜单抑制与 MouseRegion 光标补丁原样保留。

---

#### 表 C · 跨文件 widget / 控制器 / 常量（T4 / T5 去下划线，留在定义文件）

**cards → 公开（被 sections / messages / context_panel 引用）**

| 符号 | 定义 | 引用处 | 公开名 |
|---|---|---|---|
| `_AgentCommandGroupCard` | cards:10 | sections×1 | `AgentCommandGroupCard` |
| `_AgentFileEditGroupCard` | cards:95 | sections×1 | `AgentFileEditGroupCard` |
| `_AgentHighlightedCodeBlock` | cards:198 | context_panel×1 | `AgentHighlightedCodeBlock` |
| `_AgentToolCallCard` | cards:328 | sections×1 | `AgentToolCallCard` |
| `_AgentPlanDocumentCard` | cards:450 | messages×1，sections×1 | `AgentPlanDocumentCard` |
| `_AgentPermissionCard` | cards:853 | sections×1 | `AgentPermissionCard` |
| `_AgentQuestionCard` | cards:1114 | sections×1 | `AgentQuestionCard` |
| `_AgentHistoryEventCard` | cards:2021 | sections×1 | `AgentHistoryEventCard` |

**composer → 公开**

| 符号 | 定义 | 引用处 | 公开名 |
|---|---|---|---|
| `_AgentComposer` | composer:9 | sections×1 | `AgentComposer` |
| `_textAreaHeight` | composer:496 | cards×1（提问卡 textarea） | `textAreaHeight` |
| `_PermissionOptionButton` | composer:1287 | cards×1（计划文档卡内嵌权限） | `PermissionOptionButton` |

**messages → 公开**

| 符号 | 定义 | 引用处 | 公开名 |
|---|---|---|---|
| `_AgentMessageEntry` | messages:4 | sections×1 | `AgentMessageEntry` |
| `_AgentLiveActivityStatus` | messages:104 | sections×1 | `AgentLiveActivityStatus` |
| `_AgentTurnFooter` | messages:193 | sections×1 | `AgentTurnFooter` |

**sections → 公开（壳 + plan_panel）**

| 符号 | 定义 | 引用处 | 公开名 |
|---|---|---|---|
| `_AgentConversationLayout` | sections:11 | 壳×1 | `AgentConversationLayout` |
| `_AgentThreadHistoryLoading` | sections:201 | 壳×1 | `AgentThreadHistoryLoading` |
| `_AgentConversationTimeline` | sections:294 | 壳×1 | `AgentConversationTimeline` |
| `_AgentPendingInteractionSection` | sections:881 | 壳×1 | `AgentPendingInteractionSection` |
| `_AgentComposerSection` | sections:1000 | 壳×1 | `AgentComposerSection` |
| `_AgentContentAlign` | sections:1128 | 壳×2，plan_panel×1 | `AgentContentAlign` |

**header / plan_panel / navigation_rail / context_panel → 公开（壳引用）**

| 符号 | 定义 | 引用处 | 公开名 |
|---|---|---|---|
| `_AgentHeader` | header:4 | 壳×1 | `AgentHeader` |
| `_AgentActivePlanSection` | plan_panel:7 | 壳×1 | `AgentActivePlanSection` |
| `_AgentConversationNavigationRail` | navigation_rail:26 | sections×1 | `AgentConversationNavigationRail` |
| `_AgentContextPanel` | context_panel:20 | 壳×1 | `AgentContextPanel` |

**L4 composer 族 → 公开**

| 符号 | 定义 | 引用处 | 公开名 |
|---|---|---|---|
| `_ComposerSelectorPopoverLayout` | popover:5 | 同文件；但是 `Controller` 公开 API 的回调参数 | `ComposerSelectorPopoverLayout` |
| `_ComposerSelectorPopoverBuilder` | popover:22 | 同文件；同上，避免 `library_private_types_in_public_api` | `ComposerSelectorPopoverBuilder` |
| `_ComposerSelectorPopoverController` | popover:95 | 壳×6，composer×4，mode_selector×2 | `ComposerSelectorPopoverController` |
| `_ComposerSelectPopup` | popover:195 | composer×2，mode_selector×1 | `ComposerSelectPopup` |
| `_composerSelectorPopoverPreferredWidth` | model_config:3 | composer×1 | `composerSelectorPopoverPreferredWidth` |
| `_composerSelectorPopoverMaxHeight` | model_config:4 | composer×1 | `composerSelectorPopoverMaxHeight` |
| `_AgentModelConfig` | model_config:49 | composer×1，cards×1 | `AgentModelConfig` |
| `_ComposerSelectorTrigger` | model_config:496 | composer×2，mode_selector×1 | `ComposerSelectorTrigger` |
| `_ComposerSelectorPanel` | model_config:549 | skill/slash/mention picker 各×1 | `ComposerSelectorPanel` |
| `_agentSkillPickerPreferredWidth` | skill_picker:3 | 壳×1 | `agentSkillPickerPreferredWidth` |
| `_agentSkillPickerPreferredMaxHeight` | skill_picker:4 | 壳×1 | `agentSkillPickerPreferredMaxHeight` |
| `_SkillPickerListController` | skill_picker:7 | 壳（字段/键盘/dispose） | `SkillPickerListController` |
| `_AgentSkillPickerPopover` | skill_picker:56 | 壳×1 | `AgentSkillPickerPopover` |
| `_agentSlashCommandPickerPreferredWidth` | slash:3 | 壳×1 | `agentSlashCommandPickerPreferredWidth` |
| `_agentSlashCommandPickerPreferredMaxHeight` | slash:4 | 壳×1 | `agentSlashCommandPickerPreferredMaxHeight` |
| `_SlashCommandId` | slash:7 | 壳×3 | `SlashCommandId` |
| `_SlashMenuItem` | slash:11 | 壳 `_activateSlashMenuItem` | `SlashMenuItem` |
| `_SlashCommandMenuItem` | slash:20 | 壳 `switch` | `SlashCommandMenuItem` |
| `_SlashSkillMenuItem` | slash:38 | 壳 `switch` | `SlashSkillMenuItem` |
| `_SlashMenuListController` | slash:51 | 壳（字段/键盘/dispose） | `SlashMenuListController` |
| `_AgentSlashCommandPickerPopover` | slash:139 | 壳×1 | `AgentSlashCommandPickerPopover` |
| `_agentMentionFilePickerPreferredWidth` | mention:3 | 壳×1 | `agentMentionFilePickerPreferredWidth` |
| `_agentMentionFilePickerPreferredMaxHeight` | mention:4 | 壳×1 | `agentMentionFilePickerPreferredMaxHeight` |
| `_MentionFileListController` | mention:7 | 壳（字段/键盘/dispose） | `MentionFileListController` |
| `_AgentMentionFilePickerPopover` | mention:56 | 壳×1 | `AgentMentionFilePickerPopover` |

层味记录（本 WP 不搬）：通用 composer chrome（`ComposerSelectorTrigger` / `ComposerSelectorPanel` / 弹层宽高常量）定义在 `agent_model_config.dart`。WP-4 控件收敛时可再挪，本次留原文件。

---

#### 表 D · 保持私有（仅定义文件使用）

按文件。`State` 伴生类一律保持私有，不逐行展开。

| 文件 | 保持私有的顶层符号 |
|---|---|
| `agent_pane.dart`（壳） | `_AgentPaneWidthClass`、`_selectAgentPaneWidthClass`、`_AgentPaneState`、`_AgentReadOnlyNotice` |
| `agent_pane_cards.dart` | `_neverNotifies`；`_AgentCommandGroupItemRow` / `_commandGroupItemTitle`；`_AgentFileEditGroupCardState` / `_AgentFileEditItemRow`；`_AgentHighlightedCodeBlockState` / `_AgentHighlightThemeSignature`；`_toolCardTitle`；`_AgentPlanTodoList` / `_planTodoIcon`；`_AgentPermissionCardState` / `_permissionDisplayTitle` / `_permissionKindTitle` / `_permissionKindIcon` / `_AgentPermissionCommandBlock`；`_AgentQuestionCardState` / `_AgentQuestionToolbarButton` / `_AgentQuestionOptionRow` / `_AgentQuestionOtherField`；`_AgentUserInputQaList` / `_AgentUserInputQaRow` |
| `agent_pane_composer.dart` | `_AgentComposerPlanBadge(+State)`、`_ComposerMoreActionsButton(+State)`、`_ComposerRunningGlowBorder(+State)`、`_ComposerRunningGlowPainter`、`_ComposerContextWindowUsage`、`_ComposerImageDraftStrip`、`_SelectorSelect(+State)`、`_SessionConfigOptionControl`、`_sessionConfigIcon`、`_PermissionOptionButtonState`、`_PermissionOptionPopover`、`_ComposerActionButton`、`_permissionOptionCaption` |
| `agent_pane_context_panel.dart` | `_agentContextPanelWidth`、`_agentContextKeyColumnWidth`、Header/Summary/Raw 系列 widget、`_ContextSummaryRow`、`_ContextRawItem`、以及 `_copyContextRaw` / `_buildContextRawItems` / `_isMainConversationMessage` / `_contextMessageKindLabel` / `_contextToolKindLabel` / `_contextHistoryEventLabel` / `_toolCallContextText` / `_appendRawSection` / `_toolCallContextMap` / `_fileChangeSnapshotContextMap` / `_fileChangeContextMap` / `_formatContextDateTime` / `_formatContextTimestamp` / `_prettyJson`（架构守卫只 grep 源码字符串，不调用） |
| `agent_pane_header.dart` | `_AgentHeaderMoreButton(+State)` |
| `agent_pane_messages.dart` | `_AgentBubbleMessage`、`_AgentMarkdownMessage`、`_AgentFinalAnswerCard`、`_AgentPlanMessageCard`、`_nonEmptyTrimmed`、`_turnFooterMetaItems`、`_turnDurationLabel`（markdown 四件套见过表 B，不在本文件停留） |
| `agent_pane_plan_panel.dart` | `_activePlanPanelMaxWidth`、`_activePlanScrollMaxHeight`、`_FloatingPanelExtentReporter`、`_RenderFloatingPanelExtentReporter`、`_AgentActivePlanCard(+State)`、`_AgentActivePlanStepRow`、`_AgentPlanOverflowText`、`_AgentActivePlanStatusMarker`、`_activePlanCurrentIndex`、`_activePlanStatusLabel` |
| `composer_selector_popover.dart` | `_showComposerSelectorPopover`（仅 Controller 调用） |
| `agent_model_config.dart` | `_composerSelectorRowHeight`、`_AgentModelConfigPopoverState`、`_AgentModelConfigState`、`_ModelConfigTrigger`、`_ModelConfigPopover(+State)`、`_NextTurnModelConfigBanner`、`_ModelSelectionNoticeBanner`、`_ModelListItem`、`_AnimatedModelExpansion`、`_ModelExpansionInteractionGate(+State)`、`_ModelInlineConfig`、`_FastConfigRow`、`_ModelConfigInlineAlert`、`_ReasoningEffortSlider(+State)`、`_ReasoningMaxEffectPainter` |
| `agent_mode_selector.dart` | 三个 popover 尺寸常量、`_AgentModeSelectorState`、`_AgentModeSelectorPopover`、`_AgentModeSelectorDisplay`、`_agentModeSelectorDisplay`、`_agentModePresetFor`、`_agentModePresetLabel`、`_agentModeFallbackLabel` |
| `agent_skill_picker.dart` | `_AgentSkillPickerPopoverState` |
| `agent_slash_command_picker.dart` | `_buildSlashMenuItems`、`_AgentSlashCommandPickerPopoverState`、`_SlashMenuSectionHeader`、`_SlashMenuOptionRow` |
| `agent_mention_file_picker.dart` | `_AgentMentionFilePickerPopoverState` |
| `agent_pane_sections.dart` | `_AgentConversationSlot`、`_AgentConversationLayoutState`、`_AgentConversationLayoutDelegate`、`_isOperationGroupViewportItem`、`_AgentTimelineBlockSection`、`_modeSelectorStatus` |
| `agent_pane_navigation_rail.dart` | `_kNavTickWidthLong/Short/Emphasized`、`_kNavPreviewCardMaxWidth`、`_AgentConversationNavigationRailState`、`_AgentConversationNavigationTick`、`_AgentConversationNavigationPreviewCard`、`_NavStatusBadge`、`_NavMetaChip`、`_formatNavTime` |

**测试侧影响（T5 改 import，不断言）**：`test/src/features/agent/presentation/agent_mode_selector_test.dart` 当前 `import agent_pane.dart` 以拿到已公开的 `AgentModeSelector`；拆分后改为 import `widgets/agent_mode_selector.dart`。

**验收**：上表覆盖 15 个 part + 壳；每个顶层 `_` 符号有去向；无「待定」。T2–T6 按本表施工，不再重新设计。

### T2 · `agent_pane_styles.dart` 原地转为独立 library（0.5 人天） · 已完成（2026-09-03）

**做法**（2026-09-03 review 修正：不新建「kit」文件——原地转换保留 git blame/history，不发明新概念）：

1. 删掉第 1 行 `part of '../agent_pane.dart';`，补齐 import（`flutter/material.dart`、`zeta_ui`、`zeta_agent_core`、`app_localizations_x.dart`、`mixin_markdown_widget`（WP-6 后换 `zeta_markdown`，见 06 文档 §0.3）等，analyze 驱动补全）。
2. 全部顶层符号去 `_` 前缀（T1 表 A；本文件没有可保持私有的顶层符号）。
3. **二分（T1 已决议，必做）**：表 A 的 12 个文案/摘要函数移到同目录 `agent_pane_text.dart`；15 个视觉函数留在 `agent_pane_styles.dart`。两个文件各自独立转换。WP-7 T1/T2 只动文案文件。

**注意**：

- 这些函数大量引用 `context.l10n`、`IdeColors.of(context)`——import 照抄。
- 转换后该文件 import markdown 包；WP-6 T2 换包时只改这一处。

**施工记录**：壳改为 import 两个独立 library，剩余 part 继续共享壳命名空间，只把调用从 `_foo` 改成 `foo`。header 局部变量 `threadOpenStatusText` 与公开函数同名，改为 `openStatusText`（零行为，仅为解除遮蔽）。`flutter analyze` 零 issue；`tool/test_affected.sh` 57 个根测试全绿。

**验收**：`agent_pane_styles.dart` 与 `agent_pane_text.dart` 均为独立 library，analyze 无 unresolved；符号与 T1 表 A 一一对应。

### T3 · markdown 组件独立（0.5 人天，与 WP-6 协同） · 已完成（2026-09-03）

**做法**：新文件 `widgets/agent_markdown_body.dart`：

```dart
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart'; // WP-6 后换 zeta_markdown
import 'package:zeta_ui/zeta_ui.dart';
import '../agent_markdown_cache.dart';
import 'agent_pane_styles.dart';

/// 会话正文 Markdown：经 [AgentMarkdownCache] 复用控制器，支持流式增量。
class AgentMarkdownBody extends StatefulWidget {
  const AgentMarkdownBody({
    required this.messageId,
    required this.data,
    required this.cache,
    this.useStreaming = false,
    this.themeBuilder = agentMarkdownTheme, // 来自 styles（原 _agentMarkdownTheme）
    super.key,
  });
  // ... 字段与现状 _AgentMarkdownBody（agent_pane_messages.dart:603-703）一一平移
}

/// 轻量一次性 Markdown（Plan 文档等无缓存场景）。
class AgentRawMarkdownBody extends StatelessWidget { /* 平移 :706-727 */ }
```

- 右键菜单抑制（`:698,729-737`）与 MouseRegion 光标补丁（`:686-689`）**原样保留**（WP-6 T9/T10 才删）。
- 引用点只有 messages 与 cards（T1 修正：sections 不引用 markdown body），改为 import 本文件。

**施工记录**：按现状 API 平移（`message` / `useStreamingMarkdown` / `markdownCache` / `themeBuilder`），不改成骨架里的 `messageId`/`data`/`cache`。公开 widget 补 `super.key`（lint `use_key_in_widget_constructors`）；右键菜单抑制与 MouseRegion 光标补丁原样保留。壳去掉已无用的 `mixin_markdown_widget` import。`_AgentMarkdownBodyState` / `_suppressMarkdownContextMenu` 留在新文件并保持私有，因此字面 grep `_AgentMarkdownBody` 仍会命中 State 类名。`flutter analyze` 零 issue；`tool/test_affected.sh` 53 个根测试全绿。

**验收**：`grep -rn "_AgentRawMarkdownBody\|_AgentMarkdownBody[^S]" lib` 零命中；widget 测试绿。

### T4 · 转换 L2–L3 文件（1 人天） · 已完成（2026-09-03）

**每个文件的固定动作序列**（以 `agent_pane_cards.dart` 为完整示例）：

```dart
// 改前（第 1 行）
part of '../agent_pane.dart';

// 改后（按实际使用符号补齐；以下为 cards 的典型集合）
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_region_builder.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_styles.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_text.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
```

然后：

1. 该文件定义、被外部引用的符号去下划线（T1 表 C 已列明，如 `_AgentCommandGroupCard` → `AgentCommandGroupCard`）。
2. `dart format . && flutter analyze`——analyze 会报「未定义」的漏 import 和「未使用」的多余 import，**靠 analyze 驱动补全**，不要手工猜。
3. 文件内 `_neverNotifies`（cards.dart:5）这类文件级私有 helper 保持私有不动。

**转换顺序**（T1 叶序；**不可**先转 cards）：`header` 与 `navigation_rail` 可与 T5 并行 →（T5 完成后）`cards` → `messages` → `context_panel` → `sections` → `plan_panel`。

**验收**：7 个文件全部无 `part of`；analyze 零新增告警；`test_affected.sh` 绿。

**施工记录**：按 T1 叶序转换 header / navigation_rail / cards / messages / context_panel / sections / plan_panel。表 C 符号去下划线；State 与文件内 helper 保持私有。公开 widget 补 `super.key`。`AgentBuildTarget` 的 runtimeType 字符串同步为公开类名。壳去掉已无用 import（highlight / shadcn / grouping 等）。`lib/src/features/agent/presentation` 已无 `part` / `part of`。`flutter analyze` 零 issue；`tool/test_affected.sh` 53 个根测试全绿。

### T5 · 转换 L4 文件（0.5–1 人天） · 已完成（2026-09-03）

同 T4 动作序列。T1 叶序：**必须在 T4 的 cards/messages/sections 之前完成**。

顺序：`composer_selector_popover` → `agent_model_config` → `agent_mode_selector` → 三个 picker（skill / slash_command / mention_file）→ `composer`。

`ComposerSelectorPopoverLayout` / `ComposerSelectorPopoverBuilder` 虽仅在 popover 文件内被提到，但它们是即将公开的 `ComposerSelectorPopoverController` 的公开 API 类型，必须一并去下划线（T1 表 C）。

**注意**：`agent_model_config.dart`（1921 行）本次**不再细分**——内部拆分留给 WP-4 控件收敛时顺手做，避免双重 diff。

**施工记录**：按 T1 叶序将 7 个 L4 文件转为独立 library；表 C 符号去下划线；State / `_showComposerSelectorPopover` / `_composerSelectorRowHeight` 保持私有。公开 widget 补 `super.key`。`agent_mode_selector_test.dart` 改 import `widgets/agent_mode_selector.dart`。壳去掉已无用的 `gestures` / `workspace_file_corpus_port` / `agent_model_config_ui_state` import。`flutter analyze` 零 issue；`tool/test_affected.sh` 53 个根测试全绿。剩余 7 个 part：cards / context_panel / header / messages / plan_panel / sections / navigation_rail（T4）。

### T6 · 壳收缩与全量门禁（0.5 人天）

1. `agent_pane.dart` 删 15 行 `part`，改为 import 各独立文件；确认壳只留：页面组合（`AgentPane` / `_AgentPaneState`）、`IdeConstraintBucketBuilder`、滚动协作、context panel 显隐接线、图片粘贴接线（WP-1 已把 IO 下沉到 data 端口，壳不再 `import dart:io`）。
2. 自检 diff 纯度：

```powershell
git diff --stat                       # 应只有 import/part/符号重命名
git diff -U0 | grep -E "^[+-]" | grep -vE "^[+-]{3}|import |part |^[-+]\s*$" | less
# 上一条过滤后若还有大量逻辑行变化，说明夹带了行为修改，必须剔出
```

3. `bash tool/test_full.sh` 全绿；登记 `00-index.md` §6「开发记录」。

## 3. 风险与回滚

| 风险 | 缓解 |
|------|------|
| 中间态编译报错期长 | 严格按 T1 叶序；analyze 驱动；单 PR 一次做完，或 T2+T3 一 PR、T5→T4→T6 一 PR（不可先 L2–L3 后 L4） |
| 公开符号被 feature 外 import | 不建 barrel；review 检查 import 方均在 `lib/src/features/agent/` 内 |
| 夹带行为修改 | T6 的 diff 纯度自检是硬门槛 |

## 4. 完成定义（DoD）

- [ ] `grep -rnE "^(part |part of )" lib/src/features/agent/presentation` 零命中（注意必须带 `-E`，BRE 下 `|` 是字面量）。
- [ ] `agent_pane.dart` < 400 行。
- [ ] `tool/test_full.sh` 绿且测试断言零修改；CHANGELOG 无条目。
