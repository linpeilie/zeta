import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/core/observability/in_memory_zeta_metrics_port.dart';
import 'package:zeta/src/core/observability/zeta_metric.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_reducer.dart';
import 'package:zeta/src/features/agent/application/agent_event_pipeline.dart';
import 'package:zeta/src/features/agent/application/agent_pipeline_metrics_reporter.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_ui_update_scheduler.dart';

import '../../../testing/agent_event_storm_fixture.dart';
import '../../../testing/fake_agent_frame_scheduler.dart';

/// 阶段 0 固定风暴 fixture 的管线指标基线。
///
/// 指标由 [AgentPipelineMetricsReporter] 在边界采样得到：G1 共享层内容冻结，
/// 管线内部不埋点。
///
/// 这些常量来自 [AgentEventStormFixture] 的确定性事件序列：只有 fixture 规模、
/// 合并策略或 listener gate 语义变化时才允许修改，改动必须在 PR 里说明原因。
/// 它们同时给 Phase 1–4 的迁移提供“行为未变”的量化证据。
const int _expectedReceived = 10825;
const int _expectedAccepted = 309;
const int _expectedRejected = 0;
const int _expectedCoalesced = 10516;
const int _expectedDispatched = 309;

void main() {
  group('Agent 流式指标基线', () {
    test('固定风暴 fixture 的 accepted/coalesced/dispatched 基线稳定', () async {
      final first = await _runStormPipeline();
      final second = await _runStormPipeline();

      debugPrint('agent-pipeline-metrics-baseline $first');
      expect(first, second, reason: '同一 fixture 两次运行必须得到同一组指标');
      expect(first.received, _expectedReceived);
      expect(first.received, AgentEventStormFixture().expectedInputEventCount);
      expect(first.accepted, _expectedAccepted);
      expect(first.rejected, _expectedRejected);
      expect(first.coalesced, _expectedCoalesced);
      expect(first.dispatched, _expectedDispatched);
      // 合并后进入 reducer 的事件量必须显著小于原始事件量，否则合并策略失效。
      expect(first.accepted + first.coalesced, first.received);
      expect(first.pendingKeysAtClose, 0);
      expect(first.queueDepthAtClose, 0);
      expect(first.backpressureFlushes, 0);
      expect(first.sourceErrors, 0);
    });

    test('过期 runtime scope 的事件只计入 rejected', () async {
      final metrics = InMemoryZetaMetricsPort();
      final source = StreamController<AgentEvent>(sync: true);
      final processed = <AgentEvent>[];
      var currentScope = const AgentRuntimeScope(
        runtimeId: 'runtime-1',
        connectionEpoch: 1,
      );
      final reporter = AgentPipelineMetricsReporter(
        metrics: metrics,
        providerId: 'provider-neutral',
      );
      final pipeline = AgentEventPipeline(
        source: source.stream,
        providerId: 'provider-neutral',
        threadId: 'thread-1',
        runtimeScope: currentScope,
        currentRuntimeScope: () => currentScope,
        allowDetachedEvent: AgentConversationReducer.isCriticalDetachedEvent,
        processEvent: processed.add,
        onSourceError: (error, stackTrace) {},
        onDone: () {},
      );

      currentScope = const AgentRuntimeScope(
        runtimeId: 'runtime-2',
        connectionEpoch: 2,
      );
      source.add(_delta('stale'));
      await Future<void>.delayed(Duration.zero);
      reporter.report(pipeline.diagnostics);
      await pipeline.close();
      await source.close();

      final tags = ZetaMetricTags(providerId: 'provider-neutral');
      expect(processed, isEmpty);
      expect(
        metrics.totalOf(ZetaMetric.agentPipelineEventsReceived, tags: tags),
        1,
      );
      expect(
        metrics.totalOf(ZetaMetric.agentPipelineEventsRejected, tags: tags),
        1,
      );
      expect(
        metrics.totalOf(ZetaMetric.agentPipelineEventsAccepted, tags: tags),
        0,
      );
    });

    test('关闭端口时管线不产生任何采样', () async {
      final metrics = InMemoryZetaMetricsPort(enabled: false);
      final source = StreamController<AgentEvent>(sync: true);
      final reporter = AgentPipelineMetricsReporter(
        metrics: metrics,
        providerId: 'provider-neutral',
      );
      final pipeline = AgentEventPipeline(
        source: source.stream,
        providerId: 'provider-neutral',
        threadId: 'thread-1',
        runtimeScope: null,
        currentRuntimeScope: () => null,
        allowDetachedEvent: AgentConversationReducer.isCriticalDetachedEvent,
        processEvent: (_) {},
        onSourceError: (error, stackTrace) {},
        onDone: () {},
      );

      source.add(_delta('hello'));
      await Future<void>.delayed(Duration.zero);
      reporter.report(pipeline.diagnostics);
      await pipeline.close();
      await source.close();

      expect(metrics.seriesCount, 0);
    });

    test('普通流式更新每帧最多发布一次，urgent 立即发布', () {
      final metrics = InMemoryZetaMetricsPort();
      final frameScheduler = FakeAgentFrameScheduler();
      final published = <AgentUiUpdateRequest>[];
      final scheduler = AgentUiUpdateScheduler(
        published.add,
        frameScheduler: frameScheduler,
        metrics: metrics,
        providerId: 'provider-neutral',
      );
      addTearDown(scheduler.dispose);

      for (var index = 0; index < 200; index += 1) {
        scheduler.publish(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>[AgentUiRegion.liveTurn],
          ),
        );
      }
      frameScheduler.pumpFrame();

      expect(metrics.totalOf(ZetaMetric.agentUiFramePublishes), 1);
      expect(metrics.totalOf(ZetaMetric.agentUiImmediatePublishes), 0);
      expect(metrics.totalOf(ZetaMetric.agentUiPublishedRegions), 1);

      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>[AgentUiRegion.pendingInteraction],
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );

      expect(metrics.totalOf(ZetaMetric.agentUiImmediatePublishes), 1);
      expect(metrics.totalOf(ZetaMetric.agentUiFramePublishes), 1);
      expect(published, hasLength(2));
    });

    test('重复采样只上报增量，换 Pipeline 后重新计数', () async {
      final metrics = InMemoryZetaMetricsPort();
      final reporter = AgentPipelineMetricsReporter(
        metrics: metrics,
        providerId: 'provider-neutral',
      );
      final tags = ZetaMetricTags(providerId: 'provider-neutral');
      final source = StreamController<AgentEvent>.broadcast(sync: true);
      final pipeline = AgentEventPipeline(
        source: source.stream,
        providerId: 'provider-neutral',
        threadId: 'thread-1',
        runtimeScope: null,
        currentRuntimeScope: () => null,
        allowDetachedEvent: AgentConversationReducer.isCriticalDetachedEvent,
        processEvent: (_) {},
        onSourceError: (error, stackTrace) {},
        onDone: () {},
      );

      source.add(_delta('a'));
      await Future<void>.delayed(Duration.zero);
      reporter.report(pipeline.diagnostics);
      reporter.report(pipeline.diagnostics);

      expect(
        metrics.totalOf(ZetaMetric.agentPipelineEventsReceived, tags: tags),
        1,
      );

      // 新 Pipeline 的计数从 0 开始；不重置基准会把它算成负增量。
      reporter.resetForNewPipeline();
      final replacement = AgentEventPipeline(
        source: source.stream,
        providerId: 'provider-neutral',
        threadId: 'thread-1',
        runtimeScope: null,
        currentRuntimeScope: () => null,
        allowDetachedEvent: AgentConversationReducer.isCriticalDetachedEvent,
        processEvent: (_) {},
        onSourceError: (error, stackTrace) {},
        onDone: () {},
        replaces: pipeline,
      );
      source.add(_delta('b'));
      await Future<void>.delayed(Duration.zero);
      reporter.report(replacement.diagnostics);
      await replacement.close();
      await source.close();

      expect(
        metrics.totalOf(ZetaMetric.agentPipelineEventsReceived, tags: tags),
        2,
      );
    });

    test('dispose 后的 UI 更新只计入丢弃指标', () {
      final metrics = InMemoryZetaMetricsPort();
      final scheduler = AgentUiUpdateScheduler(
        (_) {},
        frameScheduler: FakeAgentFrameScheduler(),
        metrics: metrics,
      )..dispose();

      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>[AgentUiRegion.liveTurn],
        ),
      );

      expect(metrics.totalOf(ZetaMetric.agentUiRequestsAfterDispose), 1);
      expect(metrics.totalOf(ZetaMetric.agentUiFramePublishes), 0);
    });
  });
}

Future<_StormPipelineMetrics> _runStormPipeline() async {
  final fixture = AgentEventStormFixture();
  final metrics = InMemoryZetaMetricsPort();
  final source = StreamController<AgentEvent>(sync: true);
  final tags = ZetaMetricTags(providerId: 'provider-neutral');
  final reporter = AgentPipelineMetricsReporter(
    metrics: metrics,
    providerId: 'provider-neutral',
  );
  final pipeline = AgentEventPipeline(
    source: source.stream,
    providerId: 'provider-neutral',
    threadId: fixture.sessionId,
    runtimeScope: null,
    currentRuntimeScope: () => null,
    allowDetachedEvent: AgentConversationReducer.isCriticalDetachedEvent,
    processEvent: (_) {},
    onSourceError: (error, stackTrace) {},
    onDone: () {},
  );

  for (final event in fixture.events) {
    source.add(event);
  }
  // 缓冲按 microtask flush、分发按 event-loop turn 让出，需要排空后再取基线。
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (pipeline.diagnostics.dispatcher.currentQueueDepth == 0 &&
        pipeline.diagnostics.buffer.currentPendingKeys == 0 &&
        pipeline.diagnostics.acceptedEvents > 0) {
      break;
    }
    await Future<void>.delayed(Duration.zero);
  }
  reporter.report(pipeline.diagnostics);
  await pipeline.close();
  await source.close();

  return _StormPipelineMetrics(
    received: metrics.totalOf(
      ZetaMetric.agentPipelineEventsReceived,
      tags: tags,
    ),
    accepted: metrics.totalOf(
      ZetaMetric.agentPipelineEventsAccepted,
      tags: tags,
    ),
    rejected: metrics.totalOf(
      ZetaMetric.agentPipelineEventsRejected,
      tags: tags,
    ),
    coalesced: metrics.totalOf(
      ZetaMetric.agentPipelineEventsCoalesced,
      tags: tags,
    ),
    dispatched: metrics.totalOf(
      ZetaMetric.agentPipelineEventsDispatched,
      tags: tags,
    ),
    backpressureFlushes: metrics.totalOf(
      ZetaMetric.agentPipelineBackpressureFlushes,
      tags: tags,
    ),
    sourceErrors: metrics.totalOf(
      ZetaMetric.agentPipelineSourceErrors,
      tags: tags,
    ),
    pendingKeysAtClose:
        metrics.lastValueOf(ZetaMetric.agentPipelinePendingKeys, tags: tags) ??
        -1,
    queueDepthAtClose:
        metrics.lastValueOf(ZetaMetric.agentPipelineQueueDepth, tags: tags) ??
        -1,
  );
}

final class _StormPipelineMetrics {
  const _StormPipelineMetrics({
    required this.received,
    required this.accepted,
    required this.rejected,
    required this.coalesced,
    required this.dispatched,
    required this.backpressureFlushes,
    required this.sourceErrors,
    required this.pendingKeysAtClose,
    required this.queueDepthAtClose,
  });

  final int received;
  final int accepted;
  final int rejected;
  final int coalesced;
  final int dispatched;
  final int backpressureFlushes;
  final int sourceErrors;
  final int pendingKeysAtClose;
  final int queueDepthAtClose;

  @override
  bool operator ==(Object other) {
    return other is _StormPipelineMetrics &&
        other.received == received &&
        other.accepted == accepted &&
        other.rejected == rejected &&
        other.coalesced == coalesced &&
        other.dispatched == dispatched &&
        other.backpressureFlushes == backpressureFlushes &&
        other.sourceErrors == sourceErrors &&
        other.pendingKeysAtClose == pendingKeysAtClose &&
        other.queueDepthAtClose == queueDepthAtClose;
  }

  @override
  int get hashCode => Object.hash(
    received,
    accepted,
    rejected,
    coalesced,
    dispatched,
    backpressureFlushes,
    sourceErrors,
    pendingKeysAtClose,
    queueDepthAtClose,
  );

  @override
  String toString() =>
      'received:$received accepted:$accepted rejected:$rejected '
      'coalesced:$coalesced dispatched:$dispatched '
      'backpressure:$backpressureFlushes sourceErrors:$sourceErrors '
      'pendingKeys:$pendingKeysAtClose queueDepth:$queueDepthAtClose';
}

AgentMessageDeltaEvent _delta(String delta) {
  return AgentMessageDeltaEvent(
    messageId: 'message-1',
    delta: delta,
    role: AgentMessageRole.agent,
    sessionId: 'thread-1',
    turnId: 'turn-1',
  );
}
