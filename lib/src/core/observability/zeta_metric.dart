/// 阶段 0 可观测性的白名单指标定义。
///
/// 指标标识、维度和取值全部是编译期封闭集合：调用方无法用自由文本把 prompt、
/// 回复正文、文件路径、raw payload 或原始错误塞进指标流（G7）。这里是纯 Dart，
/// 不依赖 Flutter、Riverpod、`dart:io` 或任何 Provider 协议类型。
library;

/// 指标的取值语义。
enum ZetaMetricKind {
  /// 单调递增计数。
  counter,

  /// 采样时刻的瞬时值（队列深度、实例数量等）。
  gauge,

  /// 耗时采样，单位微秒。
  duration,
}

/// 指标所属区域，对应目标架构文档 §11.1 的最小指标表。
enum ZetaMetricDomain {
  appStartup,
  riverpod,
  agentPipeline,
  agentUi,
  agentRuntime,
}

/// 指标白名单。
///
/// **新增指标必须在这里登记**，并且只能记录计数、深度、耗时和封闭分类；
/// 任何需要携带正文、路径或 payload 的“指标”一律不属于本枚举。
enum ZetaMetric {
  // ---- app 启动 ----
  /// bootstrap 阶段耗时。
  appBootstrapDuration(ZetaMetricDomain.appStartup, ZetaMetricKind.duration),

  // ---- Riverpod ----
  /// Provider 初始化次数。
  riverpodProviderAdded(ZetaMetricDomain.riverpod, ZetaMetricKind.counter),

  /// Provider 状态更新次数。
  riverpodProviderUpdated(ZetaMetricDomain.riverpod, ZetaMetricKind.counter),

  /// Provider 释放次数。
  riverpodProviderDisposed(ZetaMetricDomain.riverpod, ZetaMetricKind.counter),

  /// Provider 构建或异步求值失败次数。
  riverpodProviderFailed(ZetaMetricDomain.riverpod, ZetaMetricKind.counter),

  // ---- Agent 事件管线 ----
  /// 从 Provider 事件流收到的事件数。
  agentPipelineEventsReceived(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.counter,
  ),

  /// 通过 listener generation / runtime scope 校验并进入 reducer 的事件数。
  agentPipelineEventsAccepted(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.counter,
  ),

  /// 因代数过期、runtime 失配或已关闭而丢弃的事件数。
  agentPipelineEventsRejected(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.counter,
  ),

  /// 合并进同 key 待发批次的事件数。
  agentPipelineEventsCoalesced(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.counter,
  ),

  /// 由有界 dispatcher 实际投递的事件数。
  agentPipelineEventsDispatched(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.counter,
  ),

  /// 触发 pending key 上限强制 flush 的次数。
  agentPipelineBackpressureFlushes(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.counter,
  ),

  /// 事件源错误次数（只记数量，不记错误文本）。
  agentPipelineSourceErrors(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.counter,
  ),

  /// 采样时刻的 coalescing buffer pending key 数。
  agentPipelinePendingKeys(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.gauge,
  ),

  /// 采样时刻的 dispatcher 队列深度。
  agentPipelineQueueDepth(ZetaMetricDomain.agentPipeline, ZetaMetricKind.gauge),

  /// dispatcher 让出 event queue 的次数。
  agentPipelineDispatcherYields(
    ZetaMetricDomain.agentPipeline,
    ZetaMetricKind.counter,
  ),

  // ---- Agent UI 发布 ----
  /// 合并到下一帧发布的 UI 更新次数。
  agentUiFramePublishes(ZetaMetricDomain.agentUi, ZetaMetricKind.counter),

  /// 在安全同步边界立即发布的 urgent 更新次数。
  agentUiImmediatePublishes(ZetaMetricDomain.agentUi, ZetaMetricKind.counter),

  /// 已发布请求携带的 region 总数。
  agentUiPublishedRegions(ZetaMetricDomain.agentUi, ZetaMetricKind.counter),

  /// 已发布请求携带的一次性 effect 总数。
  agentUiPublishedEffects(ZetaMetricDomain.agentUi, ZetaMetricKind.counter),

  /// 因处于 build phase 而延后到下一帧的 urgent 请求数。
  agentUiBuildPhaseDeferrals(ZetaMetricDomain.agentUi, ZetaMetricKind.counter),

  /// dispose 之后到达并被忽略的 UI 更新请求数。
  agentUiRequestsAfterDispose(ZetaMetricDomain.agentUi, ZetaMetricKind.counter),

  // ---- Provider runtime ----
  /// 命中已有共享 runtime 的租约获取次数。
  agentRuntimeLeaseReused(
    ZetaMetricDomain.agentRuntime,
    ZetaMetricKind.counter,
  ),

  /// 新建 runtime 实例的次数。
  agentRuntimeCreated(ZetaMetricDomain.agentRuntime, ZetaMetricKind.counter),

  /// 因配置变化、显式失效或空闲回收而关闭 runtime 的次数。
  agentRuntimeInvalidated(
    ZetaMetricDomain.agentRuntime,
    ZetaMetricKind.counter,
  ),

  /// 注册表整体关闭的次数。
  agentRuntimeRegistryClosed(
    ZetaMetricDomain.agentRuntime,
    ZetaMetricKind.counter,
  ),

  /// 采样时刻注册表持有的 runtime 数量。
  agentRuntimeActiveCount(ZetaMetricDomain.agentRuntime, ZetaMetricKind.gauge),

  /// 采样时刻未释放的租约数量。
  agentRuntimeActiveLeases(ZetaMetricDomain.agentRuntime, ZetaMetricKind.gauge);

  const ZetaMetric(this.domain, this.kind);

  final ZetaMetricDomain domain;
  final ZetaMetricKind kind;
}

/// 操作结果的封闭分类，用于替代原始错误文本。
enum ZetaMetricOutcome { success, failure, cancelled, stale, unsupported }

/// 指标维度。
///
/// 所有字段都会经过 [ZetaMetricTags.sanitizeLabel] 规范化：只保留
/// `[A-Za-z0-9_.-]`，其余字符替换为 `_`，长度截断到 [maxLabelLength]。
/// 这样即使调用方误传路径或标题，也不会有可读的敏感片段进入指标流。
final class ZetaMetricTags {
  factory ZetaMetricTags({
    String? providerId,
    String? component,
    ZetaMetricOutcome? outcome,
  }) {
    if (providerId == null && component == null && outcome == null) {
      return none;
    }
    return ZetaMetricTags._(
      providerId: sanitizeLabel(providerId),
      component: sanitizeLabel(component),
      outcome: outcome,
    );
  }

  const ZetaMetricTags._({this.providerId, this.component, this.outcome});

  /// 无维度采样。
  static const ZetaMetricTags none = ZetaMetricTags._();

  /// 单个标签的最大长度。
  static const int maxLabelLength = 48;

  /// Provider 标识（`codex` / `grok` / `claude_code` 之类的稳定内部 ID）。
  final String? providerId;

  /// 组件或子区域标识，例如 Riverpod provider 名、`live` / `history`。
  final String? component;

  /// 结果分类。
  final ZetaMetricOutcome? outcome;

  /// 把任意输入压成安全标签；`null`、空串和纯分隔符统一返回 `null`。
  static String? sanitizeLabel(String? value) {
    if (value == null) {
      return null;
    }
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (buffer.length >= maxLabelLength) {
        break;
      }
      final char = String.fromCharCode(rune);
      buffer.write(_safeLabelCharacter.hasMatch(char) ? char : '_');
    }
    final sanitized = buffer.toString();
    if (sanitized.isEmpty || !sanitized.contains(_labelSignal)) {
      return null;
    }
    return sanitized;
  }

  static final RegExp _safeLabelCharacter = RegExp(r'[A-Za-z0-9_.\-]');
  static final RegExp _labelSignal = RegExp(r'[A-Za-z0-9]');

  /// 稳定的序列键，用于聚合与导出。
  String get seriesKey =>
      '${providerId ?? '-'}|${component ?? '-'}|${outcome?.name ?? '-'}';

  @override
  bool operator ==(Object other) {
    return other is ZetaMetricTags &&
        other.providerId == providerId &&
        other.component == component &&
        other.outcome == outcome;
  }

  @override
  int get hashCode => Object.hash(providerId, component, outcome);

  @override
  String toString() => 'ZetaMetricTags($seriesKey)';
}

/// 单个指标采样。
///
/// [value] 对 counter 是增量，对 gauge 是瞬时值，对 duration 是微秒数。
final class ZetaMetricSample {
  const ZetaMetricSample({
    required this.metric,
    required this.value,
    this.tags = ZetaMetricTags.none,
  });

  final ZetaMetric metric;
  final int value;
  final ZetaMetricTags tags;

  @override
  String toString() =>
      'ZetaMetricSample(${metric.name}=$value ${tags.seriesKey})';
}
