import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_provider_global_runtime.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/usage_statistics/data/global_runtime_agent_usage_quota_source.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';

import '../../../testing/agent_provider_stub_base.dart';
import '../../../testing/legacy_bundle_factory_mixin.dart';

void main() {
  test(
    'reads available quota only inside global runtime and releases lease',
    () async {
      final factory = _QuotaProviderFactory(quotaThrows: false);
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final source = GlobalRuntimeAgentUsageQuotaSource(
        AgentProviderGlobalRuntime(runtimeRegistry: registry),
      );

      final result = await source.loadQuota(AgentProviderConfig.defaultCodex);

      expect(result.status, AgentUsageCapabilityStatus.available);
      expect(result.value?.providerId, defaultAgentProviderId);
      expect(factory.provider.initializeCount, 1);
      expect(factory.provider.quotaReadCount, 1);
      expect(registry.debugLeaseCount, 0);
    },
  );

  test('maps quota errors to sanitized unavailable result', () async {
    final factory = _QuotaProviderFactory(quotaThrows: true);
    final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
    addTearDown(registry.close);
    final source = GlobalRuntimeAgentUsageQuotaSource(
      AgentProviderGlobalRuntime(runtimeRegistry: registry),
    );

    final result = await source.loadQuota(AgentProviderConfig.defaultCodex);

    expect(result.status, AgentUsageCapabilityStatus.unavailable);
    expect(result.warning?.code, 'quota-unavailable');
    expect(result.warning?.message, isNot(contains('sensitive')));
    expect(registry.debugLeaseCount, 0);
  });

  test('missing bundle port is explicitly unsupported', () async {
    final factory = _PlainProviderFactory();
    final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
    addTearDown(registry.close);
    final source = GlobalRuntimeAgentUsageQuotaSource(
      AgentProviderGlobalRuntime(runtimeRegistry: registry),
    );

    final result = await source.loadQuota(AgentProviderConfig.defaultCodex);

    expect(result.status, AgentUsageCapabilityStatus.unsupported);
    expect(registry.debugLeaseCount, 0);
  });
}

final class _QuotaProviderFactory with LegacyBundleFactoryMixin {
  _QuotaProviderFactory({required bool quotaThrows})
    : provider = _QuotaProvider(quotaThrows: quotaThrows);

  final _QuotaProvider provider;

  @override
  Object create(AgentProviderConfig config) => provider;
}

final class _PlainProviderFactory with LegacyBundleFactoryMixin {
  final _PlainProvider provider = _PlainProvider();

  @override
  Object create(AgentProviderConfig config) => provider;
}

final class _QuotaProvider extends Fake
    with AgentProviderThreadLifecycleStub
    implements
        AgentRuntimePort,
        AgentConversationPort,
        AgentUsageQuotaProvider {
  _QuotaProvider({required this.quotaThrows});

  final bool quotaThrows;
  int initializeCount = 0;
  int quotaReadCount = 0;

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();

  @override
  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    quotaReadCount += 1;
    if (quotaThrows) {
      throw StateError('sensitive quota failure');
    }
    return const AgentUsageQuotaSnapshot(
      providerId: defaultAgentProviderId,
      providerName: 'Codex',
      windows: <AgentUsageWindow>[],
    );
  }

  @override
  Future<void> dispose() async {}
}

final class _PlainProvider extends Fake
    with AgentProviderThreadLifecycleStub
    implements AgentRuntimePort, AgentConversationPort {
  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}
