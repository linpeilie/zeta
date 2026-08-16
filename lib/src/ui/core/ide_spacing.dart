import 'package:flutter/widgets.dart';

/// IDE 设计系统间距 token。
///
/// 全项目间隙、padding 与 `SizedBox` 间距优先取这里的档位；禁止在 feature
/// 中散落裸数字（如 `EdgeInsets.all(12)`），以便统一调密度。
///
/// - **原始档位** `space0`…`space32`：用于 `SizedBox`、局部 `EdgeInsets` 组合。
/// - **语义 EdgeInsets**：已绑定典型组件，改一处即可联动同类 UI。
abstract final class IdeSpacing {
  // ---------------------------------------------------------------------------
  // 原始间距档位（px）
  // ---------------------------------------------------------------------------

  /// 零间隙：某一侧明确不要额外 inset。
  ///
  /// 生效位置：`IdeHome` 工作台顶部与标题栏贴齐（`fromLTRB` 的 top）。
  static const double space0 = 0;

  /// 最小间隙：图标与紧贴标签、微分隔。
  ///
  /// 生效位置：Activity Rail 垂直微 padding、Tab 指示条偏移、Toast 内小间距、
  /// 项目列表 chip 微边距等。
  static const double space2 = 2;

  /// 极紧凑间隙：菜单项内边距、行内小图标间距。
  ///
  /// 生效位置：`IdeContextMenu` 容器/分隔、Tab 关闭按钮间距、配置编辑器行间隙、
  /// Toast 图标与文案间距等。
  static const double space4 = 4;

  /// 紧凑间隙：列表行内元素、文件树缩进前缀、状态徽章间距。
  ///
  /// 生效位置：文件树节点 padding/图标间距、项目列表操作图标 gap、
  /// Agent 管理状态行、消息元信息 `runSpacing` 等。
  static const double space6 = 6;

  /// 默认组件内间隙：最常用的图标-文字间距、卡片内小节间距。
  ///
  /// 生效位置：折叠卡/选择卡间距、拖拽手柄厚度默认值、上下文菜单项图标间距、
  /// Agent Composer / 模型配置动画相关间距、Markdown 块间距、
  /// `IdeHome` 工作台左右与底部外距、大量 `SizedBox`。
  static const double space8 = 8;

  /// 中等间隙：卡片内段落、Composer 内边、消息区垂直节奏。
  ///
  /// 生效位置：状态卡动作区、Composer padding 组合、消息气泡上下间距、
  /// 配置编辑器段落间距等。
  static const double space10 = 10;

  /// 常用内边距基数：面板/页面紧凑 padding、卡片内容区。
  ///
  /// 生效位置：`all12` / `pagePaddingCompact` / `panelPadding` 的来源；
  /// 选择卡、日志视图、Agent 管理卡片内边、指标条项 padding 等。
  static const double space12 = 12;

  /// 区块级间距：页面区块、对话框、section 标题与正文之间。
  ///
  /// 生效位置：`sectionPadding` / `dialogPadding` / `pagePadding` 的垂直分量；
  /// 设置/管理页大段 `SizedBox`、消息区大块 padding。
  static const double space16 = 16;

  /// 页面级水平边距基数。
  ///
  /// 生效位置：`pagePadding` 的 `horizontal` 分量。
  static const double space20 = 20;

  /// 较大区块分隔（较少直接使用，保留档位便于扩展）。
  static const double space24 = 24;

  /// 最大步进：大段空白或特殊布局占位。
  ///
  /// 生效位置：设置页分组之间的间隙——无卡片布局下，这段留白是唯一的分组边界。
  static const double space32 = 32;

  /// 零边距别名，语义上表示「不要额外 padding」。
  static const EdgeInsets none = EdgeInsets.zero;

  // ---------------------------------------------------------------------------
  // 全向 EdgeInsets 快捷量
  // ---------------------------------------------------------------------------

  /// 四向 4：菜单容器、极紧凑浮层。
  ///
  /// 生效位置：`IdeContextMenu` 外层 padding。
  static const EdgeInsets all4 = EdgeInsets.all(space4);

  /// 四向 6：紧凑芯片/小容器。
  static const EdgeInsets all6 = EdgeInsets.all(space6);

  /// 四向 8：日志条目、列表 margin、小卡片。
  ///
  /// 生效位置：项目列表卡片 margin、日志行内 padding 等。
  static const EdgeInsets all8 = EdgeInsets.all(space8);

  /// 四向 10：与 [cardPadding] 同值，可互换；优先用语义名。
  static const EdgeInsets all10 = EdgeInsets.all(space10);

  /// 四向 12：Popover 内容、状态/日志卡片、配置面板块。
  ///
  /// 生效位置：Provider 选择 Popover、Agent 管理/日志/配置多处卡片、
  /// `CompactMetricBar` 单项 padding。
  static const EdgeInsets all12 = EdgeInsets.all(space12);

  /// 四向 16：较大内容块、空状态/说明区。
  ///
  /// 生效位置：项目列表空状态与说明块、Agent 管理说明卡、配置编辑器外层。
  static const EdgeInsets all16 = EdgeInsets.all(space16);

  /// 四向 20：少用的宽松容器。
  static const EdgeInsets all20 = EdgeInsets.all(space20);

  // ---------------------------------------------------------------------------
  // 轴向 EdgeInsets 快捷量
  // ---------------------------------------------------------------------------

  /// 水平 6 / 8 / 10 / 12 / 16 / 20：行内水平节奏。
  ///
  /// 生效位置：文件树、项目列表行、Agent 管理横向 chip 行、紧凑控件等。
  static const EdgeInsets horizontal6 = EdgeInsets.symmetric(
    horizontal: space6,
  );
  static const EdgeInsets horizontal8 = EdgeInsets.symmetric(
    horizontal: space8,
  );
  static const EdgeInsets horizontal10 = EdgeInsets.symmetric(
    horizontal: space10,
  );
  static const EdgeInsets horizontal12 = EdgeInsets.symmetric(
    horizontal: space12,
  );
  static const EdgeInsets horizontal16 = EdgeInsets.symmetric(
    horizontal: space16,
  );
  static const EdgeInsets horizontal20 = EdgeInsets.symmetric(
    horizontal: space20,
  );

  /// 垂直 4 / 6 / 8 / 12 / 16：列表分区、纵向堆叠间隙。
  ///
  /// 生效位置：项目列表外层 vertical padding、Tab 标签垂直 padding 等。
  static const EdgeInsets vertical4 = EdgeInsets.symmetric(vertical: space4);
  static const EdgeInsets vertical6 = EdgeInsets.symmetric(vertical: space6);
  static const EdgeInsets vertical8 = EdgeInsets.symmetric(vertical: space8);
  static const EdgeInsets vertical12 = EdgeInsets.symmetric(vertical: space12);
  static const EdgeInsets vertical16 = EdgeInsets.symmetric(vertical: space16);

  // ---------------------------------------------------------------------------
  // 语义 EdgeInsets（按组件角色）
  // ---------------------------------------------------------------------------

  /// 常规页面内容区内边距（宽屏）。
  ///
  /// 桌面 IDE 走高信息密度：这里刻意比移动端/网页的页面留白紧一档，
  /// 把省下的空间还给内容行数。
  ///
  /// 生效位置：`IdePageBody`（宽度 ≥ medium）；`AgentPane` 主内容；
  /// Agent 管理页；用量统计中等及以上宽度布局。
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: space16,
    vertical: space12,
  );

  /// 窄屏页面内容区内边距。
  ///
  /// 生效位置：`IdePageBody` / `AgentPane` / Agent 管理 / 用量统计在
  /// `maxWidth < mediumBreakpoint` 时的紧凑 padding。
  static const EdgeInsets pagePaddingCompact = EdgeInsets.all(space12);

  /// 独立内容区块（section / 说明卡）内边距。
  ///
  /// 生效位置：Agent 消息区大块说明/计划容器（`agent_pane_messages`）。
  static const EdgeInsets sectionPadding = EdgeInsets.all(space16);

  /// 侧栏或嵌套面板内容区内边距。
  ///
  /// 生效位置：用量统计侧栏/面板块（`UsageStatisticsPage`）。
  static const EdgeInsets panelPadding = EdgeInsets.all(space12);

  /// 卡片内容区内边距。
  ///
  /// 生效位置：`IdeStatusCard` 默认 padding；Agent 时间线卡片；
  /// Markdown 代码块 padding（`agent_pane_styles`）。
  static const EdgeInsets cardPadding = EdgeInsets.all(space10);

  /// 对话框内容区内边距。
  ///
  /// 目标生效位置：`IdeDialog` 与确认弹窗内容区。
  /// 当前未引用：实现侧尚未统一改用本 token。
  static const EdgeInsets dialogPadding = EdgeInsets.all(space16);

  /// 工具条内边距。
  ///
  /// 生效位置：`IdeToolbar`。
  static const EdgeInsets toolbarPadding = EdgeInsets.symmetric(
    horizontal: space8,
    vertical: space4,
  );

  /// 标准列表行内边距。
  ///
  /// 生效位置：`IdeListRow`。
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: space10,
    vertical: space6,
  );

  /// 卡片内设置行的内边距（更宽松，容纳控件）。
  ///
  /// 上下留白刻意大于 [rowPadding]：设置行是「标题 + 描述 + 控件」的复合行，
  /// 即使有分割线也要靠留白保证每一项读起来是独立的一块。
  ///
  /// 生效位置：`IdeSettingsRow` 默认值；Agent 管理页卡片内的信息行。
  static const EdgeInsets settingsRowPadding = EdgeInsets.symmetric(
    horizontal: space12,
    vertical: space16,
  );

  /// 平铺（无卡片）设置行的内边距：只留上下，横向交给页面。
  ///
  /// 设置页去掉卡片容器后，行的横向对齐由 `IdePageBody` 的 [pagePadding]
  /// 统一提供；行自身不再缩进，分割线因此与内容列同宽、贯穿到底。
  ///
  /// 生效位置：`SettingsPage` 各分区的 `IdeSettingsRow`。
  static const EdgeInsets settingsRowPaddingFlat = EdgeInsets.symmetric(
    vertical: space16,
  );

  /// 平铺设置分组标题的内边距：上下都留白，把标题夹在两段空隙中间。
  ///
  /// 下边距刻意大于上边距，但**远小于分组之间的 [space32] 间隙**——标题必须
  /// 明显更靠近它管辖的那几行，分组边界才由留白本身讲清楚，而不是靠框线。
  ///
  /// 生效位置：`SettingsPage` 各分组标题。
  static const EdgeInsets settingsGroupTitlePadding = EdgeInsets.only(
    top: space8,
    bottom: space12,
  );

  /// Agent Composer 外卡内边距（左上略宽，右下略紧以容纳拖拽角）。
  ///
  /// 生效位置：`agent_pane_composer` 输入面板。
  static const EdgeInsets composerPadding = EdgeInsets.fromLTRB(
    space12,
    space10,
    space8,
    space8,
  );

  /// 紧凑控件（小按钮组、分段控件）内边距。
  ///
  /// 目标生效位置：工具栏内小控件、分段选择器。
  /// 当前未引用：实现侧多直接使用 `space8`/`space4` 组合。
  static const EdgeInsets compactControlPadding = EdgeInsets.symmetric(
    horizontal: space8,
    vertical: space4,
  );

  /// 文本输入框内容区内边距。
  ///
  /// 生效位置：Agent 消息编辑输入区（`agent_pane_messages`）。
  static const EdgeInsets inputContentPadding = EdgeInsets.symmetric(
    horizontal: space12,
    vertical: space8,
  );
}
