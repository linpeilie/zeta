import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_mapping.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';

/// settings 两个切片的组合根装配。
///
/// 取代了旧的 `SettingsSliceComposition`：切片的所有权、构造顺序和释放时机全部
/// 由容器表达——store 随 provider 创建、随容器 `dispose()` 关闭，不再需要一个组合
/// 对象手工串 `dispose()`（工程规范 §3.0）。data store 与字体目录都从
/// `zeta_store_providers.dart` 读，因此组合根不再向下钻 `StorageService`。
///
/// runner 用工厂注入而不是延迟绑定：`store ↔ runner` 的构造环由
/// `AppearanceSettingsSliceEffectRunnerFactory` 解开（AGENTS.md §状态与异步）。
///
/// 闭包住在 `app` 层是刻意的：runner 适配器碰持久化端口与系统字体目录，
/// presentation 不能 import 它们，所以 provider 声明留在 presentation 做
/// fail-closed，真实构造由组合根覆盖进来（与 `ideSessionSliceOverrides` 同款）。
List<Override> settingsSliceOverrides() {
  return <Override>[
    appearanceSettingsSliceStoreProvider.overrideWith((ref) {
      final dataStore = ref.watch(appearanceSettingsStoreProvider);
      final fontCatalog = ref.watch(systemFontCatalogServiceProvider);
      final store = AppearanceSettingsSliceStore(
        initialState: AppearanceSettingsSliceState(
          value: appearanceSliceFromSettings(
            ref.watch(initialAppearanceSettingsProvider),
          ),
        ),
        effectRunnerFactory: (sliceStore) =>
            AppearanceSettingsSliceRunnerAdapter(
              store: dataStore,
              fontCatalog: fontCatalog,
              sliceStore: sliceStore,
            ),
      );
      ref.onDispose(store.close);
      // 构造完成后立即发起一次幂等加载，语义与旧组合一致。
      store.load();
      return store;
    }),
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
