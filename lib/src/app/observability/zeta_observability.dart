import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/observability/zeta_provider_observer.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 应用级可观测性组合根。
///
/// 阶段 0 的探针默认全部关闭：`fromEnvironment` 只有在显式传入
/// `--dart-define=ZETA_METRICS=true` 时才接上内存聚合器，否则整条链路使用
/// [noopZetaMetricsPort]，探针退化成一次常量分支。
///
/// 采集实现只在这里选择，业务代码一律只依赖 [ZetaMetricsPort]。
final class ZetaObservability {
  const ZetaObservability._({required this.metrics, required this.collector});

  /// 关闭全部采集。
  factory ZetaObservability.disabled() {
    return const ZetaObservability._(
      metrics: noopZetaMetricsPort,
      collector: null,
    );
  }

  /// 开启进程内聚合，可通过 [collector] 导出脱敏快照。
  factory ZetaObservability.inMemory({int maxSeries = 512}) {
    final collector = InMemoryZetaMetricsPort(maxSeries: maxSeries);
    return ZetaObservability._(metrics: collector, collector: collector);
  }

  /// 按编译期开关选择实现。
  factory ZetaObservability.fromEnvironment() {
    return _metricsEnabledByEnvironment
        ? ZetaObservability.inMemory()
        : ZetaObservability.disabled();
  }

  /// 编译期开关；未显式打开时为 false。
  static const bool _metricsEnabledByEnvironment = bool.fromEnvironment(
    'ZETA_METRICS',
  );

  /// 业务代码唯一依赖的指标端口。
  final ZetaMetricsPort metrics;

  /// 采集实现；关闭时为 null。
  final InMemoryZetaMetricsPort? collector;

  /// 根 `ProviderScope` 的观察器列表。
  ///
  /// 关闭采集时返回空列表，避免为 no-op 观察器付出遍历成本。
  List<ProviderObserver> get providerObservers {
    if (!metrics.isEnabled) {
      return const <ProviderObserver>[];
    }
    return <ProviderObserver>[ZetaProviderObserver(metrics: metrics)];
  }
}

/// 应用级可观测性组合。
///
/// 默认按编译期开关走 [ZetaObservability.fromEnvironment]，因此生产入口什么都
/// 不用传。
///
/// 组合根会在真正的容器建出来之前先解析一次它（`ProviderContainer` 的 observers
/// 只能在构造时传入），再把解析出的同一实例装回正式容器。因此 `overrideWith`
/// 工厂只执行一次，观察器与业务指标也始终共享同一份 collector。
final zetaObservabilityProvider = Provider<ZetaObservability>(
  (ref) => ZetaObservability.fromEnvironment(),
  name: 'zetaObservability',
);

/// 正式容器使用的已解析可观测性实例。
///
/// 普通独立容器直接沿用 [zetaObservabilityProvider]；`ZetaAppComposition` 会先在
/// 临时容器解析调用方 override，再把同一实例覆盖到这里，使 Provider observer 与
/// `zetaMetricsPortProvider` 共用 collector。调用方不要直接覆盖本 provider。
final zetaResolvedObservabilityProvider = Provider<ZetaObservability>(
  (ref) => ref.watch(zetaObservabilityProvider),
  name: 'zetaResolvedObservability',
);
