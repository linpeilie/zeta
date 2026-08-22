import 'package:flutter/scheduler.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent/data/agent_metric_labels.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 基于 [SchedulerBinding] 的生产 frame 调度实现。
final class SchedulerBindingAgentFrameScheduler implements AgentFrameScheduler {
  const SchedulerBindingAgentFrameScheduler();

  @override
  bool get isInBuildPhase =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  @override
  void scheduleNextFrame(VoidCallback callback) {
    final binding = SchedulerBinding.instance;
    binding.scheduleFrameCallback((_) => callback());
    binding.ensureVisualUpdate();
  }
}

/// [AgentUiUpdateScheduler] 的只读诊断快照。
///
/// 快照只包含请求、发布和队列计数，不保存消息内容、effect payload 或可变集合。
final class AgentUiUpdateSchedulerDiagnostics {
  const AgentUiUpdateSchedulerDiagnostics({
    required this.nextFrameRequestCount,
    required this.immediateRequestCount,
    required this.mergedRequestCount,
    required this.scheduledFrames,
    required this.publishCount,
    required this.immediatePublishes,
    required this.framePublishes,
    required this.publishedRegions,
    required this.publishedEffects,
    required this.buildPhaseDeferrals,
    required this.invalidatedFrameCallbacks,
    required this.ignoredFrameCallbacks,
    required this.requestsIgnoredAfterDispose,
    required this.hasPendingRequest,
    required this.pendingRegionCount,
    required this.pendingEffectCount,
    required this.hasScheduledFrame,
    required this.isDisposed,
  });

  /// 已接受的普通帧请求数。
  final int nextFrameRequestCount;

  /// 已接受的立即请求数；空请求且无 pending 时不计。
  final int immediateRequestCount;

  /// 合并进既有 pending 或被 immediate 吸收的请求数。
  final int mergedRequestCount;

  /// 交给 [AgentFrameScheduler] 的 frame callback 数。
  final int scheduledFrames;

  /// 实际调用下游发布回调的次数。
  final int publishCount;

  /// 在安全同步边界直接发布的次数。
  final int immediatePublishes;

  /// 由 frame callback 发布的次数。
  final int framePublishes;

  /// 所有已发布请求携带的 region 数量之和。
  final int publishedRegions;

  /// 所有已发布请求携带的去重后 effect 数量之和。
  final int publishedEffects;

  /// 因处于 build phase 而延至下一帧的 immediate 请求数。
  final int buildPhaseDeferrals;

  /// 被新 immediate 请求或 dispose 失效的已安排 callback 数。
  final int invalidatedFrameCallbacks;

  /// callback 到达时因代数过期或已 dispose 而忽略的次数。
  final int ignoredFrameCallbacks;

  /// dispose 后收到并忽略的请求数。
  final int requestsIgnoredAfterDispose;

  /// 获取快照时是否存在待发布请求。
  final bool hasPendingRequest;

  /// 当前 pending 请求中的 region 数。
  final int pendingRegionCount;

  /// 当前 pending 请求中的 effect 数。
  final int pendingEffectCount;

  /// 获取快照时是否已有有效 frame callback。
  final bool hasScheduledFrame;

  /// 调度器是否已释放。
  final bool isDisposed;
}

/// 将类型化 UI 请求合并到 Flutter frame 边界的 presentation 调度器。
///
/// [AgentUiUpdateUrgency.nextFrame] 请求在同一可见 frame 前合并并最多发布一次。
/// [AgentUiUpdateUrgency.immediate] 请求吸收 pending 请求并使旧 frame callback
/// 失效；若当前处于 build phase，则延迟到下一 frame，避免同步通知重入构建。
final class AgentUiUpdateScheduler implements AgentUiUpdatePort {
  AgentUiUpdateScheduler(
    this._onPublish, {
    AgentFrameScheduler? frameScheduler,
    ZetaMetricsPort metrics = noopZetaMetricsPort,
    String? providerId,
  }) : _frameScheduler =
           frameScheduler ?? const SchedulerBindingAgentFrameScheduler(),
       _metrics = metrics,
       _metricTags = metrics.isEnabled && providerId != null
           ? ZetaMetricTags(
               providerId: AgentMetricLabels.forProviderId(providerId),
             )
           : ZetaMetricTags.none;

  final void Function(AgentUiUpdateRequest request) _onPublish;
  final AgentFrameScheduler _frameScheduler;
  final ZetaMetricsPort _metrics;
  final ZetaMetricTags _metricTags;

  AgentUiUpdateRequest _pendingRequest = AgentUiUpdateRequest.none;
  bool _frameScheduled = false;
  bool _disposed = false;
  int _frameCallbackGeneration = 0;

  int _nextFrameRequestCount = 0;
  int _immediateRequestCount = 0;
  int _mergedRequestCount = 0;
  int _scheduledFrames = 0;
  int _publishCount = 0;
  int _immediatePublishes = 0;
  int _framePublishes = 0;
  int _publishedRegions = 0;
  int _publishedEffects = 0;
  int _buildPhaseDeferrals = 0;
  int _invalidatedFrameCallbacks = 0;
  int _ignoredFrameCallbacks = 0;
  int _requestsIgnoredAfterDispose = 0;

  /// 返回与内部 pending request 隔离的不可变诊断快照。
  AgentUiUpdateSchedulerDiagnostics get diagnostics =>
      AgentUiUpdateSchedulerDiagnostics(
        nextFrameRequestCount: _nextFrameRequestCount,
        immediateRequestCount: _immediateRequestCount,
        mergedRequestCount: _mergedRequestCount,
        scheduledFrames: _scheduledFrames,
        publishCount: _publishCount,
        immediatePublishes: _immediatePublishes,
        framePublishes: _framePublishes,
        publishedRegions: _publishedRegions,
        publishedEffects: _publishedEffects,
        buildPhaseDeferrals: _buildPhaseDeferrals,
        invalidatedFrameCallbacks: _invalidatedFrameCallbacks,
        ignoredFrameCallbacks: _ignoredFrameCallbacks,
        requestsIgnoredAfterDispose: _requestsIgnoredAfterDispose,
        hasPendingRequest: !_pendingRequest.isEmpty,
        pendingRegionCount: _pendingRequest.regions.length,
        pendingEffectCount: _pendingRequest.effects.length,
        hasScheduledFrame: _frameScheduled,
        isDisposed: _disposed,
      );

  @override
  void publish(AgentUiUpdateRequest request) {
    if (_disposed) {
      _requestsIgnoredAfterDispose += 1;
      _metrics.counter(
        ZetaMetric.agentUiRequestsAfterDispose,
        tags: _metricTags,
      );
      return;
    }
    switch (request.urgency) {
      case AgentUiUpdateUrgency.nextFrame:
        if (request.isEmpty) {
          return;
        }
        _nextFrameRequestCount += 1;
        _mergeIntoPending(request);
        _ensureFrameScheduled();
      case AgentUiUpdateUrgency.immediate:
        if (request.isEmpty && _pendingRequest.isEmpty) {
          return;
        }
        _immediateRequestCount += 1;
        _publishImmediate(request);
    }
  }

  /// 丢弃 pending 请求；已经交给 Flutter 的 callback 到达时只会安全退出。
  void dispose() {
    if (_disposed) {
      return;
    }
    _invalidateScheduledFrame();
    _pendingRequest = AgentUiUpdateRequest.none;
    _disposed = true;
  }

  void _publishImmediate(AgentUiUpdateRequest request) {
    final pending = _pendingRequest;
    if (!pending.isEmpty) {
      _mergedRequestCount += 1;
    }
    final combined = pending.isEmpty ? request : pending.mergedWith(request);
    _pendingRequest = AgentUiUpdateRequest.none;
    _invalidateScheduledFrame();
    if (combined.isEmpty) {
      return;
    }
    if (_frameScheduler.isInBuildPhase) {
      _buildPhaseDeferrals += 1;
      _metrics.counter(
        ZetaMetric.agentUiBuildPhaseDeferrals,
        tags: _metricTags,
      );
      _pendingRequest = combined;
      _ensureFrameScheduled();
      return;
    }
    _emit(combined, immediate: true);
  }

  void _mergeIntoPending(AgentUiUpdateRequest request) {
    if (_pendingRequest.isEmpty) {
      _pendingRequest = request;
      return;
    }
    _mergedRequestCount += 1;
    _pendingRequest = _pendingRequest.mergedWith(request);
  }

  void _ensureFrameScheduled() {
    if (_disposed || _pendingRequest.isEmpty || _frameScheduled) {
      return;
    }
    _frameScheduled = true;
    final generation = ++_frameCallbackGeneration;
    _scheduledFrames += 1;
    try {
      _frameScheduler.scheduleNextFrame(() {
        if (_disposed || generation != _frameCallbackGeneration) {
          _ignoredFrameCallbacks += 1;
          return;
        }
        _frameScheduled = false;
        final request = _pendingRequest;
        _pendingRequest = AgentUiUpdateRequest.none;
        if (request.isEmpty) {
          return;
        }
        _emit(request, immediate: false);
      });
    } catch (_) {
      if (generation == _frameCallbackGeneration) {
        _frameScheduled = false;
        _frameCallbackGeneration += 1;
      }
      rethrow;
    }
  }

  void _invalidateScheduledFrame() {
    if (!_frameScheduled) {
      return;
    }
    _frameScheduled = false;
    _frameCallbackGeneration += 1;
    _invalidatedFrameCallbacks += 1;
  }

  void _emit(AgentUiUpdateRequest request, {required bool immediate}) {
    _publishCount += 1;
    _publishedRegions += request.regions.length;
    _publishedEffects += request.effects.length;
    if (immediate) {
      _immediatePublishes += 1;
      _metrics.counter(ZetaMetric.agentUiImmediatePublishes, tags: _metricTags);
    } else {
      _framePublishes += 1;
      _metrics.counter(ZetaMetric.agentUiFramePublishes, tags: _metricTags);
    }
    _metrics.counter(
      ZetaMetric.agentUiPublishedRegions,
      increment: request.regions.length,
      tags: _metricTags,
    );
    _metrics.counter(
      ZetaMetric.agentUiPublishedEffects,
      increment: request.effects.length,
      tags: _metricTags,
    );
    _onPublish(request);
  }
}
