import 'dart:io';

import 'package:zeta/src/app/settings_slice/settings_slice_notification_source.dart';
import 'package:zeta/src/app/storage/atomic_text_file.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';
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
/// 通知设置窄端口与迁移期 ingress。设置页与 `IdeHome` 在 flag 开启时写入、读取
/// 切片；ingress 只承接仍由启动/测试入口注入的旧 controller 快照。
///
/// 新旧路径由 flag 二选一；生产已于 2026-08-23 翻旗并处于观察期。关批时会连同
/// ingress 和旧 controller 一起删除。
final class SettingsSliceComposition {
  SettingsSliceComposition._({
    required this.appearanceStore,
    required this.generalStore,
    required this.notificationSettingsSource,
    required this._ingress,
  });

  final AppearanceSettingsSliceStore appearanceStore;
  final GeneralSettingsSliceStore generalStore;
  final AgentNotificationSettingsSource notificationSettingsSource;
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

    final generalDataStore = filePersistence
        ? FileGeneralSettingsStore(
            storage: AtomicTextFile(File(dataPaths.generalSettingsFilePath)),
            fallbackLanguage: fallbackLanguage,
          )
        : MemoryGeneralSettingsStore(null, fallbackLanguage);
    final deferredGeneralRunner = _DeferredGeneralRunner();
    final generalStore = GeneralSettingsSliceStore(
      initialState: const GeneralSettingsSliceState(),
      effectRunner: deferredGeneralRunner,
    );
    deferredGeneralRunner.delegate = GeneralSettingsSliceRunnerAdapter(
      store: generalDataStore,
      sliceStore: generalStore,
    );

    final composition = SettingsSliceComposition._(
      appearanceStore: appearanceStore,
      generalStore: generalStore,
      notificationSettingsSource: GeneralSettingsSliceNotificationSource(
        dataStore: generalDataStore,
        sliceStore: generalStore,
      ),
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
