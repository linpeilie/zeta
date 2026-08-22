import 'dart:async';

import 'package:zeta_agent_providers/src/datasources/claude_code/claude_code_cli_metadata.dart';

typedef ClaudeCodeCliMetadataLoader =
    Future<ClaudeCodeCliMetadataSnapshot> Function();

/// 在同一 Claude Provider 实例内协调 metadata 探测。
///
/// 模型刷新只复用尚未结束的探测，不复用已完成快照；额度读取可在短周期内复用最近一次
/// 成功结果。应用级模型 TTL 仍只归 `AgentModelCatalogRepository` 所有。
final class ClaudeCodeCliMetadataCoordinator {
  ClaudeCodeCliMetadataCoordinator({
    required ClaudeCodeCliMetadataLoader metadataLoader,
    this.quotaReuseFor = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _loadMetadata = metadataLoader,
       _clock = clock ?? DateTime.now;

  final Duration quotaReuseFor;
  final ClaudeCodeCliMetadataLoader _loadMetadata;
  final DateTime Function() _clock;

  Future<ClaudeCodeCliMetadataSnapshot>? _inFlight;
  ClaudeCodeCliMetadataSnapshot? _lastSuccessfulSnapshot;
  DateTime? _lastSuccessfulAt;

  /// 为模型目录获取新快照；只与当前尚未完成的调用 single-flight。
  Future<ClaudeCodeCliMetadataSnapshot> refreshForModels() {
    return _startOrJoin();
  }

  /// 为额度投影读取 metadata，可复用同一 in-flight 或短周期成功快照。
  Future<ClaudeCodeCliMetadataSnapshot> readForQuota() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final snapshot = _lastSuccessfulSnapshot;
    final fetchedAt = _lastSuccessfulAt;
    if (snapshot != null && fetchedAt != null) {
      final age = _clock().difference(fetchedAt);
      if (!age.isNegative && age < quotaReuseFor) {
        return Future<ClaudeCodeCliMetadataSnapshot>.value(snapshot);
      }
    }
    return _startOrJoin();
  }

  Future<ClaudeCodeCliMetadataSnapshot> _startOrJoin() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<ClaudeCodeCliMetadataSnapshot> operation;
    operation = Future<ClaudeCodeCliMetadataSnapshot>.sync(_loadMetadata)
        .then((snapshot) {
          _lastSuccessfulSnapshot = snapshot;
          _lastSuccessfulAt = _clock();
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_inFlight, operation)) {
            _inFlight = null;
          }
        });
    _inFlight = operation;
    return operation;
  }
}
