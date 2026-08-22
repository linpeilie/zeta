import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:logger/logger.dart' as logger;
import 'package:zeta/src/core/logging/app_logging.dart';

void main() {
  group('app logging', () {
    final events = <LogEvent>[];
    late Directory logDirectory;
    late OutputCallback outputListener;

    setUp(() async {
      events.clear();
      await resetAppLoggingForTesting();
      outputListener = (event) => events.add(event.origin);
      Logger.addOutputListener(outputListener);
      logDirectory = await Directory.systemTemp.createTemp(
        'zeta-app-logging-test-',
      );
    });

    tearDown(() async {
      Logger.removeOutputListener(outputListener);
      await resetAppLoggingForTesting();
      if (await logDirectory.exists()) {
        await logDirectory.delete(recursive: true);
      }
    });

    test('forwards log events to the configured listener', () async {
      configureAppLogging();
      Logger.level = Level.all;

      loggerFor('zeta.test').i('hello logger');
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.level, Level.info);
      expect(events.single.message, '[zeta] [zeta.test] hello logger');
    });

    test('no file is written when logDirectory is omitted', () async {
      configureAppLogging();

      loggerFor('zeta.test').i('console only');
      await resetAppLoggingForTesting();

      expect(events, hasLength(1));
      expect(await logDirectory.list().isEmpty, isTrue);
    });

    test('filters events below the configured level', () async {
      configureAppLogging();
      Logger.level = Level.warning;

      final logger = loggerFor('zeta.test');
      logger.i('hidden');
      logger.w('visible');
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.message, '[zeta] [zeta.test] visible');
    });

    test('reconfiguration does not duplicate events', () async {
      configureAppLogging();
      configureAppLogging();

      loggerFor('zeta.test').i('once');
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
    });

    test('appends records to the local-date daily log file', () async {
      final nestedLogDirectory = Directory(
        '${logDirectory.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}logs',
      );
      final before = DateTime.now().toLocal();
      configureAppLogging(logDirectory: nestedLogDirectory);

      loggerFor('zeta.test').i('first record');
      loggerFor('zeta.test').w('second record');
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
        firstRun.trim().split('\n'),
        everyElement(
          matches(
            RegExp(
              r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} '
              r'\[(info|warning)\] \[zeta\] \[zeta\.test\] ',
            ),
          ),
        ),
      );
      expect(firstRun, contains('[zeta] [zeta.test] first record'));
      expect(firstRun, isNot(contains('[zeta] [zeta]')));
      expect(
        firstRun.indexOf('first record'),
        lessThan(firstRun.indexOf('second record')),
      );

      configureAppLogging(logDirectory: nestedLogDirectory);
      loggerFor('zeta.test').i('third record');
      await resetAppLoggingForTesting();

      final secondRun = await files.single.readAsString();
      expect(secondRun, contains('first record'));
      expect(secondRun, contains('third record'));
      expect(secondRun.length, greaterThan(firstRun.length));
    });

    test('控制台渲染与文件输出走同一条脱敏链路', () {
      final home =
          Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
      expect(home, isNotNull);

      final rendered = ZetaConsolePrinter()
          .log(
            logger.LogEvent(
              logger.Level.warning,
              'token=message-secret path=$home/project\n'
              'Authorization: Basic dXNlcjpwYXNz',
              error: StateError('password=error-secret'),
            ),
          )
          .join('\n');

      // 控制台曾经直接打 `ERROR: ${event.error}`，把原始异常文本原样泄露。
      expect(rendered, isNot(contains('message-secret')));
      expect(rendered, isNot(contains('error-secret')));
      expect(rendered, isNot(contains('dXNlcjpwYXNz')));
      expect(rendered, contains('token=••••••'));
      expect(rendered, contains('Authorization: ••••••'));
      expect(rendered, contains('path=~/project'));
      // 异常类型仍要看得见，否则控制台失去诊断价值。
      expect(rendered, contains('StateError'));
    });

    test('redacts file messages and stores only the error type', () async {
      final home =
          Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
      expect(home, isNotNull);
      expect(home, isNotEmpty);
      configureAppLogging(logDirectory: logDirectory);

      loggerFor('zeta.test').w(
        'Authorization: Basic dXNlcjpwYXNz\n'
        'Proxy-Authorization: Bearer abc.def.ghi\n'
        'authorization=Basic c2Vjb25kLXNlY3JldA==\n'
        'token=message-secret path=$home/project',
        error: StateError('password=error-secret'),
        stackTrace: StackTrace.fromString(
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
      expect(content, isNot(contains('\x1B[')));
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
