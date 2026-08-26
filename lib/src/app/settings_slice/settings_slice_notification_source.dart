import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general settings 切片提供的通知设置来源。
///
/// Desktop Attention 组合初始化要求 [load] 可等待。本窄端口只等待切片的首次
/// 载入结算，快照与订阅都读取切片 store；它不持有、不重复读取 data store。
final class GeneralSettingsSliceNotificationSource
    implements AgentNotificationSettingsSource {
  const GeneralSettingsSliceNotificationSource({
    required GeneralSettingsSliceStore sliceStore,
  }) : this._(sliceStore);

  const GeneralSettingsSliceNotificationSource._(this._sliceStore);

  final GeneralSettingsSliceStore _sliceStore;

  @override
  Future<AgentNotificationSettings> load() async {
    await _sliceStore.initialLoad;
    return _sliceStore.state.settings.notifications;
  }

  @override
  AgentNotificationSettings get notifications =>
      _sliceStore.state.settings.notifications;

  @override
  void Function() addListener(void Function() listener) =>
      _sliceStore.subscribe(listener);
}
