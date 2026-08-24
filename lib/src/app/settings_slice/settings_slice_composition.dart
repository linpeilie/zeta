import 'dart:io';

import 'package:zeta/src/app/settings_slice/settings_slice_notification_source.dart';
import 'package:zeta/src/app/storage/atomic_text_file.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_runners.dart';
import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_mapping.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// Phase 3 第 1 批的 settings 切片组合（app session 寿命）。
///
/// 两个切片 store 是 app session 内唯一运行态 owner；runner 独占持久化与字体目录
/// 端口，Riverpod 只镜像 store。构造完成后立即发起一次幂等加载。
final class SettingsSliceComposition {
  SettingsSliceComposition._({
    required this.appearanceStore,
    required this.generalStore,
    required this.notificationSettingsSource,
    required this._generalRunner,
  });

  final AppearanceSettingsSliceStore appearanceStore;
  final GeneralSettingsSliceStore generalStore;
  final AgentNotificationSettingsSource notificationSettingsSource;
  final GeneralSettingsSliceRunnerAdapter _generalRunner;

  /// general 设置完成首次持久化加载后的快照。
  ///
  /// 组合根用它决定何时冻结本进程 Locale；加载失败时 runner 已记录脱敏日志并
  /// 以构造期 fallback 快照完成，避免有文字的 UI 永久悬空。
  Future<GeneralSettings> get generalSettingsReady => _generalRunner.loadResult;

  factory SettingsSliceComposition.create({
    required bool useFilePersistence,
    required ZetaDataPaths? dataPaths,
    required AppLanguage fallbackLanguage,
    AppearanceSettingsStore? appearanceSettingsStore,
    GeneralSettingsStore? generalSettingsStore,
    SystemFontCatalogService? fontCatalog,
    AppearanceSettings? initialAppearanceSettings,
  }) {
    final filePersistence = useFilePersistence && dataPaths != null;
    final appearanceDataStore =
        appearanceSettingsStore ??
        (filePersistence
            ? FileAppearanceSettingsStore(
                storage: AtomicTextFile(File(dataPaths.appearanceFilePath)),
              )
            : MemoryAppearanceSettingsStore());
    final generalDataStore =
        generalSettingsStore ??
        (filePersistence
            ? FileGeneralSettingsStore(
                storage: AtomicTextFile(
                  File(dataPaths.generalSettingsFilePath),
                ),
                fallbackLanguage: fallbackLanguage,
              )
            : MemoryGeneralSettingsStore(null, fallbackLanguage));

    // store 与 runner 互相引用，用延迟绑定 runner 解开构造环。
    final deferredAppearanceRunner = _DeferredAppearanceRunner();
    final appearanceStore = AppearanceSettingsSliceStore(
      initialState: AppearanceSettingsSliceState(
        value: appearanceSliceFromSettings(
          initialAppearanceSettings ?? const AppearanceSettings(),
        ),
      ),
      effectRunner: deferredAppearanceRunner,
    );
    deferredAppearanceRunner.delegate = AppearanceSettingsSliceRunnerAdapter(
      store: appearanceDataStore,
      fontCatalog: fontCatalog ?? DesktopSystemFontCatalogService(),
      sliceStore: appearanceStore,
    );

    final deferredGeneralRunner = _DeferredGeneralRunner();
    final generalStore = GeneralSettingsSliceStore(
      initialState: GeneralSettingsSliceState(
        settings: GeneralSettings(appLanguage: fallbackLanguage),
      ),
      effectRunner: deferredGeneralRunner,
      initiallyLoaded: false,
    );
    final generalRunner = GeneralSettingsSliceRunnerAdapter(
      store: generalDataStore,
      sliceStore: generalStore,
    );
    deferredGeneralRunner.delegate = generalRunner;

    final composition = SettingsSliceComposition._(
      appearanceStore: appearanceStore,
      generalStore: generalStore,
      notificationSettingsSource: GeneralSettingsSliceNotificationSource(
        generalSettingsReady: generalRunner.loadResult,
        sliceStore: generalStore,
      ),
      generalRunner: generalRunner,
    );
    appearanceStore.load();
    generalStore.load();
    return composition;
  }

  void dispose() {
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
