import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_intent.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general 切片的 reducer。
///
/// **纯同步、无副作用**（G3）。所有修改走 **persist-first**（现状语义 B）：
/// 只登记在途身份与在途值，成功回执才应用；失败保持旧值并登记分类。
/// 相等早退与现有 controller 一致（语言路径返回 `unchanged` 的分支）。
Transition<GeneralSettingsSliceState, GeneralSettingsSliceEffect>
generalSettingsSliceReduce(
  GeneralSettingsSliceState state,
  GeneralSettingsSliceIntent intent,
) {
  switch (intent) {
    case GeneralSettingsLoadRequested():
      return Transition(state, const <GeneralSettingsSliceEffect>[
        GeneralSettingsLoadEffect(),
      ]);

    case GeneralSettingsLoaded():
      if (intent.settings == state.settings) {
        return Transition.none(state);
      }
      return Transition.stateOnly(state.copyWith(settings: intent.settings));

    case MessageSendShortcutSelected():
      return _submit(
        state,
        intent.operationId,
        GeneralSettingsPersistOperation.shortcut,
        (base) => base.copyWith(sendMessageShortcut: intent.shortcut),
        equalsCurrent: state.settings.sendMessageShortcut == intent.shortcut,
      );

    case AppLanguageSelected():
      return _submit(
        state,
        intent.operationId,
        GeneralSettingsPersistOperation.language,
        (base) => base.copyWith(appLanguage: intent.language),
        equalsCurrent: state.settings.appLanguage == intent.language,
      );

    case NotificationsEnabledToggled():
      return _submitNotification(
        state,
        intent.operationId,
        (value) => value.copyWith(enabled: intent.enabled),
      );

    case TurnTerminalNotificationsToggled():
      return _submitNotification(
        state,
        intent.operationId,
        (value) => value.copyWith(turnTerminalEnabled: intent.enabled),
      );

    case ActionRequiredNotificationsToggled():
      return _submitNotification(
        state,
        intent.operationId,
        (value) => value.copyWith(actionRequiredEnabled: intent.enabled),
      );

    case GeneralSettingsPersisted():
      if (state.pendingOperationId != intent.operationId) {
        return Transition.none(state);
      }
      return Transition.stateOnly(
        state.copyWith(
          settings: intent.settings,
          pendingOperationId: null,
          pendingValue: null,
          pendingOperation: null,
          lastPersistFailure: null,
        ),
      );

    case GeneralSettingsPersistFailed():
      if (state.pendingOperationId != intent.operationId) {
        return Transition.none(state);
      }
      // 已应用值保持不变；清掉在途，让下一次修改从未应用值重新出发
      // （与串行队列里「失败的保存不阻断后续命令」等价）。
      // pendingOperation 与 pendingOperationId 成对登记，此处必非空。
      return Transition.stateOnly(
        state.copyWith(
          pendingOperationId: null,
          pendingValue: null,
          pendingOperation: null,
          lastPersistFailure: GeneralSettingsSlicePersistFailure(
            kind: intent.kind,
            operation: state.pendingOperation!,
          ),
        ),
      );

    case GeneralSettingsFailureAcknowledged():
      if (state.lastPersistFailure == null) {
        return Transition.none(state);
      }
      return Transition.stateOnly(state.copyWith(lastPersistFailure: null));
  }
}

Transition<GeneralSettingsSliceState, GeneralSettingsSliceEffect> _submit(
  GeneralSettingsSliceState state,
  OperationId operationId,
  GeneralSettingsPersistOperation operation,
  GeneralSettings Function(GeneralSettings base) update, {
  required bool equalsCurrent,
}) {
  if (equalsCurrent || state.pendingOperationId != null) {
    return Transition.none(state);
  }
  final next = update(state.settings);
  return Transition(
    state.copyWith(
      pendingOperationId: operationId,
      pendingValue: next,
      pendingOperation: operation,
    ),
    <GeneralSettingsSliceEffect>[
      GeneralSettingsPersistEffect(operationId: operationId, value: next),
    ],
  );
}

Transition<GeneralSettingsSliceState, GeneralSettingsSliceEffect>
_submitNotification(
  GeneralSettingsSliceState state,
  OperationId operationId,
  AgentNotificationSettingsUpdator update,
) {
  if (state.pendingOperationId != null) {
    return Transition.none(state);
  }
  final nextNotifications = update(state.settings.notifications);
  if (nextNotifications == state.settings.notifications) {
    return Transition.none(state);
  }
  final next = state.settings.copyWith(notifications: nextNotifications);
  return Transition(
    state.copyWith(
      pendingOperationId: operationId,
      pendingValue: next,
      pendingOperation: GeneralSettingsPersistOperation.notifications,
    ),
    <GeneralSettingsSliceEffect>[
      GeneralSettingsPersistEffect(operationId: operationId, value: next),
    ],
  );
}

typedef AgentNotificationSettingsUpdator =
    AgentNotificationSettings Function(AgentNotificationSettings value);
