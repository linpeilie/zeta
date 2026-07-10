import 'package:flutter/widgets.dart';

/// IDE 设计系统圆角 token。
///
/// 全项目圆角只允许取自这四档 + 胶囊,禁止在业务代码中出现
/// 裸 `BorderRadius.circular(<数字>)`。
abstract final class IdeRadius {
  /// 行内元素:列表行、小按钮、菜单项、代码块。
  static const double small = 6;

  /// 面板卡片、输入框等主要容器。
  static const double medium = 8;

  /// 弹出层、对话框、浮层面板。
  static const double large = 12;

  /// Composer 输入面板与计划卡等大型强调卡片。
  static const double composer = 16;

  static const BorderRadius allSmall = BorderRadius.all(Radius.circular(small));
  static const BorderRadius allMedium = BorderRadius.all(
    Radius.circular(medium),
  );
  static const BorderRadius allLarge = BorderRadius.all(Radius.circular(large));
  static const BorderRadius allComposer = BorderRadius.all(
    Radius.circular(composer),
  );

  /// 胶囊标签 / 圆形按钮。
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// IDE 阴影与遮罩 token。
///
/// 阴影一律按亮度取预设,业务代码不允许手写 `BoxShadow`;
/// 需要新档位时先在这里补充。
abstract final class IdeEffects {
  /// 弹出层(菜单 / popover / 窄窗浮层面板)投影。
  static List<BoxShadow> overlayShadow(Brightness brightness) {
    return [
      BoxShadow(
        color: brightness == Brightness.dark
            ? const Color(0x59000000)
            : const Color(0x24101114),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// 键盘焦点环：无方向、无高度语义，不能与浮层阴影混用。
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
  static Color scrim(Brightness brightness) {
    return brightness == Brightness.dark
        ? const Color(0x8C060607)
        : const Color(0x3D17181A);
  }
}
