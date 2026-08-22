import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta_foundation/zeta_foundation.dart';

/// 根 `ProviderScope` 使用的脱敏 Riverpod 观察器。
///
/// 它只把 **provider 名称、事件类型和失败分类** 交给 [ZetaMetricsPort]：
///
/// - 绝不读取 `value` / `newValue` / `previousValue`，也不调用它们的 `toString()`；
/// - 绝不读取 family 的 `argument`（其中可能是项目路径或 thread id）；
/// - 失败只记录 `outcome: failure` 和异常运行时类型名，不记录错误文本或堆栈。
///
/// 阶段 0 只观测，不迁移任何业务状态。生产默认注入 [noopZetaMetricsPort]，
/// 此时每个回调只剩一次 `isEnabled` 常量分支。
final class ZetaProviderObserver extends ProviderObserver {
  const ZetaProviderObserver({this.metrics = noopZetaMetricsPort});

  final ZetaMetricsPort metrics;

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    metrics.counter(ZetaMetric.riverpodProviderAdded, tags: _tagsFor(provider));
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    metrics.counter(
      ZetaMetric.riverpodProviderUpdated,
      tags: _tagsFor(provider),
    );
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    metrics.counter(
      ZetaMetric.riverpodProviderDisposed,
      tags: _tagsFor(provider),
    );
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    metrics.counter(
      ZetaMetric.riverpodProviderFailed,
      tags: _tagsFor(provider, outcome: ZetaMetricOutcome.failure),
    );
  }

  /// 只使用声明期就固定的 provider 名或其实现类型名。
  ///
  /// `provider.name` 由代码里的 `name:` 常量给出；缺省时退回 `runtimeType`，
  /// 它是 Dart 类型名而不是运行期数据。两者都会再过一次标签规范化。
  ZetaMetricTags _tagsFor(
    ProviderBase<Object?> provider, {
    ZetaMetricOutcome? outcome,
  }) {
    if (!metrics.isEnabled) {
      return ZetaMetricTags.none;
    }
    return ZetaMetricTags(
      component: provider.name ?? provider.runtimeType.toString(),
      outcome: outcome,
    );
  }
}
