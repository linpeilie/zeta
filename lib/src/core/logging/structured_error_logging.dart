import 'dart:convert';
import 'dart:math' as math;

import 'package:logging/logging.dart';

import 'package:zeta/src/core/security/sensitive_data_redactor.dart';

/// 异常可实现此接口，为通用结构化日志补充协议诊断字段。
abstract interface class StructuredLogDiagnostic {
  Object? get logDiagnostic;
}

/// 写入带结构化、脱敏上下文的异常日志。
///
/// 调用方只应传身份、状态和协议诊断，不应传用户输入正文。敏感键和文本会在
/// 进入结构化消息前完成遮挡；原始异常仍作为 [LogRecord.error] 交给诊断 sink，
/// 应用文件日志只持久化其类型。
void logStructuredFailure(
  Logger logger, {
  required String message,
  Map<String, Object?> context = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  final exceptionContext = error == null
      ? null
      : <String, Object?>{
          'type': error.runtimeType.toString(),
          'message': error.toString(),
          if (error is StructuredLogDiagnostic)
            'diagnostic': error.logDiagnostic,
        };
  final encoded = encodeStructuredLogContext(<String, Object?>{
    ...context,
    'exception': ?exceptionContext,
  });
  logger.warning('$message: $encoded', error, stackTrace);
}

/// 将日志上下文递归脱敏并编码为单行 JSON。
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
        entry.key.toString(): _isSensitiveLogKey(entry.key.toString())
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

bool _isSensitiveLogKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return normalized == 'authorization' ||
      normalized == 'proxyauthorization' ||
      normalized.endsWith('apikey') ||
      normalized.endsWith('token') ||
      normalized.endsWith('secret') ||
      normalized.endsWith('password') ||
      normalized.endsWith('privatekey');
}
