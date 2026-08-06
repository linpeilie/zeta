import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/core/logging/structured_error_logging.dart';

void main() {
  test('writes structured diagnostics with recursive redaction', () async {
    final events = <LogEvent>[];
    final listener = events.add;
    Logger.addLogListener(listener);
    addTearDown(() => Logger.removeLogListener(listener));
    final error = _DiagnosticException();
    final stackTrace = StackTrace.current;

    logStructuredFailure(
      loggerFor('zeta.test.provider'),
      message: 'Provider operation failed',
      error: error,
      stackTrace: stackTrace,
      context: const <String, Object?>{
        'providerId': 'provider-a',
        'operation': 'conversation/sendMessage',
        'accessToken': 'context-secret',
        'nested': <String, Object?>{'password': 'nested-secret'},
      },
    );
    await Future<void>.delayed(Duration.zero);

    final record = events.single;
    const prefix = '[zeta] [zeta.test.provider] Provider operation failed: ';
    final context =
        jsonDecode(record.message.substring(prefix.length))
            as Map<String, Object?>;
    expect(record.level, Level.warning);
    expect(record.error, same(error));
    expect(record.stackTrace, same(stackTrace));
    expect(context['providerId'], 'provider-a');
    expect(context['accessToken'], '••••••');
    expect((context['nested']! as Map<String, Object?>)['password'], '••••••');
    final exception = context['exception']! as Map<String, Object?>;
    expect(exception['type'], '_DiagnosticException');
    expect(exception['message'], isNot(contains('exception-secret')));
    final diagnostic = exception['diagnostic']! as Map<String, Object?>;
    final rpc = diagnostic['jsonRpcError']! as Map<String, Object?>;
    expect(rpc['code'], -32003);
    expect(rpc['apiKey'], '••••••');
    expect(record.message, isNot(contains('context-secret')));
    expect(record.message, isNot(contains('nested-secret')));
  });
}

final class _DiagnosticException implements Exception, StructuredLogDiagnostic {
  @override
  Object? get logDiagnostic => const <String, Object?>{
    'jsonRpcError': <String, Object?>{'code': -32003, 'apiKey': 'rpc-secret'},
  };

  @override
  String toString() => 'request failed token=exception-secret';
}
