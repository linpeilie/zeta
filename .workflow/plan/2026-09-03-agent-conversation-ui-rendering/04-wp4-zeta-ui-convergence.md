# WP-4 · zeta_ui 控件收敛

| 项 | 值 |
|----|----|
| 状态 | 进行中 |
| 规模 | 4–5 人天，每任务独立 PR |
| 依赖 | WP-2 完成后启动（文件独立才好动）；与 WP-1/WP-3 解耦 |
| 门禁焦点 | G8（token、控件高度由内容撑开）、zeta_ui 约束（禁 Riverpod / dart:io / 业务模型，文案走 `ZetaUiTextCatalog`） |

---

## 0. 背景

四类重复控件（现状代码均已逐字核对，见各任务「现状」节）：

1. **横幅**：手写横幅确认只有 **2 处**——`_NextTurnModelConfigBanner`（`agent_model_config.dart:888-915`）与 `_ModelSelectionNoticeBanner`（`:917-962`），均为 `IdeStatusCard` 的 compact 变体。另有 2 处 info 提示行（`agent_model_config.dart:1037`、`agent_mode_selector.dart:285`）替换时评估是否同构。注意 `_AgentReadOnlyNotice`（`agent_pane.dart:1281-1306`）与 cards.dart:2037/2093 **已经在用 `IdeStatusCard`**，不在本任务范围（2026-09-03 review 修正：初版「另有 4 处近似实现 / 共 6 处」的清单有误）。
2. **弹层选择器**：施工前 `_SelectorSelect` 只剩 session config **1 处**调用（初版记录的 4 处已随 WP-2 后代码演进失效）；`ComposerSelectorTrigger/Panel` 则被模式、模型、权限与三个 picker 共用。`IdeSelect`（`packages/zeta_ui/lib/src/ide_select.dart:78-221`）不支持自定义触发器/弹层项。
3. **时间线行**：`_AgentCommandGroupItemRow`（cards.dart:62-77）、tool 卡行、diff 文件行同构（leading icon + 省略标题 + 尾部 meta）；其中命令组同时承载 tool 与历史 search/system 摘要项。独立 `AgentHistoryEventCard` 是含 description/content 的多行状态卡，不属于这一骨架。
4. **折叠卡**：`IdeCollapsibleCard` 调用点重复拼装 titleWidget/leading/bodyPadding/hoverBackground。

**zeta_ui 新原语的铁律**（每个 T 都适用）：不 import Riverpod / `dart:io` / generated l10n / 业务模型；控件自有文案经 `ZetaUiTextCatalog` 注入；高度由内容撑开，下限走 `IdeMetrics.controlMinHeightFor`；图标过 `IdeIconBox`。

## 1. 任务拆分

### T1 · `IdeStatusCard` compact 变体（0.5–1 人天） · 已完成（2026-09-03）

**现状**（`_NextTurnModelConfigBanner`，`agent_model_config.dart:893-913`）：

```dart
Container(
  height: 30,
  padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space10),
  color: colors.info.withValues(alpha: 0.1),
  child: Row(children: [
    Icon(Icons.info_outline_rounded, size: 14, color: colors.info),
    const SizedBox(width: IdeSpacing.space6),
    Text(context.l10n.agentConfigNextTurn, style: ...bodySmall.copyWith(color: colors.info, fontWeight: FontWeight.w600)),
  ]),
)
```

**设计**：`IdeStatusCard` 加密度参数（`packages/zeta_ui/lib/src/ide_status_card.dart`）：

```dart
enum IdeStatusCardDensity { regular, compact }

const IdeStatusCard({
  // ... 现有参数不动 ...
  this.density = IdeStatusCardDensity.regular,
});
```

compact 档规格（从现状 banner 反推，落成 token）：`minHeight: 30`（**用 minHeight 不用 height**，G8 容器规则）、padding `horizontal: space10, vertical: space6`、图标 14px、文字 `bodySmall` + tone 色、**`margin` 默认 `EdgeInsets.zero`**（现状 `IdeStatusCard` 默认 `bottom: space12`，横幅场景是内嵌条，不需要外间距——调用点现状就是零 margin 的 Container）。**alpha 0.1 背景作为 compact 档的内建规格落在 zeta_ui 内部**（`ide_status_card.dart` 内命名常量，如 `_kCompactBannerBackgroundAlpha = 0.1`），feature 侧不再出现该魔法数——终审修正：初版写「按 WP-7 T2 先落常量」，与 WP-7 T2 的「model_config 的 0.1 由 WP-4 T1 处理」构成循环引用，以本处为准。

**替换映射**：`_NextTurnModelConfigBanner` → `IdeStatusCard(tone: info, density: compact, leading: icon, title: ...)`；`_ModelSelectionNoticeBanner` → 同上加 `maxLines: 2` body；`agent_model_config.dart:1037` 与 `agent_mode_selector.dart:285` 两处提示行逐个评估（同构则替换，不同构在 PR 描述写明保留原因）。

**验收**：2 处手写横幅替换完成 + 2 处提示行有明确结论；`grep -n "withValues(alpha: 0.1)" agent_model_config.dart` 零命中；widget 测试绿（key 保留：`agent-model-next-turn-banner` 等 key 透传给 IdeStatusCard）。

**施工记录**：`IdeStatusCard` 新增 `IdeStatusCardDensity.compact` 与可配置的
`titleMaxLines`；compact 默认使用 30px 最小高度、`space10/space6` 内边距、零外边距、
tone 色 `bodySmall` 文案、14px `IdeIconBox` 及组件内 `_compactBannerBackgroundAlpha`。
`_NextTurnModelConfigBanner` / `_ModelSelectionNoticeBanner` 已改用该变体并保留原 key，
后者允许两行标题。另两处提示逐项核对后保留：模型项中的提示只是禁用状态尾部图标，
不是横幅；未知 conversation mode 提示是 Select 列表内带分隔线的 warning 说明行，
其表面、间距和 tone 均不同于顶部 info 横幅。新增 zeta_ui Widget 测试覆盖最小高度、
默认零外边距、tone 排版、图标盒和两行标题；现有模型配置测试覆盖两处业务 key 与文案。

### T2 · `IdePopupSelect` 原语（1.5–2 人天） · 已完成（2026-09-03）

**现状**：施工前 `_SelectorSelect<T>`（composer）= `IdeTab` 触发器 + `ComposerSelectorPopoverController` 弹层 + `ComposerSelectPopup` 内容，实际只剩 session config 一处调用；模型配置的 `ComposerSelectorTrigger/Panel` 是同一模式的另一实现。

**设计**（新文件 `packages/zeta_ui/lib/src/ide_popup_select.dart`）：

```dart
/// 触发器 + 弹层选择器：触发器形态由调用方定（tab / 工具栏钮），
/// 弹层项支持自定义行（模型项带 vendor 图标与 meta 文案）。
class IdePopupSelect<T extends Object> extends StatefulWidget {
  const IdePopupSelect({
    required this.value,
    required this.placeholder,
    required this.triggerBuilder,   // Widget Function(BuildContext, {required bool isOpen, required String label})
    required this.itemBuilder,      // Widget Function(BuildContext, T item, {required bool selected})
    required this.items,            // List<IdePopupSelectItem<T>> { value, label, enabled, key }
    required this.onChanged,
    this.popoverWidth = 280,
    this.popoverMaxHeight = 320,
    this.tooltip,
    super.key,
  });
}
```

**实现要点**（从 `_SelectorSelectState` 平移）：弹层控制器逻辑（`initState` 建 controller、值变化时 post-frame dismiss `:1143-1154`、dispose 顺序）原样进 zeta_ui；**弹层控制器本身若通用，一并下沉为 `IdePopoverController`**。

**替换映射**：`_SelectorSelect`（composer 现存 1 处实例）→ `IdePopupSelect` + `triggerBuilder: (ctx, s) => IdeTab(...)`；`ComposerSelectorTrigger/Panel` → `IdeButton.ghost(...)` + `IdePopoverPanel`，复合模型面板只下沉通用 controller，不损失展开配置语义；设置页复用 Widget 承载的 UI/code font 两处 `sf.Select` 搜索弹层 → 评估后替换（满足则 G8 基线 −2）。

**验收**：composer 与模型配置选择器行为/焦点/Esc 关闭不变（widget 测试覆盖）；zeta_ui 新文件零 Riverpod/l10n import（守卫测试断言）。

**施工记录**：新增 `IdePopupSelect<T>` / `IdePopupSelectItem<T>`，把值变更或
选项清空后的 post-frame dismiss、选中自动关闭、Esc/外点关闭与触发器回焦统一
收进组件；原 `_SelectorSelect` 已删除，session config 改用自定义 `IdeTab`
trigger。通用定位与 handle 生命周期下沉为 `IdePopoverController`，mode、permission、
skill/slash/mention picker 及模型复合面板均复用；旧
`composer_selector_popover.dart`、`ComposerSelectorTrigger/Panel` 与
`ComposerSelectPopup` 删除。模型/mode/permission 触发器改用 `IdeButton.ghost`
（展开态为 secondary），纯图标 more-actions 改用 `IdeIconButton`，控件内图标走
`IdeIconBox`，不再以 28px 固定高度兜底。模型面板仍保留展开配置、保存回滚等复合
语义，只复用通用弹层机制，不伪装成同步单值选择器。设置页实际是一个复用 Widget
承载 UI/code font 两行的异步可搜索 `sf.SelectPopup.builder`，包含 loading/empty/error
状态；`IdePopupSelect` 不提供这些语义，替换会降级交互，因此保留现状。新增 zeta_ui
Widget 测试覆盖选择、Esc、回焦与外部选项失效关闭；既有 mode/model/composer 测试
继续覆盖键盘导航、视口上翻、复杂模型配置与 Provider session config 回写。

### T3 · `IdeTimelineRow`（0.5–1 人天） · 已完成（2026-09-03）

**现状**（`_AgentCommandGroupItemRow`，cards.dart:67-76）：单行 Text + 省略号 + `_agentItemTextStyle`。tool 卡行、diff 文件行是同一骨架加 leading/trailing；历史 search/system 摘要也通过 `_AgentCommandGroupItemRow` 渲染。独立 `AgentHistoryEventCard` 是多行 `IdeStatusCard`，不在本任务范围。

**设计**：

```dart
/// 时间线信息行：leading 图标 + 省略标题 + 尾部 meta，高度由内容撑开。
class IdeTimelineRow extends StatelessWidget {
  const IdeTimelineRow({
    required this.title,          // String（内部套 maxLines:1 + ellipsis）
    this.leading,                 // Widget?（过 IdeIconBox）
    this.trailing,                // Widget?（meta 文案/耗时）
    this.onTap,
    this.semanticLabel,
    super.key,
  });
}
```

**替换**：`_AgentCommandGroupItemRow` → `IdeTimelineRow(title: _commandGroupItemTitle(item, l10n), leading: kindIcon)`；tool 卡行 / diff 行 / 历史事件行逐个对照（注意历史事件行的 tone 差异用 trailing 表达）。

**验收**：4 类行替换；行高无回归（widget 测试既有断言）；`ValueKey` 全部保留。

**施工记录**：新增 `IdeTimelineRow`，统一 leading `IdeIconBox`、单行省略标题、
尾部 meta、可选按钮语义与按内容自然增高；按真实调用并集补充 `prefix` 和
`titleStyle`，用于保留 diff 动作 caption 与等宽文件路径。命令组中的 live/history
tool 和历史 search/system 摘要、独立 tool 卡标题、diff 文件标题均已迁移；原
`agentItemTextStyle` 删除。独立 `AgentHistoryEventCard` 保持多行状态卡，因为它还
承载 description/content 与 tone，强行套入单行骨架会丢失语义。命令组、tool、diff
现有 header/body/item `ValueKey` 均保留。新增 zeta_ui Widget 测试覆盖图标盒、
prefix/title/trailing 排列、单行省略、交互语义和 2x 字号自然增高；既有命令组、
文件证据、extent 对齐与响应式回归测试继续通过。

### T4 · 折叠卡骨架参数化（1 人天）

**现状**：`_AgentCommandGroupCard`（cards.dart:17-58）= `AgentRegionBuilder<AgentExpansionState>` + `IdeCollapsibleCard(headerKey/bodyKey/expanded/onToggle/titleWidget/leading/bodyPadding/hoverBackgroundColor/semanticLabel)`；`_AgentFileEditGroupCard` 同构。

**设计**：feature 内收敛（不进 zeta_ui——它依赖 expansion state，是业务组合）：

```dart
// widgets/agent_timeline_group_card.dart（WP-2 后的独立文件）
class AgentTimelineGroupCard extends StatelessWidget {
  const AgentTimelineGroupCard({
    required this.groupId,
    required this.isExpanded,        // bool Function(String groupId) —— 由调用方从 expansion state 取
    required this.onToggle,
    required this.titleSpan,         // InlineSpan（命令组文案 / 文件组 diff 统计 span）
    required this.leadingIcon,
    required this.semanticLabel,
    required this.body,
    super.key,
  });
  // build 内统一拼装 IdeCollapsibleCard：bodyPadding / hoverBackground / key 规则只写一次
}
```

**替换**：`_AgentCommandGroupCard` / `_AgentFileEditGroupCard` 的 build 收敛为数据准备 + `AgentTimelineGroupCard`。

**验收**：两卡视觉/交互零变化；`IdeCollapsibleCard` 调用参数只出现在 `AgentTimelineGroupCard` 一处。

### T5 · `IdeSubmitButton`（0.5 人天）

**现状**（`_ComposerActionButton`，composer:1545-1593）：圆形 DecoratedBox + ClipOval + `sf.IconButton.ghost`（`size: small, density: iconDense, shape: circle`）+ `filled` 时 `disableTransition`。

**设计**：

```dart
/// 圆形提交/停止按钮：发送（filled）与停止（surface）两态。
class IdeSubmitButton extends StatelessWidget {
  const IdeSubmitButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.filled = false,
    super.key,
  });
}
```

内部实现平移 `_ComposerActionButton` 现状（含 `sf.IconButton.ghost`——zeta_ui 内部允许用 sf，feature 不允许）。颜色从现状调用点反推为参数或 tone 映射。

**验收**：composer 发送/停止按钮替换；G8 存量清单 −1（`sf.IconButton.ghost` 内嵌数从 10 → 9）。

## 2. 风险与回滚

| 风险 | 缓解 |
|------|------|
| zeta_ui 新原语过度设计 | 每个原语只覆盖现有调用点的并集；不预设未来需求 |
| 弹层选择器焦点/键盘行为回归 | 平移 `_SelectorSelectState` 的完整生命周期逻辑；widget 测试覆盖 Esc/失焦/值变更关弹层 |
| 每任务独立 PR 可单独 revert | 任务间无依赖，按序合入 |

## 3. 完成定义（DoD）

- [ ] 四类重复收敛；zeta_ui 新增 ≤3 个原语（`IdePopupSelect`、`IdeTimelineRow`、`IdeSubmitButton`）+ `IdeStatusCard` 密度参数。
- [ ] 每个 PR：`test_affected.sh` 绿 + zeta_ui 守卫（无 Riverpod/dart:io/l10n import）。
- [ ] CHANGELOG 不写（内部收敛，无用户可感知变化）。
