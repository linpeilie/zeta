import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/observability/zeta_observability.dart';
import 'package:zeta/src/app/observability/zeta_provider_observer.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 观察器不得读取的“敏感”状态；测试用它证明正文不会进入指标流。
const String _secretBody = 'prompt body /Users/tester/private/plan.md';

final _plainProvider = Provider<String>(
  (ref) => _secretBody,
  name: 'zeta.test.plain',
);

final _throwingProvider = Provider<String>(
  (ref) => throw StateError(_secretBody),
  name: 'zeta.test.throwing',
);

final _counterProvider = NotifierProvider<_CounterNotifier, int>(
  _CounterNotifier.new,
  name: 'zeta.test.counter',
);

/// family 参数常常是项目路径或 thread id；观察器绝不能把它写进指标。
final _familyProvider = Provider.autoDispose.family<String, String>(
  (ref, key) => key,
  name: 'zeta.test.family',
);

final class _CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;
}

void main() {
  group('ZetaProviderObserver', () {
    late InMemoryZetaMetricsPort metrics;
    late ProviderContainer container;

    setUp(() {
      metrics = InMemoryZetaMetricsPort();
      container = ProviderContainer(
        observers: <ProviderObserver>[ZetaProviderObserver(metrics: metrics)],
      );
      addTearDown(container.dispose);
    });

    test('记录 provider 初始化、更新与释放次数', () {
      container.read(_plainProvider);
      container.read(_counterProvider);
      container.read(_counterProvider.notifier).increment();
      container.read(_counterProvider.notifier).increment();

      expect(metrics.totalOf(ZetaMetric.riverpodProviderAdded), 2);
      expect(metrics.totalOf(ZetaMetric.riverpodProviderUpdated), 2);
      expect(
        metrics.totalOf(
          ZetaMetric.riverpodProviderUpdated,
          tags: ZetaMetricTags(component: 'zeta.test.counter'),
        ),
        2,
      );
    });

    test('provider 失败只记分类，不记错误文本', () {
      expect(() => container.read(_throwingProvider), throwsStateError);

      expect(
        metrics.totalOf(
          ZetaMetric.riverpodProviderFailed,
          tags: ZetaMetricTags(
            component: 'zeta.test.throwing',
            outcome: ZetaMetricOutcome.failure,
          ),
        ),
        1,
      );
      expect(_snapshotText(metrics), isNot(contains('StateError')));
    });

    test('autoDispose 释放会计入 dispose 指标', () async {
      final subscription = container.listen<String>(
        _familyProvider('project-a'),
        (previous, next) {},
      );
      subscription.close();
      // autoDispose 在下一个 microtask 检查引用计数。
      await Future<void>.delayed(Duration.zero);

      expect(metrics.totalOf(ZetaMetric.riverpodProviderDisposed), 1);
    });

    test('状态正文与 family 参数都不进入指标流', () async {
      container.read(_plainProvider);
      container.read(_familyProvider('/Users/tester/private/project'));
      container.read(_counterProvider.notifier).increment();

      final text = _snapshotText(metrics);
      expect(text, isNot(contains('prompt body')));
      expect(text, isNot(contains('/Users/tester')));
      expect(text, isNot(contains('private')));
      expect(text, contains('zeta.test.plain'));
    });

    test('端口关闭时观察器不产生任何序列', () {
      final disabled = InMemoryZetaMetricsPort(enabled: false);
      final observed = ProviderContainer(
        observers: <ProviderObserver>[ZetaProviderObserver(metrics: disabled)],
      );
      addTearDown(observed.dispose);

      observed.read(_plainProvider);

      expect(disabled.seriesCount, 0);
    });

    test('默认构造使用 no-op 端口', () {
      const observer = ZetaProviderObserver();

      expect(observer.metrics.isEnabled, isFalse);
    });
  });

  group('ZetaObservability', () {
    test('关闭时不注册任何观察器', () {
      final observability = ZetaObservability.disabled();

      expect(observability.metrics.isEnabled, isFalse);
      expect(observability.collector, isNull);
      expect(observability.providerObservers, isEmpty);
    });

    test('开启后注册脱敏观察器并可导出快照', () {
      final observability = ZetaObservability.inMemory();
      final container = ProviderContainer(
        observers: observability.providerObservers,
      );
      addTearDown(container.dispose);

      container.read(_plainProvider);

      expect(observability.providerObservers, hasLength(1));
      expect(
        observability.collector!.totalOf(ZetaMetric.riverpodProviderAdded),
        1,
      );
    });

    test('默认编译期开关保持关闭', () {
      expect(ZetaObservability.fromEnvironment().metrics.isEnabled, isFalse);
    });
  });
}

String _snapshotText(InMemoryZetaMetricsPort metrics) {
  return metrics.snapshot().map((series) => series.toString()).join('\n');
}
