/// Agent 对话 UI 中可独立刷新的区域。
///
/// 这里的 region 只描述 UI 发布范围，不表示 Provider 输入事件的 barrier
/// 语义，也不决定事件是否被接受、合并或排序。
enum AgentUiRegion {
  /// 已完成的历史时间线。
  history,

  /// live turn 与时间线存储之间的绑定关系。
  ///
  /// 该区域对应旧协议中的 `syncLiveTurn`，与仅发布 live turn 内容的
  /// [liveTurn] 分开，以保持现有同步行为。
  liveTurnBinding,

  /// 对话页头部摘要。
  header,

  /// 输入框及发送控制。
  composer,

  /// permission、question 等待处理的交互。
  pendingInteraction,

  /// 工具、计划及命令分组的展开状态。
  expansion,

  /// 当前流式 turn 的局部内容。
  liveTurn,
}

/// UI 更新请求进入现有发布门控的紧迫程度。
///
/// 该类型只描述 UI 调度时机；Provider 输入事件的 barrier 仍由事件缓冲器
/// 独立决定。
enum AgentUiUpdateUrgency {
  /// 与同一可见帧前的普通请求合并，并在下一 Flutter frame 发布。
  nextFrame,

  /// 不等待普通 frame cadence；若正处于 Widget build，则延至最近安全帧。
  immediate,
}

/// 一次性 UI 副作用的类型化基类。
///
/// effect 不属于持久 UI region。具体 effect 应提供结构相等性，使合并请求可
/// 去重；外部扩展类必须使用 Dart 的 `base`、`final` 或 `sealed` 修饰符。
abstract base class AgentUiEffect {
  const AgentUiEffect();
}

/// 请求 UI 在本次发布后自动滚动到最新内容。
final class AgentRequestAutoScroll extends AgentUiEffect {
  const AgentRequestAutoScroll();

  @override
  bool operator ==(Object other) => other is AgentRequestAutoScroll;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AgentRequestAutoScroll()';
}

/// 一次类型化的 Agent 对话 UI 更新请求。
///
/// [regions] 与 [effects] 会在构造时复制为不可修改集合。effect 以结构相等性
/// 去重并保留首次出现顺序，因此相同的一次性 effect 在一个合并发布中只执行一次。
final class AgentUiUpdateRequest {
  factory AgentUiUpdateRequest({
    Iterable<AgentUiRegion> regions = const <AgentUiRegion>[],
    AgentUiUpdateUrgency urgency = AgentUiUpdateUrgency.nextFrame,
    Iterable<AgentUiEffect> effects = const <AgentUiEffect>[],
  }) {
    return AgentUiUpdateRequest._(
      Set<AgentUiRegion>.unmodifiable(regions),
      urgency,
      List<AgentUiEffect>.unmodifiable(_deduplicateEffects(effects)),
    );
  }

  const AgentUiUpdateRequest._(this.regions, this.urgency, this.effects);

  /// 不包含 region 或 effect 的 next-frame 请求。
  static const AgentUiUpdateRequest none = AgentUiUpdateRequest._(
    <AgentUiRegion>{},
    AgentUiUpdateUrgency.nextFrame,
    <AgentUiEffect>[],
  );

  /// 本次发布涉及的 UI 区域。
  final Set<AgentUiRegion> regions;

  /// 本次发布应进入的帧调度路径。
  final AgentUiUpdateUrgency urgency;

  /// 发布完成时按顺序消费的一次性 UI effect。
  final List<AgentUiEffect> effects;

  /// 请求是否不包含任何可发布内容。
  bool get isEmpty => regions.isEmpty && effects.isEmpty;

  /// 合并另一个请求，不修改任一输入对象。
  ///
  /// region 取并集；任一请求为 [AgentUiUpdateUrgency.immediate] 时结果立即发布；
  /// effect 先保留当前请求顺序，再追加另一个请求中尚未出现的 effect。
  AgentUiUpdateRequest mergedWith(AgentUiUpdateRequest other) {
    return AgentUiUpdateRequest(
      regions: <AgentUiRegion>{...regions, ...other.regions},
      urgency:
          urgency == AgentUiUpdateUrgency.immediate ||
              other.urgency == AgentUiUpdateUrgency.immediate
          ? AgentUiUpdateUrgency.immediate
          : AgentUiUpdateUrgency.nextFrame,
      effects: <AgentUiEffect>[...effects, ...other.effects],
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentUiUpdateRequest &&
            urgency == other.urgency &&
            _setEquals(regions, other.regions) &&
            _listEquals(effects, other.effects);
  }

  @override
  int get hashCode => Object.hash(
    urgency,
    Object.hashAllUnordered(regions),
    Object.hashAll(effects),
  );

  @override
  String toString() {
    return 'AgentUiUpdateRequest('
        'regions: $regions, urgency: $urgency, effects: $effects)';
  }
}

List<AgentUiEffect> _deduplicateEffects(Iterable<AgentUiEffect> effects) {
  final seen = <AgentUiEffect>{};
  final result = <AgentUiEffect>[];
  for (final effect in effects) {
    if (seen.add(effect)) {
      result.add(effect);
    }
  }
  return result;
}

bool _setEquals<T>(Set<T> left, Set<T> right) {
  return left.length == right.length && left.containsAll(right);
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
