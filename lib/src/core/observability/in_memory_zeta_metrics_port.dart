import 'package:zeta/src/core/observability/zeta_metric.dart';
import 'package:zeta/src/core/observability/zeta_metrics_port.dart';

/// 单个指标序列（指标 + 标签组合）的聚合结果。
final class ZetaMetricSeriesSnapshot {
  const ZetaMetricSeriesSnapshot({
    required this.metric,
    required this.tags,
    required this.sampleCount,
    required this.total,
    required this.lastValue,
    required this.maxValue,
    required this.minValue,
  });

  final ZetaMetric metric;
  final ZetaMetricTags tags;

  /// 采样次数。
  final int sampleCount;

  /// 采样值之和；counter 即累计计数，duration 即总微秒数。
  final int total;

  /// 最近一次采样值；gauge 用它表示当前水位。
  final int lastValue;

  /// 采样值上界；gauge 用它表示历史高水位。
  final int maxValue;

  /// 采样值下界。
  final int minValue;

  /// 稳定的序列标识。
  String get seriesKey => '${metric.name}#${tags.seriesKey}';

  @override
  String toString() =>
      '$seriesKey{count:$sampleCount,total:$total,last:$lastValue,'
      'max:$maxValue,min:$minValue}';
}

/// 进程内有界指标聚合器。
///
/// 用于 Phase 0 的基线采集、测试断言和诊断导出。它只保存计数、极值和最近值，
/// 不保存采样时间序列，因此内存占用由 [maxSeries] 严格封顶。
final class InMemoryZetaMetricsPort implements ZetaMetricsPort {
  InMemoryZetaMetricsPort({this.maxSeries = 512, this.enabled = true})
    : assert(maxSeries > 0);

  /// 允许保留的不同序列数量上限，防止标签维度失控导致无界增长。
  final int maxSeries;

  /// 是否实际聚合采样；false 时与 no-op 端口等价。
  final bool enabled;

  final Map<String, _MutableSeries> _series = <String, _MutableSeries>{};
  int _droppedSeriesSamples = 0;

  @override
  bool get isEnabled => enabled;

  /// 因超过 [maxSeries] 而被丢弃的采样数。持续增长说明标签基数设计有问题。
  int get droppedSeriesSamples => _droppedSeriesSamples;

  /// 当前保留的序列数量。
  int get seriesCount => _series.length;

  @override
  void record(ZetaMetricSample sample) {
    if (!enabled) {
      return;
    }
    final key = '${sample.metric.name}#${sample.tags.seriesKey}';
    final existing = _series[key];
    if (existing != null) {
      existing.add(sample.value);
      return;
    }
    if (_series.length >= maxSeries) {
      _droppedSeriesSamples += 1;
      return;
    }
    _series[key] = _MutableSeries(
      metric: sample.metric,
      tags: sample.tags,
      value: sample.value,
    );
  }

  /// 累计值；counter 常用。
  int totalOf(ZetaMetric metric, {ZetaMetricTags? tags}) {
    return _fold(metric, tags, 0, (sum, series) => sum + series.total);
  }

  /// 最近一次采样值；gauge 常用。同指标多标签时返回任一序列的最近值。
  int? lastValueOf(ZetaMetric metric, {ZetaMetricTags? tags}) {
    for (final series in _matching(metric, tags)) {
      return series.lastValue;
    }
    return null;
  }

  /// 历史高水位。
  int? maxValueOf(ZetaMetric metric, {ZetaMetricTags? tags}) {
    int? result;
    for (final series in _matching(metric, tags)) {
      final current = series.maxValue;
      if (result == null || current > result) {
        result = current;
      }
    }
    return result;
  }

  /// 采样次数。
  int sampleCountOf(ZetaMetric metric, {ZetaMetricTags? tags}) {
    return _fold(metric, tags, 0, (sum, series) => sum + series.sampleCount);
  }

  /// 导出全部序列快照，按序列键稳定排序。
  List<ZetaMetricSeriesSnapshot> snapshot() {
    final keys = _series.keys.toList(growable: false)..sort();
    return List<ZetaMetricSeriesSnapshot>.unmodifiable(
      keys.map((key) => _series[key]!.toSnapshot()),
    );
  }

  /// 清空已聚合的序列，用于分段基线采集。
  void reset() {
    _series.clear();
    _droppedSeriesSamples = 0;
  }

  int _fold(
    ZetaMetric metric,
    ZetaMetricTags? tags,
    int initial,
    int Function(int accumulator, _MutableSeries series) combine,
  ) {
    var result = initial;
    for (final series in _matching(metric, tags)) {
      result = combine(result, series);
    }
    return result;
  }

  Iterable<_MutableSeries> _matching(ZetaMetric metric, ZetaMetricTags? tags) {
    return _series.values.where(
      (series) =>
          series.metric == metric && (tags == null || series.tags == tags),
    );
  }
}

final class _MutableSeries {
  _MutableSeries({required this.metric, required this.tags, required int value})
    : sampleCount = 1,
      total = value,
      lastValue = value,
      maxValue = value,
      minValue = value;

  final ZetaMetric metric;
  final ZetaMetricTags tags;
  int sampleCount;
  int total;
  int lastValue;
  int maxValue;
  int minValue;

  void add(int value) {
    sampleCount += 1;
    total += value;
    lastValue = value;
    if (value > maxValue) {
      maxValue = value;
    }
    if (value < minValue) {
      minValue = value;
    }
  }

  ZetaMetricSeriesSnapshot toSnapshot() {
    return ZetaMetricSeriesSnapshot(
      metric: metric,
      tags: tags,
      sampleCount: sampleCount,
      total: total,
      lastValue: lastValue,
      maxValue: maxValue,
      minValue: minValue,
    );
  }
}
