import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

/// 全局 Provider 实例的一次操作上下文。
@immutable
final class AgentProviderGlobalRuntimeContext {
  const AgentProviderGlobalRuntimeContext({
    required this.bundle,
    required this.runtimeIdentity,
  });

  final AgentProviderBundle bundle;
  final AgentProviderRuntimeIdentity runtimeIdentity;

  AgentProviderConfig get config => bundle.runtime.config;
  AgentProviderCapabilities get capabilities => bundle.runtime.capabilities;
}

/// 会话建立前所有 Provider 操作的统一入口。
///
/// global scope 不参与空闲回收；调用者只能在 [run] 回调期间使用 bundle，避免把
/// 原始 Provider 或 lease 缓存进 ViewModel。
final class AgentProviderGlobalRuntime {
  AgentProviderGlobalRuntime({required this.runtimeRegistry});

  final AgentProviderRuntimeRegistry runtimeRegistry;
  final Map<AgentProviderRuntimeIdentity, Future<void>> _initializations =
      <AgentProviderRuntimeIdentity, Future<void>>{};

  Future<T> run<T>(
    AgentProviderConfig config,
    Future<T> Function(AgentProviderGlobalRuntimeContext runtime) operation,
  ) async {
    final lease = await runtimeRegistry.acquire(
      config,
      scope: AgentProviderRuntimeScopeKey.global,
    );
    try {
      final bundle = lease.provider.bundle;
      _initializations.removeWhere(
        (identity, _) =>
            identity.providerId == config.id &&
            identity != lease.runtimeIdentity,
      );
      final initialization = _initializations.putIfAbsent(
        lease.runtimeIdentity,
        bundle.runtime.initialize,
      );
      try {
        await initialization;
      } catch (_) {
        if (identical(
          _initializations[lease.runtimeIdentity],
          initialization,
        )) {
          _initializations.remove(lease.runtimeIdentity);
        }
        rethrow;
      }
      return await operation(
        AgentProviderGlobalRuntimeContext(
          bundle: bundle,
          runtimeIdentity: lease.runtimeIdentity,
        ),
      );
    } finally {
      await lease.release();
    }
  }
}
