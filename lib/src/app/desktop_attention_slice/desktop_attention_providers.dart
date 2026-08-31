import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/features/desktop_notifications/data/flutter_desktop_notification_service.dart';
import 'package:zeta/src/features/desktop_notifications/data/method_channel_desktop_attention_indicator.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';

/// 桌面通知端口。
///
/// 默认按宿主模式选：`local` 用系统通知中心，`ephemeral` 用不做事的实现——
/// widget test 里弹真通知既打不到平台通道，也会把用例挂在系统 UI 上。
///
/// 通知标题带用户语言，因此这里依赖 [desktopAttentionTextCatalogProvider]：
/// 显示语言冻结之前读它会 fail-closed 抛错，而不是先发一条英文通知。
final desktopNotificationServiceProvider = Provider<DesktopNotificationService>(
  (ref) => ref.watch(zetaHostModeProvider).usesNativeDesktopIntegration
      ? FlutterDesktopNotificationService(
          linuxActionName: ref
              .watch(desktopAttentionTextCatalogProvider)
              .linuxAction,
        )
      : const NoopDesktopNotificationService(),
  name: 'desktopNotificationService',
);

/// 任务栏 / Dock 的注意力指示端口。
final desktopAttentionIndicatorProvider = Provider<DesktopAttentionIndicator>(
  (ref) => ref.watch(zetaHostModeProvider).usesNativeDesktopIntegration
      ? MethodChannelDesktopAttentionIndicator()
      : const NoopDesktopAttentionIndicator(),
  name: 'desktopAttentionIndicator',
);
