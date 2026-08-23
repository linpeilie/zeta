import 'package:flutter/material.dart' show ThemeMode;

import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// `ZetaThemeModePreference` ↔ Flutter `ThemeMode` 的双向映射。
///
/// 映射只允许出现在 presentation / app 层（domain 与 application 不得
/// 命名 Flutter 类型，§12.5）。
ThemeMode themeModeForPreference(ZetaThemeModePreference preference) {
  return switch (preference) {
    ZetaThemeModePreference.system => ThemeMode.system,
    ZetaThemeModePreference.light => ThemeMode.light,
    ZetaThemeModePreference.dark => ThemeMode.dark,
  };
}

ZetaThemeModePreference preferenceForThemeMode(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => ZetaThemeModePreference.system,
    ThemeMode.light => ZetaThemeModePreference.light,
    ThemeMode.dark => ZetaThemeModePreference.dark,
  };
}
