import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_metric_labels.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

final _log = loggerFor('zeta.agent.runtime_registry');

/// registry 内部使用的复合键：Provider ID + 所属 [AgentProviderRuntimeScopeKey]。
typedef _RuntimeKey = ({String providerId, AgentProviderRuntimeScopeKey scope});

/// 应用级 Provider 运行时注册表。
///
/// 每个 Provider 在每个 [AgentProviderRuntimeScopeKey] 下各自维护一份运行实例；
/// 同一 (providerId, scope) 只会有一个。调用方必须显式声明 global 或 session scope，
/// 避免遗漏参数时意外借用永不空闲回收的 global runtime。
class AgentProviderRuntimeRegistry extends ChangeNotifier {
  AgentProviderRuntimeRegistry({
    required this.providerFactory,
    this.metrics = noopZetaMetricsPort,
  });

  final AgentProviderBundleFactory providerFactory;

  /// 脱敏指标端口；只记录生命周期计数与实例/租约水位。
  final ZetaMetricsPort metrics;

  final Map<_RuntimeKey, _AgentProviderRuntimeEntry> _entries =
      <_RuntimeKey, _AgentProviderRuntimeEntry>{};
  final Map<_RuntimeKey, Future<void>> _closingByKey =
      <_RuntimeKey, Future<void>>{};

  // generation 按 providerId 跨 scope 单调递增，保证旧候选中的 identity
  // 永远不会与后来创建的 session runtime 相等。
  final Map<String, int> _generationByProviderId = <String, int>{};
  bool _closed = false;
  Future<void>? _closeFuture;

  /// 获取指定 Provider 在指定 [scope] 下的共享运行时租约。
  ///
  /// 创建过程会在首次 `await` 前登记实例，因此同一事件循环中的并发调用也只会
  /// 触发一次 factory 创建。影响进程启动的配置变化会先关闭旧实例再创建新实例。
  Future<AgentProviderRuntimeLease> acquire(
    AgentProviderConfig config, {
    required AgentProviderRuntimeScopeKey scope,
  }) async {
    final key = (providerId: config.id, scope: scope);
    while (true) {
      if (_closed) {
        throw StateError('Agent provider runtime registry is closed');
      }

      // 同一个逻辑会话的旧进程必须彻底退出后才能拉起新进程。仅从 _entries
      // 移除旧 entry 会留下一个 dispose/acquire 窗口，使只能承载单会话的 CLI
      // 在短时间内出现两个同 scope 进程。
      final closing = _closingByKey[key];
      if (closing != null) {
        await closing;
        continue;
      }

      final existing = _entries[key];
      if (existing != null) {
        if (_requiresRuntimeRestart(existing.bundle.runtime.config, config)) {
          await _invalidateEntry(key, existing);
          continue;
        }
        metrics.counter(
          ZetaMetric.agentRuntimeLeaseReused,
          tags: _tagsFor(config.id),
        );
        final lease = _createLease(existing);
        _publishRuntimeGauges();
        return lease;
      }

      _log.t('Creating application Agent provider: ${config.id} ($scope)');
      final bundle = providerFactory.createBundle(config);
      if (bundle.runtime.config.id != config.id) {
        // 测试/嵌入宿主的简化 factory 可能为不同配置返回同一对象；若该对象已由
        // 其他 entry 持有，不能因本次身份错配把仍在使用的共享运行时关闭。
        if (!_isRegisteredRuntime(bundle.runtime)) {
          try {
            await bundle.runtime.dispose();
          } catch (error, stackTrace) {
            _log.w(
              'Could not dispose mismatched Agent provider '
              '${bundle.runtime.config.id}',
              error: error,
              stackTrace: stackTrace,
            );
          }
        }
        throw StateError(
          'AgentProviderBundleFactory returned ${bundle.runtime.config.id} '
          'for ${config.id}',
        );
      }

      final generation = (_generationByProviderId[config.id] ?? 0) + 1;
      final identity = AgentProviderRuntimeIdentity(
        providerId: config.id,
        generation: generation,
      );
      final entry = _AgentProviderRuntimeEntry(bundle, identity, scope);
      // acquire 在此之前没有让出执行权；若未来 factory 改成异步，这个保护仍可避免
      // 覆盖已登记的共享实例。
      final raced = _entries[key];
      if (raced != null) {
        if (!identical(raced.bundle.runtime, bundle.runtime) &&
            !_isRegisteredRuntime(bundle.runtime)) {
          await bundle.runtime.dispose();
        }
        continue;
      }
      _generationByProviderId[config.id] = generation;
      _entries[key] = entry;
      metrics.counter(
        ZetaMetric.agentRuntimeCreated,
        tags: _tagsFor(config.id),
      );
      notifyListeners();
      final lease = _createLease(entry);
      _publishRuntimeGauges();
      return lease;
    }
  }

  /// 关闭并移除指定 Provider 在**全部** scope 下的共享运行时。
  ///
  /// 所有指向旧实例的租约会立即失效；控制器收到通知后会在下一次访问时重新获取。
  Future<void> invalidateProvider(String providerId) async {
    final matches = _entries.entries
        .where((entry) => entry.key.providerId == providerId)
        .toList(growable: false);
    await Future.wait(
      matches.map((entry) => _invalidateEntry(entry.key, entry.value)),
    );
  }

  /// 关闭并移除指定 Provider 在**单个** [scope] 下的共享运行时；其余 scope 不受影响。
  Future<void> invalidateScope(
    String providerId,
    AgentProviderRuntimeScopeKey scope,
  ) async {
    final key = (providerId: providerId, scope: scope);
    final entry = _entries[key];
    if (entry == null) {
      return;
    }
    await _invalidateEntry(key, entry);
  }

  /// 仅当 [scope] 仍指向 [expectedIdentity] 时失效运行时。
  ///
  /// 空闲扫描必须使用这个入口，避免扫描快照中的旧候选在 await 之后误杀同一
  /// scope 下后来创建的新实例（ABA）。
  Future<bool> invalidateScopeIfCurrent({
    required String providerId,
    required AgentProviderRuntimeScopeKey scope,
    required AgentProviderRuntimeIdentity expectedIdentity,
  }) async {
    final key = (providerId: providerId, scope: scope);
    final entry = _entries[key];
    if (entry == null || entry.identity != expectedIdentity) {
      return false;
    }
    await _invalidateEntry(key, entry);
    return true;
  }

  /// 关闭注册表拥有的全部 Provider 进程。
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    final future = _closeOnce();
    _closeFuture = future;
    return future;
  }

  /// 当前已创建的 Provider 数量，仅用于生命周期测试与诊断。
  @visibleForTesting
  int get debugProviderCount => _entries.length;

  /// 当前尚未释放的租约数量，仅用于生命周期测试与诊断。
  @visibleForTesting
  int get debugLeaseCount =>
      _entries.values.fold(0, (total, entry) => total + entry.leaseCount);

  AgentProviderRuntimeLease _createLease(_AgentProviderRuntimeEntry entry) {
    entry.leaseCount += 1;
    return AgentProviderRuntimeLease._(this, entry);
  }

  bool _isCurrent(_AgentProviderRuntimeEntry entry) {
    final key = (
      providerId: entry.bundle.runtime.config.id,
      scope: entry.scope,
    );
    return !_closed && !entry.invalidated && identical(_entries[key], entry);
  }

  bool _isRegisteredRuntime(AgentRuntimePort runtime) {
    return _entries.values.any(
      (entry) => identical(entry.bundle.runtime, runtime),
    );
  }

  void _release(_AgentProviderRuntimeEntry entry) {
    if (entry.leaseCount > 0) {
      entry.leaseCount -= 1;
    }
    _publishRuntimeGauges();
  }

  /// Provider ID 只作为标签透传；registry 不按 Provider 分支。
  ZetaMetricTags _tagsFor(String providerId) {
    return metrics.isEnabled
        ? ZetaMetricTags(
            providerId: AgentMetricLabels.forProviderId(providerId),
          )
        : ZetaMetricTags.none;
  }

  void _publishRuntimeGauges() {
    if (!metrics.isEnabled) {
      return;
    }
    metrics.gauge(ZetaMetric.agentRuntimeActiveCount, _entries.length);
    metrics.gauge(ZetaMetric.agentRuntimeActiveLeases, debugLeaseCount);
  }

  Future<void> _invalidateEntry(
    _RuntimeKey key,
    _AgentProviderRuntimeEntry expected,
  ) async {
    if (!identical(_entries[key], expected)) {
      return;
    }
    _entries.remove(key);
    expected.invalidated = true;
    metrics.counter(
      ZetaMetric.agentRuntimeInvalidated,
      tags: _tagsFor(key.providerId),
    );
    _publishRuntimeGauges();
    notifyListeners();
    final disposing = _disposeEntry(expected);
    _closingByKey[key] = disposing;
    try {
      await disposing;
    } finally {
      if (identical(_closingByKey[key], disposing)) {
        _closingByKey.remove(key);
      }
    }
  }

  Future<void> _closeOnce() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final entries = _entries.values.toList(growable: false);
    _entries.clear();
    for (final entry in entries) {
      entry.invalidated = true;
    }
    metrics.counter(ZetaMetric.agentRuntimeRegistryClosed);
    _publishRuntimeGauges();
    notifyListeners();
    await Future.wait(<Future<void>>[
      ...entries.map(_disposeEntry),
      ..._closingByKey.values,
    ]);
    _closingByKey.clear();
  }

  Future<void> _disposeEntry(_AgentProviderRuntimeEntry entry) {
    final existing = entry.disposeFuture;
    if (existing != null) {
      return existing;
    }
    final future = entry.bundle.runtime.dispose().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _log.w(
        'Could not close Agent provider ${entry.bundle.runtime.config.id}',
        error: error,
        stackTrace: stackTrace,
      );
    });
    entry.disposeFuture = future;
    return future;
  }

  bool _requiresRuntimeRestart(
    AgentProviderConfig current,
    AgentProviderConfig requested,
  ) {
    return current.kind != requested.kind ||
        current.command != requested.command ||
        !listEquals(current.arguments, requested.arguments) ||
        !mapEquals(current.environment, requested.environment);
  }
}

/// 对应用级共享 Provider 的可释放引用。
final class AgentProviderRuntimeLease {
  AgentProviderRuntimeLease._(this._registry, this._entry);

  AgentProviderRuntimeRegistry? _registry;
  final _AgentProviderRuntimeEntry _entry;

  AgentProviderBundle get bundle => _entry.bundle;

  /// 当前租约绑定的 provider runtime identity/generation。
  AgentProviderRuntimeIdentity get runtimeIdentity => _entry.identity;

  /// 租约是否仍指向注册表中的当前运行实例。
  bool get isCurrent => _registry?._isCurrent(_entry) ?? false;

  /// 释放引用；Provider 仍由应用注册表保温，直到配置失效或应用退出。
  Future<void> release() async {
    final registry = _registry;
    if (registry == null) {
      return;
    }
    _registry = null;
    registry._release(_entry);
  }
}

final class _AgentProviderRuntimeEntry {
  _AgentProviderRuntimeEntry(this.bundle, this.identity, this.scope);

  final AgentProviderBundle bundle;
  final AgentProviderRuntimeIdentity identity;
  final AgentProviderRuntimeScopeKey scope;
  int leaseCount = 0;

  bool invalidated = false;
  Future<void>? disposeFuture;
}
