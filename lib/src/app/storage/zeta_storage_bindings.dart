import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/app/storage/file_storage_service.dart';
import 'package:zeta/src/app/storage/zeta_storage_providers.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';

/// 应用级文档存储的唯一装配点。
///
/// `ZetaDataPaths` 只在这里解析成一组已绑定位置的 [StorageService]；
/// `MainApp` 与 feature store 不再接收路径对象。
final class ZetaStorageBindings {
  const ZetaStorageBindings({
    required this.appearance,
    required this.generalSettings,
    required this.providerConfig,
    required this.ideSession,
    required this.usageStatistics,
    required this.agentModelCatalog,
    required this.claudeHiddenThreads,
    required this.turnContextFactory,
    required this.claudeSessionDecisionFactory,
  });

  /// 生产：每个固定文件一个 [FileStorageService]，动态文件走工厂。
  factory ZetaStorageBindings.file(ZetaDataPaths paths) {
    return ZetaStorageBindings(
      appearance: FileStorageService(File(paths.appearanceFilePath)),
      generalSettings: FileStorageService(File(paths.generalSettingsFilePath)),
      providerConfig: FileStorageService(File(paths.providersFilePath)),
      ideSession: FileStorageService(File(paths.ideSessionFilePath)),
      usageStatistics: FileStorageService(
        File(paths.usageStatisticsIndexFilePath),
      ),
      agentModelCatalog: FileStorageService(
        File(paths.agentModelCatalogCacheFilePath),
      ),
      claudeHiddenThreads: FileStorageService(
        _claudeCodeHiddenThreadsFile(paths),
      ),
      turnContextFactory: (key) =>
          FileStorageService(_fileUnder(paths.sessionStateDirectoryPath, key)),
      claudeSessionDecisionFactory: (sessionId) =>
          FileStorageService(_claudeCodeSessionDecisionFile(paths, sessionId)),
    );
  }

  /// 临时宿主 / widget test：全部留在进程内，不触碰 `~/.zeta`。
  factory ZetaStorageBindings.memory() {
    final keyed = <String, MemoryStorageService>{};
    MemoryStorageService open(String key) =>
        keyed.putIfAbsent(key, MemoryStorageService.new);
    return ZetaStorageBindings(
      appearance: MemoryStorageService(),
      generalSettings: MemoryStorageService(),
      providerConfig: MemoryStorageService(),
      ideSession: MemoryStorageService(),
      usageStatistics: MemoryStorageService(),
      agentModelCatalog: MemoryStorageService(),
      claudeHiddenThreads: MemoryStorageService(),
      turnContextFactory: (key) => open('turn:$key'),
      claudeSessionDecisionFactory: (sessionId) =>
          open('claude-session:$sessionId'),
    );
  }

  final StorageService appearance;
  final StorageService generalSettings;
  final StorageService providerConfig;
  final StorageService ideSession;
  final StorageService usageStatistics;
  final StorageService agentModelCatalog;
  final StorageService claudeHiddenThreads;
  final StorageServiceFactory turnContextFactory;
  final StorageServiceFactory claudeSessionDecisionFactory;

  /// 装进 `ProviderContainer` 的定长 override。
  List<Override> get providerOverrides => <Override>[
    appearanceStorageProvider.overrideWithValue(appearance),
    generalSettingsStorageProvider.overrideWithValue(generalSettings),
    providerConfigStorageProvider.overrideWithValue(providerConfig),
    ideSessionStorageProvider.overrideWithValue(ideSession),
    usageStatisticsStorageProvider.overrideWithValue(usageStatistics),
    agentModelCatalogStorageProvider.overrideWithValue(agentModelCatalog),
    claudeHiddenThreadsStorageProvider.overrideWithValue(claudeHiddenThreads),
    turnContextStorageFactoryProvider.overrideWithValue(turnContextFactory),
    claudeSessionDecisionStorageFactoryProvider.overrideWithValue(
      claudeSessionDecisionFactory,
    ),
  ];
}

File _fileUnder(String root, String relativeKey) {
  final segments = relativeKey.split('/');
  if (segments.isEmpty ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw ArgumentError.value(relativeKey, 'relativeKey');
  }
  return File(([root, ...segments]).join(Platform.pathSeparator));
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
