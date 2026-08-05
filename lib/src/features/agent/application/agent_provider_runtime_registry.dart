import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/application/agent_permission_state_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

final _log = loggerFor('zeta.agent.runtime_registry');

/// 应用级 Provider 运行时注册表。
///
/// 同一个 Provider ID 在一个 Zeta 进程内只对应一个运行实例。页面、任务工作区、
/// 项目列表和诊断功能通过 [AgentProviderRuntimeLease] 共享实例，不再分别拉起
/// app-server 或 stdio 子进程。
class AgentProviderRuntimeRegistry extends ChangeNotifier {
  AgentProviderRuntimeRegistry({
    required this.providerFactory,
    AgentPermissionStateStore? permissionStateStore,
  }) : permissionStateStore =
           permissionStateStore ?? AgentPermissionStateStore(),
       _ownsPermissionStateStore = permissionStateStore == null;

  final AgentProviderFactory providerFactory;
  final AgentPermissionStateStore permissionStateStore;
  final bool _ownsPermissionStateStore;

  final Map<String, _AgentProviderRuntimeEntry> _entries =
      <String, _AgentProviderRuntimeEntry>{};
  final Map<String, int> _generationByProviderId = <String, int>{};
  bool _closed = false;
  Future<void>? _closeFuture;

  /// 获取指定 Provider 的共享运行时租约。
  ///
  /// 创建过程会在首次 `await` 前登记实例，因此同一事件循环中的并发调用也只会
  /// 触发一次 factory 创建。影响进程启动的配置变化会先关闭旧实例再创建新实例。
  Future<AgentProviderRuntimeLease> acquire(AgentProviderConfig config) async {
    while (true) {
      if (_closed) {
        throw StateError('Agent provider runtime registry is closed');
      }

      final existing = _entries[config.id];
      if (existing != null) {
        if (_requiresRuntimeRestart(existing.provider.config, config)) {
          await _invalidateEntry(config.id, existing);
          continue;
        }
        return _createLease(existing);
      }

      _log.fine('Creating application Agent provider: ${config.id}');
      final provider = providerFactory.create(config);
      if (provider.config.id != config.id) {
        // 测试/嵌入宿主的简化 factory 可能为不同配置返回同一对象；若该对象已由
        // 其他 entry 持有，不能因本次身份错配把仍在使用的共享运行时关闭。
        if (!_isRegisteredProvider(provider)) {
          try {
            await provider.dispose();
          } catch (error, stackTrace) {
            _log.warning(
              'Could not dispose mismatched Agent provider '
              '${provider.config.id}',
              error,
              stackTrace,
            );
          }
        }
        throw StateError(
          'AgentProviderFactory returned ${provider.config.id} for ${config.id}',
        );
      }

      final generation = (_generationByProviderId[config.id] ?? 0) + 1;
      final identity = AgentProviderRuntimeIdentity(
        providerId: config.id,
        generation: generation,
      );
      final entry = _AgentProviderRuntimeEntry(provider, identity);
      // acquire 在此之前没有让出执行权；若未来 factory 改成异步，这个保护仍可避免
      // 覆盖已登记的共享实例。
      final raced = _entries[config.id];
      if (raced != null) {
        if (!identical(raced.provider, provider) &&
            !_isRegisteredProvider(provider)) {
          await provider.dispose();
        }
        continue;
      }
      _generationByProviderId[config.id] = generation;
      _entries[config.id] = entry;
      final configuredOptionId = config.resolvedPermissionOptionId?.trim();
      permissionStateStore.activateRuntime(
        identity,
        initialProviderDefault:
            configuredOptionId == null || configuredOptionId.isEmpty
            ? null
            : AgentPermissionSelection(optionId: configuredOptionId),
      );
      notifyListeners();
      return _createLease(entry);
    }
  }

  /// 关闭并移除指定 Provider 的共享运行时。
  ///
  /// 所有指向旧实例的租约会立即失效；控制器收到通知后会在下一次访问时重新获取。
  Future<void> invalidateProvider(String providerId) async {
    final entry = _entries[providerId];
    if (entry == null) {
      return;
    }
    await _invalidateEntry(providerId, entry);
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
    return !_closed &&
        !entry.invalidated &&
        identical(_entries[entry.provider.config.id], entry);
  }

  bool _isRegisteredProvider(AgentProvider provider) {
    return _entries.values.any((entry) => identical(entry.provider, provider));
  }

  void _release(_AgentProviderRuntimeEntry entry) {
    if (entry.leaseCount > 0) {
      entry.leaseCount -= 1;
    }
  }

  Future<void> _invalidateEntry(
    String providerId,
    _AgentProviderRuntimeEntry expected,
  ) async {
    if (!identical(_entries[providerId], expected)) {
      return;
    }
    _entries.remove(providerId);
    expected.invalidated = true;
    permissionStateStore.retireRuntime(expected.identity);
    notifyListeners();
    await _disposeEntry(expected);
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
      permissionStateStore.retireRuntime(entry.identity);
    }
    notifyListeners();
    await Future.wait(entries.map(_disposeEntry));
    if (_ownsPermissionStateStore) {
      permissionStateStore.dispose();
    }
  }

  Future<void> _disposeEntry(_AgentProviderRuntimeEntry entry) {
    final existing = entry.disposeFuture;
    if (existing != null) {
      return existing;
    }
    final future = entry.provider.dispose().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _log.warning(
        'Could not close Agent provider ${entry.provider.config.id}',
        error,
        stackTrace,
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

  AgentProvider get provider => _entry.provider;

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
  _AgentProviderRuntimeEntry(this.provider, this.identity);

  final AgentProvider provider;
  final AgentProviderRuntimeIdentity identity;
  int leaseCount = 0;
  bool invalidated = false;
  Future<void>? disposeFuture;
}
