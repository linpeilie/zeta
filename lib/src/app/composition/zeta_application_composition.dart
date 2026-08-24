import 'dart:io';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/app/storage/atomic_text_file.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// 应用级 feature data 的唯一构造点。
///
/// `MainApp` 只负责 Flutter / 窗口生命周期与组合输入；**哪个 store 用文件、哪个用
/// 内存**这类决策全部收在这里，由 [ZetaHostMode] 显式驱动，不再从"有没有传
/// session 回调"反推（旧行为见
/// `test/src/app/main_app_host_persistence_characterization_test.dart`）。
///
/// 生命周期：本对象持有的都是无状态或自管理的 store，没有需要显式释放的资源；
/// Agent runtime registry 与插件目录**不在这里**，它们的关闭顺序由
/// `shutdownAgentResourcesInOrder` 单独保证。
final class ZetaApplicationComposition {
  ZetaApplicationComposition._(
    this._injectedConfigStore, {
    required this.hostMode,
    required this.dataPaths,
    required this.ideSessionStore,
    required this.usageStatisticsPartitionStore,
    required this.agentModelCatalogRepository,
    required this.turnContextStore,
  });

  /// 按宿主模式组装应用级 feature data。
  ///
  /// 每个 `?? ` 分支的语义都是"调用方显式注入优先，否则按宿主模式选实现"。
  factory ZetaApplicationComposition.create({
    required ZetaHostMode hostMode,
    ZetaDataPaths? dataPaths,
    IdeSessionStore? ideSessionStore,
    UsageStatisticsPartitionStore? usageStatisticsPartitionStore,
    AgentModelCatalogRepository? agentModelCatalogRepository,
    AgentTurnContextStore? turnContextStore,
    AgentProviderConfigStore? agentProviderConfigStore,
  }) {
    final useFiles = hostMode.usesFilePersistence && dataPaths != null;
    return ZetaApplicationComposition._(
      agentProviderConfigStore,
      hostMode: hostMode,
      dataPaths: dataPaths,
      ideSessionStore:
          ideSessionStore ??
          (useFiles
              ? FileIdeSessionStore(
                  storage: AtomicTextFile(File(dataPaths.ideSessionFilePath)),
                )
              : MemoryIdeSessionStore()),
      usageStatisticsPartitionStore:
          usageStatisticsPartitionStore ??
          (useFiles
              ? FileUsageStatisticsPartitionStore(
                  storage: AtomicTextFile(
                    File(dataPaths.usageStatisticsIndexFilePath),
                  ),
                )
              : MemoryUsageStatisticsPartitionStore()),
      agentModelCatalogRepository:
          agentModelCatalogRepository ??
          AgentModelCatalogRepository(
            fingerprintExtraKeysFor: builtInAgentProviderDefinitionCatalog
                .modelCatalogFingerprintExtraKeysFor,
            store: useFiles
                ? FileAgentModelCatalogCacheStore(
                    storage: AtomicTextFile(
                      File(dataPaths.agentModelCatalogCacheFilePath),
                    ),
                  )
                : MemoryAgentModelCatalogCacheStore(),
          ),
      turnContextStore:
          turnContextStore ??
          (useFiles
              ? FileAgentTurnContextStore(
                  rootDirectory: Directory(dataPaths.sessionStateDirectoryPath),
                  createStorage: (path) => AtomicTextFile(File(path)),
                )
              : MemoryAgentTurnContextStore()),
    );
  }

  final ZetaHostMode hostMode;
  final ZetaDataPaths? dataPaths;
  final IdeSessionStore ideSessionStore;
  final UsageStatisticsPartitionStore usageStatisticsPartitionStore;
  final AgentModelCatalogRepository agentModelCatalogRepository;
  final AgentTurnContextStore turnContextStore;

  final AgentProviderConfigStore? _injectedConfigStore;

  /// 是否使用本机文件持久化。
  bool get usesFilePersistence =>
      hostMode.usesFilePersistence && dataPaths != null;

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
    final paths = dataPaths;
    if (usesFilePersistence && paths != null) {
      return FileAgentProviderConfigStore(
        storage: AtomicTextFile(File(paths.providersFilePath)),
        codec: codec,
      );
    }
    return MemoryAgentProviderConfigStore();
  }

  /// Claude Code 每会话决策存储工厂；临时宿主模式下为 `null`（插件回退到内存）。
  ClaudeCodeSessionDecisionStore Function(String sessionId)?
  get claudeCodeSessionDecisionStoreFactory {
    final paths = dataPaths;
    if (!usesFilePersistence || paths == null) {
      return null;
    }
    return (sessionId) => FileClaudeCodeSessionDecisionStore(
      storage: AtomicTextFile(_claudeCodeSessionDecisionFile(paths, sessionId)),
    );
  }

  /// Claude Code 隐藏 thread 存储；临时宿主模式下为 `null`。
  ClaudeCodeHiddenThreadStore? get claudeCodeHiddenThreadStore {
    final paths = dataPaths;
    if (!usesFilePersistence || paths == null) {
      return null;
    }
    return FileClaudeCodeHiddenThreadStore(
      storage: AtomicTextFile(_claudeCodeHiddenThreadsFile(paths)),
    );
  }
}

File _claudeCodeSessionDecisionFile(ZetaDataPaths dataPaths, String sessionId) {
  final encodedSessionId = Uri.encodeComponent(sessionId);
  return File(
    '${dataPaths.stateDirectoryPath}${Platform.pathSeparator}'
    'claude_code${Platform.pathSeparator}session_$encodedSessionId.json',
  );
}

File _claudeCodeHiddenThreadsFile(ZetaDataPaths dataPaths) {
  return File(
    '${dataPaths.stateDirectoryPath}${Platform.pathSeparator}'
    'claude_code${Platform.pathSeparator}hidden_threads.json',
  );
}
