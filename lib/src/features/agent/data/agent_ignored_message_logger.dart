import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:zeta/src/core/logging/app_logging.dart';

/// 统一记录 agent provider 丢弃的协议消息。
///
/// provider 和协议 mapper 只提供稳定的 method、原因与结构化摘要；该类负责
/// 开发态日志、按原因计数以及记录原始 JSON 报文。生产构建保留计数但不
/// 输出 fine 日志，避免原始报文进入正式日志。
final class AgentIgnoredMessageLogger {
  AgentIgnoredMessageLogger({
    required this.providerLabel,
    required String loggerName,
  }) : _log = loggerFor(loggerName);

  /// 用于日志前缀的稳定 provider 名称。
  final String providerLabel;
  final Logger _log;

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
  /// [payload] 用于生成可检索的结构化摘要；[rawPayload] 应传入未经加工的
  /// 原始 JSON-RPC 报文，未提供时回退到 [payload]。
  void record({
    required String method,
    required String reason,
    Map<String, Object?> payload = const <String, Object?>{},
    Object? rawPayload,
    Map<String, Object?> details = const <String, Object?>{},
    bool unmatched = false,
  }) {
    final countKey = '$method|$reason';
    _ignoredCounts[countKey] = (_ignoredCounts[countKey] ?? 0) + 1;
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
      ..._safePayloadShape(payload),
      ..._safeDetails(details),
    };
    final suffix = fields.isEmpty
        ? ''
        : '; ${fields.entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}';
    final rawText = _encodeRawPayload(rawPayload ?? payload);
    _log.fine(
      '$prefix: ${_safeLogLabel(method)} '
      '(reason=${_safeLogLabel(reason)}$suffix; raw=$rawText)',
    );
  }

  static String _encodeRawPayload(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return '<unserializable:${value.runtimeType}>';
    }
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
      final key = _safeLogLabel(entry.key);
      if (key.isEmpty) {
        continue;
      }
      safe[key] = _safeDetailValue(entry.value);
    }
    return safe;
  }

  String _safeDetailValue(Object? value) {
    return switch (value) {
      null => 'null',
      final String text => _safeLogLabel(text),
      final num number => number.toString(),
      final bool boolean => boolean.toString(),
      final Map _ => '<map>',
      final List _ => '<list>',
      _ => '<${value.runtimeType}>',
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
      return _safeLogLabel(value);
    }
    return null;
  }

  static String _safeLogLabel(String value) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    if (normalized.length <= 64) {
      return normalized;
    }
    return '${normalized.substring(0, 64)}…';
  }
}
