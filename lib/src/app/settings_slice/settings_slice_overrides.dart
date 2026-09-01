import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_notifier.dart';

/// settings 组合根装配。
///
/// 外观由 `AppearanceSettingsNotifier` 自己从 application provider 取值；
/// 本函数只装配 general 切片的 effect runner 工厂。
///
/// 取代了旧的「provider body 里 new 一个 store 再手工 `load()` / `onDispose`」：
/// 状态由 `generalSettingsSliceProvider` 拥有，runner 随 notifier 一起创建、一起
/// 释放，自启动的首次 load 也归切片自己（工程规范 §3.0）。
List<Override> settingsSliceOverrides() {
  return <Override>[
    generalSettingsSliceEffectRunnerFactoryProvider.overrideWith((ref) {
      final dataStore = ref.watch(generalSettingsStoreProvider);
      return (slice) =>
          GeneralSettingsSliceRunnerAdapter(store: dataStore, slice: slice);
    }),
  ];
}
