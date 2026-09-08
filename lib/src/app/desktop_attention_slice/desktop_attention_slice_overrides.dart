import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/app/desktop_attention_slice/desktop_attention_providers.dart';
import 'package:zeta/src/app/desktop_attention_slice/desktop_attention_slice_runner.dart';
import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_notification_source.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_notifier.dart';

/// Desktop Attention 切片的组合根装配。
///
/// 取代了旧的 `DesktopAttentionSliceComposition`：切片的所有权、构造顺序和释放
/// 时机全部由容器表达——状态由 `desktopAttentionSliceProvider` 拥有，runner 随
/// notifier 一起创建、一起释放，不再需要一个组合对象手工串 `dispose()`
/// （工程规范 §3.0）。
///
/// 这里只装 runner 工厂。通知服务、任务栏指示器、文案与 target activator 各自是
/// 独立 provider，**组合根一律不碰**：Riverpod 对同一容器内的重复 override 直接
/// 断言失败，装了调用方就再也换不掉 fake。
List<Override> desktopAttentionSliceOverrides() {
  return <Override>[
    desktopAttentionSliceEffectRunnerFactoryProvider.overrideWith((ref) {
      final notificationService = ref.watch(desktopNotificationServiceProvider);
      final indicator = ref.watch(desktopAttentionIndicatorProvider);
      final notificationSettingsSource = GeneralSettingsSliceNotificationSource(
        ref,
      );
      final relay = ref.watch(desktopAttentionTargetActivatorRelayProvider);
      final textCatalog = ref.watch(desktopAttentionTextCatalogProvider);
      return (notifier) => DesktopAttentionSliceRunner(
        notifier,
        notificationService: notificationService,
        indicator: indicator,
        notificationSettingsSource: notificationSettingsSource,
        activateTarget: (providerId, threadId) {
          if (relay.isBound) {
            return relay.call(providerId, threadId);
          }
          return _activateFromRouter(ref, providerId, threadId);
        },
        textCatalog: textCatalog,
      );
    }),
  ];
}

Future<bool> _activateFromRouter(
  Ref ref,
  String providerId,
  String threadId,
) async {
  await ref.read(zetaWindowHostProvider).revealWindow();
  return ref
      .read(routerCoordinatorProvider)
      .activateThreadFromDeepLink(providerId, threadId);
}
