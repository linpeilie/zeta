import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/features/desktop_notifications/data/flutter_desktop_notification_service.dart';
import 'package:zeta/src/features/desktop_notifications/data/method_channel_desktop_attention_indicator.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';

/// 桌面通知端口。
///
/// 生产默认走系统通知中心。widget test 由 `zetaTestComposition` 换成
/// [NoopDesktopNotificationService]，避免打平台通道或挂在系统 UI 上。
///
/// 通知标题带用户语言，因此这里依赖 [desktopAttentionTextCatalogProvider]：
/// 显示语言冻结之前读它会 fail-closed 抛错，而不是先发一条英文通知。
final desktopNotificationServiceProvider = Provider<DesktopNotificationService>(
  (ref) => FlutterDesktopNotificationService(
    linuxActionName: ref.watch(desktopAttentionTextCatalogProvider).linuxAction,
  ),
  name: 'desktopNotificationService',
);

/// 任务栏 / Dock 的注意力指示端口。
final desktopAttentionIndicatorProvider = Provider<DesktopAttentionIndicator>(
  (ref) => MethodChannelDesktopAttentionIndicator(),
  name: 'desktopAttentionIndicator',
);

/// 「点开通知就跳到那个会话」的落点。
///
/// 生产默认走 [RouterCoordinator.activateThreadFromDeepLink]。测试和 IdeHome
/// 的 toast / 用量收口仍可 [bind] 本 relay；未绑定则组合根走 coordinator。
final desktopAttentionTargetActivatorRelayProvider =
    Provider<DesktopAttentionTargetActivatorRelay>(
      (ref) => DesktopAttentionTargetActivatorRelay(),
      name: 'desktopAttentionTargetActivatorRelay',
    );

/// target activator 在 `IdeHome.initState` 绑定、`dispose` 解绑。
final class DesktopAttentionTargetActivatorRelay {
  DesktopAttentionTargetActivator? _activator;

  bool get isBound => _activator != null;

  void bind(DesktopAttentionTargetActivator activator) {
    if (_activator != null && !identical(_activator, activator)) {
      throw StateError('Desktop attention target activator is already bound');
    }
    _activator = activator;
  }

  void unbind(DesktopAttentionTargetActivator activator) {
    if (identical(_activator, activator)) {
      _activator = null;
    }
  }

  Future<bool> call(String providerId, String threadId) async {
    final activator = _activator;
    return activator == null ? false : activator(providerId, threadId);
  }
}
