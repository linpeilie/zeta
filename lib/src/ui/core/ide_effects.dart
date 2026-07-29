import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// IDE 设计系统圆角 token。
///
/// 全项目圆角只允许取自这四档 + 胶囊，禁止在业务代码中出现
/// 裸 `BorderRadius.circular(<数字>)`。需要新档位时先在这里补充。
abstract final class IdeRadius {
  /// 行内元素圆角：列表行、小按钮、菜单项、代码块、Tab、Activity Rail 项。
  ///
  /// 生效位置：`IdeListRow` / `PaneInteractiveSurface` 默认小圆角、
  /// `IdeContextMenu` 菜单项、`IdeTabs`/`IdeActivityRail`、窗口控制按钮、
  /// Markdown 代码块/引用、模型配置下拉项、Composer 内小控件等
  /// （多通过 [allSmall] 引用）。
  static const double small = 6;

  /// 面板卡片、输入框、状态卡等主要容器圆角。
  ///
  /// 生效位置：`IdeChoiceCard`、`IdeStatusCard`、`IdeToast`、Composer 外卡、
  /// 消息气泡、`IdeSurface` 的 pane 级、workbench 窄屏浮层面板、
  /// `PaneCard` 默认等（多通过 [allMedium] 引用）。
  static const double medium = 8;

  /// 弹出层、对话框、浮层面板圆角。
  ///
  /// 生效位置：Provider 选择 Popover、`IdeSurface` 的 popover 级
  /// （多通过 [allLarge] 引用）。
  static const double large = 12;

  /// 历史：大型强调卡片（Composer）曾用此档。
  ///
  /// Composer 已统一改用 [medium] / [allMedium]；本值保留兼容，
  /// 请勿在新代码中使用。
  static const double composer = 16;

  /// [small] 的四向 `BorderRadius`。
  static const BorderRadius allSmall = BorderRadius.all(Radius.circular(small));

  /// [medium] 的四向 `BorderRadius`。
  static const BorderRadius allMedium = BorderRadius.all(
    Radius.circular(medium),
  );

  /// [large] 的四向 `BorderRadius`。
  static const BorderRadius allLarge = BorderRadius.all(Radius.circular(large));

  @Deprecated('Composer 已统一使用 IdeRadius.allMedium')
  static const BorderRadius allComposer = BorderRadius.all(
    Radius.circular(composer),
  );

  /// 胶囊标签 / 圆形按钮：足够大的半径，实际表现为 pill。
  ///
  /// 生效位置：状态徽章、圆形图标按钮等需要全圆角的控件。
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// IDE 阴影与遮罩 token。
///
/// 阴影一律按亮度取预设，业务代码不允许手写 `BoxShadow`；
/// 需要新档位时先在这里补充。
abstract final class IdeEffects {
  /// 弹出层（菜单 / popover / 窄窗浮层面板 / Toast）投影。
  ///
  /// 生效位置：`IdeSurface` popover 级、`IdeToast`、`IdeWorkbenchScaffold`
  /// 窄屏浮层侧栏、项目列表 Provider 选择 Popover 等。
  static List<BoxShadow> overlayShadow(Brightness brightness) {
    return [
      BoxShadow(
        color: brightness == Brightness.dark
            ? sf.Colors.black.withValues(alpha: 0.35)
            : sf.Colors.zinc[900].withValues(alpha: 0.14),
        blurRadius: 24,
        offset: const Offset(0, 8),
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
