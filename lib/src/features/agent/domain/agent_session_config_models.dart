import 'package:zeta/src/features/agent/domain/agent_model_codec.dart';

/// Provider session 配置项的中立类型。
enum AgentSessionConfigOptionKind { select, boolean, string, number, unknown }

/// 可选配置值；[id] 是写回协议的稳定值，[label] 只用于展示。
class AgentSessionConfigValue {
  const AgentSessionConfigValue({
    required this.id,
    required this.label,
    this.description,
    this.raw = const <String, Object?>{},
  });

  final Object id;
  final String label;
  final String? description;
  final Map<String, Object?> raw;
}

/// Provider 暴露的单个 session 配置项。
///
/// 该模型不携带 ACP/Cursor 字段名，presentation 可统一渲染模型、模式及未来自定义项。
class AgentSessionConfigOption {
  const AgentSessionConfigOption({
    required this.id,
    required this.name,
    required this.kind,
    this.description,
    this.category,
    this.currentValue,
    this.values = const <AgentSessionConfigValue>[],
    this.raw = const <String, Object?>{},
  });

  final String id;
  final String name;
  final AgentSessionConfigOptionKind kind;
  final String? description;
  final String? category;
  final Object? currentValue;
  final List<AgentSessionConfigValue> values;
  final Map<String, Object?> raw;

  /// 宽容解码 ACP 风格配置项；损坏或缺少 id/name 的数据返回 `null`。
  static AgentSessionConfigOption? tryDecode(Object? value) {
    final map = decodeObjectMap(value);
    if (map.isEmpty) {
      return null;
    }
    final id = decodeOptionalString(map['id']);
    final name = decodeOptionalString(map['name']);
    if (id == null || name == null) {
      return null;
    }
    final rawType = decodeOptionalString(map['type']);
    final kind = switch (rawType) {
      'select' => AgentSessionConfigOptionKind.select,
      'boolean' => AgentSessionConfigOptionKind.boolean,
      'string' => AgentSessionConfigOptionKind.string,
      'number' => AgentSessionConfigOptionKind.number,
      _ => AgentSessionConfigOptionKind.unknown,
    };
    final decodedValues = <AgentSessionConfigValue>[];
    final rawValues = map['options'] ?? map['values'];
    if (rawValues is List) {
      for (final rawValue in rawValues) {
        final option = decodeObjectMap(rawValue);
        if (option.isEmpty) {
          continue;
        }
        final optionId = option['value'] ?? option['id'];
        final label =
            decodeOptionalString(option['name']) ??
            decodeOptionalString(option['label']);
        if (optionId == null || label == null) {
          continue;
        }
        decodedValues.add(
          AgentSessionConfigValue(
            id: optionId,
            label: label,
            description: decodeOptionalString(option['description']),
            raw: option,
          ),
        );
      }
    }
    return AgentSessionConfigOption(
      id: id,
      name: name,
      kind: kind,
      description: decodeOptionalString(map['description']),
      category: decodeOptionalString(map['category']),
      currentValue: map['currentValue'] ?? map['current_value'],
      values: List<AgentSessionConfigValue>.unmodifiable(decodedValues),
      raw: map,
    );
  }
}
