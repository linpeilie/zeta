import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// `AppearanceSettings` ↔ [AppearanceSettingsSlice] 的双向转换。
///
/// domain 纯化后两者字段一一对应（`themeMode` 已是同一枚举），这里只是
/// 逐字段搬运；跨层使用（app runner / presentation ingress）都不会引入
/// Flutter 类型。
AppearanceSettingsSlice appearanceSliceFromSettings(AppearanceSettings value) {
  return AppearanceSettingsSlice(
    themeMode: value.themeMode,
    uiFontChoice: value.uiFontChoice,
    codeFontChoice: value.codeFontChoice,
    uiFontSize: value.uiFontSize,
    codeFontSize: value.codeFontSize,
  );
}

AppearanceSettings appearanceSettingsFromSlice(AppearanceSettingsSlice value) {
  return AppearanceSettings(
    themeMode: value.themeMode,
    uiFontChoice: value.uiFontChoice,
    codeFontChoice: value.codeFontChoice,
    uiFontSize: value.uiFontSize,
    codeFontSize: value.codeFontSize,
  );
}
