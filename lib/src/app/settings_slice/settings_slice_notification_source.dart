import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general settings 切片提供的通知设置来源。
///
/// Desktop Attention 组合初始化要求 [load] 可等待。本窄端口只等待 runner
/// 的首次加载结果，快照与订阅都读取切片 store；它不持有、不重复
/// 读取 data store。
final class GeneralSettingsSliceNotificationSource
    implements AgentNotificationSettingsSource {
  const GeneralSettingsSliceNotificationSource({
    required Future<GeneralSettings> generalSettingsReady,
    required GeneralSettingsSliceStore sliceStore,
  }) : this._(generalSettingsReady, sliceStore);

  const GeneralSettingsSliceNotificationSource._(
    this._generalSettingsReady,
    this._sliceStore,
  );

  final Future<GeneralSettings> _generalSettingsReady;
  final GeneralSettingsSliceStore _sliceStore;

  @override
  Future<AgentNotificationSettings> load() async {
    await _generalSettingsReady;
    return _sliceStore.state.settings.notifications;
  }

  @override
  AgentNotificationSettings get notifications =>
      _sliceStore.state.settings.notifications;

  @override
  void Function() addListener(void Function() listener) =>
      _sliceStore.subscribe(listener);
}
