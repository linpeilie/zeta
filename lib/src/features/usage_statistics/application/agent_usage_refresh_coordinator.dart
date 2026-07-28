import 'dart:async';

/// 将一次刷新任务提交到宿主调度器。
typedef AgentUsageRefreshTaskScheduler =
    void Function(Future<void> Function() task);

/// 合并 Agent 用量刷新请求。
///
/// 调用方决定任务优先级；协调器只保证同一时刻最多执行一次刷新。尚未执行时的
/// 重复请求会被合并，执行期间收到的新请求会直接丢弃。
class AgentUsageRefreshCoordinator {
  factory AgentUsageRefreshCoordinator({
    required Future<void> Function() refresh,
    required AgentUsageRefreshTaskScheduler schedule,
  }) {
    return AgentUsageRefreshCoordinator._(refresh, schedule);
  }

  AgentUsageRefreshCoordinator._(this._refresh, this._schedule);

  final Future<void> Function() _refresh;
  final AgentUsageRefreshTaskScheduler _schedule;

  bool _scheduled = false;
  bool _running = false;
  bool _disposed = false;

  /// 请求一次刷新；已提交的重复请求会合并，执行期间的新请求会丢弃。
  void requestRefresh() {
    if (_disposed) {
      return;
    }
    if (_running) {
      return;
    }
    if (_scheduled) {
      return;
    }

    _scheduled = true;
    try {
      _schedule(_runScheduledRefresh);
    } catch (_) {
      _scheduled = false;
      rethrow;
    }
  }

  Future<void> _runScheduledRefresh() async {
    _scheduled = false;
    if (_disposed) {
      return;
    }

    _running = true;
    try {
      await _refresh();
    } finally {
      _running = false;
    }
  }

  /// 停止接收请求；已经提交但尚未执行的任务会安全退出。
  void dispose() {
    _disposed = true;
  }
}
