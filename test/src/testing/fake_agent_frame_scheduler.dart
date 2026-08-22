import 'package:flutter/foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 可确定性推进 frame callback 的测试调度器。
final class FakeAgentFrameScheduler implements AgentFrameScheduler {
  final List<VoidCallback> _callbacks = <VoidCallback>[];
  bool _isInBuildPhase = false;
  int _scheduledCallbackCount = 0;

  @override
  bool get isInBuildPhase => _isInBuildPhase;

  int get pendingCallbackCount => _callbacks.length;

  int get scheduledCallbackCount => _scheduledCallbackCount;

  @override
  void scheduleNextFrame(VoidCallback callback) {
    _scheduledCallbackCount += 1;
    _callbacks.add(callback);
  }

  /// 在 build phase 标记下同步执行 [body]，用于验证禁止同步重入。
  T runInBuildPhase<T>(T Function() body) {
    final previous = _isInBuildPhase;
    _isInBuildPhase = true;
    try {
      return body();
    } finally {
      _isInBuildPhase = previous;
    }
  }

  /// 在 build phase 标记下执行异步测试体，便于推进事件流 microtask。
  Future<T> runInBuildPhaseAsync<T>(Future<T> Function() body) async {
    final previous = _isInBuildPhase;
    _isInBuildPhase = true;
    try {
      return await body();
    } finally {
      _isInBuildPhase = previous;
    }
  }

  /// 推进一帧；本帧 callback 新排入的任务留给下一次调用。
  void pumpFrame() {
    final callbacks = List<VoidCallback>.of(_callbacks);
    _callbacks.clear();
    final previous = _isInBuildPhase;
    _isInBuildPhase = false;
    try {
      for (final callback in callbacks) {
        callback();
      }
    } finally {
      _isInBuildPhase = previous;
    }
  }

  /// 推进至队列为空，并对意外的无限续排提供上限保护。
  void drainFrames({int maxFrames = 100}) {
    var frames = 0;
    while (_callbacks.isNotEmpty) {
      if (frames >= maxFrames) {
        throw StateError('Fake frame scheduler did not become idle');
      }
      pumpFrame();
      frames += 1;
    }
  }
}
