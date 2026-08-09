import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.idle_reaper');

/// 空闲会话实例回收器。
///
/// 04-目标态与步骤.md §S6：周期扫描 [AgentProviderRuntimeRegistry] 里
/// `scope != global` 的实例，命中 `pinCount == 0 && now - lastActiveAt >=
/// idleTtl` 就调用 [AgentProviderRuntimeRegistry.invalidateScope] 回收——
/// **不发明任何新的失效语义**（§0.1）：`invalidateScope` 的下游行为（租约失效
/// → controller 下次访问自动重建 → 新 runtime identity）本就存在，这个类只
/// 决定"何时对哪个 scope 调用它"。
///
/// [AgentProviderRuntimeScopeKey.global] 永远不参与扫描——它承担会话建立前的
/// 一切（用量/skill/模型列表/thread 历史读取，§0.4），回收会打破 AC7。
///
/// 纯副作用容器（application 层，持有 [Timer]），不进 reducer（**G3**）。由
/// registry 的唯一真所有者（`app.dart`、`ide_shell_controller.dart`）组合、
/// 启动与关闭；**不要**在任何自建临时 registry 的 fallback 分支里构造它。
final class AgentProviderIdleReaper {
  AgentProviderIdleReaper({
    required this._registry,
    this._scanInterval = const Duration(seconds: 60),
    this._idleTtl = const Duration(minutes: 10),
  });

  final AgentProviderRuntimeRegistry _registry;
  final Duration _scanInterval;
  final Duration _idleTtl;
  Timer? _timer;

  /// 是否已启动周期扫描，仅用于测试与诊断。
  @visibleForTesting
  bool get isRunning => _timer != null;

  /// 启动周期扫描；重复调用是安全的空操作（不会叠加出第二个 Timer）。
  void start() {
    if (_timer != null) {
      return;
    }
    _timer = _registry.timerFactory(_scanInterval, (_) => _sweep());
  }

  /// 停止周期扫描并释放 Timer；重复调用、或从未 start 过都是安全的空操作。
  /// registry 关闭时必须由调用方一并调用，否则悬挂 Timer 会一直持有 registry。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sweep() async {
    final now = _registry.clock();
    final candidates = _registry.snapshotEntries().where(
      (entry) =>
          entry.scope is! AgentProviderRuntimeGlobalScope &&
          entry.pinCount == 0 &&
          now.difference(entry.lastActiveAt) >= _idleTtl,
    );
    for (final candidate in candidates) {
      try {
        await _registry.invalidateScope(candidate.providerId, candidate.scope);
      } catch (error, stackTrace) {
        _log.w(
          'Idle reaper failed to invalidate '
          '${candidate.providerId} (${candidate.scope})',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}
