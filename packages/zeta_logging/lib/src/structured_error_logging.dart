import 'dart:convert';
import 'dart:math' as math;

import 'package:zeta_logging/src/app_logging.dart';
import 'package:zeta_logging/src/sensitive_data_redactor.dart';

/// Optional structured diagnostic data exposed by a failure.
abstract interface class StructuredLogDiagnostic {
  /// Presentation-neutral, non-secret diagnostic values.
  Object? get logDiagnostic;
}

/// Writes a failure with recursively sanitized structured context.
void logStructuredFailure(
  AppLogger logger, {
  required String message,
  Map<String, Object?> context = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  final exceptionContext = error == null
      ? null
      : <String, Object?>{
          'category': error is Error ? 'error' : 'exception',
          if (error is StructuredLogDiagnostic)
            'diagnostic': error.logDiagnostic,
        };
  final encoded = encodeStructuredLogContext(<String, Object?>{
    ...context,
    'exception': ?exceptionContext,
  });
  logger.w('$message: $encoded', error: error, stackTrace: stackTrace);
}

/// Recursively sanitizes [context] and encodes it as single-line JSON.
String encodeStructuredLogContext(Map<String, Object?> context) {
  final sanitized = _sanitizeStructuredLogValue(context);
  final encoded = jsonEncode(sanitized);
  if (encoded.length <= _maxStructuredLogContextLength) {
    return encoded;
  }
  final previewLength = math.min(
    encoded.length,
    _maxStructuredLogContextLength ~/ 2,
  );
  return jsonEncode(<String, Object?>{
    'truncated': true,
    'originalLength': encoded.length,
    'preview': encoded.substring(0, previewLength),
  });
}

const _maxStructuredLogContextLength = 12000;

Object? _sanitizeStructuredLogValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        _safeStructuredLogKey(entry.key):
            _isSensitiveLogKey(
              entry.key.toString(),
            )
            ? '••••••'
            : _sanitizeStructuredLogValue(entry.value),
    };
  }
  if (value is Iterable) {
    return <Object?>[
      for (final item in value) _sanitizeStructuredLogValue(item),
    ];
  }
  if (value == null || value is num || value is bool) {
    return value;
  }
  return redactSensitiveText(value.toString());
}

String _safeStructuredLogKey(Object? key) {
  final value = key?.toString() ?? '';
  return RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,63}$').hasMatch(value)
      ? value
      : 'invalidField';
}

bool _isSensitiveLogKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return normalized == 'authorization' ||
      normalized == 'proxyauthorization' ||
      normalized.endsWith('apikey') ||
      normalized.endsWith('token') ||
      normalized.endsWith('secret') ||
      normalized.endsWith('password') ||
      normalized.endsWith('privatekey') ||
      const <String>{
        'prompt',
        'content',
        'providercontent',
        'input',
        'output',
        'body',
        'payload',
        'raw',
      }.contains(normalized);
}
