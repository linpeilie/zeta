import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// ACP session 创建/加载返回的动态配置快照。
class AcpSessionConfigSnapshot {
  const AcpSessionConfigSnapshot({
    required this.options,
    required this.usesLegacyModes,
  });

  final List<AgentSessionConfigOption> options;
  final bool usesLegacyModes;
}

/// 标准 ACP session config options 与旧 session modes 的宽容映射器。
class AcpSessionConfigMapper {
  const AcpSessionConfigMapper();

  AcpSessionConfigSnapshot mapSessionSetup(Map<String, Object?> payload) {
    if (payload.containsKey('configOptions')) {
      return AcpSessionConfigSnapshot(
        options:
            tryMapConfigOptions(payload['configOptions']) ??
            const <AgentSessionConfigOption>[],
        usesLegacyModes: false,
      );
    }
    final legacyMode = _mapLegacyModes(payload['modes']);
    return AcpSessionConfigSnapshot(
      options: legacyMode == null
          ? const <AgentSessionConfigOption>[]
          : <AgentSessionConfigOption>[legacyMode],
      usesLegacyModes: legacyMode != null,
    );
  }

  /// 解码完整 config options 列表；字段不是列表时返回 null，以区分“空状态”和“缺失”。
  List<AgentSessionConfigOption>? tryMapConfigOptions(Object? value) {
    if (value is! List) {
      return null;
    }
    final options = <AgentSessionConfigOption>[];
    for (final item in value) {
      final option = AgentSessionConfigOption.tryDecode(item);
      if (option != null) {
        options.add(option);
      }
    }
    return List<AgentSessionConfigOption>.unmodifiable(options);
  }

  /// 应用旧 `current_mode_update`，同时保留服务端给出的可用模式集合。
  List<AgentSessionConfigOption> applyCurrentMode(
    List<AgentSessionConfigOption> options,
    Object? modeId,
  ) {
    if (modeId == null) {
      return options;
    }
    var changed = false;
    final next = <AgentSessionConfigOption>[
      for (final option in options)
        if (option.category == 'mode' || option.id == 'mode')
          (() {
            changed = true;
            return option.copyWith(currentValue: modeId);
          })()
        else
          option,
    ];
    return changed
        ? List<AgentSessionConfigOption>.unmodifiable(next)
        : options;
  }

  AgentSessionConfigOption? _mapLegacyModes(Object? value) {
    final modes = _asMap(value);
    if (modes == null) {
      return null;
    }
    final available = modes['availableModes'];
    if (available is! List) {
      return null;
    }
    return AgentSessionConfigOption.tryDecode(<String, Object?>{
      'id': 'mode',
      'name': 'Mode',
      'category': 'mode',
      'type': 'select',
      'currentValue': modes['currentModeId'],
      'options': <Map<String, Object?>>[
        for (final item in available)
          if (_asMap(item) case final mode?)
            <String, Object?>{
              'value': mode['id'],
              'name': mode['name'] ?? mode['id'],
              if (mode['description'] != null)
                'description': mode['description'],
            },
      ],
      '_legacyModes': true,
    });
  }
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}
