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
  void didAddProvider(ProviderObserverContext context, Object? value) {
    metrics.counter(ZetaMetric.riverpodProviderAdded, tags: _tagsFor(context));
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    metrics.counter(
      ZetaMetric.riverpodProviderUpdated,
      tags: _tagsFor(context),
    );
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    metrics.counter(
      ZetaMetric.riverpodProviderDisposed,
      tags: _tagsFor(context),
    );
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    metrics.counter(
      ZetaMetric.riverpodProviderFailed,
      tags: _tagsFor(context, outcome: ZetaMetricOutcome.failure),
    );
  }

  /// 只使用声明期就固定的 provider 名或其实现类型名。
  ///
  /// `provider.name` 由代码里的 `name:` 常量给出；缺省时退回 `runtimeType`，
  /// 它是 Dart 类型名而不是运行期数据。泛型参数会被去掉（`Impl<Foo>` → `Impl`），
  /// 否则尖括号不符合标签白名单形态，会被整体丢弃。
  ZetaMetricTags _tagsFor(
    ProviderObserverContext context, {
    ZetaMetricOutcome? outcome,
  }) {
    if (!metrics.isEnabled) {
      return ZetaMetricTags.none;
    }
    final provider = context.provider;
    final name = provider.name ?? _typeLabel(provider);
    // provider 名与类型名都是声明期常量；形态异常时会自动降级成 hash。
    return ZetaMetricTags(
      component: ZetaMetricLabel.declaredIdentifier(name),
      outcome: outcome,
    );
  }

  String _typeLabel(Object provider) {
    final runtimeType = provider.runtimeType.toString();
    final generic = runtimeType.indexOf('<');
    return generic < 0 ? runtimeType : runtimeType.substring(0, generic);
  }
}
