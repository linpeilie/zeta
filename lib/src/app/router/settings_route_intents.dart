import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置页标题栏点「用量」：先离开设置，回到壳后再打开用量覆盖层。
final openUsageStatisticsAfterSettingsProvider =
    NotifierProvider<OpenUsageStatisticsAfterSettings, bool>(
      OpenUsageStatisticsAfterSettings.new,
      name: 'openUsageStatisticsAfterSettings',
    );

final class OpenUsageStatisticsAfterSettings extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  void cancel() {
    if (state) {
      state = false;
    }
  }

  bool consume() {
    if (!state) {
      return false;
    }
    state = false;
    return true;
  }
}
