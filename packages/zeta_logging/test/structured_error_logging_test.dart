import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  group('structured error logging', () {
    late List<LogEvent> events;
    late OutputCallback listener;

    setUp(() async {
      await resetAppLoggingForTesting();
      events = <LogEvent>[];
      listener = (event) => events.add(event.origin);
      Logger.addOutputListener(listener);
      configureAppLogging(level: Level.all);
    });

    tearDown(() async {
      Logger.removeOutputListener(listener);
      await resetAppLoggingForTesting();
    });

    test('recursively redacts sensitive and provider-authored fields', () {
      final encoded = encodeStructuredLogContext(<String, Object?>{
        'providerId': 'provider-a',
        'accessToken': 'token-secret',
        'prompt': 'private prompt',
        'nested': <String, Object?>{
          'password': 'password-secret',
          'values': <Object?>[1, true, null, 'token=list-secret'],
        },
        'bad key token=key-secret': 'value',
      });
      final context = jsonDecode(encoded) as Map<String, Object?>;

      expect(context['providerId'], 'provider-a');
      expect(context['accessToken'], '••••••');
      expect(context['prompt'], '••••••');
      final nested = context['nested']! as Map<String, Object?>;
      expect(nested['password'], '••••••');
      expect(nested['values'], <Object?>[1, true, null, 'token=••••••']);
      expect(context['invalidField'], '••••••');
      expect(encoded, isNot(contains('private prompt')));
      expect(encoded, isNot(contains('key-secret')));
    });

    test('truncates oversized sanitized contexts', () {
      final encoded = encodeStructuredLogContext(<String, Object?>{
        'safe': 'x' * 13000,
      });
      final context = jsonDecode(encoded) as Map<String, Object?>;

      expect(context['truncated'], isTrue);
      expect(context['originalLength'], greaterThan(12000));
      expect((context['preview']! as String).length, 6000);
    });

    test('logs safe diagnostics without retaining exception text', () async {
      final error = _DiagnosticException();

      logStructuredFailure(
        loggerFor('zeta.provider'),
        message: 'Provider failed',
        context: const <String, Object?>{'operation': 'send'},
        error: error,
        stackTrace: StackTrace.fromString('token=stack-secret'),
      );
      await Future<void>.delayed(Duration.zero);

      final event = events.single;
      const prefix = '[zeta] [zeta.provider] Provider failed: ';
      final context = jsonDecode(
        (event.message as String).substring(prefix.length),
      ) as Map<String, Object?>;
      expect(event.level, Level.warning);
      expect(event.error, 'Exception');
      expect(context['operation'], 'send');
      final exception = context['exception']! as Map<String, Object?>;
      expect(exception['category'], 'exception');
      final diagnostic = exception['diagnostic']! as Map<String, Object?>;
      expect(diagnostic['apiKey'], '••••••');
      expect('${event.message}${event.stackTrace}', isNot(contains('secret')));
    });

    test('supports failures without exception context', () async {
      logStructuredFailure(loggerFor('zeta.provider'), message: 'No error');
      await Future<void>.delayed(Duration.zero);

      expect(events.single.message, contains('{}'));
      expect(events.single.error, isNull);
    });
  });
}

final class _DiagnosticException implements Exception, StructuredLogDiagnostic {
  @override
  Object? get logDiagnostic => const <String, Object?>{
    'apiKey': 'diagnostic-secret',
  };

  @override
  String toString() => 'token=exception-secret';
}
