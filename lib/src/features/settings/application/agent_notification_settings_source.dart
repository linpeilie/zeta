import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 通知设置快照与变更订阅的纯 Dart 端口（Phase 3 第 1 批步骤 2）。
///
/// desktop_notifications 只依赖这个端口，不依赖 settings 的 controller 形态
/// ——旧 `ChangeNotifier` controller 与 Phase 3 切片 store 都能实现它。
/// 实现必须保证 [load] 返回前设置已加载完成。
abstract interface class AgentNotificationSettingsSource {
  /// 加载设置并返回通知快照。
  Future<AgentNotificationSettings> load();

  /// 当前通知设置（[load] 之后同步读取）。
  AgentNotificationSettings get notifications;

  /// 订阅变更，返回取消订阅回调。
  void Function() addListener(void Function() listener);
}

/// 旧路径桥：把现有 [GeneralSettingsController] 适配成
/// [AgentNotificationSettingsSource]。
///
/// 切片路径启用后由切片 store 的适配实现取代；两条路径给的是同一份事实。
final class GeneralSettingsControllerNotificationSource
    implements AgentNotificationSettingsSource {
  const GeneralSettingsControllerNotificationSource(this._controller);

  final GeneralSettingsController _controller;

  @override
  Future<AgentNotificationSettings> load() async =>
      (await _controller.load()).notifications;

  @override
  AgentNotificationSettings get notifications =>
      _controller.settings.notifications;

  @override
  void Function() addListener(void Function() listener) {
    _controller.addListener(listener);
    return () => _controller.removeListener(listener);
  }
}
