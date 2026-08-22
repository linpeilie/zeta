import 'package:zeta_agent_providers/src/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 将 Claude Code `control_response.initialize` 投影为最小元数据快照。
///
/// `value` 是 Claude CLI 接受的稳定模型参数；旧形状缺少 `value` 时才读取
/// `name`。Claude 的 `default` 别名不进入 Composer；`resolvedModel` 保存在中立
/// [AgentModelInfo.model] 中，用于把历史里的实际模型名归一化回稳定 `value`。
/// `supportedEffortLevels` 在 Provider 边界映射为中立推理档位；尚未接入中立契约的
/// Fast/auto 字段会被忽略，原始 payload 也不会写入 [AgentModelInfo.raw]。
ClaudeCodeCliMetadataSnapshot mapClaudeCodeInitializeMetadata(Object? raw) {
  final frame = _asMap(raw);
  if (frame == null || frame['type'] != 'control_response') {
    return ClaudeCodeCliMetadataSnapshot.empty;
  }

  final envelope = _asMap(frame['response']);
  if (envelope == null || envelope['subtype'] != 'success') {
    return ClaudeCodeCliMetadataSnapshot.empty;
  }

  final payload = _asMap(envelope['response']);
  if (payload == null) {
    return ClaudeCodeCliMetadataSnapshot.empty;
  }

  final models = <AgentModelInfo>[];
  final seenIds = <String>{};
  final rawModels = payload['models'];
  if (rawModels is List<Object?>) {
    for (final rawModel in rawModels) {
      final item = _asMap(rawModel);
      final id =
          _nonEmptyString(item?['value']) ?? _nonEmptyString(item?['name']);
      if (item == null || id == null || id == 'default' || !seenIds.add(id)) {
        continue;
      }
      models.add(
        AgentModelInfo(
          id: id,
          model: _nonEmptyString(item['resolvedModel']) ?? id,
          displayName: _nonEmptyString(item['displayName']) ?? id,
          description: _nonEmptyString(item['description']),
          supportedReasoningEfforts: _reasoningEfforts(item),
        ),
      );
    }
  }

  final account = _asMap(payload['account']);
  return ClaudeCodeCliMetadataSnapshot(
    models: AgentModelList(models: List<AgentModelInfo>.unmodifiable(models)),
    subscriptionType: _nonEmptyString(account?['subscriptionType']),
  );
}

List<AgentModelReasoningEffort> _reasoningEfforts(Map<String, Object?> model) {
  if (model['supportsEffort'] != true) {
    return const <AgentModelReasoningEffort>[];
  }
  final rawLevels = model['supportedEffortLevels'];
  if (rawLevels is! List) {
    return const <AgentModelReasoningEffort>[];
  }

  final efforts = <AgentModelReasoningEffort>[];
  final seen = <String>{};
  for (final rawLevel in rawLevels) {
    final effort = _nonEmptyString(rawLevel);
    if (effort == null || !seen.add(effort)) {
      continue;
    }
    efforts.add(AgentModelReasoningEffort(effort: effort));
  }
  return List<AgentModelReasoningEffort>.unmodifiable(efforts);
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}
