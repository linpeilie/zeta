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

/// IDE 容器形状 token。
///
/// 只有**面板级容器**（[IdeRadius.large]，12px）使用平滑圆角
/// （rounded superellipse，即俗称的 squircle）；控件级一律保持圆形圆角。
///
/// **为什么按档位分而不是全局统一**：superellipse 与圆形圆角的路径差异随
/// 半径线性放大。在 4~8px 上肉眼不可辨，只有 12px 以上才读得出那种「苹果味」
/// 的连续曲率。给小控件上 squircle 是纯成本无收益——`BoxDecoration` 不支持
/// superellipse（Flutter 框架层面就没有），每个调用点都得改成 `ShapeDecoration`，
/// 而其中不少位于虚拟化时间线的重建热路径上。
///
/// 另外注意 `shadcn_flutter` 的组件参数只接受 `BorderRadius`、不接受
/// `ShapeBorder`，所以 sf 渲染的表面必然保持圆形圆角。把平滑圆角限制在
/// 面板档，正好也避开了这层无法统一的混合状态。
abstract final class IdeShapes {
  /// 面板 / 侧栏 / 画布 / 浮层的平滑圆角形状。
  ///
  /// 生效位置：`IdeSurface` 的 pane / popover / canvas 级、`PanelCard`
  /// 取到 [IdeRadius.allLarge] 时。
  ///
  /// 描边通过 [side] 传入。注意 `IdeSurface` 与 `PanelCard` 把填充放在
  /// `decoration`、把描边放在 `foregroundDecoration`（不透明子树会盖住画在
  /// 下层的四角描边），所以那两处需要各构造一次：填充用默认的
  /// `BorderSide.none`，描边再传一次 [side]。
  static ShapeBorder panel({BorderSide side = BorderSide.none}) {
    return RoundedSuperellipseBorder(
      borderRadius: IdeRadius.allLarge,
      side: side,
    );
  }

  /// 控件级形状：圆形圆角，与 `BoxDecoration(borderRadius:)` 视觉等价。
  ///
  /// 供需要 `ShapeBorder` 的 API 使用；普通调用点继续直接写
  /// `BoxDecoration(borderRadius: IdeRadius.allSmall)` 即可，不必绕这里。
  static ShapeBorder control(
    BorderRadiusGeometry radius, {
    BorderSide side = BorderSide.none,
  }) {
    return RoundedRectangleBorder(borderRadius: radius, side: side);
  }

  /// 判断某个半径是否属于面板档，决定走 [panel] 还是 [control]。
  static bool isPanelTier(BorderRadiusGeometry radius) {
    return radius == IdeRadius.allLarge;
  }
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
