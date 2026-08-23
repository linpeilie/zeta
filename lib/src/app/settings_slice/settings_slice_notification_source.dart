import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general settings 切片提供的通知设置来源。
///
/// Desktop Attention 组合初始化要求 [load] 可等待，因此这里直接读取既有
/// data store，再用 typed result intent 更新切片。初始化完成后，快照与订阅都只
/// 读取切片 store，避免通知 context 回头依赖旧 ChangeNotifier controller。
final class GeneralSettingsSliceNotificationSource
    implements AgentNotificationSettingsSource {
  const GeneralSettingsSliceNotificationSource({
    required GeneralSettingsStore dataStore,
    required GeneralSettingsSliceStore sliceStore,
  }) : this._(dataStore, sliceStore);

  const GeneralSettingsSliceNotificationSource._(
    this._dataStore,
    this._sliceStore,
  );

  final GeneralSettingsStore _dataStore;
  final GeneralSettingsSliceStore _sliceStore;

  @override
  Future<AgentNotificationSettings> load() async {
    final settings = await _dataStore.load();
    _sliceStore.loaded(settings);
    return settings.notifications;
  }

  @override
  AgentNotificationSettings get notifications =>
      _sliceStore.state.settings.notifications;

  @override
  void Function() addListener(void Function() listener) =>
      _sliceStore.subscribe(listener);
}
