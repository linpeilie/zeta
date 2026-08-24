import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// appearance 切片的副作用描述（只是描述，不执行）。
///
/// 执行由组合层的 runner 完成：它持有 `AppearanceSettingsStore` 与
/// `SystemFontCatalogService`，并负责 `ThemeMode ↔ ZetaThemeModePreference`
/// 的双向映射（application 层不得命名 Flutter 类型）。
sealed class AppearanceSettingsSliceEffect {
  const AppearanceSettingsSliceEffect();
}

/// 从 data store 载入偏好，并按现状完成存储字体目录校验（不可解析回落
/// 默认并尽力回写；目录暂不可用时保留用户设置）。
final class AppearanceSettingsLoadEffect extends AppearanceSettingsSliceEffect {
  const AppearanceSettingsLoadEffect();
}

/// 原子持久化完整外观偏好。失败时回执 [AppearanceSettingsSliceIntent] 的
/// `AppearanceSettingsPersistFailed`（语义 A：不回滚内存值）。
final class AppearanceSettingsPersistEffect
    extends AppearanceSettingsSliceEffect {
  const AppearanceSettingsPersistEffect({
    required this.operationId,
    required this.previousValue,
    required this.value,
  });

  final OperationId operationId;
  final AppearanceSettingsSlice previousValue;
  final AppearanceSettingsSlice value;
}

/// 载入字体目录选项（界面 / 代码槽位）。
///
/// runner 经 `SystemFontCatalogService` 读取；失败时以空列表回执
/// `AppearanceFontCatalogLoaded`，弹层显示为空而非报错。
final class AppearanceFontCatalogLoadEffect
    extends AppearanceSettingsSliceEffect {
  const AppearanceFontCatalogLoadEffect({required this.forCodeFont});

  final bool forCodeFont;
}

/// 经系统字体目录解析字体选择（代码槽位要求等宽）。
///
/// kind 规则由 runner 执行，与现状一致：界面槽位拒绝 bundled、代码槽位
/// 拒绝 systemDefault；解析成功回执 `AppearanceFontChoiceResolved`，失败或
/// 拒绝回执 `AppearanceFontChoiceRejected`。
final class AppearanceFontChoiceResolveEffect
    extends AppearanceSettingsSliceEffect {
  const AppearanceFontChoiceResolveEffect({
    required this.operationId,
    required this.forCodeFont,
    required this.choice,
  });

  final OperationId operationId;
  final bool forCodeFont;
  final AppearanceFontChoice choice;
}
