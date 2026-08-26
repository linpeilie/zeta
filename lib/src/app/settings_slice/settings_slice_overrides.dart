import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';

/// settings 组合根装配。
///
/// 外观由 [AppearanceSettingsNotifier] 自己从 application provider 取值；
/// 本函数只装配仍走切片的 general store。
List<Override> settingsSliceOverrides() {
  return <Override>[
    generalSettingsSliceStoreProvider.overrideWith((ref) {
      final dataStore = ref.watch(generalSettingsStoreProvider);
      final store = GeneralSettingsSliceStore(
        initialState: GeneralSettingsSliceState(
          settings: GeneralSettings(
            appLanguage: ref.watch(settingsFallbackLanguageProvider),
          ),
        ),
        effectRunnerFactory: (sliceStore) => GeneralSettingsSliceRunnerAdapter(
          store: dataStore,
          sliceStore: sliceStore,
        ),
        initiallyLoaded: false,
      );
      ref.onDispose(store.close);
      store.load();
      return store;
    }),
  ];
}
