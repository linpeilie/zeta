import 'dart:async';
import 'dart:convert';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

final _log = loggerFor('zeta.agent.model_catalog');

/// 从 Provider 权威来源刷新模型目录。
///
/// 只有共享仓储判断缓存缺失、过期或被强制刷新时才会调用；实现必须绕过 Provider
/// 实例内的目录缓存，避免下层缓存重新延长共享仓储的 TTL。
typedef AgentModelCatalogLoader = Future<AgentModelList> Function();

/// 一次模型目录读取的结果。
class AgentModelCatalogLoadResult {
  const AgentModelCatalogLoadResult({
    required this.models,
    required this.fetchedAt,
    required this.fromCache,
    required this.refreshed,
    required this.isStale,
    this.refreshError,
  });

  final AgentModelList models;
  final DateTime fetchedAt;
  final bool fromCache;
  final bool refreshed;
  final bool isStale;

  /// 后台刷新失败时保留的错误；此时 [models] 仍是最近一次可用缓存。
  final Object? refreshError;
}

/// 应用级共享模型目录。
///
/// 目录采用 stale-while-revalidate：新鲜缓存直接返回；过期但仍可用的缓存会先通过
/// [onCacheHit] 发布，再用 single-flight 刷新。持久化失败只影响下次启动，不阻断
/// 当前会话使用已经获取的模型。
class AgentModelCatalogRepository {
  AgentModelCatalogRepository({
    required this.store,
    this.freshFor = const Duration(hours: 1),
    this.maxStaleFor = const Duration(days: 7),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AgentModelCatalogCacheStore store;
  final Duration freshFor;
  final Duration maxStaleFor;
  final DateTime Function() _clock;

  final Map<String, AgentModelCatalogSnapshot> _snapshots =
      <String, AgentModelCatalogSnapshot>{};
  final Map<String, Future<AgentModelCatalogSnapshot>> _refreshes =
      <String, Future<AgentModelCatalogSnapshot>>{};
  final Map<String, int> _providerGenerations = <String, int>{};
  final Map<String, int> _slotGenerations = <String, int>{};
  Future<void>? _loadOperation;
  Future<void>? _saveOperation;
  int _stateRevision = 0;
  int _persistedRevision = 0;

  /// 读取缓存并在需要时刷新模型目录。
  Future<AgentModelCatalogLoadResult> load({
    required AgentProviderConfig config,
    required String source,
    required AgentModelCatalogLoader refreshLoader,
    bool includeHidden = false,
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  }) async {
    await _ensureLoaded();
    final cached = _cachedSnapshot(config, includeHidden: includeHidden);
    if (cached != null) {
      onCacheHit?.call(cached);
      if (!forceRefresh && _isFresh(cached)) {
        return AgentModelCatalogLoadResult(
          models: cached.models,
          fetchedAt: cached.fetchedAt,
          fromCache: true,
          refreshed: false,
          isStale: false,
        );
      }
    }

    try {
      final refreshed = await _refresh(
        config: config,
        includeHidden: includeHidden,
        source: source,
        refreshLoader: refreshLoader,
      );
      return AgentModelCatalogLoadResult(
        models: refreshed.models,
        fetchedAt: refreshed.fetchedAt,
        fromCache: false,
        refreshed: true,
        isStale: false,
      );
    } catch (error, stackTrace) {
      if (cached == null) {
        rethrow;
      }
      _log.w(
        'Could not refresh model catalog for ${config.id}; using stale cache',
        error: error,
        stackTrace: stackTrace,
      );
      return AgentModelCatalogLoadResult(
        models: cached.models,
        fetchedAt: cached.fetchedAt,
        fromCache: true,
        refreshed: false,
        isStale: true,
        refreshError: error,
      );
    }
  }

  /// 记录 Provider 主动推送的完整模型目录，例如 Grok session payload。
  Future<void> record({
    required AgentProviderConfig config,
    required AgentModelList models,
    required String source,
    bool includeHidden = false,
  }) async {
    await _ensureLoaded();
    final key = _cacheKey(config.id, includeHidden);
    final previous = _snapshots[key];
    if (previous != null &&
        previous.configFingerprint == configFingerprint(config) &&
        _modelListsEqual(previous.models, models)) {
      return;
    }
    _slotGenerations[key] = (_slotGenerations[key] ?? 0) + 1;
    _storeSnapshot(
      config: config,
      includeHidden: includeHidden,
      models: models,
      source: source,
    );
    await _persistBestEffort();
  }

  /// 清除指定 Provider 的全部可见/隐藏目录缓存。
  Future<void> invalidateProvider(String providerId) async {
    // 必须在首个 await 前废弃旧代，避免配置切换与旧 refreshLoader 完成形成竞态。
    _providerGenerations[providerId] =
        (_providerGenerations[providerId] ?? 0) + 1;
    await _ensureLoaded();
    final previousLength = _snapshots.length;
    _snapshots.removeWhere((_, snapshot) => snapshot.providerId == providerId);
    if (_snapshots.length != previousLength) {
      _stateRevision += 1;
      await _persistBestEffort();
    }
  }

  /// 为缓存生成不包含环境变量值或原始扩展配置的稳定指纹。
  String configFingerprint(AgentProviderConfig config) {
    final environmentKeys = config.environment.keys.toList()..sort();
    const extraKeys = <String>[
      claudeCodeAccountDataEnrichmentKey,
      'cliPath',
      'detectedCurrentVersion',
      'modelProvider',
      'modelProviderId',
      'profile',
    ];
    final safeJson = jsonEncode(<String, Object?>{
      'kind': config.kind.name,
      'command': config.command,
      'arguments': config.arguments,
      'defaultModel': config.defaultModel,
      'environmentKeys': environmentKeys,
      'extra': <String, Object?>{
        for (final key in extraKeys)
          if (config.extra.containsKey(key)) key: '${config.extra[key]}',
      },
    });
    return _fnv1a32(safeJson);
  }

  Future<AgentModelCatalogSnapshot> _refresh({
    required AgentProviderConfig config,
    required bool includeHidden,
    required String source,
    required AgentModelCatalogLoader refreshLoader,
  }) async {
    final key = _cacheKey(config.id, includeHidden);
    final fingerprint = configFingerprint(config);
    final providerGeneration = _providerGenerations[config.id] ?? 0;
    final refreshKey = '$key|$fingerprint|$providerGeneration';
    final inFlight = _refreshes[refreshKey];
    if (inFlight != null) {
      return inFlight;
    }
    final slotGeneration = (_slotGenerations[key] ?? 0) + 1;
    _slotGenerations[key] = slotGeneration;
    final operation = () async {
      final models = await refreshLoader();
      _ensureRefreshCurrent(
        config: config,
        key: key,
        providerGeneration: providerGeneration,
        slotGeneration: slotGeneration,
      );
      final snapshot = _storeSnapshot(
        config: config,
        includeHidden: includeHidden,
        models: models,
        source: source,
      );
      await _persistBestEffort();
      _ensureRefreshCurrent(
        config: config,
        key: key,
        providerGeneration: providerGeneration,
        slotGeneration: slotGeneration,
      );
      return snapshot;
    }();
    _refreshes[refreshKey] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshes[refreshKey], operation)) {
        _refreshes.remove(refreshKey);
      }
    }
  }

  AgentModelCatalogSnapshot _storeSnapshot({
    required AgentProviderConfig config,
    required bool includeHidden,
    required AgentModelList models,
    required String source,
  }) {
    final normalized = AgentModelList(
      models: List<AgentModelInfo>.unmodifiable(models.models),
    );
    final snapshot = AgentModelCatalogSnapshot(
      providerId: config.id,
      configFingerprint: configFingerprint(config),
      includeHidden: includeHidden,
      models: normalized,
      fetchedAt: _clock().toUtc(),
      source: source,
    );
    _snapshots[_cacheKey(config.id, includeHidden)] = snapshot;
    _stateRevision += 1;
    _log.i(
      'Stored model catalog for ${config.id} '
      '(source=$source, includeHidden=$includeHidden): '
      '${normalized.describeForLog()}',
    );
    return snapshot;
  }

  void _ensureRefreshCurrent({
    required AgentProviderConfig config,
    required String key,
    required int providerGeneration,
    required int slotGeneration,
  }) {
    if ((_providerGenerations[config.id] ?? 0) != providerGeneration ||
        (_slotGenerations[key] ?? 0) != slotGeneration) {
      throw _AgentModelCatalogRefreshSuperseded(config.id);
    }
  }

  AgentModelCatalogSnapshot? _cachedSnapshot(
    AgentProviderConfig config, {
    required bool includeHidden,
  }) {
    final key = _cacheKey(config.id, includeHidden);
    final snapshot = _snapshots[key];
    if (snapshot == null) {
      return null;
    }
    final age = _clock().toUtc().difference(snapshot.fetchedAt.toUtc());
    if (snapshot.configFingerprint != configFingerprint(config) ||
        age > maxStaleFor) {
      _snapshots.remove(key);
      _stateRevision += 1;
      unawaited(_persistBestEffort());
      return null;
    }
    return snapshot;
  }

  bool _isFresh(AgentModelCatalogSnapshot snapshot) {
    final age = _clock().toUtc().difference(snapshot.fetchedAt.toUtc());
    return !age.isNegative && age <= freshFor;
  }

  Future<void> _ensureLoaded() {
    final existing = _loadOperation;
    if (existing != null) {
      return existing;
    }
    final operation = () async {
      try {
        final loaded = await store.load();
        for (final snapshot in loaded) {
          final key = _cacheKey(snapshot.providerId, snapshot.includeHidden);
          final previous = _snapshots[key];
          if (previous == null ||
              snapshot.fetchedAt.isAfter(previous.fetchedAt)) {
            _snapshots[key] = snapshot;
          }
        }
      } catch (error, stackTrace) {
        _log.w(
          'Could not read model catalog cache',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }();
    _loadOperation = operation;
    return operation;
  }

  Future<void> _persistBestEffort() {
    if (_persistedRevision == _stateRevision) {
      return Future<void>.value();
    }
    final existing = _saveOperation;
    if (existing != null) {
      return existing;
    }
    var completedSuccessfully = false;
    late final Future<void> trackedOperation;
    trackedOperation = _runPersistLoop()
        .then<void>((value) => completedSuccessfully = value)
        .whenComplete(() {
          if (identical(_saveOperation, trackedOperation)) {
            _saveOperation = null;
            // 正常保存结束与清理 operation 之间仍可能插入一次状态更新；仅在前一轮
            // 成功时补跑。I/O 失败则等待下一次真实状态更新再重试，避免自旋写盘。
            if (completedSuccessfully && _persistedRevision != _stateRevision) {
              unawaited(_persistBestEffort());
            }
          }
        });
    _saveOperation = trackedOperation;
    return trackedOperation;
  }

  Future<bool> _runPersistLoop() async {
    while (_persistedRevision != _stateRevision) {
      final revision = _stateRevision;
      final snapshots = List<AgentModelCatalogSnapshot>.unmodifiable(
        _snapshots.values,
      );
      try {
        await store.save(snapshots);
        _persistedRevision = revision;
      } catch (error, stackTrace) {
        _log.w(
          'Could not persist model catalog cache',
          error: error,
          stackTrace: stackTrace,
        );
        return false;
      }
    }
    return true;
  }
}

final class _AgentModelCatalogRefreshSuperseded implements Exception {
  const _AgentModelCatalogRefreshSuperseded(this.providerId);

  final String providerId;

  @override
  String toString() =>
      'Model catalog refresh for $providerId was superseded by newer config';
}

/// 按 Provider 能力选择普通读取或强制刷新。
Future<AgentModelList> fetchAgentProviderModels(
  AgentModelCatalogPort modelCatalog, {
  bool forceRefresh = false,
  int limit = 20,
  bool includeHidden = false,
}) {
  return modelCatalog.listModels(
    limit: limit,
    includeHidden: includeHidden,
    forceRefresh: forceRefresh,
  );
}

String _cacheKey(String providerId, bool includeHidden) =>
    '$providerId|${includeHidden ? 'all' : 'visible'}';

String _fnv1a32(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

bool _modelListsEqual(AgentModelList left, AgentModelList right) {
  if (left.models.length != right.models.length) {
    return false;
  }
  for (var index = 0; index < left.models.length; index += 1) {
    if (!_modelsEqual(left.models[index], right.models[index])) {
      return false;
    }
  }
  return true;
}

bool _modelsEqual(AgentModelInfo left, AgentModelInfo right) {
  return left.id == right.id &&
      left.model == right.model &&
      left.displayName == right.displayName &&
      left.description == right.description &&
      left.hidden == right.hidden &&
      _reasoningEffortsEqual(
        left.supportedReasoningEfforts,
        right.supportedReasoningEfforts,
      ) &&
      left.defaultReasoningEffort == right.defaultReasoningEffort &&
      _serviceTiersEqual(left.serviceTiers, right.serviceTiers) &&
      left.defaultServiceTier == right.defaultServiceTier &&
      left.isDefault == right.isDefault &&
      left.enabled == right.enabled &&
      left.unavailableReason == right.unavailableReason &&
      left.contextWindowTokens == right.contextWindowTokens;
}

bool _reasoningEffortsEqual(
  List<AgentModelReasoningEffort> left,
  List<AgentModelReasoningEffort> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].effort != right[index].effort ||
        left[index].description != right[index].description) {
      return false;
    }
  }
  return true;
}

bool _serviceTiersEqual(
  List<AgentModelServiceTier> left,
  List<AgentModelServiceTier> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final leftTier = left[index];
    final rightTier = right[index];
    if (leftTier.id != rightTier.id ||
        leftTier.name != rightTier.name ||
        leftTier.description != rightTier.description ||
        leftTier.enabled != rightTier.enabled ||
        leftTier.unavailableReason != rightTier.unavailableReason) {
      return false;
    }
  }
  return true;
}
