import 'package:test/test.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

void main() {
  group('ZetaMetricTags', () {
    test('运行期内容只能经 hash 入口，序列键里不留可读片段', () {
      const path = '/Users/somebody/projects/secret plan.md';
      final tags = ZetaMetricTags(component: ZetaMetricLabel.hashed(path));

      expect(tags.component!.value, startsWith('h.'));
      for (final fragment in const <String>[
        'Users',
        'somebody',
        'projects',
        'secret',
        'plan',
      ]) {
        expect(tags.seriesKey, isNot(contains(fragment)));
      }
    });

    test('声明期入口遇到非法形态自动降级为 hash', () {
      for (final invalid in <String>[
        '',
        '   ',
        '///',
        '9leading-digit',
        'has space',
        r'C:\Users\me',
        'a' * 33,
      ]) {
        final label = ZetaMetricLabel.declaredIdentifier(invalid);
        expect(label.value, startsWith('h.'), reason: '非法输入：$invalid');
        expect(ZetaMetricLabel.isValidLiteral(label.value), isTrue);
      }
      expect(const ZetaMetricTags(), same(ZetaMetricTags.none));
    });

    test('稳定标识符原样保留', () {
      expect(ZetaMetricLabel.declaredIdentifier('codex').value, 'codex');
      expect(
        ZetaMetricLabel.declaredIdentifier('zeta.agent.pipeline').value,
        'zeta.agent.pipeline',
      );
      expect(ZetaMetricLabel.isValidLiteral('claude_code'), isTrue);
      expect(ZetaMetricLabel.isValidLiteral('/Users/me'), isFalse);
    });

    test('同一进程内 hash 稳定，不同取值不相撞', () {
      final first = ZetaMetricLabel.hashed('/Users/a/project');
      final second = ZetaMetricLabel.hashed('/Users/a/project');
      final other = ZetaMetricLabel.hashed('/Users/b/project');

      expect(first, second);
      expect(first, isNot(other));
    });

    test('序列键只由三个封闭维度组成', () {
      const tags = ZetaMetricTags(
        providerId: ZetaMetricLabel.constant('codex'),
        component: ZetaMetricLabel.constant('live'),
        outcome: ZetaMetricOutcome.failure,
      );

      expect(tags.seriesKey, 'codex|live|failure');
      expect(ZetaMetricTags.none.seriesKey, '-|-|-');
    });

    test('相同维度的标签相等且哈希一致', () {
      const first = ZetaMetricTags(
        providerId: ZetaMetricLabel.constant('grok'),
        component: ZetaMetricLabel.constant('history'),
      );
      const second = ZetaMetricTags(
        providerId: ZetaMetricLabel.constant('grok'),
        component: ZetaMetricLabel.constant('history'),
      );

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
      final codex = const ZetaMetricTags(
        providerId: ZetaMetricLabel.constant('codex'),
      );
      final grok = const ZetaMetricTags(
        providerId: ZetaMetricLabel.constant('grok'),
      );

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
          tags: const ZetaMetricTags(providerId: ZetaMetricLabel.constant('a')),
        )
        ..counter(
          ZetaMetric.agentRuntimeCreated,
          tags: const ZetaMetricTags(providerId: ZetaMetricLabel.constant('b')),
        )
        ..counter(
          ZetaMetric.agentRuntimeCreated,
          tags: const ZetaMetricTags(providerId: ZetaMetricLabel.constant('c')),
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
