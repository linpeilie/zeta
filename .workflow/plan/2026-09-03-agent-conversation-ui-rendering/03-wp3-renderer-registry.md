# WP-3 · 时间线渲染分发注册表（插件化）

| 项 | 值 |
|----|----|
| 状态 | 已完成 |
| 规模 | 3–4 人天，1–2 个 PR |
| 依赖 | **WP-2 完成后启动**（文件先独立）；与 WP-1 解耦（只依赖 `AgentConversationCommandPort` 窄接口） |
| 门禁焦点 | G6；「新增条目类型 = 新增一个 renderer 文件」 |

---

## 0. 背景与现状代码

一种 block 类型的渲染职责目前**分散在四个文件**（以命令集为例）：

| 职责 | 现状位置 | 现状代码 |
|---|---|---|
| 分组归约 | `agent_timeline_grouping.dart:140-250` | `buildAgentTimelineRenderBlocks` |
| extent 估算 | `agent_timeline_extent_descriptor.dart:403-418` | `_estimateCommandGroup` |
| 展开态指纹 | 同上 `:337-354` | `_blockExpansionFingerprint` |
| Widget 构建 | `agent_pane_sections.dart:777-778` | switch case → `_AgentCommandGroupCard`（cards.dart:10-60） |
| 导航目录 | `agent_pane_navigation_rail.dart` | 独立谓词 |

新增一种卡片要同步改 4 处，漏改 extent 就引发滚动跳动（`IdeAnchoredDynamicSliverList` 用估算高度维持锚点）。

**现状两处 switch**（`agent_pane_sections.dart`）：

```dart
// :771-781  block → Widget
final content = switch (block) {
  AgentTimelineEntryRenderBlock(:final entry) => _buildTimelineEntry(context, entry, ...),
  AgentTimelineCommandGroupRenderBlock(:final group) => _AgentCommandGroupCard(...),
  AgentTimelineFileEditGroupRenderBlock(:final group) => _AgentFileEditGroupCard(...),
};

// :804-831  entry → Widget（_buildTimelineEntry 内）
return switch (entry) {
  AgentMessageTimelineEntry(:final message) => _AgentMessageEntry(...),
  AgentToolTimelineEntry(:final toolCall) => _AgentToolCallCard(...),
  AgentPermissionTimelineEntry() => const SizedBox.shrink(),
  AgentQuestionTimelineEntry() => const SizedBox.shrink(),
  AgentPlanApprovalTimelineEntry(:final request) => _buildPlanApprovalCard(context, request),
  AgentTurnFileChangesTimelineEntry() => const SizedBox.shrink(),
  AgentHistoryEventTimelineEntry(:final event) => _AgentHistoryEventCard(event: event),
};
```

extent 工厂侧对应的分支在 `_kindOf`（`:167-190`）与 `_estimateExtent`（`:356-401`）。

## 1. 目标与非目标

- **目标**：`AgentTimelineRendererRegistry` 把「渲染 + extent 估算 + 展开指纹 + 目录谓词」收敛为单条目；两处 switch 收敛为一次注册表查询；新增类型只加一个文件 + 一行注册。
- **非目标**：不改 `buildAgentTimelineRenderBlocks` 的归约算法；不改 `IdeAnchoredDynamicSliverList`；不改任何卡片视觉；viewport 层的 `AgentLiveActivityViewportItem` / `AgentTurnFooterViewportItem` 不是 block，**不进注册表**（它们的 kind/估算留在工厂，构建留在 `_buildViewportItem`）。

## 2. 总体设计（实现前读完）

### 2.1 核心类型（新文件 `presentation/timeline_rendering/agent_timeline_renderer.dart`）

```dart
/// 渲染上下文：renderer 需要的**稳定**外部依赖，每个 AgentPane 创建一次。
/// 终审修正：pendingState / turn / isLive 是逐 build 变化的量，**不进 context**
///（否则 context 必须每帧重建，「创建一次」不成立）——它们作为 build 的调用点参数传入。
final class AgentTimelineRenderContext {
  const AgentTimelineRenderContext({
    required this.commands,          // AgentConversationCommandPort（窄接口，WP-1 后由 provider 提供）
    required this.bindingKey,        // AgentConversationBindingKey（AgentRegionBuilder 用；WP-1 后替代 viewModel 参数）
    required this.markdownCache,
    required this.planRevisionDrafts,
  });

  final AgentConversationCommandPort commands;
  final AgentConversationBindingKey bindingKey;
  final AgentMarkdownCache markdownCache;
  final AgentPlanRevisionDraftStore planRevisionDrafts;
}

/// 单个 payload 类型的完整渲染条目。payload 可能是 block（命令集/文件编辑组）
/// 也可能是 entry（消息/工具卡/…）——registry resolve 时对 AgentTimelineEntryRenderBlock 解包。
///
/// 泛型说明：Dart 泛型类协变，`AgentTimelineRenderer<AgentMessageTimelineEntry>`
/// 可直接赋值给 `AgentTimelineRenderer<Object>` 使用；registry 按精确 runtimeType
/// 解析，build/estimate 入参的运行时类型必然匹配，协变插入的运行时检查不会触发。
abstract interface class AgentTimelineRenderer<P extends Object> {
  /// 该 renderer 接管的 payload 运行时类型（entry 类型或 block 类型）。
  Type get payloadType;

  /// extent 工厂用的稳定 kind 字符串（值必须等于 AgentTimelineExtentKinds 既有常量）。
  String get kind;

  /// 构建 Widget。turn 与 pendingState 随调用点传入（payload 里没有 turn 概念；
  /// 现状 _buildTimelineEntry 的 isLiveTurn 判断 = viewModel.liveTurnState?.id == turn.id）。
  Widget build(
    P payload,
    AgentTimelineRenderContext context, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  });

  /// 估算主轴高度。语义与现状 _estimateExtent 完全一致：
  /// 输入 crossAxisExtent / textScale / 展开态 / 操作组邻接，输出 logical px。
  double estimateExtent(
    P payload, {
    required double crossAxisExtent,
    required double textScale,
    required AgentTimelineExpansionLookup expansion,
    required bool precededByOperationGroup,
    required bool followedByOperationGroup,
  });

  /// 布局修订指纹：内容或展开态变化必须改变返回值（现状 _layoutRevision 语义）。
  Object layoutRevision(P payload, AgentTimelineExpansionLookup expansion);

  /// 是否计入导航目录（现状导航谓词内联语义）。
  bool get rendersInline;

  /// 可选：Sliver child 创建前的保温准备（现状 _prepareMarkdownWarmEntry 语义）。
  /// 返回非 null 时列表层包 ValueListenableBuilder + KeepAlive；默认 null = 不保温。
  /// isLive 取 viewport item 的 isLive 标志（现状 preferIncrementalUpdate 的数据源）。
  /// 只有 agent 正文 markdown 消息实现它。
  ValueListenable<bool>? prepareWarmEntry(
    P payload,
    AgentTimelineRenderContext context, {
    required bool isLive,
  }) =>
      null;
}
```

### 2.2 注册表（同目录 `agent_timeline_renderer_registry.dart`）

**单层注册表**（2026-09-03 review 修正：取代初版的「block 级 + entry 级两级注册 + meta-renderer 再分发」——解包后一张平表即可，去掉一层间接）：

```dart
final class AgentTimelineRendererRegistry {
  AgentTimelineRendererRegistry(List<AgentTimelineRenderer<Object>> renderers)
      : _byPayloadType = {for (final r in renderers) r.payloadType: r} {
    assert(_byPayloadType.isNotEmpty);
  }

  final Map<Type, AgentTimelineRenderer<Object>> _byPayloadType;

  /// 解析失败即抛——fail-closed，不允许静默回退（G4 精神）。
  AgentTimelineRenderer<Object> resolve(AgentTimelineRenderBlock block) {
    // entry 级 block 解包：按 entry 类型查表。
    final key = block is AgentTimelineEntryRenderBlock
        ? block.entry.runtimeType
        : block.runtimeType;
    return _byPayloadType[key] ??
        (throw UnsupportedError('未注册的时间线渲染类型: $key'));
  }
}
```

注册清单共 **9 条**（平铺）：entry 级 7 条（`AgentMessageTimelineEntry` / `AgentToolTimelineEntry` / `AgentPermissionTimelineEntry` / `AgentQuestionTimelineEntry` / `AgentPlanApprovalTimelineEntry` / `AgentTurnFileChangesTimelineEntry` / `AgentHistoryEventTimelineEntry`）+ block 级 2 条（`AgentTimelineCommandGroupRenderBlock` / `AgentTimelineFileEditGroupRenderBlock`）；不允许兜底，未注册即抛。

**hidden 类 entry 的显式登记**（review 修正：消除一处现状隐患）：permission / question / turnFileChanges 三个 renderer 的 `build` 返回 `const SizedBox.shrink()`、`kind` 返回 `AgentTimelineExtentKinds.hidden`、`estimateExtent` 返回 0。注意现状 `_estimateEntry`（`agent_timeline_extent_descriptor.dart:441-479`）对这三类落到 `48 * scale` 兜底、而 sections 渲染零高度——`AgentTimelineExtentKinds.hidden`（`:35`）定义了却没有分支返回它。**迁移时先核对这三类 entry 是否真的到达视口**（读 `projectAgentTimelineViewportItems`）：若到达，现状就是「估算 48px、实际 0px」的虚拟化错位，本 WP 顺手修正并在 PR 描述记录；若不到达（被提前过滤），hidden renderer 是防御性登记，同样保留。

### 2.3 extent 工厂改造

`AgentTimelineExtentDescriptorFactory.describe`（`:134-165`）内的 `_kindOf` / `_layoutRevision` / `_estimateExtent` 三个私有方法的 block 分支，改为查询注册表：

```dart
// 改后骨架
String _kindOf(AgentTimelineViewportItem item) => switch (item) {
  AgentLiveActivityViewportItem() => AgentTimelineExtentKinds.liveActivity,   // 保留
  AgentTurnFooterViewportItem() => AgentTimelineExtentKinds.turnFooter,       // 保留
  AgentBlockViewportItem(:final block) => _registry.resolve(block).kind,      // 注册表（内部解包 entry）
};
```

`AgentTimelineLayoutContext` / `describeAll` 的 descriptor 复用机制（`:106-131`）原样保留，不动。

`_estimateExtent` / `_layoutRevision` 同理：viewport 级两种保留现状分支，block 级委托 `renderer.estimateExtent(...)` / `renderer.layoutRevision(...)`。

### 2.4 sections 改造

`_AgentTimelineBlockSection.build`（`:769-796`）的两处 switch 收敛为：

```dart
@override
Widget build(BuildContext context) {
  final renderer = registry.resolve(block);
  final payload = block is AgentTimelineEntryRenderBlock ? block.entry : block;
  final content = renderer.build(
    payload,
    renderContext,
    turn: turn,
    pendingState: pendingState,   // 本 section 的既有字段，逐 build 传入
  );
  final child = isAgentTimelineOperationGroupBlock(block)
      ? Padding(padding: _operationGroupOuterPadding(...), child: content)  // 保留现状
      : content;
  return KeyedSubtree(key: ValueKey<String>('turn-block-${turn.id}-${block.id}'), child: child);
}
```

操作组外间距逻辑（`:782-791`）**保留在列表层**，不进 renderer——它是块间关系，不是块内职责。

**保温钩子同步迁移**：`_prepareMarkdownWarmEntry`（`:707-730`）的类型判断链删除，itemBuilder 里（`:427-440`）改为：

```dart
final keepAliveListenable = item is AgentBlockViewportItem
    ? registry.resolve(item.block).prepareWarmEntry(
        item.block is AgentTimelineEntryRenderBlock ? item.block.entry : item.block,
        renderContext,
        isLive: item.isLive,
      )
    : null;
// null → 不包 KeepAlive（现状行为）；非 null → ValueListenableBuilder + KeepAlive（现状行为）
```

只有 `AgentMessageRenderer.prepareWarmEntry` 返回非 null（agent 角色 + 非 plan 时调 `context.markdownCache.prepareWarmEntry(messageId:..., data:..., preferIncrementalUpdate: isLive)`）——逻辑逐行平移，判断条件不变。

### 2.5 注入

`AgentPane` 组合段创建一次注册表与 `AgentTimelineRenderContext`（`AgentPane` initState 或组合根；context 只含稳定依赖，创建一次成立），沿 `_AgentConversationTimeline` 构造参数下传（该构造已有 12 个参数，viewModel/markdownCache/planRevisionDrafts 并入 context；`pendingState` 保持现状作为 `_AgentTimelineBlockSection` 的逐 build 字段，不进 context）。**不做**全局单例/静态注册表——测试要能注入裁剪版。

## 3. 任务拆分

### T1 · 类型与注册表落地（0.5 人天） · 已完成（2026-09-03）

1. 按 §2.1/§2.2 建两个文件；`AgentTimelineExtentKinds` 常量从 extent_descriptor 平移或复用（保持字符串值不变）。
2. 单测：注册表 resolve 命中/未命中抛 `UnsupportedError`；重复注册同类型抛错（构造函数里加断言）。

**施工记录**：新增 `presentation/timeline_rendering/agent_timeline_renderer.dart`（context + 接口 + `AgentTimelineRendererBase`）与 `agent_timeline_renderer_registry.dart`（单层平表）；测试 `test/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer_registry_test.dart` 3 条绿。`AgentTimelineExtentKinds` 直接 import 复用，不平移。`flutter analyze` 零 issue；`test_affected.sh` 140 个根测试全绿。

**对照仓库代码的 5 处设计修正**（以代码为准，§2.1 骨架按此理解；T2 照此实现）：

| # | 文档原设计 | 实际落地 | 原因 |
|---|-----------|---------|------|
| 1 | `String get kind` | `String kindOf(P payload)` | 消息条目的 kind 取决于 role 与 `isPlan`（`_kindForMessage`，extent_descriptor.dart:192-201），一种 entry 类型对应 4 个 kind 值。kind 决定虚拟化列表的测量 cohort，收敛成常量会改变行为 |
| 2 | `build(payload, context, {turn, pendingState})` | 首参补 `BuildContext context` | 现状 `_buildPlanApprovalCard` 用 `context.l10n`（sections:880），卡片族普遍依赖 `IdeColors.of(context)` |
| 3 | context 持 `commands` + `bindingKey` 两个字段 | 持 `controller`（`AgentConversationRuntimeController`），另暴露 `commands` / `bindingKey` 两个只读 getter | WP-1 收尾后卡片族统一接收 `controller`（如 `AgentCommandGroupCard({group, controller})`）；改成窄接口要动全部卡片签名，属 WP-4 范围。窄依赖意图由两个 getter 保留 |
| 4 | 重复注册用 `assert` | 抛 `ArgumentError` | assert 在 release 被剥离；重复注册的后果是分发结果取决于清单顺序，应 release 也 fail-closed |
| 5 | `prepareWarmEntry` 在接口里带 `=> null` 默认实现 | 接口不带实现体，默认值下沉到 `AgentTimelineRendererBase` | Dart `implements` 不继承实现体，写在 `abstract interface class` 里的默认实现对实现者无效 |

另补：注册表提供 `static Object payloadOf(AgentTimelineRenderBlock)` 解包助手，供 sections / 保温钩子调用点复用同一份解包规则。

**验收**：类型编译通过；注册表单测 3 条绿。✅

### T2 · 迭代迁移 renderer（1.5–2 人天）

**顺序**：`AgentCommandGroupRenderer`（最简单，做样板）→ `AgentFileEditGroupRenderer` → entry 级 7 个（message / toolCall / permission / question / planApproval / turnFileChanges / historyEvent，其中 permission/question/turnFileChanges 按 §2.2 的 hidden 规约登记）。

**样板：命令集 renderer 完整迁移**（照此模式做其余 8 个）：

```dart
final class AgentCommandGroupRenderer
    implements AgentTimelineRenderer<AgentTimelineCommandGroupRenderBlock> {
  const AgentCommandGroupRenderer();

  @override
  Type get payloadType => AgentTimelineCommandGroupRenderBlock;

  @override
  String get kind => AgentTimelineExtentKinds.commandGroup; // 值不变

  @override
  Widget build(
    AgentTimelineCommandGroupRenderBlock block,
    AgentTimelineRenderContext context, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  }) {
    // 平移 _AgentCommandGroupCard（cards.dart:10-60）的 build：
    // viewModel.toggleCommandGroup → context.commands.toggleCommandGroup
    // AgentRegionBuilder 的 viewModel 参数 → context.bindingKey
    // 卡片构造参数以 WP-2 后的实际签名为准（此处为示意）
    return AgentCommandGroupCard(group: block.group, renderContext: context);
  }

  @override
  double estimateExtent(...) {
    // 平移 _estimateCommandGroup（extent_descriptor.dart:403-418）原逻辑，逐行不改
  }

  @override
  Object layoutRevision(block, expansion) {
    // 平移 _blockExpansionFingerprint 中 commandGroup 分支（:337-354）
  }

  @override
  bool get rendersInline => true;
  // prepareWarmEntry 不覆写：默认 null（命令集无 markdown 保温）
}
```

**每迁移一个条目，跑对齐测试**（新文件 `test/.../agent_timeline_extent_alignment_test.dart`）：

```dart
test('commandGroup extent 与迁移前一致', () {
  // 用固定 fixture block + 固定 layoutContext，对比 renderer.estimateExtent
  // 与迁移前工厂输出的快照值（先把现状值作为 expected 写死，再迁移）
});
```

**验收**：9 个条目全部迁移；每个都有 extent 对齐断言；`test_affected.sh` 绿。 ✅

**施工记录（2026-09-03）**：

- 新增 `timeline_rendering/renderers/` 共 10 个文件：命令集 / 文件编辑组 / 消息 / 工具调用 / 计划审批 / 历史事件各一，permission / question / turnFileChanges 各一（共享 `agent_hidden_entry_renderer.dart` 基类）。
- 新增 `timeline_rendering/agent_timeline_renderers.dart`：默认清单 `buildAgentTimelineRendererRegistry()`——**新增条目类型 = 新增 1 个 renderer 文件 + 在这里加 1 行**。
- 新增 `timeline_rendering/agent_timeline_extent_math.dart`：把 `_estimateMarkdownExtent` / `_planInteractionChromeExtent` / 宽高缩放归一化 / 操作组外间距四个算式从 descriptor 工厂提出来共享。**工厂同步改为调用这份共享算式**，因此 renderer 与工厂不存在两份公式（纯提取，数值零变化，三个既有 extent 测试原样绿）。
- 计划审批卡装配下沉为 `buildAgentPlanApprovalCard()`（`widgets/agent_pane_cards.dart`），sections 的 `_buildPlanApprovalCard` 改为委托——T2 阶段 renderer 与 sections 共用同一份实现，不出现两份卡片装配代码。
- 测试 `test/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_alignment_test.dart` 11 条：**对齐基线直接取现役 descriptor 工厂的输出**（而非文档设想的写死快照值），覆盖 9 个条目 × 折叠/展开/邻接/空正文/交互态 plan 等情形，另含 layoutRevision 失效性与清单计数。工厂公式将来若调整，两侧不会悄悄分叉。
- `flutter analyze` 零 issue；`tool/test_affected.sh` 384 个测试全绿。

**两处需要在 T3 接线时知道的设计**：

1. **命令集条目指纹靠注入而非中心 switch**。`_blockContentRevision` 的命令集分支要哈希组内每个 entry 的内容，而 entry 指纹归各自 renderer 所有。装配函数先建 entry 级查表，再把 `entryLayoutRevision` 闭包注入 `AgentCommandGroupRenderer`——避免在命令集里重写一份 entry 类型分支，「新增类型 = 1 个文件 + 1 行」才真正成立。
2. **`layoutRevision` 只覆盖 payload 自身**：返回 `Object.hash(内容指纹, 展开指纹)`。turn id / block id / 操作组邻接仍由工厂在外层合成（T3 接线时保留现状的外层 `Object.hash('block', turn.id, block.id, …)`，只把中间两项换成 `renderer.layoutRevision(...)`）。

**顺带修正的现状缺陷（§2.2 预判已核实）**：读 `buildAgentTimelineRenderBlocks`（`agent_timeline_grouping.dart:196-244`）确认——

| entry | 是否到达视口 | 迁移前估算 | 实际渲染 | renderer 登记 |
|---|---|---|---|---|
| `AgentPermissionTimelineEntry` | **会**（`_shouldSkipTimelineEntry` 不过滤，落 `AgentTimelineEntryRenderBlock`） | `toolCard` / `48 * scale` | `SizedBox.shrink()` = 0 | `hidden` / 0 |
| `AgentQuestionTimelineEntry` | **会**（同上） | `toolCard` / `48 * scale` | `SizedBox.shrink()` = 0 | `hidden` / 0 |
| `AgentTurnFileChangesTimelineEntry` | 不会（快照非空转成文件编辑组，空则丢弃） | `fileEditGroup` / `80 * scale` | — | `hidden` / 0（防御性登记） |

即 permission / question 两类此前每条会让虚拟化多算 48px。**该修正在 T3/T4 接线后才生效**（T2 阶段工厂仍走旧分支），届时要在 PR 描述里记录。三个 renderer 的 `rendersInline` 同时为 false，供 T3 的导航锚点使用。

**T3 的导航谓词有一处与文档不同**：`agent_pane_navigation_rail.dart` 没有 block 级谓词；实际取锚点的是 `buildAgentConversationNavigationEntries`（`agent_conversation_navigation.dart:114-116`），优先用户消息块、否则 `blocks.first`。`blocks.first` 可能是零高度块（跳过去等于跳到不可见位置），T3 改成「首个 `rendersInline` 的块」即可顺带修掉。

### T3 · 收敛 switch + 导航谓词（0.5–1 人天）

1. sections 两处 switch 按 §2.4 收敛；`_buildTimelineEntry` / `_buildPlanApprovalCard` 删除（逻辑已在 renderer 内）。
2. `agent_pane_navigation_rail.dart` 的目录收集改为 `registry.resolve(block).rendersInline`。
3. 守卫测试（放 `test/src/features/agent/architecture/`）：

```dart
test('所有 block 类型均有注册 renderer', () {
  // 反射不可行——用穷举：构造每种 block 的 fixture 实例，registry.resolve 不抛
});
```

**验收**：`grep -n "switch (block)\|switch (entry)" agent_pane_sections.dart` 零命中。 ✅（实测零命中）

**施工记录（2026-09-03）**：

- `_AgentTimelineBlockSection` 收缩为「拿已解析的 renderer 调 build + 包操作组 Padding + KeyedSubtree」，`_buildTimelineEntry` / `_buildPlanApprovalCard` 删除；`_prepareMarkdownWarmEntry` 的四层类型判断链换成 `registry.resolve(block).prepareWarmEntry(...)`。sections 净减 ~130 行。
- **extent 工厂同步接线**（§2.3）：`_kindOf` / `_layoutRevision` / `_estimateExtent` 的 block 分支全部委托注册表，`_kindForMessage` / `_blockContentRevision` / `_entryContentRevision` / `_blockExpansionFingerprint` / `_estimateCommandGroup` / `_estimateFileEditGroup` / `_estimateEntry` / `_estimateMessage` 八个私有方法删除。文件从 585 行降到 255 行，只剩 viewport 级两项（live 活动条 / turn footer）与 descriptor 复用机制。
- 工厂构造改为 `AgentTimelineExtentDescriptorFactory({required registry})`——**不设全局单例**，5 处测试调用点显式传清单。
- 导航谓词按实际代码落在 `buildAgentConversationNavigationEntries`：新增 `rendersInline` 谓词参数（默认全可见，保持既有调用者行为），兜底锚点由 `blocks.first` 改为 `_firstInlineBlock`。sections 传入 `registry.resolve(block).rendersInline`。
- 守卫测试 `test/src/features/agent/architecture/agent_timeline_renderer_registry_guard_test.dart` 4 条：从 `agent_conversation_timeline_store.dart` 与 `agent_timeline_grouping.dart` 源码盘点密封子类名，双向比对注册表（漏登记与多余登记都失败），外加三种 block fixture 的 resolve 冒烟。

**一处踩坑**：为兼容而在 `agent_timeline_extent_descriptor.dart` 加的 `export`（re-export `AgentTimelineExtentKinds` / `AgentTimelineExpansionLookup`）被 `test/src/architecture/deleted_transition_api_guard_test.dart` 的「lib/src 不得新增过渡 re-export」零容忍守卫拦下。已改为两个符号迁到 `timeline_rendering/agent_timeline_extent_math.dart` 后，各引用点直接 import 真源。

### T4 · 注入接线 + 收尾（0.5 人天） · 已完成（2026-09-03）

- [x] `AgentPane` 组合段建注册表 + context；`_AgentConversationTimeline` 构造参数收敛（12 个参数中 viewModel/markdownCache/planRevisionDrafts 并入 context；pendingState 保持逐 build 传递）。
- [x] `bash tool/test_full.sh` 绿；登记 `00-index.md` §6「开发记录」。

**施工记录**：`_AgentPaneState` 持 `_rendererRegistry`（无状态，Pane 生命周期一份）与 `_renderContext`；后者在 `initState` 与 `didUpdateWidget` 换会话时重建——controller 与 markdown 缓存 / 计划草稿宿主都会换实例，上下文必须跟着换代。`AgentConversationTimeline` 与 `AgentPaneBody` 的 `markdownCache` / `planRevisionDrafts` 两个参数合并为 `renderContext` + `rendererRegistry`（净减 1 个参数，且两个缓存不再各传一路）。

## 4. 风险与回滚

| 风险 | 缓解 |
|------|------|
| extent 迁移偏差 → 滚动跳动 | T2 逐条目对齐测试；Windows Profile 采样对比（AGENTS.md 热路径要求） |
| 展开指纹漏迁 → 展开态不触发重布局 | `layoutRevision` 迁移时对照 `_blockExpansionFingerprint` 逐字段核对 |
| 与 WP-1 并行改 sections 冲突 | 按 DR-003 顺序；context 的 `commands/bindingKey` 字段已兼容 WP-1 目标形态 |

## 5. 完成定义（DoD）

- [x] 新增条目类型 = 新增 1 个 renderer 文件 + 1 行注册（清单在 `timeline_rendering/agent_timeline_renderers.dart`；架构守卫测试会在漏登记时失败）。
- [x] sections 无 block/entry switch；extent 工厂无 block 类型分支。
- [x] `tool/test_full.sh` 绿；CHANGELOG 无条目。

**接线后生效的行为变化（PR 描述需记录）**：permission / question 两类条目此前按 `toolCard` / 48px 估算而实际渲染 0px，现在按 `hidden` / 0 估算，长会话滚动锚点少一份系统性偏差；导航兜底锚点不再可能落在这类零高度块上。
