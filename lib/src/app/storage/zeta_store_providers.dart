import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/storage/zeta_storage_providers.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// 应用级 feature data 的唯一装配点。
///
/// 每个 store 都只依赖 `zeta_storage_providers.dart` 里那一份已绑定位置的
/// [StorageService]：**落盘还是内存由 `ZetaStorageBindings` 在组合根一次性决定**，
/// 这里不再判断宿主模式，也不再从路径是否为 null 反推。
///
/// 这层住在 `app` 而不是各 feature 的 `data/`：`data` 与 `domain` 禁 Riverpod
/// （G6，`feature_layering_guard_test` 零容忍），装配决策本来就属于组合层。
///
/// 生命周期：这里的都是无状态或自管理的 store，没有需要显式释放的资源；Agent
/// runtime registry 与插件目录**不在这里**，它们的关闭顺序由
/// `shutdownAgentResourcesInOrder` 单独保证。测试要换实现时覆盖对应 provider，
/// 不要再往下钻构造参数。

// ---------------------------------------------------------------------------
// 组合根输入：没有存储语义，但 store 构造需要
// ---------------------------------------------------------------------------

/// 常规设置文件缺失或损坏时使用的语言。
///
/// 有安全默认值，因此不 fail-closed；组合根按 `MainApp.fallbackLanguage` 覆盖。
final settingsFallbackLanguageProvider = Provider<AppLanguage>(
  (ref) => AppLanguage.simplifiedChinese,
  name: 'settingsFallbackLanguage',
);

/// Provider 配置的编解码器。
///
/// definitions 来自插件目录，而插件目录要等显示语言冻结才能建。这条依赖链是
/// **接线顺序的守卫**：过早读 codec 会一路传导到文本目录那里 fail-closed 抛错，
/// 而不是静默用一份空 definitions 去解码用户配置。
final agentProviderSettingsCodecProvider = Provider<AgentProviderSettingsCodec>(
  (ref) => AgentProviderSettingsCodec(
    providerDefinitions: ref.watch(agentProviderDefinitionCatalogProvider),
  ),
  name: 'agentProviderSettingsCodec',
);

// ---------------------------------------------------------------------------
// feature data
// ---------------------------------------------------------------------------

/// IDE 会话仓库。
final ideSessionStoreProvider = Provider<IdeSessionStore>(
  (ref) => FileIdeSessionStore(storage: ref.watch(ideSessionStorageProvider)),
  name: 'ideSessionStore',
);

/// 使用统计派生索引仓库。
final usageStatisticsPartitionStoreProvider =
    Provider<UsageStatisticsPartitionStore>(
      (ref) => FileUsageStatisticsPartitionStore(
        storage: ref.watch(usageStatisticsStorageProvider),
      ),
      name: 'usageStatisticsPartitionStore',
    );

/// 应用级共享模型目录仓库。
final agentModelCatalogRepositoryProvider =
    Provider<AgentModelCatalogRepository>(
      (ref) => AgentModelCatalogRepository(
        fingerprintExtraKeysFor: builtInAgentProviderDefinitionCatalog
            .modelCatalogFingerprintExtraKeysFor,
        store: FileAgentModelCatalogCacheStore(
          storage: ref.watch(agentModelCatalogStorageProvider),
        ),
      ),
      name: 'agentModelCatalogRepository',
    );

/// turn 上下文仓库；相对键由 store 自己编码，文档由工厂打开。
final agentTurnContextStoreProvider = Provider<AgentTurnContextStore>(
  (ref) => FileAgentTurnContextStore(
    createStorage: ref.watch(turnContextStorageFactoryProvider),
  ),
  name: 'agentTurnContextStore',
);

/// Provider 配置仓库。
final agentProviderConfigStoreProvider = Provider<AgentProviderConfigStore>(
  (ref) => FileAgentProviderConfigStore(
    storage: ref.watch(providerConfigStorageProvider),
    codec: ref.watch(agentProviderSettingsCodecProvider),
  ),
  name: 'agentProviderConfigStore',
);

/// Claude Code 隐藏 thread 仓库。
final claudeCodeHiddenThreadStoreProvider =
    Provider<ClaudeCodeHiddenThreadStore>(
      (ref) => FileClaudeCodeHiddenThreadStore(
        storage: ref.watch(claudeHiddenThreadsStorageProvider),
      ),
      name: 'claudeCodeHiddenThreadStore',
    );

/// Claude Code 每会话决策仓库工厂。
final claudeCodeSessionDecisionStoreFactoryProvider =
    Provider<ClaudeCodeSessionDecisionStoreFactory>((ref) {
      final openStorage = ref.watch(
        claudeSessionDecisionStorageFactoryProvider,
      );
      return (sessionId) =>
          FileClaudeCodeSessionDecisionStore(storage: openStorage(sessionId));
    }, name: 'claudeCodeSessionDecisionStoreFactory');

/// 常规设置仓库。
final generalSettingsStoreProvider = Provider<GeneralSettingsStore>(
  (ref) => FileGeneralSettingsStore(
    storage: ref.watch(generalSettingsStorageProvider),
    fallbackLanguage: ref.watch(settingsFallbackLanguageProvider),
  ),
  name: 'generalSettingsStore',
);

/// 外观仓库装配。生产走 [FileAppearanceSettingsRepository]，不缓存；测试传入内存实现。
Override appearanceSettingsRepositoryOverride([
  AppearanceSettingsRepository? injected,
]) {
  if (injected != null) {
    return appearanceSettingsRepositoryProvider.overrideWithValue(injected);
  }
  return appearanceSettingsRepositoryProvider.overrideWith(
    (ref) => FileAppearanceSettingsRepository(
      storage: ref.watch(appearanceStorageProvider),
    ),
  );
}
