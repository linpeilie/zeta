import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/settings_slice/settings_slice_notification_source.dart';
import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_notifier.dart';
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
    final harness = _harness();
    addTearDown(harness.dispose);
    // runner 回流首次载入：`load()` 等的就是切片自己的这个信号。
    harness.slice.loaded(initial);

    final notifications = await harness.source.load();

    expect(notifications, initial.notifications);
    expect(harness.source.notifications, initial.notifications);
    expect(harness.slice.state.settings, initial);
  });

  test('订阅跟随切片状态，取消后不再回调', () async {
    final harness = _harness();
    addTearDown(harness.dispose);
    harness.slice.loaded(const GeneralSettings());
    var notifications = 0;
    final unsubscribe = harness.source.addListener(() => notifications += 1);

    final operationId = harness.slice.setNotificationsEnabled(false);
    harness.slice.persisted(operationId, harness.slice.state.pendingValue!);
    await pumpEventQueue();

    expect(harness.source.notifications.enabled, isFalse);
    // 只回调一次：切片把同一 microtask 内的多次提交合并成一次广播，而本订阅还
    // 用 `select` 只盯通知设置——persist-first 的 pending 提交并不改变它。
    expect(notifications, 1);

    unsubscribe();
    final nextOperationId = harness.slice.setNotificationsEnabled(true);
    harness.slice.persisted(nextOperationId, harness.slice.state.pendingValue!);
    await pumpEventQueue();

    expect(harness.source.notifications.enabled, isTrue);
    expect(notifications, 1);
  });
}

/// 与生产同一形状：source 住在**另一个** provider 里，订阅在那个 body 建立。
///
/// 不能把它塞进 general 切片自己的 runner 工厂——那会让工厂在构建途中反向读切片，
/// 构成自环（生产里它住在 Desktop Attention 的工厂，不是同一个 provider）。
final _notificationSourceProvider = Provider<AgentNotificationSettingsSource>(
  (ref) => GeneralSettingsSliceNotificationSource(ref),
);

_Harness _harness() {
  final container = ProviderContainer(
    overrides: <Override>[
      generalSettingsSliceEffectRunnerFactoryProvider.overrideWithValue(
        (_) => _NoopRunner(),
      ),
    ],
  );
  return _Harness(
    container: container,
    slice: container.read(generalSettingsSliceProvider.notifier),
    source: container.read(_notificationSourceProvider),
  );
}

final class _Harness {
  const _Harness({
    required this.container,
    required this.slice,
    required this.source,
  });

  final ProviderContainer container;
  final GeneralSettingsSliceNotifier slice;
  final AgentNotificationSettingsSource source;

  void dispose() => container.dispose();
}

final class _NoopRunner implements GeneralSettingsSliceEffectRunner {
  @override
  void run(GeneralSettingsSliceEffect effect) {}
}
