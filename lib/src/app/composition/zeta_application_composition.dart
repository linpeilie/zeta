import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/app/storage/zeta_storage_bindings.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// 应用级 feature data 的唯一构造点。
///
/// `MainApp` 只负责 Flutter / 窗口生命周期与组合输入；落盘还是内存由注入的
/// [ZetaStorageBindings] 决定，不再从路径是否为 null 反推。
///
/// 生命周期：本对象持有的都是无状态或自管理的 store，没有需要显式释放的资源；
/// Agent runtime registry 与插件目录**不在这里**，它们的关闭顺序由
/// `shutdownAgentResourcesInOrder` 单独保证。
final class ZetaApplicationComposition {
  ZetaApplicationComposition._(
    this._injectedConfigStore, {
    required this.hostMode,
    required this.storage,
    required this.ideSessionStore,
    required this.usageStatisticsPartitionStore,
    required this.agentModelCatalogRepository,
    required this.turnContextStore,
  });

  /// 按宿主模式与存储绑定组装应用级 feature data。
  ///
  /// 每个 `?? ` 分支的语义都是"调用方显式注入优先，否则用 codec store +
  /// bindings 里的 StorageService"。
  factory ZetaApplicationComposition.create({
    required ZetaHostMode hostMode,
    required ZetaStorageBindings storage,
    IdeSessionStore? ideSessionStore,
    UsageStatisticsPartitionStore? usageStatisticsPartitionStore,
    AgentModelCatalogRepository? agentModelCatalogRepository,
    AgentTurnContextStore? turnContextStore,
    AgentProviderConfigStore? agentProviderConfigStore,
  }) {
    return ZetaApplicationComposition._(
      agentProviderConfigStore,
      hostMode: hostMode,
      storage: storage,
      ideSessionStore:
          ideSessionStore ?? FileIdeSessionStore(storage: storage.ideSession),
      usageStatisticsPartitionStore:
          usageStatisticsPartitionStore ??
          FileUsageStatisticsPartitionStore(storage: storage.usageStatistics),
      agentModelCatalogRepository:
          agentModelCatalogRepository ??
          AgentModelCatalogRepository(
            fingerprintExtraKeysFor: builtInAgentProviderDefinitionCatalog
                .modelCatalogFingerprintExtraKeysFor,
            store: FileAgentModelCatalogCacheStore(
              storage: storage.agentModelCatalog,
            ),
          ),
      turnContextStore:
          turnContextStore ??
          FileAgentTurnContextStore(createStorage: storage.turnContextFactory),
    );
  }

  final ZetaHostMode hostMode;
  final ZetaStorageBindings storage;
  final IdeSessionStore ideSessionStore;
  final UsageStatisticsPartitionStore usageStatisticsPartitionStore;
  final AgentModelCatalogRepository agentModelCatalogRepository;
  final AgentTurnContextStore turnContextStore;

  final AgentProviderConfigStore? _injectedConfigStore;

  /// Provider 配置仓库。
  ///
  /// 单独做成方法而不是字段：codec 依赖插件目录解析出的 Provider definitions，
  /// 而插件目录要等本地化运行时就绪才能建。
  AgentProviderConfigStore createAgentProviderConfigStore(
    AgentProviderSettingsCodec codec,
  ) {
    final injected = _injectedConfigStore;
    if (injected != null) {
      return injected;
    }
    return FileAgentProviderConfigStore(
      storage: storage.providerConfig,
      codec: codec,
    );
  }

  /// Claude Code 每会话决策存储工厂。
  ClaudeCodeSessionDecisionStore Function(String sessionId)
  get claudeCodeSessionDecisionStoreFactory {
    return (sessionId) => FileClaudeCodeSessionDecisionStore(
      storage: storage.claudeSessionDecisionFactory(sessionId),
    );
  }

  /// Claude Code 隐藏 thread 存储。
  ClaudeCodeHiddenThreadStore get claudeCodeHiddenThreadStore {
    return FileClaudeCodeHiddenThreadStore(
      storage: storage.claudeHiddenThreads,
    );
  }
}
