import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_effect.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_effect.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 完整使用统计页的 app effect runner。
final class UsageStatisticsSliceRunnerAdapter
    implements UsageStatisticsSliceEffectRunner {
  UsageStatisticsSliceRunnerAdapter({
    required this.repository,
    required this.textCatalog,
  });

  @override
  final UsageStatisticsRepository repository;
  final UsageStatisticsTextCatalog textCatalog;
  UsageStatisticsSliceStore? store;
  bool _closed = false;

  @override
  void run(UsageStatisticsSliceEffect effect) {
    if (_closed) {
      return;
    }
    switch (effect) {
      case LoadUsageStatisticsSourceEffect():
        unawaited(_load(effect));
    }
  }

  Future<void> _load(LoadUsageStatisticsSourceEffect effect) async {
    try {
      final source = await repository.load(
        earliest: effect.earliest,
        forceRefresh: effect.forceRefresh,
      );
      if (!_closed) {
        store?.sourceLoaded(
          operationId: effect.operationId,
          earliest: effect.earliest,
          source: source,
          reportNow: effect.reportNow,
        );
      }
    } catch (error) {
      if (!_closed) {
        store?.loadFailed(
          operationId: effect.operationId,
          message: textCatalog.loadFailed(error),
        );
      }
    }
  }

  @override
  void close() {
    _closed = true;
    store = null;
  }
}

/// Agent Usage Panel 的 app effect runner。
///
/// 目录请求在一个 drain 内合并：在途期间新增的刷新最多再触发一轮目录查询，所有
/// 调用方等待最终目录；Provider 查询的 keyed single-flight 由 store 负责。
final class AgentUsagePanelSliceRunnerAdapter
    implements AgentUsagePanelSliceEffectRunner {
  AgentUsagePanelSliceRunnerAdapter({
    required this.repository,
    required this.textCatalog,
  });

  @override
  final AgentUsagePanelRepository repository;
  final UsageStatisticsTextCatalog textCatalog;
  AgentUsagePanelSliceStore? store;
  void Function(String? providerId)? selectionPersistenceHandler;
  final List<DiscoverAgentUsageProvidersEffect> _directoryQueue =
      <DiscoverAgentUsageProvidersEffect>[];
  Future<void>? _directoryDrain;
  bool _closed = false;

  @override
  void run(AgentUsagePanelSliceEffect effect) {
    if (_closed) {
      return;
    }
    switch (effect) {
      case DiscoverAgentUsageProvidersEffect():
        _directoryQueue.add(effect);
        _ensureDirectoryDrain();
      case LoadAgentUsageProviderEffect():
        unawaited(_loadProvider(effect));
      case PersistAgentUsageSelectionEffect():
        selectionPersistenceHandler?.call(effect.providerId);
    }
  }

  void _ensureDirectoryDrain() {
    if (_directoryDrain != null || _closed) {
      return;
    }
    late final Future<void> drain;
    drain = _drainDirectory().whenComplete(() {
      if (identical(_directoryDrain, drain)) {
        _directoryDrain = null;
      }
      if (_directoryQueue.isNotEmpty && !_closed) {
        _ensureDirectoryDrain();
      }
    });
    _directoryDrain = drain;
  }

  Future<void> _drainDirectory() async {
    final operationIds = <OperationId>[];
    List<AgentUsagePanelProvider>? finalProviders;
    String? finalError;
    while (_directoryQueue.isNotEmpty && !_closed) {
      final batch = List<DiscoverAgentUsageProvidersEffect>.of(_directoryQueue);
      _directoryQueue.clear();
      operationIds.addAll(batch.map((effect) => effect.operationId));
      try {
        finalProviders = await repository.discoverProviders();
        finalError = null;
      } catch (_) {
        finalProviders = null;
        finalError = textCatalog.agentUsageTemporarilyUnavailable;
      }
    }
    if (_closed || operationIds.isEmpty) {
      return;
    }
    if (finalProviders case final providers?) {
      store?.directoryLoaded(operationIds: operationIds, providers: providers);
    } else {
      store?.directoryFailed(
        operationIds: operationIds,
        message: finalError ?? textCatalog.agentUsageTemporarilyUnavailable,
      );
    }
  }

  Future<void> _loadProvider(LoadAgentUsageProviderEffect effect) async {
    try {
      final result = await repository.loadProvider(
        effect.providerId,
        forceRefresh: effect.forceRefresh,
      );
      if (_closed) {
        return;
      }
      if (result == null) {
        store?.providerFailed(
          operationId: effect.operationId,
          providerId: effect.providerId,
          message: textCatalog.agentDisabledOrUnavailable,
          synchronizeDirectory: true,
        );
        return;
      }
      store?.providerLoaded(
        operationId: effect.operationId,
        providerId: effect.providerId,
        result: result,
      );
    } catch (_) {
      if (!_closed) {
        store?.providerFailed(
          operationId: effect.operationId,
          providerId: effect.providerId,
          message: textCatalog.agentUsageTemporarilyUnavailable,
        );
      }
    }
  }

  @override
  void close() {
    _closed = true;
    _directoryQueue.clear();
    selectionPersistenceHandler = null;
    store = null;
  }
}
