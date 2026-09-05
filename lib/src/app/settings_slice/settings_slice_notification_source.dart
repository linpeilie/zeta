import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_notifier.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general settings 切片提供的通知设置来源。
///
/// Desktop Attention 的 runner 要求 [load] 可等待。本窄端口只等待切片的首次载入
/// 结算，快照与订阅都读容器；它不持有、不重复读取 data store。
///
/// **订阅在构造时建立**：本对象由 `desktopAttentionSliceOverrides()` 在 provider
/// body 里 new 出来，那正是唯一允许调 `ref.listen` 的时机，订阅也随那个 provider
/// 一起释放。之后 runner 调 [addListener] 只是登记回调——它只有一个消费者，因此
/// 这里不需要一份 listener 列表。
final class GeneralSettingsSliceNotificationSource
    implements AgentNotificationSettingsSource {
  GeneralSettingsSliceNotificationSource(this._ref) {
    _ref.listen<AgentNotificationSettings>(
      generalSettingsSliceProvider.select(
        (state) => state.settings.notifications,
      ),
      (previous, next) => _listener?.call(),
    );
  }

  final Ref _ref;
  void Function()? _listener;

  @override
  Future<AgentNotificationSettings> load() async {
    final settings = await _ref
        .read(generalSettingsSliceProvider.notifier)
        .initialLoad;
    return settings.notifications;
  }

  @override
  AgentNotificationSettings get notifications => _ref
      .read(generalSettingsSliceProvider.notifier)
      .state
      .settings
      .notifications;

  @override
  void Function() addListener(void Function() listener) {
    _listener = listener;
    return () {
      if (identical(_listener, listener)) {
        _listener = null;
      }
    };
  }
}
