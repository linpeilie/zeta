import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_theme.dart';

const _lightForegroundColor = Color(0xFF111827);
const _darkForegroundColor = Color(0xFFE8E8E8);
const _darkSurfaceElevatedColor = Color(0xFF222222);
const _lightSurfaceElevatedColor = Color(0xFFFBFBFC);
const _darkSurfaceOverlayColor = Color(0xFF282828);
const _lightSurfaceOverlayColor = Color(0xFFFFFFFF);
const _darkBorderSubtleColor = Color(0xFF252525);
const _lightBorderSubtleColor = Color(0xFFECEEF2);
const _darkTextTertiaryColor = Color(0xFF6B7280);
const _lightTextTertiaryColor = Color(0xFF9CA3AF);
const _darkErrorColor = Color(0xFFE06C75);
const _lightErrorColor = Color(0xFFDC2626);
const _darkInfoColor = Color(0xFF5B9BD5);
const _lightInfoColor = Color(0xFF2B7AC5);
const _darkPrimaryMutedColor = Color(0x2E4FB286);
const _lightPrimaryMutedColor = Color(0x1A1E9E58);
const _darkWindowHoverColor = Color(0xFF303030);
const _lightWindowHoverColor = Color(0xFFEAECEF);
const _darkWindowIconColor = Color(0xFFB8B8B8);
const _lightWindowIconColor = Color(0xFF4B5563);
const _sharedCloseHoverColor = Color(0xFFD84E4E);

abstract final class _IdeColorSchemeCustomKeys {
  static const frame = 'frame';
  static const surface = 'surface';
  static const surfaceElevated = 'surfaceElevated';
  static const surfaceOverlay = 'surfaceOverlay';
  static const panel = 'panel';
  static const editor = 'editor';
  static const borderSubtle = 'borderSubtle';
  static const mutedText = 'mutedText';
  static const textPrimary = 'textPrimary';
  static const textSecondary = 'textSecondary';
  static const textTertiary = 'textTertiary';
  static const warning = 'warning';
  static const error = 'error';
  static const success = 'success';
  static const info = 'info';
  static const primaryMuted = 'primaryMuted';
  static const windowHover = 'windowHover';
  static const windowIcon = 'windowIcon';
  static const closeHover = 'closeHover';
}

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
    surfaceElevated: _darkSurfaceElevatedColor,
    surfaceOverlay: _darkSurfaceOverlayColor,
    panel: idePanelColor,
    editor: ideEditorColor,
    border: ideBorderColor,
    borderSubtle: _darkBorderSubtleColor,
    mutedText: ideMutedTextColor,
    textPrimary: _darkForegroundColor,
    textSecondary: ideMutedTextColor,
    textTertiary: _darkTextTertiaryColor,
    accent: ideAccentColor,
    primaryMuted: _darkPrimaryMutedColor,
    warning: ideWarningColor,
    error: _darkErrorColor,
    success: ideAccentColor,
    info: _darkInfoColor,
    accentForeground: Colors.white,
    windowHover: _darkWindowHoverColor,
    windowIcon: _darkWindowIconColor,
    closeHover: _sharedCloseHoverColor,
  );

  /// 浅色调色板：现代扁平风，以接近白的浅灰为底，低饱和绿作为强调色，
  /// 警告色加深为琥珀色以保证白底对比度。
  static const IdeColors light = IdeColors(
    frame: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: _lightSurfaceElevatedColor,
    surfaceOverlay: _lightSurfaceOverlayColor,
    panel: Color(0xFFFFFFFF),
    editor: Color(0xFFFBFBFC),
    border: Color(0xFFE4E6EB),
    borderSubtle: _lightBorderSubtleColor,
    mutedText: Color(0xFF6B7280),
    textPrimary: _lightForegroundColor,
    textSecondary: Color(0xFF6B7280),
    textTertiary: _lightTextTertiaryColor,
    accent: Color(0xFF1E9E58),
    primaryMuted: _lightPrimaryMutedColor,
    warning: Color(0xFFB45309),
    error: _lightErrorColor,
    success: Color(0xFF1E9E58),
    info: _lightInfoColor,
    accentForeground: Color(0xFF1E9E58),
    windowHover: _lightWindowHoverColor,
    windowIcon: _lightWindowIconColor,
    closeHover: _sharedCloseHoverColor,
  );

  /// 从 [context] 取出当前主题下的 [IdeColors]。
  ///
  /// 运行时优先从 [ShadTheme] 解析；仅在旧测试或兼容场景下回退到
  /// Material ThemeExtension。
  static IdeColors of(BuildContext context) {
    final shadTheme = ShadTheme.maybeOf(context, listen: false);
    if (shadTheme != null) {
      return ideColorsFromShadTheme(shadTheme);
    }

    final materialTheme = Theme.of(context);
    final colors = materialTheme.extension<IdeColors>();
    if (colors != null) {
      return colors;
    }

    return materialTheme.brightness == Brightness.light ? light : dark;
  }

  @override
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
      windowHover: Color.lerp(windowHover, other.windowHover, t)!,
      windowIcon: Color.lerp(windowIcon, other.windowIcon, t)!,
      closeHover: Color.lerp(closeHover, other.closeHover, t)!,
    );
  }
}

/// 将 [IdeColors] 语义映射到 shadcn 颜色系统，并通过 custom 透传扩展 token。
ShadColorScheme shadColorSchemeFromIdeColors(
  IdeColors colors, {
  required Brightness brightness,
}) {
  return ShadColorScheme(
    background: colors.frame,
    foreground: colors.textPrimary,
    card: colors.surface,
    cardForeground: colors.textPrimary,
    popover: colors.surfaceOverlay,
    popoverForeground: colors.textPrimary,
    primary: colors.accent,
    primaryForeground: colors.accentForeground,
    secondary: colors.surfaceElevated,
    secondaryForeground: colors.textPrimary,
    muted: colors.surfaceElevated,
    mutedForeground: colors.textSecondary,
    accent: colors.accent,
    accentForeground: colors.accentForeground,
    destructive: colors.error,
    destructiveForeground: Colors.white,
    border: colors.border,
    input: colors.borderSubtle,
    ring: colors.accent,
    selection: colors.primaryMuted,
    custom: <String, Color>{
      _IdeColorSchemeCustomKeys.frame: colors.frame,
      _IdeColorSchemeCustomKeys.surface: colors.surface,
      _IdeColorSchemeCustomKeys.surfaceElevated: colors.surfaceElevated,
      _IdeColorSchemeCustomKeys.surfaceOverlay: colors.surfaceOverlay,
      _IdeColorSchemeCustomKeys.panel: colors.panel,
      _IdeColorSchemeCustomKeys.editor: colors.editor,
      _IdeColorSchemeCustomKeys.borderSubtle: colors.borderSubtle,
      _IdeColorSchemeCustomKeys.mutedText: colors.mutedText,
      _IdeColorSchemeCustomKeys.textPrimary: colors.textPrimary,
      _IdeColorSchemeCustomKeys.textSecondary: colors.textSecondary,
      _IdeColorSchemeCustomKeys.textTertiary: colors.textTertiary,
      _IdeColorSchemeCustomKeys.warning: colors.warning,
      _IdeColorSchemeCustomKeys.error: colors.error,
      _IdeColorSchemeCustomKeys.success: colors.success,
      _IdeColorSchemeCustomKeys.info: colors.info,
      _IdeColorSchemeCustomKeys.primaryMuted: colors.primaryMuted,
      _IdeColorSchemeCustomKeys.windowHover: colors.windowHover,
      _IdeColorSchemeCustomKeys.windowIcon: colors.windowIcon,
      _IdeColorSchemeCustomKeys.closeHover: colors.closeHover,
    },
  );
}

/// 从 [ShadThemeData] 中提取等价的 [IdeColors]。
IdeColors ideColorsFromShadTheme(ShadThemeData theme) {
  return ideColorsFromShadColorScheme(
    theme.colorScheme,
    brightness: theme.brightness,
  );
}

/// 从 [ShadColorScheme] 中提取等价的 [IdeColors]。
IdeColors ideColorsFromShadColorScheme(
  ShadColorScheme scheme, {
  required Brightness brightness,
}) {
  final custom = scheme.custom;
  final surfaceElevated =
      custom[_IdeColorSchemeCustomKeys.surfaceElevated] ?? scheme.muted;
  final surfaceOverlay =
      custom[_IdeColorSchemeCustomKeys.surfaceOverlay] ?? scheme.popover;
  final textSecondary =
      custom[_IdeColorSchemeCustomKeys.textSecondary] ?? scheme.mutedForeground;
  return IdeColors(
    frame: custom[_IdeColorSchemeCustomKeys.frame] ?? scheme.background,
    surface: custom[_IdeColorSchemeCustomKeys.surface] ?? scheme.card,
    surfaceElevated: surfaceElevated,
    surfaceOverlay: surfaceOverlay,
    panel: custom[_IdeColorSchemeCustomKeys.panel] ?? surfaceElevated,
    editor: custom[_IdeColorSchemeCustomKeys.editor] ?? surfaceElevated,
    border: scheme.border,
    borderSubtle:
        custom[_IdeColorSchemeCustomKeys.borderSubtle] ?? scheme.input,
    mutedText: custom[_IdeColorSchemeCustomKeys.mutedText] ?? textSecondary,
    textPrimary:
        custom[_IdeColorSchemeCustomKeys.textPrimary] ?? scheme.foreground,
    textSecondary: textSecondary,
    textTertiary:
        custom[_IdeColorSchemeCustomKeys.textTertiary] ??
        _textTertiaryForBrightness(brightness),
    accent: scheme.primary,
    primaryMuted:
        custom[_IdeColorSchemeCustomKeys.primaryMuted] ?? scheme.selection,
    warning:
        custom[_IdeColorSchemeCustomKeys.warning] ??
        _warningForBrightness(brightness),
    error: custom[_IdeColorSchemeCustomKeys.error] ?? scheme.destructive,
    success: custom[_IdeColorSchemeCustomKeys.success] ?? scheme.primary,
    info:
        custom[_IdeColorSchemeCustomKeys.info] ??
        _infoForBrightness(brightness),
    accentForeground: scheme.primaryForeground,
    windowHover:
        custom[_IdeColorSchemeCustomKeys.windowHover] ??
        _windowHoverForBrightness(brightness),
    windowIcon:
        custom[_IdeColorSchemeCustomKeys.windowIcon] ??
        _windowIconForBrightness(brightness),
    closeHover:
        custom[_IdeColorSchemeCustomKeys.closeHover] ?? _sharedCloseHoverColor,
  );
}

Color _infoForBrightness(Brightness brightness) {
  return brightness == Brightness.dark ? _darkInfoColor : _lightInfoColor;
}

Color _textTertiaryForBrightness(Brightness brightness) {
  return brightness == Brightness.dark
      ? _darkTextTertiaryColor
      : _lightTextTertiaryColor;
}

Color _warningForBrightness(Brightness brightness) {
  return brightness == Brightness.dark
      ? ideWarningColor
      : IdeColors.light.warning;
}

Color _windowHoverForBrightness(Brightness brightness) {
  return brightness == Brightness.dark
      ? _darkWindowHoverColor
      : _lightWindowHoverColor;
}

Color _windowIconForBrightness(Brightness brightness) {
  return brightness == Brightness.dark
      ? _darkWindowIconColor
      : _lightWindowIconColor;
}
