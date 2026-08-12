import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 将 Claude Code `control_response.initialize` 投影为最小元数据快照。
///
/// `value` 是 Claude CLI 接受的稳定模型参数；旧形状缺少 `value` 时才读取
/// `name`。`resolvedModel` 和尚未接入中立契约的 effort/Fast/auto 字段会被忽略，
/// 原始 payload 也不会写入 [AgentModelInfo.raw]。
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
      if (item == null || id == null || !seenIds.add(id)) {
        continue;
      }
      models.add(
        AgentModelInfo(
          id: id,
          model: id,
          displayName: _nonEmptyString(item['displayName']) ?? id,
          description: _nonEmptyString(item['description']),
          isDefault: id == 'default',
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
