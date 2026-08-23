import 'dart:io';

import 'package:zeta/src/app/storage/atomic_text_file.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_ingress.dart';

/// Phase 3 第 1 批的 settings 切片组合（app session 寿命）。
///
/// flag 开启时由 `MainApp` 创建：两个切片 store、各自的 runner 适配器，
/// 以及迁移期 ingress——**写入仍走旧 controller**（设置页要到步骤 4 才切），
/// ingress 把旧 controller 的变化镜像进切片，主题构建因此能立即读切片。
///
/// 与旧 controller 的文件读写共享同一批底层文件；过渡期只有旧 controller
/// 一个写入方（用户操作都还从设置页走旧路径），不存在双写竞争。
final class SettingsSliceComposition {
  SettingsSliceComposition._({
    required this.appearanceStore,
    required this.generalStore,
    required this._ingress,
  });

  final AppearanceSettingsSliceStore appearanceStore;
  final GeneralSettingsSliceStore generalStore;
  final SettingsSliceIngress _ingress;

  factory SettingsSliceComposition.create({
    required bool useFilePersistence,
    required ZetaDataPaths? dataPaths,
    required AppLanguage fallbackLanguage,
    required AppearanceSettingsController appearanceController,
    required GeneralSettingsController generalController,
    required SystemFontCatalogService fontCatalog,
  }) {
    final filePersistence = useFilePersistence && dataPaths != null;

    // store 与 runner 互相引用，用延迟绑定 runner 解开构造环。
    final deferredAppearanceRunner = _DeferredAppearanceRunner();
    final appearanceStore = AppearanceSettingsSliceStore(
      initialState: const AppearanceSettingsSliceState(),
      effectRunner: deferredAppearanceRunner,
    );
    deferredAppearanceRunner.delegate = AppearanceSettingsSliceRunnerAdapter(
      store: filePersistence
          ? FileAppearanceSettingsStore(
              storage: AtomicTextFile(File(dataPaths.appearanceFilePath)),
            )
          : MemoryAppearanceSettingsStore(),
      fontCatalog: fontCatalog,
      sliceStore: appearanceStore,
    );

    final deferredGeneralRunner = _DeferredGeneralRunner();
    final generalStore = GeneralSettingsSliceStore(
      initialState: const GeneralSettingsSliceState(),
      effectRunner: deferredGeneralRunner,
    );
    deferredGeneralRunner.delegate = GeneralSettingsSliceRunnerAdapter(
      store: filePersistence
          ? FileGeneralSettingsStore(
              storage: AtomicTextFile(File(dataPaths.generalSettingsFilePath)),
              fallbackLanguage: fallbackLanguage,
            )
          : MemoryGeneralSettingsStore(null, fallbackLanguage),
      sliceStore: generalStore,
    );

    final composition = SettingsSliceComposition._(
      appearanceStore: appearanceStore,
      generalStore: generalStore,
      ingress: SettingsSliceIngress(
        appearanceController: appearanceController,
        generalController: generalController,
        appearanceSlice: appearanceStore,
        generalSlice: generalStore,
      ),
    );
    appearanceStore.load();
    generalStore.load();
    return composition;
  }

  void dispose() {
    _ingress.dispose();
    appearanceStore.close();
    generalStore.close();
  }
}

/// 构造期占位、创建完成后立即绑定真实 runner。
final class _DeferredAppearanceRunner
    implements AppearanceSettingsSliceEffectRunner {
  AppearanceSettingsSliceEffectRunner? delegate;

  @override
  void run(AppearanceSettingsSliceEffect effect) => delegate?.run(effect);
}

final class _DeferredGeneralRunner implements GeneralSettingsSliceEffectRunner {
  GeneralSettingsSliceEffectRunner? delegate;

  @override
  void run(GeneralSettingsSliceEffect effect) => delegate?.run(effect);
}
