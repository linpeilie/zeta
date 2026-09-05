import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general 切片的意图。
///
/// 命令类意图携带 [OperationId]，由 store 在 dispatch 前铸造（G3）。
/// 所有修改类意图走 **persist-first**（现状语义 B）：reducer 只登记在途
/// 身份与在途值，persist 成功回执才应用。
sealed class GeneralSettingsSliceIntent {
  const GeneralSettingsSliceIntent();
}

/// 请求载入持久化的常规设置（重复 load 由 store 侧记忆化挡住）。
final class GeneralSettingsLoadRequested extends GeneralSettingsSliceIntent {
  const GeneralSettingsLoadRequested();
}

/// 载入完成；损坏 / 不支持版本由 codec 宽容解码回落后回执。
final class GeneralSettingsLoaded extends GeneralSettingsSliceIntent {
  const GeneralSettingsLoaded(this.settings);

  final GeneralSettings settings;
}

final class MessageSendShortcutSelected extends GeneralSettingsSliceIntent {
  const MessageSendShortcutSelected(this.operationId, this.shortcut);

  final OperationId operationId;
  final MessageSendShortcut shortcut;
}

/// 选择下次启动的界面语言；当前进程 locale 不变（冻结语义在组合层）。
final class AppLanguageSelected extends GeneralSettingsSliceIntent {
  const AppLanguageSelected(this.operationId, this.language);

  final OperationId operationId;
  final AppLanguage language;
}

final class NotificationsEnabledToggled extends GeneralSettingsSliceIntent {
  const NotificationsEnabledToggled(this.operationId, this.enabled);

  final OperationId operationId;
  final bool enabled;
}

final class TurnTerminalNotificationsToggled
    extends GeneralSettingsSliceIntent {
  const TurnTerminalNotificationsToggled(this.operationId, this.enabled);

  final OperationId operationId;
  final bool enabled;
}

final class ActionRequiredNotificationsToggled
    extends GeneralSettingsSliceIntent {
  const ActionRequiredNotificationsToggled(this.operationId, this.enabled);

  final OperationId operationId;
  final bool enabled;
}

/// persist 成功回执：应用 [settings] 值并清空在途。
final class GeneralSettingsPersisted extends GeneralSettingsSliceIntent {
  const GeneralSettingsPersisted(this.operationId, this.settings);

  final OperationId operationId;
  final GeneralSettings settings;
}

/// persist 失败回执：保持已应用值不变，登记失败分类。
final class GeneralSettingsPersistFailed extends GeneralSettingsSliceIntent {
  const GeneralSettingsPersistFailed(this.operationId, this.kind);

  final OperationId operationId;
  final SettingsPersistFailureKind kind;
}

/// presentation 消费完失败提示后的确认（防止 rebuild 重放一次性提示）。
final class GeneralSettingsFailureAcknowledged
    extends GeneralSettingsSliceIntent {
  const GeneralSettingsFailureAcknowledged();
}
