import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'ide_spacing.dart';

/// 交互控件的密度档位。
///
/// `regular` 用于设置页和工具栏，`compact` 用于 Pane 内的独立 Tab 与紧凑动作。
enum IdeControlSize { compact, regular }

/// IDE 布局与密度 Token。
///
/// 与 [IdeSpacing] 不同，这些值描述**稳定的组件尺寸**和**响应式阈值**，
/// 而不是可叠加的间隙。改这里会影响 workbench 骨架、侧栏宽度夹紧、
/// 页面内容最大宽和多处布局断点。
///
/// 读取约定：业务代码直接引用 `IdeMetrics.xxx`；不要在 feature 内复制
/// 同名魔法数字。尚未接线的 token 在注释中标明「当前未引用」。
abstract final class IdeMetrics {
  // ---------------------------------------------------------------------------
  // 壳层高度
  // ---------------------------------------------------------------------------

  /// 自定义窗口标题栏最小高度。
  ///
  /// 生效位置：`WindowFrame` 标题栏；有 Menubar 时由内容撑开，不低于本值。
  /// 窗口控制按钮在可伸展区域内垂直拉满标题栏高度。
  static const double titleBarHeight = 32;

  /// 页面顶栏（标题 + 操作区）固定高度。
  ///
  /// 生效位置：`IdePageHeader`（Agent 管理详情页、用量统计等页面顶栏）。
  /// 设置页与 Agent 管理列表页已取消顶栏，内容直接从 `IdePageBody` 起排。
  static const double pageHeaderHeight = 44;

  /// 侧栏 / Pane 内部标题条高度。
  ///
  /// 与 [titleBarHeight] 取齐：IDE 壳层里所有「条」保持同一节奏，
  /// 高信息密度靠压缩 chrome 换取内容行数。
  ///
  /// 生效位置：`Pane` 头部条。
  static const double paneHeaderHeight = 32;

  /// macOS 自绘标题栏左侧为原生交通灯按钮让出的宽度。
  ///
  /// 生效位置：`WindowFrame` 标题栏；仅 macOS 生效，且该区域不拦截点击。
  static const double macOSTrafficLightGutter = 76;

  /// 工具条最小高度。
  ///
  /// 这是**条**的下限，不是控件高度：工具条的实际高度由内部控件加
  /// [toolbarPadding] 撑开，本值只保证条在没有内容时也不塌。
  ///
  /// 生效位置：`IdeToolbar`；用量统计页筛选/操作条等复用该高度。
  static const double toolbarHeight = 34;

  // ---------------------------------------------------------------------------
  // 控件尺寸（内容撑高体系）
  // ---------------------------------------------------------------------------
  //
  // 三个 token 合起来定义**唯一**的控件高度公式：
  //
  //     控件高度 = max(2 × controlPaddingYFor(size),
  //                    controlMinHeightFor(size) − 内容高度) + 内容高度
  //     内容高度 = max(文字行盒, controlIconBoxFor(文字样式))
  //
  // 也就是「竖向内边距 + 内容，低于点击目标下限时再抬到下限」。所有交互
  // 控件——Select / Tabs / Button / 未来的 TextField 与 IconButton——都必须
  // 走这一条公式，不允许再出现第二套内边距。
  //
  // 默认 UI 字号（12）下的落点：常规档 10×2 + 15 = 35，紧凑档 6×2 + 15 = 27。
  //
  // **控件实现只应引用内边距与下限这两个 token，不要去算高度**：一旦有人把
  // 算出来的数字塞进 `SizedBox`，高度就又有了第二个出处，也就回到了迁移前
  // 「固定高度替内边距的分歧兜底」的老路。需要一个具体数字（回归测试、为
  // 控件预留空位的骨架屏）时走 [controlNaturalHeightFor]。

  /// 常规控件的竖向内边距（单侧）。
  ///
  /// 生效位置：`IdeSelect` / `IdeTabs` / `IdeButton`（常规档）。
  static const double controlPaddingYRegular = IdeSpacing.space10;

  /// 紧凑控件的竖向内边距（单侧）。
  ///
  /// 生效位置：`IdeTab` 与 Pane 内紧凑按钮。
  static const double controlPaddingYCompact = IdeSpacing.space6;

  /// 常规控件的最小外框高度（点击目标下限）。
  ///
  /// 只在内容小到不好点时才生效（默认字号下不生效，UI 字号 ≤ 10 时才轮到
  /// 它），不决定正常状态下的控件高度——那是内边距和内容的事。
  static const double controlMinHeightRegular = 28;

  /// 紧凑控件的最小外框高度（点击目标下限）。
  ///
  /// 图标按钮另有 [iconButtonHitSize]（28）作为点击区域下限，不共用这一档。
  static const double controlMinHeightCompact = 24;

  /// 按密度档解析竖向内边距（单侧）。
  static double controlPaddingYFor(IdeControlSize size) {
    return switch (size) {
      IdeControlSize.compact => controlPaddingYCompact,
      IdeControlSize.regular => controlPaddingYRegular,
    };
  }

  /// 按密度档解析最小外框高度。
  static double controlMinHeightFor(IdeControlSize size) {
    return switch (size) {
      IdeControlSize.compact => controlMinHeightCompact,
      IdeControlSize.regular => controlMinHeightRegular,
    };
  }

  /// 解析控件内图标的**方形外框**边长。
  ///
  /// 内容撑高体系里，控件高度由「最高的那个内容」决定。图标一旦比文字行盒
  /// 高，带图标的控件就会比纯文字控件高一截——shadcn 官网自己的 Select(32)
  /// 比 Button(30) 高 2px，原因就是里面那个 16px 的 chevron。所以图标不能
  /// 直接摆进 Row，必须先套进一个**与文字行盒等高**的方框。
  ///
  /// 取整方式对齐 Flutter 对文字行盒的处理（四舍五入到整像素）：11 × 1.35 =
  /// 14.85 排出来是 15，图标盒也取 15，图标控件与文字控件才严丝合缝等高。
  ///
  /// 生效位置：`IdeIconBox`；所有控件内图标都应经由它落地。
  static double controlIconBoxFor(TextStyle textStyle) {
    final fontSize = textStyle.fontSize ?? 0;
    return (fontSize * (textStyle.height ?? 1)).roundToDouble();
  }

  /// 按公式预估控件的自然外框高度。
  ///
  /// **控件实现不得用它设定高度**——高度必须由内边距和内容自然得出，否则就
  /// 又回到了「固定高度」那一套。它存在只为两种用途：
  /// - 回归测试用同一条公式表达期望值，而不是把 35 这种数字抄进断言；
  /// - 需要为尚未构建的控件预留空位的布局（骨架屏、占位测量）。
  ///
  /// 内容高度按纯文字/等高图标算，即 [controlIconBoxFor]；控件里塞了更高的
  /// 自定义组件时，本函数的结果会偏小。
  static double controlNaturalHeightFor(
    TextStyle textStyle, {
    required IdeControlSize size,
  }) {
    return math.max(
      controlMinHeightFor(size),
      2 * controlPaddingYFor(size) + controlIconBoxFor(textStyle),
    );
  }

  // ---------------------------------------------------------------------------
  // 行与点击目标
  // ---------------------------------------------------------------------------

  /// 紧凑数据行最小高度。
  ///
  /// 生效位置：`IdeDataRow`；文件树行、Agent 管理中的紧凑行约束。
  static const double compactRowHeight = 28;

  /// 标准列表行最小高度。
  ///
  /// 生效位置：`IdeListRow`（会话列表、通用列表项）。
  static const double listRowHeight = 32;

  /// 设置类表单行最小高度（标签 + 控件并排时）。
  ///
  /// 生效位置：`IdeSettingsRow`。
  static const double settingsRowMinHeight = 52;

  /// 密集键值行的字段名列宽。
  ///
  /// 取值依据：本产品最长的中文字段名是「可执行文件路径」，7 字 × 12px（
  /// `IdeTextStyles.titleSmall` 基准字号）≈ 84px，留 8px 余量到 92。固定宽度是
  /// 这一档的关键——只有所有行的值都从同一条竖线起排，纵向扫视才能一眼比对。
  ///
  /// 生效位置：`IdeKeyValueRow`。
  static const double keyValueLabelWidth = 92;

  /// 图标按钮的最小点击区域（宽/高）。
  ///
  /// 生效位置：项目列表操作按钮、文件树折叠按钮、侧栏图标按钮等。
  static const double iconButtonHitSize = 28;

  // ---------------------------------------------------------------------------
  // 开关（IdeSwitch）
  // ---------------------------------------------------------------------------

  /// 开关轨道宽度。
  ///
  /// 生效位置：`IdeSwitch`。
  static const double switchTrackWidth = 36;

  /// 开关轨道高度。
  ///
  /// 生效位置：`IdeSwitch`。轨道走 `IdeRadius.small`（6）而非胶囊：与分段
  /// 控件、hover 底色共用同一套「小圆角」语言。
  static const double switchTrackHeight = 20;

  /// 开关滑块边长（正方形，圆角走 `IdeRadius.micro`）。
  ///
  /// 生效位置：`IdeSwitch`。
  static const double switchThumbSize = 16;

  /// 开关轨道到滑块的内边距。
  ///
  /// 生效位置：`IdeSwitch`；等于 (`switchTrackHeight` − `switchThumbSize`) / 2。
  static const double switchTrackPadding = 2;

  /// 会话消息内联图片缩略图边长（正方形）。
  ///
  /// 生效位置：`agent_pane_messages` 的用户消息附图；Composer 草稿附件复用
  /// 更小的自有尺寸，不走本 token。
  static const double messageThumbnailSize = 120;

  /// Activity Rail（左右图标条）宽度。
  ///
  /// 生效位置：`IdeWorkbenchScaffold` 的 rail 列宽。Scaffold 内总占用为
  /// `activityRailWidth + IdeSpacing.space4`（内侧 gap `space4`，外侧贴
  /// scaffold 边；窗口级外距由 `IdeHome` 的工作台 padding 提供：左右/底
  /// `space8`，顶部 `space0` 与标题栏贴齐）。
  static const double activityRailWidth = 36;

  /// Activity Rail 图标尺寸。
  ///
  /// 生效位置：`IdeActivityRail` 的图标；比通用图标略大，保证 36pt 窄条里
  /// 仍有清晰的点击目标。
  static const double activityRailIconSize = 19;

  // ---------------------------------------------------------------------------
  // 侧栏与导航宽度
  // ---------------------------------------------------------------------------

  /// 设置页等固定导航栏宽度。
  ///
  /// 生效位置：`SettingsPage` 左侧导航栏。
  static const double navigationPaneWidth = 240;

  /// 可拖拽侧栏的默认宽度。
  ///
  /// 生效位置：`IdeHome` 初始面板宽；`IdeWorkbenchScaffold.navigationWidth`
  /// 默认值。
  static const double sidePaneDefaultWidth = 280;

  /// 可拖拽侧栏允许的最小宽度。
  ///
  /// 生效位置：`IdeHome` / `IdeWorkbenchScaffold` 对 navigation 与 inspector
  /// 宽度的 `clamp` 下界。
  static const double sidePaneMinWidth = 220;

  /// 可拖拽侧栏允许的最大宽度。
  ///
  /// 生效位置：同上，`clamp` 上界；拖拽手柄不能把侧栏拉得更宽。
  static const double sidePaneMaxWidth = 400;

  /// Inspector（右侧检查器）默认宽度。
  ///
  /// 生效位置：`IdeWorkbenchScaffold.inspectorWidth` 默认值。
  static const double inspectorPaneWidth = 300;

  /// 合并左栏折叠统计摘要为 Projects 正文优先保留的最小高度。
  ///
  /// 生效位置：`ProjectAgentSidebar` 的折叠摘要高度上界。
  static const double projectsPaneMinHeight = 160;

  // ---------------------------------------------------------------------------
  // 内容最大宽与主编辑区
  // ---------------------------------------------------------------------------

  /// Agent 会话正文等可读内容的最大宽度。
  ///
  /// 生效位置：Agent Markdown/消息区（`agent_pane_styles`、
  /// `agent_pane_sections`）的 `maxContentWidth` / `maxWidth` 约束。
  static const double contentMaxWidth = 920;

  /// 设置类页面内容区最大宽度。
  ///
  /// 生效位置：`IdePageBody` 默认 `maxWidth`；Agent 管理页内容约束。
  static const double settingsContentMaxWidth = 960;

  /// 用量统计等数据密集页的内容最大宽度。
  ///
  /// 生效位置：`UsageStatisticsPage` 主内容 `ConstrainedBox`。
  static const double analyticsContentMaxWidth = 1440;

  /// 主编辑区（中央 Canvas）在并排侧栏时的最小保留宽度。
  ///
  /// 生效位置：`IdeWorkbenchScaffold` 布局计算——侧栏过宽时优先保证中央
  /// 区域不小于该值，避免 Agent Canvas 被挤没。
  static const double mainEditorMinWidth = 480;

  // ---------------------------------------------------------------------------
  // 指标条
  // ---------------------------------------------------------------------------

  /// `CompactMetricBar` 从固定项宽切换为均分宽度的断点。
  ///
  /// 生效位置：`compact_metric_bar.dart`；宽度 ≥ 本值时各项均分，否则每项
  /// 使用 [metricBarItemWidth] 并横向滚动。
  static const double metricBarEqualWidthBreakpoint = 900;

  /// 指标条在非均分模式下的单项固定宽度。
  ///
  /// 生效位置：`CompactMetricBar` 窄屏横向滚动布局。
  static const double metricBarItemWidth = 180;

  /// 指标条项之间竖向分隔线的高度。
  ///
  /// 生效位置：`CompactMetricBar` 中的 `VerticalDivider` 高度。
  static const double metricBarDividerHeight = 36;

  // ---------------------------------------------------------------------------
  // 响应式断点
  // ---------------------------------------------------------------------------

  /// 宽屏 workbench 断点：navigation + canvas + inspector 三栏并排。
  ///
  /// 生效位置：`resolveWorkbenchLayoutMode`（`IdeWorkbenchScaffold`）；
  /// 用量统计页宽布局判断。
  static const double wideBreakpoint = 1180;

  /// 中等宽度断点：navigation + canvas 两栏，inspector 收起为浮层/隐藏。
  ///
  /// 生效位置：`resolveWorkbenchLayoutMode`；`IdePageBody` / Agent 管理 /
  /// 用量统计在 `< medium` 时切换紧凑 padding 或纵向堆叠。
  static const double mediumBreakpoint = 820;

  /// 行内标签/控件改为上下堆叠的断点。
  ///
  /// 生效位置：`IdeSettingsRow`、`IdeSection` 标题行、Agent 消息元信息行、
  /// Agent 主内容在极窄宽度下的 padding 选择。
  static const double stackedRowBreakpoint = 640;
}
