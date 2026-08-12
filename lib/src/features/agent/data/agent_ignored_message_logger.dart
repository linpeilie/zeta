import 'package:flutter/foundation.dart';
import 'package:zeta/src/core/logging/app_logging.dart';

/// 统一记录 agent provider 丢弃的协议消息。
///
/// provider 和协议 mapper 只提供稳定的 method、原因与结构化摘要；该类负责
/// 开发态白名单日志和按原因计数。原始 JSON 报文可能携带 prompt、文件内容、
/// 工具输出或凭据，无论构建模式都不得进入日志。
final class AgentIgnoredMessageLogger {
  AgentIgnoredMessageLogger({
    required this.providerLabel,
    required String loggerName,
  }) : _log = loggerFor(loggerName);

  /// 用于日志前缀的稳定 provider 名称。
  final String providerLabel;
  final AppLogger _log;

  final Map<String, int> _ignoredCounts = <String, int>{};
  final Map<String, int> _unmatchedCounts = <String, int>{};

  /// 被忽略消息按 method + reason 的累计次数。
  Map<String, int> get ignoredCounts =>
      Map<String, int>.unmodifiable(_ignoredCounts);

  /// 未匹配消息按 method 的累计次数。
  Map<String, int> get unmatchedCounts =>
      Map<String, int>.unmodifiable(_unmatchedCounts);

  /// 记录一条被忽略的消息；同一消息的重复出现不会被去重。
  ///
  /// [payload] 仅用于生成字段存在性、类型与数量摘要。
  ///
  /// [rawPayload] 为旧调用点保留，但会被有意忽略；不得重新编码或记录。
  void record({
    required String method,
    required String reason,
    Map<String, Object?> payload = const <String, Object?>{},
    Object? rawPayload,
    Map<String, Object?> details = const <String, Object?>{},
    bool unmatched = false,
  }) {
    final countKey = '$method|$reason';
    final occurrence = (_ignoredCounts[countKey] ?? 0) + 1;
    _ignoredCounts[countKey] = occurrence;
    if (unmatched) {
      _unmatchedCounts[method] = (_unmatchedCounts[method] ?? 0) + 1;
    }
    if (kReleaseMode) {
      return;
    }

    final prefix = unmatched
        ? 'Ignoring unmatched $providerLabel notification'
        : 'Ignoring $providerLabel notification';
    final fields = <String, String>{
      'count': occurrence.toString(),
      ..._safePayloadShape(payload),
      ..._safeDetails(details),
    };
    final suffix = fields.isEmpty
        ? ''
        : '; ${fields.entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}';
    _log.t(
      '$prefix: ${_safeProtocolLabel(method)} '
      '(reason=${_safeReason(reason)}$suffix)',
    );
  }

  Map<String, String> _safePayloadShape(Map<String, Object?> payload) {
    final item = _asMap(payload['item']);
    final update = _asMap(payload['update']);
    final thread = _asMap(payload['thread']);
    final protocolLabel = _firstProtocolLabel(<Object?>[
      item?['type'],
      payload['type'],
      update?['sessionUpdate'],
      payload['sessionUpdate'],
      update?['type'],
    ]);
    return <String, String>{
      'threadId': _presence(payload['threadId']),
      'thread': thread == null ? 'missing' : 'present',
      'sessionId': _presence(payload['sessionId']),
      'turnId': _presence(payload['turnId']),
      'itemId': _presence(payload['itemId'] ?? item?['id']),
      'itemType': protocolLabel ?? 'missing',
      'paramKeys': payload.length.toString(),
    };
  }

  Map<String, String> _safeDetails(Map<String, Object?> details) {
    final safe = <String, String>{};
    for (final entry in details.entries) {
      if (!_safeDetailKeys.contains(entry.key)) {
        continue;
      }
      safe[entry.key] = _safeDetailValue(entry.value);
    }
    return safe;
  }

  String _safeDetailValue(Object? value) {
    return switch (value) {
      null => 'missing',
      final String text => _safeProtocolLabel(text),
      final num number => number.toString(),
      final bool boolean => boolean.toString(),
      _ => '<invalid>',
    };
  }

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map(
      (key, dynamic item) => MapEntry(key.toString(), item as Object?),
    );
  }

  static String _presence(Object? value) {
    return value is String && value.trim().isNotEmpty ? 'present' : 'missing';
  }

  static String? _firstProtocolLabel(Iterable<Object?> values) {
    for (final value in values) {
      if (value is! String || value.trim().isEmpty) {
        continue;
      }
      return _safeProtocolLabel(value);
    }
    return null;
  }

  static String _safeProtocolLabel(String value) {
    final normalized = value.trim();
    return _protocolLabelPattern.hasMatch(normalized)
        ? normalized
        : '<invalid>';
  }

  static String _safeReason(String value) {
    final normalized = value.trim();
    return _reasonPattern.hasMatch(normalized) ? normalized : '<invalid>';
  }

  static const Set<String> _safeDetailKeys = <String>{
    'errorKind',
    'updateKind',
  };

  static final RegExp _protocolLabelPattern = RegExp(
    r'^[A-Za-z0-9_][A-Za-z0-9._/-]{0,63}$',
  );
  static final RegExp _reasonPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9 ._/:()-]{0,95}$',
  );
}
