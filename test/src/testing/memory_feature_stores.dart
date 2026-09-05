import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart'
    as provider_sdk;
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings_repository.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

export 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart'
    show MemoryAgentModelCatalogCacheStore;

/// 测试用外观仓库：预置 typed 状态，不走 JSON。
class MemoryAppearanceSettingsStore implements AppearanceSettingsRepository {
  MemoryAppearanceSettingsStore([AppearanceSettings? settings])
    : _settings = settings ?? const AppearanceSettings();

  AppearanceSettings _settings;

  @override
  Future<AppearanceSettings> load() async => _settings;

  @override
  Future<void> save(AppearanceSettings settings) async {
    _settings = settings;
  }
}

/// 测试用常规设置仓库。
class MemoryGeneralSettingsStore implements GeneralSettingsStore {
  MemoryGeneralSettingsStore([
    GeneralSettings? settings,
    AppLanguage fallbackLanguage = AppLanguage.simplifiedChinese,
  ]) : _settings = settings ?? GeneralSettings(appLanguage: fallbackLanguage);

  GeneralSettings _settings;

  @override
  Future<GeneralSettings> load() async => _settings;

  @override
  Future<void> save(GeneralSettings settings) async {
    _settings = settings;
  }
}

/// 根测试兼容层：为 SDK 的中立内存仓库补入当前内置 Provider 默认设置。
class MemoryAgentProviderConfigStore
    extends provider_sdk.MemoryAgentProviderConfigStore {
  MemoryAgentProviderConfigStore([AgentProviderSettings? settings])
    : super(settings ?? zetaBuiltInAgentProviderSettings);
}

/// 测试用用量分区仓库。
final class MemoryUsageStatisticsPartitionStore
    implements UsageStatisticsPartitionStore {
  MemoryUsageStatisticsPartitionStore({
    Map<String, UsageStatisticsIndexPartition> partitions =
        const <String, UsageStatisticsIndexPartition>{},
  }) : _partitions = <String, UsageStatisticsIndexPartition>{...partitions};

  final Map<String, UsageStatisticsIndexPartition> _partitions;

  @override
  Future<UsageStatisticsIndexPartition?> readPartition(String sourceKey) async {
    return _partitions[sourceKey.trim()];
  }

  @override
  Future<void> writePartition(
    String sourceKey,
    UsageStatisticsIndexPartition partition,
  ) async {
    _partitions[sourceKey.trim()] = partition;
  }
}
