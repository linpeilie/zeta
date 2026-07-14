import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:zeta/src/core/logging/app_logging.dart';

void main() {
  group('app logging', () {
    final records = <LogRecord>[];
    late Directory logDirectory;

    setUp(() async {
      records.clear();
      await resetAppLoggingForTesting();
      logDirectory = await Directory.systemTemp.createTemp(
        'zeta-app-logging-test-',
      );
    });

    tearDown(() async {
      await resetAppLoggingForTesting();
      if (await logDirectory.exists()) {
        await logDirectory.delete(recursive: true);
      }
    });

    test('forwards log records to the configured sink', () async {
      configureAppLogging(level: Level.ALL, sink: records.add);

      loggerFor('zeta.test').info('hello logger');
      await Future<void>.delayed(Duration.zero);

      expect(records, hasLength(1));
      expect(records.single.loggerName, 'zeta.test');
      expect(records.single.level, Level.INFO);
      expect(records.single.message, 'hello logger');
    });

    test('an explicit sink takes precedence over the file sink', () async {
      configureAppLogging(
        level: Level.ALL,
        sink: records.add,
        logDirectory: logDirectory,
      );

      loggerFor('zeta.test').info('custom sink only');
      await resetAppLoggingForTesting();

      expect(records, hasLength(1));
      expect(await logDirectory.list().isEmpty, isTrue);
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

    test('appends records to the local-date daily log file', () async {
      final nestedLogDirectory = Directory(
        '${logDirectory.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}logs',
      );
      final before = DateTime.now().toLocal();
      configureAppLogging(level: Level.ALL, logDirectory: nestedLogDirectory);

      loggerFor('zeta.test').info('first record');
      loggerFor('zeta.test').warning('second record');
      final after = DateTime.now().toLocal();
      await flushAppLogging();

      final files = await nestedLogDirectory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      expect(<String>{
        _dailyFileName(before),
        _dailyFileName(after),
      }, contains(_fileName(files.single.path)));
      final firstRun = await files.single.readAsString();
      expect(firstRun, contains('first record'));
      expect(firstRun, contains('second record'));
      expect(
        firstRun.indexOf('first record'),
        lessThan(firstRun.indexOf('second record')),
      );

      configureAppLogging(level: Level.ALL, logDirectory: nestedLogDirectory);
      loggerFor('zeta.test').info('third record');
      await resetAppLoggingForTesting();

      final secondRun = await files.single.readAsString();
      expect(secondRun, contains('first record'));
      expect(secondRun, contains('third record'));
      expect(secondRun.length, greaterThan(firstRun.length));
    });

    test('redacts file messages and stores only the error type', () async {
      final home =
          Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
      expect(home, isNotNull);
      expect(home, isNotEmpty);
      configureAppLogging(level: Level.ALL, logDirectory: logDirectory);

      loggerFor('zeta.test').warning(
        'Authorization: Basic dXNlcjpwYXNz\n'
        'Proxy-Authorization: Bearer abc.def.ghi\n'
        'authorization=Basic c2Vjb25kLXNlY3JldA==\n'
        'token=message-secret path=$home/project',
        StateError('password=error-secret'),
        StackTrace.fromString(
          'frame at $home/source.dart:10\napi_key=stack-secret',
        ),
      );
      await resetAppLoggingForTesting();

      final file = await logDirectory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .single;
      final content = await file.readAsString();
      expect(content, contains('Authorization: ••••••'));
      expect(content, contains('Proxy-Authorization: ••••••'));
      expect(content, contains('authorization=••••••'));
      expect(content, contains('token=••••••'));
      expect(content, contains('path=~/project'));
      expect(content, contains('error=StateError'));
      expect(content, contains(r'\n'));
      expect(content, isNot(contains('abc.def.ghi')));
      expect(content, isNot(contains('dXNlcjpwYXNz')));
      expect(content, isNot(contains('c2Vjb25kLXNlY3JldA==')));
      expect(content, isNot(contains('message-secret')));
      expect(content, isNot(contains('error-secret')));
      expect(content, isNot(contains('stack-secret')));
      expect(content, isNot(contains(home!)));
      expect('\n'.allMatches(content), hasLength(1));
    });
  });
}

String _dailyFileName(DateTime localTime) {
  final month = localTime.month.toString().padLeft(2, '0');
  final day = localTime.day.toString().padLeft(2, '0');
  return 'zeta-${localTime.year}-$month-$day.log';
}

String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;
