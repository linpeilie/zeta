import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 外观设置文档。生产组合必须覆盖；缺失即为接线错误。
final appearanceStorageProvider = Provider<StorageService>(
  (ref) => throw StateError('Appearance storage is not installed'),
  name: 'appearanceStorage',
);

/// 常规设置文档。
final generalSettingsStorageProvider = Provider<StorageService>(
  (ref) => throw StateError('General settings storage is not installed'),
  name: 'generalSettingsStorage',
);

/// Provider 配置文档。
final providerConfigStorageProvider = Provider<StorageService>(
  (ref) => throw StateError('Provider config storage is not installed'),
  name: 'providerConfigStorage',
);

/// IDE 会话文档。
final ideSessionStorageProvider = Provider<StorageService>(
  (ref) => throw StateError('IDE session storage is not installed'),
  name: 'ideSessionStorage',
);

/// 使用统计派生索引文档。
final usageStatisticsStorageProvider = Provider<StorageService>(
  (ref) => throw StateError('Usage statistics storage is not installed'),
  name: 'usageStatisticsStorage',
);

/// Agent 模型目录缓存文档。
final agentModelCatalogStorageProvider = Provider<StorageService>(
  (ref) => throw StateError('Agent model catalog storage is not installed'),
  name: 'agentModelCatalogStorage',
);

/// Claude Code 隐藏 thread 文档。
final claudeHiddenThreadsStorageProvider = Provider<StorageService>(
  (ref) => throw StateError('Claude hidden threads storage is not installed'),
  name: 'claudeHiddenThreadsStorage',
);

/// turn 上下文的按键工厂。
final turnContextStorageFactoryProvider = Provider<StorageServiceFactory>(
  (ref) => throw StateError('Turn context storage factory is not installed'),
  name: 'turnContextStorageFactory',
);

/// Claude Code 每会话决策的按键工厂。
final claudeSessionDecisionStorageFactoryProvider =
    Provider<StorageServiceFactory>(
      (ref) => throw StateError(
        'Claude session decision storage factory is not installed',
      ),
      name: 'claudeSessionDecisionStorageFactory',
    );
