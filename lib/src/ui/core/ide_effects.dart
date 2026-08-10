import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// IDE 设计系统圆角 token。
///
/// 全项目圆角只允许取自这四档 + 胶囊，禁止在业务代码中出现
/// 裸 `BorderRadius.circular(<数字>)`。需要新档位时先在这里补充。
///
/// **嵌套规则（强制）**：带圆角的元素套在另一个带圆角的容器里时，
/// 内层档位必须严格小于外层。典型链路是
/// 面板 [large] → 卡片 [medium] → 代码块 [small] → 行内高亮 [micro]。
/// 同档嵌套会让内外两条弧线打架，评审按违规处理。
abstract final class IdeRadius {
  /// 微元素圆角：标签 / chip / hover 高亮底 / 行内代码底 / 小提示块。
  ///
  /// 这一档专门服务「贴着文字的小色块」——它们尺寸太小，用 [small] 会显得
  /// 过圆而失去精确感，也会与外层代码块的圆角撞在一起。
  ///
  /// 生效位置：`IdeChip`、Markdown 行内代码与代码块内高亮底、消息图片缩略图、
  /// 状态标签等（多通过 [allMicro] 引用）。
  static const double micro = 4;

  /// 基础交互组件圆角：按钮、输入框、代码块、列表行、菜单项、Tab。
  ///
  /// 生效位置：`IdeListRow` / `PaneInteractiveSurface` 默认小圆角、
  /// `IdeContextMenu` 菜单项、`IdeTabs`/`IdeActivityRail`、窗口控制按钮、
  /// Markdown 代码块/引用外框、模型配置下拉项、Composer 内小控件等
  /// （多通过 [allSmall] 引用）。
  static const double small = 6;

  /// 卡片、状态卡、Composer 外卡等内容容器圆角。
  ///
  /// 生效位置：`IdeChoiceCard`、`IdeStatusCard`、`IdeToast`、Composer 外卡、
  /// 时间线卡片、`PaneCard` 默认等（多通过 [allMedium] 引用）。
  static const double medium = 8;

  /// 大面板圆角：侧栏容器、画布、弹出层、对话框。
  ///
  /// 这是嵌套链路的最外层，因此比 [medium] 明显更圆，让「面板」和
  /// 「面板里的卡片」一眼可分。
  ///
  /// 生效位置：`IdeSurface` 的 pane / popover 级、Provider 选择 Popover、
  /// workbench 窄屏浮层面板（多通过 [allLarge] 引用）。
  static const double large = 12;

  /// [micro] 的四向 `BorderRadius`。
  static const BorderRadius allMicro = BorderRadius.all(Radius.circular(micro));

  /// [small] 的四向 `BorderRadius`。
  static const BorderRadius allSmall = BorderRadius.all(Radius.circular(small));

  /// [medium] 的四向 `BorderRadius`。
  static const BorderRadius allMedium = BorderRadius.all(
    Radius.circular(medium),
  );

  /// [large] 的四向 `BorderRadius`。
  static const BorderRadius allLarge = BorderRadius.all(Radius.circular(large));

  /// 胶囊标签 / 圆形按钮：足够大的半径，实际表现为 pill。
  ///
  /// 生效位置：状态徽章、圆形图标按钮等需要全圆角的控件。
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// IDE 阴影与遮罩 token。
///
/// **零阴影法则**：层级一律靠表面明暗（`IdeColors` 的 frame → surface →
/// surfaceElevated → surfaceOverlay 阶梯）加 1px 极低透明度描边表达。
/// 深色开发者工具里的投影既廉价又糊，业务代码**不允许**手写 `BoxShadow`，
/// 也不允许 Material `elevation`。
///
/// 唯一豁免是脱离文档流的浮层：它们盖在任意内容之上，只靠表面明度分不开。
/// 因此 [overlayShadow] 保留，但刻意压到「几乎看不见」的强度做兜底。
abstract final class IdeEffects {
  /// 弹出层（菜单 / popover / 窄窗浮层面板 / Toast）的极淡投影。
  ///
  /// 这是全项目**唯一**允许的投影。分层主要靠更亮的
  /// `IdeColors.surfaceOverlay` 加 `border` 细边，本阴影只负责让浮层边缘
  /// 不至于和同色背景糊在一起，所以模糊半径和偏移都远小于常规 Material 浮层。
  ///
  /// 生效位置：`IdeSurface` popover 级、`IdeToast`、`IdeWorkbenchScaffold`
  /// 窄屏浮层侧栏、项目列表 Provider 选择 Popover 等。
  static List<BoxShadow> overlayShadow(Brightness brightness) {
    return [
      BoxShadow(
        color: brightness == Brightness.dark
            ? sf.Colors.black.withValues(alpha: 0.28)
            : sf.Colors.zinc[900].withValues(alpha: 0.10),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// 键盘焦点环：无方向、无高度语义，不能与浮层阴影混用。
  ///
  /// [accent] 通常传入 `IdeColors.focusRing`。
  ///
  /// 生效位置：Agent Composer 外卡聚焦态（`agent_pane_composer`）；
  /// 其它可聚焦控件可复用同一套环。
  static List<BoxShadow> focusRing(
    Brightness brightness, {
    required Color accent,
  }) {
    return [
      BoxShadow(
        color: accent.withValues(
          alpha: brightness == Brightness.dark ? 0.54 : 0.36,
        ),
        blurRadius: 0,
        spreadRadius: 2,
      ),
    ];
  }

  /// 窄窗口浮层背后的遮罩色。
  ///
  /// 生效位置：`IdeWorkbenchScaffold` 在 medium 布局下打开浮层
  /// navigation/inspector 时背后的 `ColoredBox` scrim。
  static Color scrim(Brightness brightness) {
    return brightness == Brightness.dark
        ? sf.Colors.black.withValues(alpha: 0.55)
        : sf.Colors.zinc[300].withValues(alpha: 0.24);
  }
}
