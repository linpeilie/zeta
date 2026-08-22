import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent/data/agent_metric_labels.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 把 [AgentEventPipelineDiagnostics] 增量翻译成白名单指标的采样器。
///
/// **为什么不直接在 Pipeline 里埋点**：`AgentEventPipeline` 属于 G1 共享适配层
/// 且内容基线被冻结（T18）。事件管线本来就维护了完整的脱敏诊断计数，因此这里
/// 采取「外部按边界采样 + 上报增量」的方式：
///
/// - 共享层保持零改动，也不会被观测代码污染；
/// - 采样点由调用方选择（帧边界、backpressure、pipeline 关闭），
///   热路径上没有逐事件开销，关闭端口时更是只剩一次 `isEnabled` 分支；
/// - Provider ID 只作为标签透传，不参与任何分支判断（G1）。
final class AgentPipelineMetricsReporter {
  AgentPipelineMetricsReporter({
    required ZetaMetricsPort metrics,
    required String providerId,
  }) : _metrics = metrics,
       _tags = metrics.isEnabled
           ? ZetaMetricTags(
               providerId: AgentMetricLabels.forProviderId(providerId),
             )
           : ZetaMetricTags.none;

  final ZetaMetricsPort _metrics;
  final ZetaMetricTags _tags;

  int _received = 0;
  int _accepted = 0;
  int _rejected = 0;
  int _sourceErrors = 0;
  int _coalesced = 0;
  int _dispatched = 0;
  int _backpressureFlushes = 0;
  int _dispatcherYields = 0;

  /// 上报自上次调用以来的增量，并刷新队列水位 gauge。
  ///
  /// [diagnostics] 为 null（尚未安装 pipeline）时直接返回。
  void report(AgentEventPipelineDiagnostics? diagnostics) {
    if (!_metrics.isEnabled || diagnostics == null) {
      return;
    }
    _emitDelta(
      ZetaMetric.agentPipelineEventsReceived,
      diagnostics.receivedEvents,
      _received,
      (value) => _received = value,
    );
    _emitDelta(
      ZetaMetric.agentPipelineEventsAccepted,
      diagnostics.acceptedEvents,
      _accepted,
      (value) => _accepted = value,
    );
    _emitDelta(
      ZetaMetric.agentPipelineEventsRejected,
      diagnostics.rejectedStaleEvents,
      _rejected,
      (value) => _rejected = value,
    );
    _emitDelta(
      ZetaMetric.agentPipelineSourceErrors,
      diagnostics.sourceErrorCount,
      _sourceErrors,
      (value) => _sourceErrors = value,
    );
    _emitDelta(
      ZetaMetric.agentPipelineEventsCoalesced,
      diagnostics.buffer.coalescedEvents,
      _coalesced,
      (value) => _coalesced = value,
    );
    _emitDelta(
      ZetaMetric.agentPipelineBackpressureFlushes,
      diagnostics.buffer.backpressureFlushes,
      _backpressureFlushes,
      (value) => _backpressureFlushes = value,
    );
    _emitDelta(
      ZetaMetric.agentPipelineEventsDispatched,
      diagnostics.dispatcher.deliveredEvents,
      _dispatched,
      (value) => _dispatched = value,
    );
    _emitDelta(
      ZetaMetric.agentPipelineDispatcherYields,
      diagnostics.dispatcher.yieldCount,
      _dispatcherYields,
      (value) => _dispatcherYields = value,
    );
    _metrics.gauge(
      ZetaMetric.agentPipelinePendingKeys,
      diagnostics.buffer.currentPendingKeys,
      tags: _tags,
    );
    _metrics.gauge(
      ZetaMetric.agentPipelineQueueDepth,
      diagnostics.dispatcher.currentQueueDepth,
      tags: _tags,
    );
  }

  /// pipeline 被替换或关闭后，下一段计数从零重新开始。
  ///
  /// 每个 pipeline 实例的诊断计数都是独立的，不重置会把新实例的首次采样
  /// 误算成负增量。
  void resetForNewPipeline() {
    _received = 0;
    _accepted = 0;
    _rejected = 0;
    _sourceErrors = 0;
    _coalesced = 0;
    _dispatched = 0;
    _backpressureFlushes = 0;
    _dispatcherYields = 0;
  }

  void _emitDelta(
    ZetaMetric metric,
    int current,
    int previous,
    void Function(int value) store,
  ) {
    final delta = current - previous;
    if (delta <= 0) {
      // pipeline 实例被替换时计数会回退；此时只同步状态，不上报负增量。
      store(current);
      return;
    }
    store(current);
    _metrics.counter(metric, increment: delta, tags: _tags);
  }
}
