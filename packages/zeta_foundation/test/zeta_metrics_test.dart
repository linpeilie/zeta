import 'package:test/test.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

void main() {
  group('ZetaMetricTags', () {
    test('把不安全字符替换成下划线并截断长度', () {
      final tags = ZetaMetricTags(
        component: '/Users/somebody/projects/secret plan.md',
      );

      expect(tags.component, isNotNull);
      expect(tags.component, isNot(contains('/')));
      expect(tags.component, isNot(contains(' ')));
      expect(tags.component!.length, lessThanOrEqualTo(48));
      expect(tags.providerId, isNull);
      expect(tags.outcome, isNull);
    });

    test('空标签和无字母数字的标签统一归一为 null', () {
      expect(ZetaMetricTags(component: '').component, isNull);
      expect(ZetaMetricTags(component: '   ').component, isNull);
      expect(ZetaMetricTags(component: '///').component, isNull);
      expect(ZetaMetricTags(), same(ZetaMetricTags.none));
    });

    test('序列键只由三个封闭维度组成', () {
      final tags = ZetaMetricTags(
        providerId: 'codex',
        component: 'live',
        outcome: ZetaMetricOutcome.failure,
      );

      expect(tags.seriesKey, 'codex|live|failure');
      expect(ZetaMetricTags.none.seriesKey, '-|-|-');
    });

    test('相同维度的标签相等且哈希一致', () {
      final first = ZetaMetricTags(providerId: 'grok', component: 'history');
      final second = ZetaMetricTags(providerId: 'grok', component: 'history');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('NoopZetaMetricsPort', () {
    test('关闭状态下不接受任何采样', () {
      const port = noopZetaMetricsPort;

      expect(port.isEnabled, isFalse);
      // 不抛异常即可；no-op 端口没有可观察副作用。
      port.counter(ZetaMetric.riverpodProviderAdded);
      port.gauge(ZetaMetric.agentRuntimeActiveCount, 3);
      port.duration(
        ZetaMetric.appBootstrapDuration,
        const Duration(milliseconds: 5),
      );
    });
  });

  group('InMemoryZetaMetricsPort', () {
    test('counter 累加、gauge 记录最近值与高水位', () {
      final port = InMemoryZetaMetricsPort();

      port
        ..counter(ZetaMetric.agentPipelineEventsReceived, increment: 4)
        ..counter(ZetaMetric.agentPipelineEventsReceived, increment: 6)
        ..gauge(ZetaMetric.agentPipelineQueueDepth, 12)
        ..gauge(ZetaMetric.agentPipelineQueueDepth, 3);

      expect(port.totalOf(ZetaMetric.agentPipelineEventsReceived), 10);
      expect(port.sampleCountOf(ZetaMetric.agentPipelineEventsReceived), 2);
      expect(port.lastValueOf(ZetaMetric.agentPipelineQueueDepth), 3);
      expect(port.maxValueOf(ZetaMetric.agentPipelineQueueDepth), 12);
    });

    test('duration 以微秒累计', () {
      final port = InMemoryZetaMetricsPort();

      port.duration(
        ZetaMetric.appBootstrapDuration,
        const Duration(milliseconds: 2),
      );

      expect(port.totalOf(ZetaMetric.appBootstrapDuration), 2000);
    });

    test('increment 为 0 的计数不产生序列', () {
      final port = InMemoryZetaMetricsPort();

      port.counter(ZetaMetric.agentPipelineEventsCoalesced, increment: 0);

      expect(port.seriesCount, 0);
    });

    test('按标签分序列聚合，也可按指标汇总', () {
      final port = InMemoryZetaMetricsPort();
      final codex = ZetaMetricTags(providerId: 'codex');
      final grok = ZetaMetricTags(providerId: 'grok');

      port
        ..counter(ZetaMetric.agentRuntimeCreated, tags: codex)
        ..counter(ZetaMetric.agentRuntimeCreated, tags: codex)
        ..counter(ZetaMetric.agentRuntimeCreated, tags: grok);

      expect(port.totalOf(ZetaMetric.agentRuntimeCreated, tags: codex), 2);
      expect(port.totalOf(ZetaMetric.agentRuntimeCreated, tags: grok), 1);
      expect(port.totalOf(ZetaMetric.agentRuntimeCreated), 3);
      expect(port.seriesCount, 2);
    });

    test('序列数量有上限，超出后只计丢弃数不再增长', () {
      final port = InMemoryZetaMetricsPort(maxSeries: 2);

      port
        ..counter(
          ZetaMetric.agentRuntimeCreated,
          tags: ZetaMetricTags(providerId: 'a'),
        )
        ..counter(
          ZetaMetric.agentRuntimeCreated,
          tags: ZetaMetricTags(providerId: 'b'),
        )
        ..counter(
          ZetaMetric.agentRuntimeCreated,
          tags: ZetaMetricTags(providerId: 'c'),
        );

      expect(port.seriesCount, 2);
      expect(port.droppedSeriesSamples, 1);
      expect(port.totalOf(ZetaMetric.agentRuntimeCreated), 2);
    });

    test('快照按序列键稳定排序并与内部状态隔离', () {
      final port = InMemoryZetaMetricsPort();

      port
        ..counter(ZetaMetric.riverpodProviderUpdated)
        ..counter(ZetaMetric.riverpodProviderAdded);
      final snapshot = port.snapshot();
      port.counter(ZetaMetric.riverpodProviderAdded);

      expect(
        snapshot.map((series) => series.metric),
        orderedEquals(<ZetaMetric>[
          ZetaMetric.riverpodProviderAdded,
          ZetaMetric.riverpodProviderUpdated,
        ]),
      );
      expect(snapshot.first.total, 1);
      expect(port.totalOf(ZetaMetric.riverpodProviderAdded), 2);
    });

    test('禁用实例与 no-op 行为一致', () {
      final port = InMemoryZetaMetricsPort(enabled: false);

      port.counter(ZetaMetric.riverpodProviderAdded);

      expect(port.isEnabled, isFalse);
      expect(port.seriesCount, 0);
    });

    test('reset 清空聚合结果', () {
      final port = InMemoryZetaMetricsPort()
        ..counter(ZetaMetric.riverpodProviderAdded)
        ..reset();

      expect(port.seriesCount, 0);
      expect(port.totalOf(ZetaMetric.riverpodProviderAdded), 0);
    });
  });
}
