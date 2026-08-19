import 'package:zeta_logging/src/app_logging.dart';

const _isProductMode = bool.fromEnvironment('dart.vm.product');

/// Counts ignored provider messages and logs only whitelisted shape metadata.
final class AgentIgnoredMessageLogger {
  /// Creates a safe ignored-message logger.
  AgentIgnoredMessageLogger({
    required String providerLabel,
    required String loggerName,
    bool? enabled,
  }) : _providerLabel = _safeProtocolLabel(providerLabel),
       _log = loggerFor(loggerName),
       _enabled = enabled ?? !_isProductMode;

  final String _providerLabel;
  final AppLogger _log;
  final bool _enabled;
  final Map<String, int> _ignoredCounts = <String, int>{};
  final Map<String, int> _unmatchedCounts = <String, int>{};

  /// Ignored counts keyed by sanitized method and reason.
  Map<String, int> get ignoredCounts =>
      Map<String, int>.unmodifiable(_ignoredCounts);

  /// Unmatched counts keyed by sanitized method.
  Map<String, int> get unmatchedCounts =>
      Map<String, int>.unmodifiable(_unmatchedCounts);

  /// Records one ignored message without retaining raw payload values.
  void record({
    required String method,
    required String reason,
    Map<String, Object?> payload = const <String, Object?>{},
    Object? rawPayload,
    Map<String, Object?> details = const <String, Object?>{},
    bool unmatched = false,
  }) {
    final safeMethod = _safeProtocolLabel(method);
    final safeReason = _safeReason(reason);
    final countKey = '$safeMethod|$safeReason';
    final occurrence = (_ignoredCounts[countKey] ?? 0) + 1;
    _ignoredCounts[countKey] = occurrence;
    if (unmatched) {
      _unmatchedCounts[safeMethod] = (_unmatchedCounts[safeMethod] ?? 0) + 1;
    }
    if (!_enabled) {
      return;
    }

    final prefix = unmatched
        ? 'Ignoring unmatched $_providerLabel notification'
        : 'Ignoring $_providerLabel notification';
    final fields = <String, String>{
      'count': occurrence.toString(),
      ..._safePayloadShape(payload),
      ..._safeDetails(details),
    };
    final suffix = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    _log.t('$prefix: $safeMethod (reason=$safeReason; $suffix)');
  }

  /// Closes the owned logger.
  Future<void> close() => _log.close();

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
      if (_safeDetailKeys.contains(entry.key)) {
        safe[entry.key] = _safeDetailValue(entry.value);
      }
    }
    return safe;
  }

  static String _safeDetailValue(Object? value) {
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
      if (value is String && value.trim().isNotEmpty) {
        return _safeProtocolLabel(value);
      }
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

  static const _safeDetailKeys = <String>{'errorKind', 'updateKind'};
  static final _protocolLabelPattern = RegExp(
    r'^[A-Za-z0-9_][A-Za-z0-9._/-]{0,63}$',
  );
  static final _reasonPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9 ._/:()-]{0,95}$',
  );
}
