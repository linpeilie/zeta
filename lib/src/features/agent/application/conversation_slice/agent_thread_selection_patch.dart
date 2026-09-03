import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 历史 / session 配置未给出该字段时的占位。
///
/// 与 `null` 不同：`null` 表示「明确清空」，本哨兵表示「不要覆盖已有值」。
const Object kAgentThreadSelectionUnset = Object();

/// 从历史或 session 配置抽出的模型选择补丁。
///
/// [reasoningEffort] / [serviceTierId] / [fastEnabled] 使用
/// [kAgentThreadSelectionUnset] 表示未给出；显式 `null` 表示清空。
final class AgentThreadSelectionPatch {
  const AgentThreadSelectionPatch({
    this.modelId,
    this.reasoningEffort = kAgentThreadSelectionUnset,
    this.serviceTierId = kAgentThreadSelectionUnset,
    this.fastEnabled = kAgentThreadSelectionUnset,
  });

  final String? modelId;
  final Object? reasoningEffort;
  final Object? serviceTierId;
  final Object? fastEnabled;

  bool get hasAny =>
      (modelId != null && modelId!.isNotEmpty) ||
      !identical(reasoningEffort, kAgentThreadSelectionUnset) ||
      !identical(serviceTierId, kAgentThreadSelectionUnset) ||
      !identical(fastEnabled, kAgentThreadSelectionUnset);
}

/// 从后往前找最近一次可用的历史选择：优先带 modelId 的 turn，否则任意非空补丁。
AgentThreadSelectionPatch? latestAgentThreadSelectionPatch(
  List<AgentHistoryTurn> turns,
) {
  for (var index = turns.length - 1; index >= 0; index -= 1) {
    final patch = agentThreadSelectionPatchFromHistoryTurn(turns[index]);
    if (patch != null && _nonEmpty(patch.modelId) != null) {
      return patch;
    }
  }
  for (var index = turns.length - 1; index >= 0; index -= 1) {
    final patch = agentThreadSelectionPatchFromHistoryTurn(turns[index]);
    if (patch != null && patch.hasAny) {
      return patch;
    }
  }
  return null;
}

/// 把单个历史 turn 投影成选择补丁；没有任何可应用字段时返回 null。
AgentThreadSelectionPatch? agentThreadSelectionPatchFromHistoryTurn(
  AgentHistoryTurn? turn,
) {
  if (turn == null) {
    return null;
  }
  Object? reasoningEffort = kAgentThreadSelectionUnset;
  if (turn.reasoningEffort.isKnown) {
    reasoningEffort = _nonEmpty(turn.reasoningEffort.value);
  }

  Object? serviceTierId = kAgentThreadSelectionUnset;
  final typedServiceTierId = _nonEmpty(turn.serviceTierId);
  if (typedServiceTierId != null) {
    serviceTierId = typedServiceTierId;
  }

  Object? fastEnabled = kAgentThreadSelectionUnset;
  if (turn.explicitFast != null) {
    fastEnabled = turn.explicitFast;
  }

  final patch = AgentThreadSelectionPatch(
    modelId: _nonEmpty(turn.modelId),
    reasoningEffort: reasoningEffort,
    serviceTierId: serviceTierId,
    fastEnabled: fastEnabled,
  );
  return patch.hasAny ? patch : null;
}

/// 用 [overlay] 覆盖 [base]：overlay 的非空 modelId 与非 unset 字段胜出。
AgentThreadSelectionPatch? mergeAgentThreadSelectionPatches(
  AgentThreadSelectionPatch? base,
  AgentThreadSelectionPatch? overlay,
) {
  if (base == null) {
    return overlay;
  }
  if (overlay == null) {
    return base;
  }
  final merged = AgentThreadSelectionPatch(
    modelId: _nonEmpty(overlay.modelId) ?? base.modelId,
    reasoningEffort:
        identical(overlay.reasoningEffort, kAgentThreadSelectionUnset)
        ? base.reasoningEffort
        : overlay.reasoningEffort,
    serviceTierId: identical(overlay.serviceTierId, kAgentThreadSelectionUnset)
        ? base.serviceTierId
        : overlay.serviceTierId,
    fastEnabled: identical(overlay.fastEnabled, kAgentThreadSelectionUnset)
        ? base.fastEnabled
        : overlay.fastEnabled,
  );
  return merged.hasAny ? merged : null;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
