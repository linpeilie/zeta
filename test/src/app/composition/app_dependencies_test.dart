import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/composition/app_dependencies.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

void main() {
  group('应用级依赖 Provider', () {
    test('默认值安全：系统时钟 + no-op 指标端口', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(zetaMetricsPortProvider).isEnabled, isFalse);
      expect(container.read(zetaClockProvider)(), isA<DateTime>());
    });

    test('组合根可以覆盖依赖，业务代码只读端口', () {
      final metrics = InMemoryZetaMetricsPort();
      final instant = DateTime.utc(2026, 8, 21, 9);
      final container = ProviderContainer(
        overrides: <Override>[
          zetaMetricsPortProvider.overrideWithValue(metrics),
          zetaClockProvider.overrideWithValue(fixedClock(instant)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(zetaMetricsPortProvider), same(metrics));
      expect(container.read(zetaClockProvider)(), instant);
    });

    test('无默认实现的依赖未覆盖时 fail-closed', () {
      final dependency = requiredDependency<String>('zeta.test.required');
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(dependency), throwsStateError);
    });

    test('覆盖后必需依赖正常读取', () {
      final dependency = requiredDependency<String>('zeta.test.required');
      final container = ProviderContainer(
        overrides: <Override>[dependency.overrideWithValue('injected')],
      );
      addTearDown(container.dispose);

      expect(container.read(dependency), 'injected');
    });

    test('Provider 名称稳定，便于观察器按名聚合', () {
      expect(zetaClockProvider.name, 'zeta.clock');
      expect(zetaMetricsPortProvider.name, 'zeta.metrics');
    });
  });
}
