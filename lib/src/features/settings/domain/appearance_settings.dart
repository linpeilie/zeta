import 'package:flutter/material.dart';

import 'package:zeta/src/core/constants/app_typography.dart';

/// 界面字号允许的最小值。
const double minUiFontSize = 10;

/// 界面字号允许的最大值。
const double maxUiFontSize = 20;

/// 代码字号允许的最小值。
const double minCodeFontSize = 10;

/// 代码字号允许的最大值。
const double maxCodeFontSize = 24;

/// 字体选择来源。
enum AppearanceFontChoiceKind { systemDefault, system, bundledJetBrainsMono }

/// 单个字体设置项。
@immutable
class AppearanceFontChoice {
  const AppearanceFontChoice.systemDefault()
    : kind = AppearanceFontChoiceKind.systemDefault,
      fontFamily = null;

  const AppearanceFontChoice.system(this.fontFamily)
    : kind = AppearanceFontChoiceKind.system,
      assert(fontFamily != '');

  const AppearanceFontChoice.bundledJetBrainsMono()
    : kind = AppearanceFontChoiceKind.bundledJetBrainsMono,
      fontFamily = bundledCodeFontFamily;

  final AppearanceFontChoiceKind kind;
  final String? fontFamily;

  bool get isSystemDefault => kind == AppearanceFontChoiceKind.systemDefault;

  bool get isSystemFont => kind == AppearanceFontChoiceKind.system;

  bool get isBundledJetBrainsMono =>
      kind == AppearanceFontChoiceKind.bundledJetBrainsMono;

  /// 稳定标识，供测试 key 和缓存使用。
  String get stableId => switch (kind) {
    AppearanceFontChoiceKind.systemDefault => 'system-default',
    AppearanceFontChoiceKind.system => 'system-${fontFamily ?? ''}',
    AppearanceFontChoiceKind.bundledJetBrainsMono => 'bundled-jetbrains-mono',
  };

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': switch (kind) {
        AppearanceFontChoiceKind.systemDefault => 'systemDefault',
        AppearanceFontChoiceKind.system => 'system',
        AppearanceFontChoiceKind.bundledJetBrainsMono => 'bundledJetBrainsMono',
      },
      if (fontFamily != null) 'fontFamily': fontFamily,
    };
  }

  static AppearanceFontChoice tryDecode(
    Object? raw, {
    required AppearanceFontChoice fallback,
  }) {
    if (raw is! Map) {
      return fallback;
    }
    final map = Map<Object?, Object?>.from(raw);
    final kind = map['kind'];
    final fontFamily = map['fontFamily'];
    return switch (kind) {
      'systemDefault' => const AppearanceFontChoice.systemDefault(),
      'system' when fontFamily is String && fontFamily.isNotEmpty =>
        AppearanceFontChoice.system(fontFamily),
      'bundledJetBrainsMono' =>
        const AppearanceFontChoice.bundledJetBrainsMono(),
      _ => fallback,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AppearanceFontChoice &&
        other.kind == kind &&
        other.fontFamily == fontFamily;
  }

  @override
  int get hashCode => Object.hash(kind, fontFamily);
}

/// 全局外观设置。
@immutable
class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.uiFontChoice = const AppearanceFontChoice.systemDefault(),
    this.codeFontChoice = const AppearanceFontChoice.bundledJetBrainsMono(),
    this.uiFontSize = defaultUiFontSize,
    this.codeFontSize = defaultCodeFontSize,
  }) : assert(uiFontSize >= minUiFontSize && uiFontSize <= maxUiFontSize),
       assert(
         codeFontSize >= minCodeFontSize && codeFontSize <= maxCodeFontSize,
       );

  final ThemeMode themeMode;
  final AppearanceFontChoice uiFontChoice;
  final AppearanceFontChoice codeFontChoice;

  /// 普通界面文本的基准字号，其他界面排版 token 按比例缩放。
  final double uiFontSize;

  /// 代码正文的基准字号，较小代码 token 按比例缩放。
  final double codeFontSize;

  String? get uiFontFamily =>
      uiFontChoice.isSystemFont ? uiFontChoice.fontFamily : null;

  String get codeFontFamily => codeFontChoice.isSystemFont
      ? codeFontChoice.fontFamily!
      : bundledCodeFontFamily;

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    AppearanceFontChoice? uiFontChoice,
    AppearanceFontChoice? codeFontChoice,
    double? uiFontSize,
    double? codeFontSize,
  }) {
    return AppearanceSettings(
      themeMode: themeMode ?? this.themeMode,
      uiFontChoice: uiFontChoice ?? this.uiFontChoice,
      codeFontChoice: codeFontChoice ?? this.codeFontChoice,
      uiFontSize: uiFontSize ?? this.uiFontSize,
      codeFontSize: codeFontSize ?? this.codeFontSize,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': 1,
      'themeMode': switch (themeMode) {
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
      },
      'uiFontChoice': uiFontChoice.toJson(),
      'codeFontChoice': codeFontChoice.toJson(),
      'uiFontSize': uiFontSize,
      'codeFontSize': codeFontSize,
    };
  }

  static AppearanceSettings tryDecode(Object? raw) {
    if (raw is! Map) {
      return const AppearanceSettings();
    }
    final map = Map<Object?, Object?>.from(raw);
    if (map['version'] != 1) {
      return const AppearanceSettings();
    }
    return AppearanceSettings(
      themeMode: _parseThemeMode(map['themeMode']),
      uiFontChoice: AppearanceFontChoice.tryDecode(
        map['uiFontChoice'],
        fallback: const AppearanceFontChoice.systemDefault(),
      ),
      codeFontChoice: AppearanceFontChoice.tryDecode(
        map['codeFontChoice'],
        fallback: const AppearanceFontChoice.bundledJetBrainsMono(),
      ),
      uiFontSize: _parseFontSize(
        map['uiFontSize'],
        fallback: defaultUiFontSize,
        min: minUiFontSize,
        max: maxUiFontSize,
      ),
      codeFontSize: _parseFontSize(
        map['codeFontSize'],
        fallback: defaultCodeFontSize,
        min: minCodeFontSize,
        max: maxCodeFontSize,
      ),
    );
  }

  static AppearanceSettings fromLegacyThemeMode(String? rawThemeMode) {
    return AppearanceSettings(themeMode: _parseThemeMode(rawThemeMode));
  }

  static ThemeMode _parseThemeMode(Object? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.system,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AppearanceSettings &&
        other.themeMode == themeMode &&
        other.uiFontChoice == uiFontChoice &&
        other.codeFontChoice == codeFontChoice &&
        other.uiFontSize == uiFontSize &&
        other.codeFontSize == codeFontSize;
  }

  @override
  int get hashCode => Object.hash(
    themeMode,
    uiFontChoice,
    codeFontChoice,
    uiFontSize,
    codeFontSize,
  );
}

double _parseFontSize(
  Object? raw, {
  required double fallback,
  required double min,
  required double max,
}) {
  if (raw is! num) {
    return fallback;
  }
  final value = raw.toDouble();
  return value.isFinite && value >= min && value <= max ? value : fallback;
}
