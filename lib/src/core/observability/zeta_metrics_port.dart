import 'package:zeta/src/core/observability/zeta_metric.dart';

/// 应用统一的指标出口。
///
/// 事件管线、UI 调度器、runtime 注册表和 Riverpod 观察器都只依赖这个端口，
/// 不直接写日志、不自己聚合、也不知道采集实现是内存、文件还是 no-op。
///
/// 实现必须满足两条硬约束：
///
/// 1. **关闭即近似零开销**：[isEnabled] 为 false 时调用方可以整段跳过采样计算；
/// 2. **不落敏感内容**：只接受 [ZetaMetricSample] 中的白名单指标与规范化标签。
abstract interface class ZetaMetricsPort {
  /// 是否有实际采集方。false 时调用方应跳过一切额外计算。
  bool get isEnabled;

  /// 记录一次采样。实现不得抛出异常，避免观测破坏业务路径。
  void record(ZetaMetricSample sample);
}

/// 默认实现：完全丢弃采样。
///
/// 生产默认使用它，因此未显式开启可观测性时探针只剩一次常量分支。
final class NoopZetaMetricsPort implements ZetaMetricsPort {
  const NoopZetaMetricsPort();

  @override
  bool get isEnabled => false;

  @override
  void record(ZetaMetricSample sample) {}
}

/// 全局可复用的 no-op 实例。
const ZetaMetricsPort noopZetaMetricsPort = NoopZetaMetricsPort();

/// 便捷记录方法。
///
/// 放在扩展里而不是接口上，实现方只需实现 [ZetaMetricsPort.record]。
extension ZetaMetricsPortRecording on ZetaMetricsPort {
  /// 记录计数增量。
  void counter(
    ZetaMetric metric, {
    int increment = 1,
    ZetaMetricTags tags = ZetaMetricTags.none,
  }) {
    assert(
      metric.kind == ZetaMetricKind.counter,
      '${metric.name} is not a counter',
    );
    if (!isEnabled || increment == 0) {
      return;
    }
    record(ZetaMetricSample(metric: metric, value: increment, tags: tags));
  }

  /// 记录瞬时值。
  void gauge(
    ZetaMetric metric,
    int value, {
    ZetaMetricTags tags = ZetaMetricTags.none,
  }) {
    assert(
      metric.kind == ZetaMetricKind.gauge,
      '${metric.name} is not a gauge',
    );
    if (!isEnabled) {
      return;
    }
    record(ZetaMetricSample(metric: metric, value: value, tags: tags));
  }

  /// 记录耗时；内部统一存微秒。
  void duration(
    ZetaMetric metric,
    Duration value, {
    ZetaMetricTags tags = ZetaMetricTags.none,
  }) {
    assert(
      metric.kind == ZetaMetricKind.duration,
      '${metric.name} is not a duration',
    );
    if (!isEnabled) {
      return;
    }
    record(
      ZetaMetricSample(metric: metric, value: value.inMicroseconds, tags: tags),
    );
  }
}
