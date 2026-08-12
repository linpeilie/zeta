import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 将 Anthropic `/v1/models` 响应映射为中立模型目录。
///
/// 响应损坏或没有有效条目时返回空目录，由 Claude Code 自有 catalog 决定是否
/// 回退静态列表。Provider 原始字段只保留声明过的 `capabilities` 节点。
AgentModelList mapClaudeCodeModelCatalog(Object? raw) {
  final response = _asMap(raw);
  final data = response?['data'];
  if (data is! List<Object?>) {
    return const AgentModelList(models: <AgentModelInfo>[]);
  }

  final models = <AgentModelInfo>[];
  var hasDefault = false;
  for (final value in data) {
    final item = _asMap(value);
    final id = _nonEmptyString(item?['id']);
    if (item == null || id == null) {
      continue;
    }

    final capabilities = _asMap(item['capabilities']);
    final isDefault = !hasDefault && _isSonnetModel(id);
    hasDefault = hasDefault || isDefault;
    models.add(
      AgentModelInfo(
        id: id,
        model: id,
        displayName: _nonEmptyString(item['display_name']) ?? id,
        isDefault: isDefault,
        contextWindowTokens: _positiveInteger(item['max_input_tokens']),
        raw: capabilities == null
            ? const <String, Object?>{}
            : <String, Object?>{
                'capabilities': Map<String, Object?>.unmodifiable(capabilities),
              },
      ),
    );
  }

  return AgentModelList(models: List<AgentModelInfo>.unmodifiable(models));
}

bool _isSonnetModel(String id) {
  final normalized = id.toLowerCase();
  return normalized.startsWith('sonnet') ||
      normalized.startsWith('claude-sonnet');
}

int? _positiveInteger(Object? value) {
  if (value is int) {
    return value > 0 ? value : null;
  }
  if (value is num &&
      value.isFinite &&
      value > 0 &&
      value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
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
