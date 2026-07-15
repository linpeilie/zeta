import 'package:flutter/material.dart';

import 'app_theme.dart';

const _sharedCloseHoverColor = Color(0xFFE5484D);

/// IDE 主题专用调色板。
///
/// 这组颜色完全由 Graphite token 定义，并通过 [IdeThemeScope] 在运行时解析。
/// 深色调色板中的 accent / warning 直接复用顶层真值常量（[ideAccentColor] /
/// [ideWarningColor]）。
@immutable
class IdeColors {
  const IdeColors({
    required this.frame,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceOverlay,
    required this.panel,
    required this.editor,
    required this.border,
    required this.borderSubtle,
    required this.mutedText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.primaryMuted,
    required this.warning,
    required this.error,
    required this.success,
    required this.info,
    required this.accentForeground,
    required this.onAccent,
    required this.windowHover,
    required this.windowIcon,
    required this.closeHover,
  });

  /// 窗口外框 / scaffold 背景。
  final Color frame;

  /// 卡片、浮层等次级表面。
  final Color surface;

  /// 抬升一层的表面色，用于面板、Toast 等容器。
  final Color surfaceElevated;

  /// 最上层浮层背景，用于 popover、dialog 等覆盖层。
  final Color surfaceOverlay;

  /// 面板背景。保留旧字段以兼容历史调用。
  final Color panel;

  /// 中间编辑区背景。保留旧字段以兼容历史调用。
  final Color editor;

  /// 常规边框 / 分隔线。
  final Color border;

  /// 低对比度边框，用于弱化层级。
  final Color borderSubtle;

  /// 次要文本与图标。保留旧字段以兼容历史调用。
  final Color mutedText;

  /// 主文本颜色。
  final Color textPrimary;

  /// 次级文本 / 标签颜色。
  final Color textSecondary;

  /// 三级文本 / 占位符 / 禁用态颜色。
  final Color textTertiary;

  /// 主题强调色（运行中、选中态等）。
  final Color accent;

  /// 主强调色的弱化背景，用于 selected 态。
  final Color primaryMuted;

  /// 警告 / 待审批色。
  final Color warning;

  /// 错误 / destructive 色。
  final Color error;

  /// 成功色。
  final Color success;

  /// 信息色。
  final Color info;

  /// 选中/激活态落在浅底或 [primaryMuted] 上时的前景色（图标/标签）。
  ///
  /// 深色下为白；浅色下使用 [accent]，以便在浅底面板上保持可见。
  /// 不要用于实心 [accent] 填充上的文字——那种场景用 [onAccent]。
  final Color accentForeground;

  /// 落在实心 [accent] 填充上的前景色（Primary 按钮文字/图标等）。
  ///
  /// 深浅主题均为高对比白色，与 [accentForeground]（选中态强调色）语义分离。
  final Color onAccent;

  /// Windows/Linux 自绘窗口按钮的悬停背景。
  final Color windowHover;

  /// Windows/Linux 自绘窗口按钮的图标颜色。
  final Color windowIcon;

  /// 关闭按钮的悬停背景（两个主题共用红色）。
  final Color closeHover;

  /// 深色调色板「Graphite Night」：中性石墨底 + 蔚蓝强调，
  /// 无色相偏移的灰阶层次，长时间注视友好。
  static const IdeColors dark = IdeColors(
    frame: Color(0xFF0A0A0B),
    surface: Color(0xFF18191B),
    surfaceElevated: Color(0xFF212225),
    surfaceOverlay: Color(0xFF2C2D30),
    panel: Color(0xFF18191B),
    editor: Color(0xFF141517),
    border: Color(0xFF2C2D31),
    borderSubtle: Color(0xFF212225),
    mutedText: Color(0xFF9EA1A7),
    textPrimary: Color(0xFFECEDEF),
    textSecondary: Color(0xFF9EA1A7),
    textTertiary: Color(0xFF63666C),
    accent: ideAccentColor,
    primaryMuted: Color(0x521B84FF),
    warning: ideWarningColor,
    error: Color(0xFFF0616B),
    success: Color(0xFF4EC583),
    info: Color(0xFF55A8F5),
    accentForeground: Colors.white,
    onAccent: Colors.white,
    windowHover: Color(0xFF2A2B2E),
    windowIcon: Color(0xFFA6A9AE),
    closeHover: _sharedCloseHoverColor,
  );

  /// 浅色调色板「Graphite Day」：中性浅灰白底 + 蔚蓝强调，扁平清爽，
  /// 与深色主题共享同一套语义层级。
  static const IdeColors light = IdeColors(
    // frame: Color(0xFFEEEFF1),
    // surface: Color(0xFFFFFFFF),
    frame: Color(0xFFFFFFFF),
    surface: Color(0xFFF9F9FA),
    surfaceElevated: Color(0xFFF4F5F7),
    surfaceOverlay: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    editor: Color(0xFFFAFAFB),
    border: Color(0xFFE4E5E9),
    borderSubtle: Color(0xFFEFF0F2),
    mutedText: Color(0xFF5B5E66),
    textPrimary: Color(0xFF1C1D1F),
    textSecondary: Color(0xFF5B5E66),
    textTertiary: Color(0xFF8F929B),
    accent: Color(0xFF0B76D8),
    primaryMuted: Color(0x3D0B76D8),
    warning: Color(0xFFB45309),
    error: Color(0xFFDE3B4E),
    success: Color(0xFF178A50),
    info: Color(0xFF1173CF),
    accentForeground: Color(0xFF0B76D8),
    onAccent: Colors.white,
    windowHover: Color(0xFFE1E2E6),
    windowIcon: Color(0xFF5B5E66),
    closeHover: _sharedCloseHoverColor,
  );

  /// 从 [context] 取出当前主题下的 [IdeColors]。
  static IdeColors of(BuildContext context) {
    return IdeThemeScope.of(context).colors;
  }

  IdeColors copyWith({
    Color? frame,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceOverlay,
    Color? panel,
    Color? editor,
    Color? border,
    Color? borderSubtle,
    Color? mutedText,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? primaryMuted,
    Color? warning,
    Color? error,
    Color? success,
    Color? info,
    Color? accentForeground,
    Color? onAccent,
    Color? windowHover,
    Color? windowIcon,
    Color? closeHover,
  }) {
    final resolvedTextSecondary =
        textSecondary ?? mutedText ?? this.textSecondary;
    final resolvedMutedText = mutedText ?? textSecondary ?? this.mutedText;
    return IdeColors(
      frame: frame ?? this.frame,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      panel: panel ?? this.panel,
      editor: editor ?? this.editor,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      mutedText: resolvedMutedText,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: resolvedTextSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      primaryMuted: primaryMuted ?? this.primaryMuted,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      success: success ?? this.success,
      info: info ?? this.info,
      accentForeground: accentForeground ?? this.accentForeground,
      onAccent: onAccent ?? this.onAccent,
      windowHover: windowHover ?? this.windowHover,
      windowIcon: windowIcon ?? this.windowIcon,
      closeHover: closeHover ?? this.closeHover,
    );
  }

  IdeColors lerp(IdeColors other, double t) {
    return IdeColors(
      frame: Color.lerp(frame, other.frame, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      editor: Color.lerp(editor, other.editor, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      primaryMuted: Color.lerp(primaryMuted, other.primaryMuted, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      windowHover: Color.lerp(windowHover, other.windowHover, t)!,
      windowIcon: Color.lerp(windowIcon, other.windowIcon, t)!,
      closeHover: Color.lerp(closeHover, other.closeHover, t)!,
    );
  }
}
