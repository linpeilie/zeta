/// 当前 live turn 的主活动相位（标题栏 segment 用）。
///
/// 等待审批/输入由 thread status 胶囊单独表达，不占用此枚举。
enum AgentTurnActivityPhase {
  /// Turn 已启动，尚无思考/回复/工具产出。
  starting,

  /// Reasoning / think 卡片进行中。
  thinking,

  /// Agent 消息流式输出中。
  responding,

  /// 非 think 类工具执行中。
  toolRunning,

  /// 无进行中的 turn。
  idle,
}

/// 当前 turn 主活动段快照。
///
/// [segmentStartedAt] 在相位或主工具切换时刷新；[turnStartedAt] 取自 turn 元数据。
class AgentTurnActivitySnapshot {
  const AgentTurnActivitySnapshot({
    required this.phase,
    this.label,
    this.segmentStartedAt,
    this.turnStartedAt,
    this.primaryToolId,
  });

  static const AgentTurnActivitySnapshot idle = AgentTurnActivitySnapshot(
    phase: AgentTurnActivityPhase.idle,
  );

  final AgentTurnActivityPhase phase;

  /// 工具短标题等；思考/启动/回复通常为空。
  final String? label;

  /// 当前主活动段开始时间（本地时钟）。
  final DateTime? segmentStartedAt;

  /// 当前 turn 开始时间（本地时钟）。
  final DateTime? turnStartedAt;

  /// 主工具 id（toolRunning / thinking 时可选）。
  final String? primaryToolId;

  bool get isActive => phase != AgentTurnActivityPhase.idle;
}

/// 解析展示用耗时：终态优先 [frozenDuration]，否则 `end - startedAt`。
Duration? resolveAgentElapsed({
  required DateTime now,
  DateTime? startedAt,
  DateTime? completedAt,
  Duration? frozenDuration,
}) {
  if (frozenDuration != null) {
    return frozenDuration.isNegative ? Duration.zero : frozenDuration;
  }
  if (startedAt == null) {
    return null;
  }
  final end = completedAt ?? now;
  final elapsed = end.difference(startedAt);
  if (elapsed.isNegative) {
    return Duration.zero;
  }
  return elapsed;
}

/// 紧凑时长文案：`12s` / `1m 5s` / `0.4s`。
///
/// 不足 1 秒时按 **0.1s 向上取整** 展示（最多一位小数），例如 1–100ms → `0.1s`，
/// 101–200ms → `0.2s`，901–999ms → `1s`。
///
/// [includeSubSecond] 为 true 时，恰好 0 显示 `0s`（live 活动条刚启动）；
/// 为 false 时 0 返回 null（终态无有效耗时不展示）。
String? formatAgentDuration(
  Duration? duration, {
  bool includeSubSecond = false,
}) {
  if (duration == null) {
    return null;
  }
  if (duration.isNegative) {
    return null;
  }
  final totalMs = duration.inMilliseconds;
  if (totalMs <= 0) {
    return includeSubSecond ? '0s' : null;
  }
  // < 1s：ceil 到 0.1s 精度。
  if (totalMs < Duration.millisecondsPerSecond) {
    final tenths = (totalMs + 99) ~/ 100;
    if (tenths >= 10) {
      return '1s';
    }
    return '0.${tenths}s';
  }
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}

/// 标题栏主 segment 文案（不含时长）。
String? agentActivitySegmentLabel(AgentTurnActivitySnapshot activity) {
  return switch (activity.phase) {
    AgentTurnActivityPhase.starting => '启动中',
    AgentTurnActivityPhase.thinking => '思考中',
    AgentTurnActivityPhase.responding => '回复中',
    AgentTurnActivityPhase.toolRunning => () {
      final label = activity.label?.trim();
      if (label == null || label.isEmpty) {
        return '执行中';
      }
      // 过长命令截断，避免头栏撑破布局。
      final short = label.length > 28 ? '${label.substring(0, 28)}…' : label;
      return '执行中 · $short';
    }(),
    AgentTurnActivityPhase.idle => null,
  };
}
