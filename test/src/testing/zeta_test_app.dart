import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/composition/zeta_app_composition.dart';
import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/app/observability/zeta_observability.dart';
import 'package:zeta/src/app/storage/zeta_storage_bindings.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings_repository.dart';
import 'package:zeta/src/features/settings/domain/system_font_catalog_service.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/ui/core/system_file_manager.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

/// 测试用的 [MainApp]。
///
/// 生产代码里 `MainApp` 只接一个 [ZetaAppComposition]，注入口径全在组合根上；测试
/// 专用的便利参数留在这里，**不再污染 Widget 的构造函数**。已经是 provider 的依赖
/// 会被折成 `overrides`，其余的直接进 [ZetaAppComposition.create]。
///
/// 组合根会自动 `addTearDown(dispose)`，容器与三个切片组合随用例结束一起关。
MainApp zetaTestApp({
  Key? key,
  bool enableNativeWindowFrame = false,
  bool showWindowControls = true,
  ZetaHostMode hostMode = ZetaHostMode.ephemeral,
  AppLanguage fallbackLanguage = AppLanguage.simplifiedChinese,
  AppLanguage? displayLanguageOverride,
  bool waitForGeneralSettings = false,
  ZetaObservability? observability,
  ZetaStorageBindings? storageBindings,
  AgentProviderBundleFactory? agentProviderFactory,
  AgentProviderRuntimeRegistry? agentProviderRuntimeRegistry,
  AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader,
  HomeProviderDetectionLoader? homeProviderDetectionLoader,
  ProjectLocationOpener? projectLocationOpener,
  AgentUsagePanelRepository? agentUsagePanelRepository,
  DesktopNotificationService? desktopNotificationService,
  DesktopAttentionIndicator? desktopAttentionIndicator,
  // 以下依赖都已经是 provider，折成 overrides 装进容器。
  IdeSessionStore? ideSessionStore,
  AgentProviderConfigStore? agentProviderConfigStore,
  GeneralSettingsStore? generalSettingsStore,
  AppearanceSettingsRepository? appearanceSettingsStore,
  AppearanceSettings? initialAppearanceSettings,
  SystemFontCatalogService? systemFontCatalogService,
  UsageStatisticsPartitionStore? usageStatisticsPartitionStore,
  AgentModelCatalogRepository? agentModelCatalogRepository,
  AgentTurnContextStore? turnContextStore,
  List<Override> overrides = const <Override>[],
}) {
  return MainApp(
    key: key,
    composition: zetaTestComposition(
      enableNativeWindowFrame: enableNativeWindowFrame,
      showWindowControls: showWindowControls,
      hostMode: hostMode,
      fallbackLanguage: fallbackLanguage,
      displayLanguageOverride: displayLanguageOverride,
      waitForGeneralSettings: waitForGeneralSettings,
      observability: observability,
      storageBindings: storageBindings,
      agentProviderFactory: agentProviderFactory,
      agentProviderRuntimeRegistry: agentProviderRuntimeRegistry,
      agentProviderAvailabilityLoader: agentProviderAvailabilityLoader,
      homeProviderDetectionLoader: homeProviderDetectionLoader,
      projectLocationOpener: projectLocationOpener,
      agentUsagePanelRepository: agentUsagePanelRepository,
      desktopNotificationService: desktopNotificationService,
      desktopAttentionIndicator: desktopAttentionIndicator,
      ideSessionStore: ideSessionStore,
      agentProviderConfigStore: agentProviderConfigStore,
      generalSettingsStore: generalSettingsStore,
      appearanceSettingsStore: appearanceSettingsStore,
      initialAppearanceSettings: initialAppearanceSettings,
      systemFontCatalogService: systemFontCatalogService,
      usageStatisticsPartitionStore: usageStatisticsPartitionStore,
      agentModelCatalogRepository: agentModelCatalogRepository,
      turnContextStore: turnContextStore,
      overrides: overrides,
    ),
  );
}

/// 建一份测试组合根并登记 tear-down。
///
/// 需要 `takeStateSnapshot()` 或直接读容器的用例，自己拿这个返回值；只要 Widget 的
/// 用例用 [zetaTestApp] 即可。
ZetaAppComposition zetaTestComposition({
  bool enableNativeWindowFrame = false,
  bool showWindowControls = true,
  ZetaHostMode hostMode = ZetaHostMode.ephemeral,
  AppLanguage fallbackLanguage = AppLanguage.simplifiedChinese,
  AppLanguage? displayLanguageOverride,
  bool waitForGeneralSettings = false,
  ZetaObservability? observability,
  ZetaStorageBindings? storageBindings,
  AgentProviderBundleFactory? agentProviderFactory,
  AgentProviderRuntimeRegistry? agentProviderRuntimeRegistry,
  AgentProviderAvailabilityLoader? agentProviderAvailabilityLoader,
  HomeProviderDetectionLoader? homeProviderDetectionLoader,
  ProjectLocationOpener? projectLocationOpener,
  AgentUsagePanelRepository? agentUsagePanelRepository,
  DesktopNotificationService? desktopNotificationService,
  DesktopAttentionIndicator? desktopAttentionIndicator,
  IdeSessionStore? ideSessionStore,
  AgentProviderConfigStore? agentProviderConfigStore,
  GeneralSettingsStore? generalSettingsStore,
  AppearanceSettingsRepository? appearanceSettingsStore,
  AppearanceSettings? initialAppearanceSettings,
  SystemFontCatalogService? systemFontCatalogService,
  UsageStatisticsPartitionStore? usageStatisticsPartitionStore,
  AgentModelCatalogRepository? agentModelCatalogRepository,
  AgentTurnContextStore? turnContextStore,
  List<Override> overrides = const <Override>[],
}) {
  final composition = ZetaAppComposition.create(
    hostMode: hostMode,
    enableNativeWindowFrame: enableNativeWindowFrame,
    showWindowControls: showWindowControls,
    fallbackLanguage: fallbackLanguage,
    displayLanguageOverride: displayLanguageOverride,
    waitForGeneralSettings: waitForGeneralSettings,
    observability: observability,
    storageBindings: storageBindings,
    agentProviderFactory: agentProviderFactory,
    agentProviderRuntimeRegistry: agentProviderRuntimeRegistry,
    agentProviderAvailabilityLoader: agentProviderAvailabilityLoader,
    homeProviderDetectionLoader: homeProviderDetectionLoader,
    projectLocationOpener: projectLocationOpener,
    agentUsagePanelRepository: agentUsagePanelRepository,
    desktopNotificationService: desktopNotificationService,
    desktopAttentionIndicator: desktopAttentionIndicator,
    overrides: <Override>[
      // ephemeral 宿主不装触碰本机的平台实现，这里补上与生产等价的默认值，
      // 用例显式传入时以用例为准。
      appearanceSettingsStore == null
          ? appearanceSettingsRepositoryOverride()
          : appearanceSettingsRepositoryProvider.overrideWithValue(
              appearanceSettingsStore,
            ),
      appearanceFontCatalogProvider.overrideWith(
        (ref) => systemFontCatalogService ?? DesktopSystemFontCatalogService(),
      ),
      if (initialAppearanceSettings case final settings?)
        initialAppearanceSettingsProvider.overrideWithValue(settings),
      if (ideSessionStore case final store?)
        ideSessionStoreProvider.overrideWithValue(store),
      if (agentProviderConfigStore case final store?)
        agentProviderConfigStoreProvider.overrideWithValue(store),
      if (generalSettingsStore case final store?)
        generalSettingsStoreProvider.overrideWithValue(store),
      if (usageStatisticsPartitionStore case final store?)
        usageStatisticsPartitionStoreProvider.overrideWithValue(store),
      if (agentModelCatalogRepository case final repository?)
        agentModelCatalogRepositoryProvider.overrideWithValue(repository),
      if (turnContextStore case final store?)
        agentTurnContextStoreProvider.overrideWithValue(store),
      ...overrides,
    ],
  );
  addTearDown(composition.dispose);
  return composition;
}
