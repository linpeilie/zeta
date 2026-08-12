import 'package:zeta/src/features/usage_statistics/data/providers/usage_scan_cache.dart';

/// 仅供 v4 Store 读取 v2/v3 派生索引的专用 decoder。
///
/// Provider legacy key 不得扩散到通用 partition store、query service 或 UI。
abstract final class LegacyUsageStatisticsIndexDecoder {
  static const int codexOnlyVersion = 2;
  static const int typedProvidersVersion = 3;
  static const String _codexSourceKey = 'codex';

  static Map<String, Map<String, Object?>> tryDecode(
    Map<String, Object?> root,
  ) {
    return switch (_integer(root['version'])) {
      codexOnlyVersion => _decodeV2(root),
      typedProvidersVersion => _decodeV3(root),
      _ => const <String, Map<String, Object?>>{},
    };
  }

  static Map<String, Map<String, Object?>> _decodeV2(
    Map<String, Object?> root,
  ) {
    final sessions = root['sessions'];
    if (sessions is! List) {
      return const <String, Map<String, Object?>>{};
    }
    return <String, Map<String, Object?>>{
      _codexSourceKey: _sanitizePartition(<String, Object?>{
        'sessions': sessions,
      }),
    };
  }

  static Map<String, Map<String, Object?>> _decodeV3(
    Map<String, Object?> root,
  ) {
    final providers = _objectMap(root['providers']);
    if (providers == null) {
      return const <String, Map<String, Object?>>{};
    }
    final partitions = <String, Map<String, Object?>>{};
    for (final entry in providers.entries) {
      final payload = _objectMap(entry.value);
      if (entry.key.trim().isEmpty || payload == null) {
        continue;
      }
      partitions[entry.key] = _sanitizePartition(payload);
    }
    return Map<String, Map<String, Object?>>.unmodifiable(partitions);
  }
}

/// 旧索引可能来自尚未执行白名单收口的版本；迁移时只保留统计重建所需字段。
Map<String, Object?> _sanitizePartition(Map<String, Object?> payload) {
  final sessions = payload['sessions'];
  if (sessions is! List) {
    return <String, Object?>{'sessions': <Object?>[]};
  }
  return <String, Object?>{
    'sessions': <Object?>[
      for (final value in sessions) ?_sanitizeSession(value),
    ],
  };
}

Map<String, Object?>? _sanitizeSession(Object? value) {
  final session = _objectMap(value);
  if (session == null) {
    return null;
  }
  final sourcePath = _text(session['sourcePath']);
  final sourceId =
      _text(session['sourceId']) ??
      (sourcePath == null ? null : usageSourceId(sourcePath));
  if (sourceId == null) {
    return null;
  }
  final turns = session['turns'];
  return <String, Object?>{
    'sourceId': sourceId,
    for (final key in _safeSessionScalarKeys)
      if (session.containsKey(key) && _isJsonScalar(session[key]))
        key: session[key],
    'turns': turns is List
        ? <Object?>[for (final value in turns) ?_sanitizeTurn(value)]
        : <Object?>[],
  };
}

Map<String, Object?>? _sanitizeTurn(Object? value) {
  final turn = _objectMap(value);
  if (turn == null || _text(turn['id']) == null) {
    return null;
  }
  final samples = turn['samples'];
  return <String, Object?>{
    for (final key in _safeTurnScalarKeys)
      if (turn.containsKey(key) && _isJsonScalar(turn[key])) key: turn[key],
    if (samples is List)
      'samples': <Object?>[
        for (final value in samples) ?_sanitizeSample(value),
      ],
  };
}

Map<String, Object?>? _sanitizeSample(Object? value) {
  final sample = _objectMap(value);
  if (sample == null || _text(sample['deduplicationKey']) == null) {
    return null;
  }
  return <String, Object?>{
    for (final key in _safeSampleScalarKeys)
      if (sample.containsKey(key) && _isJsonScalar(sample[key]))
        key: sample[key],
  };
}

const _safeSessionScalarKeys = <String>[
  'fingerprint',
  'threadId',
  'projectPath',
  'sourceKind',
  'createdAt',
  'modifiedAt',
];

const _safeTurnScalarKeys = <String>[
  'id',
  'status',
  'startedAt',
  'completedAt',
  'durationMs',
  'timeToFirstTokenMs',
  'cwd',
  'model',
  'inputTokens',
  'cachedInputTokens',
  'outputTokens',
  'reasoningTokens',
  'totalTokens',
  'errorCategoryHint',
];

const _safeSampleScalarKeys = <String>[
  'deduplicationKey',
  'timestamp',
  'inputTokens',
  'cachedInputTokens',
  'outputTokens',
  'reasoningTokens',
  'totalTokens',
];

bool _isJsonScalar(Object? value) =>
    value == null || value is bool || value is num || value is String;

String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        return null;
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
  return null;
}

int? _integer(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};
