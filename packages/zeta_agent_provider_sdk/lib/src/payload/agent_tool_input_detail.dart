import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 从 Provider 的工具输入 payload 里推导一句展示用细节（命令 / 路径 / 查询）。
///
/// 这是**对 wire 形状的启发式猜测**：候选键名来自三个 CLI 的实际 payload。
/// 它属于 Provider 语义，因此住在适配层——中立内核只接受算好的
/// `AgentToolCall.inputDetail`，不自己解析原文（G2）。
String? deriveAgentToolInputDetail(Map<String, Object?> rawInput) {
  if (rawInput.isEmpty) {
    return null;
  }

  const preferredKeys = <String>[
    'command',
    'cmd',
    'shell',
    'script',
    'query',
    'pattern',
    'search',
    'url',
    'uri',
    'path',
    'file',
    'file_path',
    'filePath',
    'target',
    'target_path',
    'targetPath',
    'name',
    'tool',
    'toolName',
    'tool_name',
    'description',
  ];

  for (final key in preferredKeys) {
    final value = rawInput[key];
    final text = _nonEmptyString(value);
    if (text != null) {
      return _isPathLikeKey(key)
          ? shortenAgentToolPath(text)
          : shortenAgentToolText(text);
    }
  }

  // 常见嵌套：{ arguments: { path: ... } } 或 JSON 字符串参数。
  final nested =
      rawInput['arguments'] ?? rawInput['input'] ?? rawInput['params'];
  if (nested is Map) {
    final nestedMap = nested.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final nestedDetail = deriveAgentToolInputDetail(nestedMap);
    if (nestedDetail != null) {
      return nestedDetail;
    }
  } else {
    final nestedText = _nonEmptyString(nested);
    if (nestedText != null) {
      return shortenAgentToolText(nestedText);
    }
  }

  return null;
}

bool _isPathLikeKey(String key) {
  final lower = key.toLowerCase();
  return lower.contains('path') || lower == 'file' || lower == 'target';
}

String? _nonEmptyString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is List) {
    final parts = value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' ');
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
