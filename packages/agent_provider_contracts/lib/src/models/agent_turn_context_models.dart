import 'package:agent_provider_contracts/src/models/agent_turn_history_models.dart';
import 'package:agent_provider_contracts/src/models/immutable_collections.dart';

/// 单个 turn 的 Zeta 侧白名单上下文。
///
/// 只保存发起回合时已知的基础元数据，不包含 prompt、回复、工具输出或 raw payload。
final class AgentTurnContextRecord {
  const AgentTurnContextRecord({
    required this.turnId,
    this.modelId,
    this.reasoningEffort,
    this.serviceTierId,
    this.explicitFast,
    this.startedAt,
    this.completedAt,
    this.status,
  });

  /// Provider turn id。
  final String turnId;

  /// 本回合使用的模型 id。
  final String? modelId;

  /// 本回合明确选择的推理深度档位。
  final String? reasoningEffort;

  /// 本回合选择的服务档位 id。
  final String? serviceTierId;

  /// 本回合 Fast 开关证据。
  final bool? explicitFast;

  /// 回合开始时间。
  final DateTime? startedAt;

  /// 回合结束时间。
  final DateTime? completedAt;

  /// 回合终态；开始事件不写该字段。
  final AgentHistoryTurnStatus? status;

  /// 用 [incoming] 的非空字段覆盖当前记录，空值保留已有数据。
  AgentTurnContextRecord merge(AgentTurnContextRecord incoming) {
    return AgentTurnContextRecord(
      turnId: turnId,
      modelId: incoming.modelId ?? modelId,
      reasoningEffort: incoming.reasoningEffort ?? reasoningEffort,
      serviceTierId: incoming.serviceTierId ?? serviceTierId,
      explicitFast: incoming.explicitFast ?? explicitFast,
      startedAt: incoming.startedAt ?? startedAt,
      completedAt: incoming.completedAt ?? completedAt,
      status: incoming.status ?? status,
    );
  }
}

/// 一个 thread 下 Zeta 记录的 turn 上下文集合。
final class AgentThreadTurnContext {
  AgentThreadTurnContext({
    required this.providerId,
    required this.threadId,
    List<AgentTurnContextRecord> turns = const <AgentTurnContextRecord>[],
    this.version = currentVersion,
  }) : turns = immutableList(turns);

  /// 当前持久化结构版本。
  static const int currentVersion = 1;

  /// Provider 稳定 id。
  final String providerId;

  /// Provider thread / session id。
  final String threadId;

  /// 按首次出现顺序保存的 turn 记录。
  final List<AgentTurnContextRecord> turns;

  /// 文件格式版本。
  final int version;

  /// 按 turnId 查找记录。
  AgentTurnContextRecord? turnById(String turnId) {
    for (final turn in turns) {
      if (turn.turnId == turnId) {
        return turn;
      }
    }
    return null;
  }

  /// 按 turnId 字段级 upsert，新 turn 追加到末尾。
  AgentThreadTurnContext upsertTurn(AgentTurnContextRecord incoming) {
    final nextTurns = <AgentTurnContextRecord>[];
    var replaced = false;
    for (final turn in turns) {
      if (turn.turnId == incoming.turnId) {
        nextTurns.add(turn.merge(incoming));
        replaced = true;
      } else {
        nextTurns.add(turn);
      }
    }
    if (!replaced) {
      nextTurns.add(incoming);
    }
    return AgentThreadTurnContext(
      providerId: providerId,
      threadId: threadId,
      turns: List<AgentTurnContextRecord>.unmodifiable(nextTurns),
    );
  }
}
