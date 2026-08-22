import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// `zeta_agent_core` 的包内契约测试入口。
///
/// 这里只放**不依赖宿主**的内核契约；大量既有的 reducer / pipeline / timeline
/// 行为测试仍在根测试树里（它们复用应用侧 fixture 与 harness），迁移是后续增量。
void main() {
  group('中立内核可脱离宿主使用', () {
    test('事件缓冲与有界分发不需要任何宿主设施', () async {
      final delivered = <AgentEvent>[];
      final dispatcher = BoundedEventDispatcher<AgentEvent>(
        onEvent: delivered.add,
      );
      final buffer = CoalescingEventBuffer<AgentEvent, AgentEventKey>(
        policy: const AgentEventCoalescingPolicy(),
        onEmit: dispatcher.add,
      );

      buffer
        ..add(_delta('a'))
        ..add(_delta('b'))
        ..flush();
      dispatcher.flush();

      expect(delivered, hasLength(1));
      expect((delivered.single as AgentMessageDeltaEvent).delta, 'ab');
      await dispatcher.close(drain: false);
    });

    test('runtime registry 默认把 Provider ID 变成 hash 标签', () async {
      final metrics = InMemoryZetaMetricsPort();
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: _ThrowingBundleFactory(),
        metrics: metrics,
      );
      addTearDown(registry.close);

      // 内核不认识 Provider 身份：没有注入解析函数时只会看到 hash。
      expect(registry.debugProviderCount, 0);
      expect(metrics.seriesCount, 0);
      expect(ZetaMetricLabel.hashed('codex').value, startsWith('h.'));
    });

    test('TimelineStore 在无宿主环境下可创建并释放', () {
      final timeline = AgentConversationTimelineStore();

      expect(timeline.timelineEntries, isEmpty);
      expect(timeline.isTurnRunning, isFalse);

      timeline.dispose();
    });
  });
}

AgentMessageDeltaEvent _delta(String delta) => AgentMessageDeltaEvent(
  messageId: 'message-1',
  delta: delta,
  role: AgentMessageRole.agent,
  sessionId: 'thread-1',
  turnId: 'turn-1',
);

final class _ThrowingBundleFactory implements AgentProviderBundleFactory {
  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    throw UnsupportedError('包内契约测试不创建真实 bundle');
  }
}
