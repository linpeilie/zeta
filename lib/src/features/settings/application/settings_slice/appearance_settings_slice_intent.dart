import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/appearance_font_option.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// appearance 切片的意图。
///
/// 命令类意图携带 [OperationId]，由 store 在 dispatch 前铸造（G3：reducer
/// 不铸造身份）。变体按「发生的事」命名（Phase 1 §3）。
sealed class AppearanceSettingsSliceIntent {
  const AppearanceSettingsSliceIntent();
}

/// 请求载入持久化的外观偏好（重复 load 由 store 侧记忆化挡住）。
final class AppearanceSettingsLoadRequested
    extends AppearanceSettingsSliceIntent {
  const AppearanceSettingsLoadRequested();
}

/// 载入完成；损坏 / 版本不符时 runner 已按现状回落默认值。
final class AppearanceSettingsLoaded extends AppearanceSettingsSliceIntent {
  const AppearanceSettingsLoaded(this.value);

  final AppearanceSettingsSlice value;
}

/// 选择主题模式。**乐观语义**（现状语义 A）：reducer 立即应用，持久化失败
/// 只产生诊断回执、不回滚状态。
final class AppearanceThemeModeSelected extends AppearanceSettingsSliceIntent {
  const AppearanceThemeModeSelected(this.operationId, this.mode);

  final OperationId operationId;
  final ZetaThemeModePreference mode;
}

/// 调整界面基准字号；非法输入（非有限值）不产生任何转移。
final class AppearanceUiFontSizeAdjusted extends AppearanceSettingsSliceIntent {
  const AppearanceUiFontSizeAdjusted(this.operationId, this.value);

  final OperationId operationId;
  final double value;
}

/// 调整代码基准字号；非法输入不产生任何转移。
final class AppearanceCodeFontSizeAdjusted
    extends AppearanceSettingsSliceIntent {
  const AppearanceCodeFontSizeAdjusted(this.operationId, this.value);

  final OperationId operationId;
  final double value;
}

/// 选择界面字体。**先解析后应用**（现状）：系统字体须经字体目录解析，
/// bundled 字体对界面槽位是非法选择——reducer 只登记在途身份并产出解析
/// effect，解析成功经 [AppearanceFontChoiceResolved] 回流后才应用。
final class AppearanceUiFontChoiceSelected
    extends AppearanceSettingsSliceIntent {
  const AppearanceUiFontChoiceSelected(this.operationId, this.choice);

  final OperationId operationId;
  final AppearanceFontChoice choice;
}

/// 选择代码字体（必须等宽）。语义同上。
final class AppearanceCodeFontChoiceSelected
    extends AppearanceSettingsSliceIntent {
  const AppearanceCodeFontChoiceSelected(this.operationId, this.choice);

  final OperationId operationId;
  final AppearanceFontChoice choice;
}

/// 字体解析成功（runner 回流）。槽位在途身份对不上即为迟到结果。
final class AppearanceFontChoiceResolved extends AppearanceSettingsSliceIntent {
  const AppearanceFontChoiceResolved({
    required this.operationId,
    required this.forCodeFont,
    required this.resolved,
  });

  final OperationId operationId;
  final bool forCodeFont;
  final AppearanceFontChoice resolved;
}

/// 字体解析被拒绝（无法解析 / 非等宽 / 槽位不允许的 kind）。
final class AppearanceFontChoiceRejected extends AppearanceSettingsSliceIntent {
  const AppearanceFontChoiceRejected(this.operationId);

  final OperationId operationId;
}

/// 请求载入字体目录选项（界面 / 代码槽位）。
///
/// 目录是 OS 只读投影：请求幂等、可重复发起，最后一次结果生效。
final class AppearanceFontCatalogRequested
    extends AppearanceSettingsSliceIntent {
  const AppearanceFontCatalogRequested({required this.forCodeFont});

  final bool forCodeFont;
}

/// 字体目录载入完成；失败时 runner 以空列表回执（弹层显示为空而非报错）。
final class AppearanceFontCatalogLoaded extends AppearanceSettingsSliceIntent {
  const AppearanceFontCatalogLoaded({
    required this.forCodeFont,
    required this.options,
    required this.displayNames,
  });

  final bool forCodeFont;
  final List<AppearanceFontOption> options;
  final Map<String, String> displayNames;
}

/// persist 成功回执。语义 A 下不改变状态（值早已应用）。
final class AppearanceSettingsPersisted extends AppearanceSettingsSliceIntent {
  const AppearanceSettingsPersisted(this.operationId);

  final OperationId operationId;
}

/// persist 失败回执。**语义 A：状态不回滚**，与现状「内存已更新、失败仅
/// 记日志」一致；诊断由 runner 记入脱敏日志。
final class AppearanceSettingsPersistFailed
    extends AppearanceSettingsSliceIntent {
  const AppearanceSettingsPersistFailed(this.operationId);

  final OperationId operationId;
}
