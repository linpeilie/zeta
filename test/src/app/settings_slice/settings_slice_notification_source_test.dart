import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/settings_slice/settings_slice_notification_source.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

void main() {
  test('load 返回持久化通知设置并投影进切片', () async {
    const initial = GeneralSettings(
      sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
      notifications: AgentNotificationSettings(
        enabled: false,
        turnTerminalEnabled: false,
      ),
    );
    final sliceStore = _sliceStore();
    addTearDown(sliceStore.close);
    final ready = Future<GeneralSettings>.sync(() {
      sliceStore.loaded(initial);
      return initial;
    });
    final source = GeneralSettingsSliceNotificationSource(
      generalSettingsReady: ready,
      sliceStore: sliceStore,
    );

    final notifications = await source.load();

    expect(notifications, initial.notifications);
    expect(source.notifications, initial.notifications);
    expect(sliceStore.state.settings, initial);
  });

  test('订阅跟随切片状态，取消后不再回调', () {
    final sliceStore = _sliceStore();
    addTearDown(sliceStore.close);
    final source = GeneralSettingsSliceNotificationSource(
      generalSettingsReady: Future<GeneralSettings>.value(
        const GeneralSettings(),
      ),
      sliceStore: sliceStore,
    );
    var notifications = 0;
    final unsubscribe = source.addListener(() => notifications += 1);

    final operationId = sliceStore.setNotificationsEnabled(false);
    sliceStore.persisted(operationId, sliceStore.state.pendingValue!);

    expect(source.notifications.enabled, isFalse);
    expect(notifications, 2, reason: 'pending 与 persisted 各发布一次');

    unsubscribe();
    final nextOperationId = sliceStore.setNotificationsEnabled(true);
    sliceStore.persisted(nextOperationId, sliceStore.state.pendingValue!);

    expect(source.notifications.enabled, isTrue);
    expect(notifications, 2);
  });
}

GeneralSettingsSliceStore _sliceStore() {
  return GeneralSettingsSliceStore(
    initialState: const GeneralSettingsSliceState(),
    effectRunner: _NoopRunner(),
  );
}

final class _NoopRunner implements GeneralSettingsSliceEffectRunner {
  @override
  void run(GeneralSettingsSliceEffect effect) {}
}
