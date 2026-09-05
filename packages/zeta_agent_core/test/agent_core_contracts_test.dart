import 'dart:async';

import 'package:test/test.dart';
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

    test('纯 Dart value signal 只在值变化时按注册顺序通知', () {
      final signal = AgentValueNotifier<int>(1);
      final notifications = <String>[];
      void first() => notifications.add('first:${signal.value}');
      void second() => notifications.add('second:${signal.value}');
      signal
        ..addListener(first)
        ..addListener(second)
        ..value = 1;

      expect(notifications, isEmpty);

      signal.value = 2;

      expect(notifications, <String>['first:2', 'second:2']);
      signal
        ..removeListener(first)
        ..value = 3
        ..dispose();
      expect(notifications, <String>['first:2', 'second:2', 'second:3']);
      expect(() => signal.addListener(first), throwsStateError);
    });

    test('通知期间移除的监听器不会在同一轮迟到执行', () {
      final signal = AgentValueNotifier<int>(0);
      final notifications = <String>[];
      void second() => notifications.add('second');
      void first() {
        notifications.add('first');
        signal.removeListener(second);
      }

      signal
        ..addListener(first)
        ..addListener(second)
        ..value = 1;

      expect(notifications, <String>['first']);
      signal.dispose();
    });

    test('坏监听器不截断后续通知且异常交给当前 Zone', () {
      final signal = AgentValueNotifier<int>(0);
      final reportedErrors = <Object>[];
      var healthyNotifications = 0;

      runZonedGuarded(() {
        signal
          ..addListener(() => throw StateError('listener fixture'))
          ..addListener(() => healthyNotifications += 1)
          ..value = 1;
      }, (error, stackTrace) => reportedErrors.add(error));

      expect(healthyNotifications, 1);
      expect(reportedErrors, hasLength(1));
      expect(reportedErrors.single, isA<StateError>());
      signal.dispose();
    });

    test('runtime registry close 释放监听器并进入不可订阅终态', () async {
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: _ThrowingBundleFactory(),
      );
      void listener() {}
      registry.addListener(listener);

      expect(registry.hasListeners, isTrue);

      await registry.close();

      expect(registry.hasListeners, isFalse);
      expect(() => registry.addListener(listener), throwsStateError);
      // 重复 close 仍返回已经结算的同一终态，不会二次 dispose。
      await registry.close();
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
