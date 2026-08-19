import 'dart:io';

import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  group('app logging', () {
    late Directory directory;
    late List<LogEvent> events;
    late OutputCallback listener;

    setUp(() async {
      await resetAppLoggingForTesting();
      directory = await Directory.systemTemp.createTemp('zeta-logging-');
      events = <LogEvent>[];
      listener = (event) => events.add(event.origin);
      Logger.addOutputListener(listener);
      configureAppLogging(level: Level.all);
    });

    tearDown(() async {
      Logger.removeOutputListener(listener);
      await resetAppLoggingForTesting();
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    test(
      'emits every supported level through the sanitized boundary',
      () async {
        loggerFor('zeta.test')
          ..t('trace')
          ..d('debug')
          ..i('info')
          ..w('warning')
          ..e('error')
          ..f('fatal')
          ..log(Level.info, () => 'callback');
        await Future<void>.delayed(Duration.zero);

        expect(events.map((event) => event.level), <Level>[
          Level.trace,
          Level.debug,
          Level.info,
          Level.warning,
          Level.error,
          Level.fatal,
          Level.info,
        ]);
        expect(events.last.message, '[zeta] [zeta.test] callback');
      },
    );

    test(
      'sanitizes message, scope, error, and stack before listeners',
      () async {
        const secret = 'message-secret-value';
        final home =
            Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']!;
        loggerFor('token=scope-secret\nnext').w(
          'Authorization: Bearer abc.def.ghi\n'
          'token=$secret path=$home/project',
          error: StateError('password=error-secret'),
          stackTrace: StackTrace.fromString(
            'frame $home/source.dart token=stack-secret',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final event = events.single;
        final rendered = '${event.message} ${event.error} ${event.stackTrace}';
        expect(event.error, 'Error');
        expect(rendered, contains('token=••••••'));
        expect(rendered, contains('Authorization: ••••••'));
        for (final forbidden in <String>[
          secret,
          'abc.def.ghi',
          'scope-secret',
          'error-secret',
          'stack-secret',
          home,
        ]) {
          expect(rendered, isNot(contains(forbidden)));
        }
      },
    );

    test('uses a safe fallback when a lazy message throws', () async {
      loggerFor('').i(() => throw StateError('token=callback-secret'));
      await Future<void>.delayed(Duration.zero);

      expect(events.single.message, '[zeta] [zeta] <message callback failed>');
    });

    test('filters events below the configured level', () async {
      configureAppLogging(level: Level.warning);
      loggerFor('zeta.test')
        ..i('hidden')
        ..w('visible');
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.message, contains('visible'));
    });

    test('writes escaped and sanitized records to a daily file', () async {
      configureAppLogging(level: Level.all, logDirectory: directory);
      final time = DateTime(2026, 8, 19, 12, 34, 56, 789);

      loggerFor('zeta.test').w(
        'first\ntoken=file-secret',
        time: time,
        error: Exception('password=error-secret'),
        stackTrace: StackTrace.fromString('api_key=stack-secret'),
      );
      loggerFor('zeta.test').i('second', time: time);
      await flushAppLogging();

      final files = directory.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(fileName(files.single.path), 'zeta-2026-08-19.log');
      final content = files.single.readAsStringSync();
      expect(content, contains(r'first\ntoken=••••••'));
      expect(content, contains('error=Exception'));
      expect(content, contains('stack=api_key=••••••'));
      expect(content.indexOf('first'), lessThan(content.indexOf('second')));
      expect(content, isNot(contains('file-secret')));
      expect(content, isNot(contains('error-secret')));
      expect(content, isNot(contains('stack-secret')));
      expect(content, isNot(contains('\x1B[')));
    });

    test('reconfiguration drains the retired file sink', () async {
      final secondDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}second',
      );
      configureAppLogging(level: Level.all, logDirectory: directory);
      loggerFor('zeta.test').i('first');

      configureAppLogging(level: Level.all, logDirectory: secondDirectory);
      loggerFor('zeta.test').i('second');
      await shutdownAppLogging();

      expect(
        directory.listSync().whereType<File>().single.readAsStringSync(),
        contains('first'),
      );
      expect(
        secondDirectory.listSync().whereType<File>().single.readAsStringSync(),
        contains('second'),
      );
    });

    test('swallows file sink failures without recursive logging', () async {
      final blocker = File('${directory.path}${Platform.pathSeparator}blocker')
        ..writeAsStringSync('file');
      configureAppLogging(
        level: Level.all,
        logDirectory: Directory(
          '${blocker.path}${Platform.pathSeparator}logs',
        ),
      );

      loggerFor('zeta.test').w('safe message');
      await flushAppLogging();

      expect(blocker.readAsStringSync(), 'file');
      expect(events, hasLength(1));
    });

    test(
      'logger close is observable and idempotent shutdown is safe',
      () async {
        final subject = loggerFor('zeta.test');

        expect(subject.isClosed, isFalse);
        await subject.close();
        await shutdownAppLogging();
        await shutdownAppLogging();

        expect(subject.isClosed, isTrue);
      },
    );
  });
}

String fileName(String value) => value.replaceAll(r'\', '/').split('/').last;
