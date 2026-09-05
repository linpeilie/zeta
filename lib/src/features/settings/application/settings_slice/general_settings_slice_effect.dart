import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general 切片的副作用描述（只是描述，不执行）。
sealed class GeneralSettingsSliceEffect {
  const GeneralSettingsSliceEffect();
}

/// 从 data store 载入设置（codec 宽容解码在 data 层完成）。
final class GeneralSettingsLoadEffect extends GeneralSettingsSliceEffect {
  const GeneralSettingsLoadEffect();
}

/// 持久化完整设置值（persist-first：成功回执 `GeneralSettingsPersisted`
/// 后状态才应用；失败回执 `GeneralSettingsPersistFailed`）。
///
/// runner 必须以单写者串行执行这些 effect（等价现有 controller 的
/// `_enqueue` 队列），保证落盘顺序与提交顺序一致。
final class GeneralSettingsPersistEffect extends GeneralSettingsSliceEffect {
  const GeneralSettingsPersistEffect({
    required this.operationId,
    required this.value,
  });

  final OperationId operationId;
  final GeneralSettings value;
}
