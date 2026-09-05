import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 通知设置快照与变更订阅的纯 Dart 端口（Phase 3 第 1 批步骤 2）。
///
/// desktop_notifications 只依赖这个端口，不依赖 settings 的 store 形态。
/// 实现必须保证 [load] 返回前设置已加载完成。
abstract interface class AgentNotificationSettingsSource {
  /// 加载设置并返回通知快照。
  Future<AgentNotificationSettings> load();

  /// 当前通知设置（[load] 之后同步读取）。
  AgentNotificationSettings get notifications;

  /// 订阅变更，返回取消订阅回调。
  void Function() addListener(void Function() listener);
}
