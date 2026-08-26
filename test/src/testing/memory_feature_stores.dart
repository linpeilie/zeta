import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// 测试用外观仓库：预置 typed 状态，不走 JSON。
class MemoryAppearanceSettingsStore implements AppearanceSettingsStore {
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

/// 测试用 Provider 配置仓库。codec 依赖插件目录，测试用 typed 状态绕过它。
class MemoryAgentProviderConfigStore implements AgentProviderConfigStore {
  MemoryAgentProviderConfigStore([AgentProviderSettings? settings])
    : _settings = settings ?? builtInAgentProviderSettings;

  AgentProviderSettings _settings;

  @override
  Future<AgentProviderSettings> load() async => _settings;

  @override
  Future<void> save(AgentProviderSettings settings) async {
    _settings = settings;
  }
}

/// 测试用模型目录缓存。
class MemoryAgentModelCatalogCacheStore implements AgentModelCatalogCacheStore {
  MemoryAgentModelCatalogCacheStore([
    List<AgentModelCatalogSnapshot> snapshots =
        const <AgentModelCatalogSnapshot>[],
  ]) : _snapshots = List<AgentModelCatalogSnapshot>.from(snapshots);

  List<AgentModelCatalogSnapshot> _snapshots;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async =>
      List<AgentModelCatalogSnapshot>.unmodifiable(_snapshots);

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) async {
    _snapshots = List<AgentModelCatalogSnapshot>.from(snapshots);
  }
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
