import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:zeta/src/core/logging/app_logging.dart';

void main() {
  group('app logging', () {
    final records = <LogRecord>[];

    setUp(() async {
      records.clear();
      await resetAppLoggingForTesting();
    });

    tearDown(resetAppLoggingForTesting);

    test('forwards log records to the configured sink', () async {
      configureAppLogging(level: Level.ALL, sink: records.add);

      loggerFor('zeta.test').info('hello logger');
      await Future<void>.delayed(Duration.zero);

      expect(records, hasLength(1));
      expect(records.single.loggerName, 'zeta.test');
      expect(records.single.level, Level.INFO);
      expect(records.single.message, 'hello logger');
    });

    test('filters records below the configured level', () async {
      configureAppLogging(level: Level.WARNING, sink: records.add);
      final logger = loggerFor('zeta.test');

      logger.info('hidden');
      logger.warning('visible');
      await Future<void>.delayed(Duration.zero);

      expect(records, hasLength(1));
      expect(records.single.message, 'visible');
    });

    test('reconfiguration does not duplicate records', () async {
      configureAppLogging(level: Level.ALL, sink: records.add);
      configureAppLogging(level: Level.ALL, sink: records.add);

      loggerFor('zeta.test').info('once');
      await Future<void>.delayed(Duration.zero);

      expect(records, hasLength(1));
    });
  });
}
