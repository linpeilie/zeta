import 'package:flutter/material.dart';

import 'app_theme.dart';

/// IDE 主题专用调色板。
///
/// 通过 [ThemeExtension] 注册到 [ThemeData]，配合 [IdeColors.of] 在运行时
/// 根据 [Brightness] 解析颜色，从而支持浅色/深色/跟随系统切换。深色调色板沿用
/// 顶层 const 颜色（如 [ideAccentColor]），以保证旧测试与历史外观一致。
@immutable
class IdeColors extends ThemeExtension<IdeColors> {
  const IdeColors({
    required this.frame,
    required this.surface,
    required this.panel,
    required this.editor,
    required this.border,
    required this.mutedText,
    required this.accent,
    required this.warning,
    required this.accentForeground,
    required this.windowHover,
    required this.windowIcon,
    required this.closeHover,
  });

  /// 窗口外框 / scaffold 背景。
  final Color frame;

  /// 卡片、浮层等次级表面。
  final Color surface;

  /// 面板背景。
  final Color panel;

  /// 中间编辑区背景。
  final Color editor;

  /// 细边框 / 分隔线。
  final Color border;

  /// 次要文本与图标。
  final Color mutedText;

  /// 主题强调色（运行中、选中态等）。
  final Color accent;

  /// 警告 / 待审批色。
  final Color warning;

  /// 处于选中/激活态时前景图标的颜色。深色下为白；浅色下使用 [accent]，
  /// 以便在浅底面板上保持可见。
  final Color accentForeground;

  /// Windows/Linux 自绘窗口按钮的悬停背景。
  final Color windowHover;

  /// Windows/Linux 自绘窗口按钮的图标颜色。
  final Color windowIcon;

  /// 关闭按钮的悬停背景（两个主题共用红色）。
  final Color closeHover;

  /// 深色调色板：沿用旧版 const 颜色，保证历史外观与测试断言不变。
  static const IdeColors dark = IdeColors(
    frame: ideFrameColor,
    surface: ideSurfaceColor,
    panel: idePanelColor,
    editor: ideEditorColor,
    border: ideBorderColor,
    mutedText: ideMutedTextColor,
    accent: ideAccentColor,
    warning: ideWarningColor,
    accentForeground: Colors.white,
    windowHover: Color(0xFF303030),
    windowIcon: Color(0xFFB8B8B8),
    closeHover: Color(0xFFD84E4E),
  );

  /// 浅色调色板：现代扁平风，以接近白的浅灰为底，低饱和绿作为强调色，
  /// 警告色加深为琥珀色以保证白底对比度。
  static const IdeColors light = IdeColors(
    frame: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    editor: Color(0xFFFBFBFC),
    border: Color(0xFFE4E6EB),
    mutedText: Color(0xFF6B7280),
    accent: Color(0xFF1E9E58),
    warning: Color(0xFFB45309),
    accentForeground: Color(0xFF1E9E58),
    windowHover: Color(0xFFEAECEF),
    windowIcon: Color(0xFF4B5563),
    closeHover: Color(0xFFD84E4E),
  );

  /// 从 [context] 取出当前主题下的 [IdeColors]。
  ///
  /// 必须在已注册该扩展的 [ThemeData] 子树中调用；缺失时回退到 [dark]，
  /// 以避免在测试或未配置场景下抛异常。
  static IdeColors of(BuildContext context) {
    final colors = Theme.of(context).extension<IdeColors>();
    return colors ?? dark;
  }

  @override
  IdeColors copyWith({
    Color? frame,
    Color? surface,
    Color? panel,
    Color? editor,
    Color? border,
    Color? mutedText,
    Color? accent,
    Color? warning,
    Color? accentForeground,
    Color? windowHover,
    Color? windowIcon,
    Color? closeHover,
  }) {
    return IdeColors(
      frame: frame ?? this.frame,
      surface: surface ?? this.surface,
      panel: panel ?? this.panel,
      editor: editor ?? this.editor,
      border: border ?? this.border,
      mutedText: mutedText ?? this.mutedText,
      accent: accent ?? this.accent,
      warning: warning ?? this.warning,
      accentForeground: accentForeground ?? this.accentForeground,
      windowHover: windowHover ?? this.windowHover,
      windowIcon: windowIcon ?? this.windowIcon,
      closeHover: closeHover ?? this.closeHover,
    );
  }

  @override
  IdeColors lerp(ThemeExtension<IdeColors>? other, double t) {
    if (other is! IdeColors) {
      return this;
    }
    return IdeColors(
      frame: Color.lerp(frame, other.frame, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      editor: Color.lerp(editor, other.editor, t)!,
      border: Color.lerp(border, other.border, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
      windowHover: Color.lerp(windowHover, other.windowHover, t)!,
      windowIcon: Color.lerp(windowIcon, other.windowIcon, t)!,
      closeHover: Color.lerp(closeHover, other.closeHover, t)!,
    );
  }
}
