import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  group(AgentIgnoredMessageLogger, () {
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

    test('logs only whitelisted shape data and freezes counters', () async {
      const privateSentinel = 'PRIVATE_PROVIDER_CONTENT';
      final subject =
          AgentIgnoredMessageLogger(
            providerLabel: 'Codex',
            loggerName: 'zeta.ignored',
            enabled: true,
          )..record(
            method: 'future/method',
            reason: 'unsupported notification',
            payload: <String, Object?>{
              'threadId': 'private-thread',
              'sessionId': '',
              'turnId': 'private-turn',
              'thread': <String, Object?>{'name': privateSentinel},
              'item': <String, Object?>{
                'id': 'private-item',
                'type': 'fileChange',
                'content': privateSentinel,
              },
            },
            rawPayload: const <String, Object?>{'raw': privateSentinel},
            details: const <String, Object?>{
              'updateKind': 'file_change',
              'errorKind': 2,
              'private': privateSentinel,
            },
            unmatched: true,
          );
      await Future<void>.delayed(Duration.zero);

      final rendered = events.single.message as String;
      expect(rendered, contains('Ignoring unmatched Codex notification'));
      expect(rendered, contains('threadId=present'));
      expect(rendered, contains('thread=present'));
      expect(rendered, contains('sessionId=missing'));
      expect(rendered, contains('turnId=present'));
      expect(rendered, contains('itemId=present'));
      expect(rendered, contains('itemType=fileChange'));
      expect(rendered, contains('updateKind=file_change'));
      expect(rendered, contains('errorKind=2'));
      expect(rendered, isNot(contains(privateSentinel)));
      expect(subject.ignoredCounts, <String, int>{
        'future/method|unsupported notification': 1,
      });
      expect(subject.unmatchedCounts, <String, int>{'future/method': 1});
      expect(() => subject.ignoredCounts.clear(), throwsUnsupportedError);
      expect(() => subject.unmatchedCounts.clear(), throwsUnsupportedError);
      await subject.close();
    });

    test('sanitizes invalid labels, reasons, and detail value kinds', () async {
      AgentIgnoredMessageLogger(
          providerLabel: 'bad\nprovider',
          loggerName: 'zeta.ignored',
          enabled: true,
        )
        ..record(
          method: 'bad\nmethod',
          reason: 'bad\nreason',
          payload: const <String, Object?>{
            'update': <String, Object?>{'sessionUpdate': 'valid_update'},
          },
          details: const <String, Object?>{
            'updateKind': null,
            'errorKind': <String>[],
          },
        )
        ..record(
          method: 'valid/method',
          reason: 'valid reason',
          payload: const <String, Object?>{'sessionUpdate': 'fallback_update'},
          details: const <String, Object?>{
            'updateKind': true,
            'errorKind': 'kind',
          },
        );
      await Future<void>.delayed(Duration.zero);

      final rendered = events.map((event) => event.message).join('\n');
      expect(rendered, contains('Ignoring <invalid> notification'));
      expect(rendered, contains('reason=<invalid>'));
      expect(rendered, contains('itemType=valid_update'));
      expect(rendered, contains('updateKind=missing'));
      expect(rendered, contains('errorKind=<invalid>'));
      expect(rendered, contains('itemType=fallback_update'));
      expect(rendered, contains('updateKind=true'));
      expect(rendered, contains('errorKind=kind'));
    });

    test('disabled logging still counts sanitized identities', () async {
      final subject =
          AgentIgnoredMessageLogger(
            providerLabel: 'Provider',
            loggerName: 'zeta.ignored',
            enabled: false,
          )..record(
            method: 'bad\nprivate',
            reason: 'bad\nprivate',
            unmatched: true,
          );
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      expect(subject.ignoredCounts, <String, int>{'<invalid>|<invalid>': 1});
      expect(subject.unmatchedCounts, <String, int>{'<invalid>': 1});
    });
  });
}
