import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

void main() {
  group('AgentIgnoredMessageLogger', () {
    final events = <LogEvent>[];
    late Directory logDirectory;
    late OutputCallback outputListener;

    setUp(() async {
      events.clear();
      await resetAppLoggingForTesting();
      outputListener = (event) => events.add(event.origin);
      Logger.addOutputListener(outputListener);
      Logger.level = Level.all;
      logDirectory = await Directory.systemTemp.createTemp(
        'zeta-ignored-message-logger-test-',
      );
      configureAppLogging(logDirectory: logDirectory);
    });

    tearDown(() async {
      Logger.removeOutputListener(outputListener);
      await resetAppLoggingForTesting();
      if (await logDirectory.exists()) {
        await logDirectory.delete(recursive: true);
      }
    });

    test('logs only whitelisted shape data in memory and on disk', () async {
      const privatePatch = 'PRIVATE_PATCH_SENTINEL';
      const privatePath = 'PRIVATE_PATH_SENTINEL';
      const privateDetail = 'PRIVATE_DETAIL_SENTINEL';
      const privateRaw = 'PRIVATE_RAW_SENTINEL';
      const privateLabel = 'PRIVATE_LABEL_SENTINEL';
      final ignored = AgentIgnoredMessageLogger(
        providerLabel: 'Test',
        loggerName: 'zeta.test.ignored',
      );

      ignored.record(
        method: 'future/method',
        reason: 'unsupported notification method',
        payload: <String, Object?>{
          'threadId': 'private-thread-id',
          'item': <String, Object?>{
            'id': 'private-item-id',
            'type': 'fileChange',
            'changes': <Object?>[
              <String, Object?>{'path': privatePath, 'diff': privatePatch},
            ],
          },
        },
        rawPayload: <String, Object?>{'raw': privateRaw},
        details: const <String, Object?>{
          'updateKind': 'file_change',
          'privateDetail': privateDetail,
        },
        unmatched: true,
      );
      ignored.record(
        method: 'future/method\n$privateLabel',
        reason: 'invalid reason\n$privateLabel',
        payload: const <String, Object?>{'type': 'invalid\n$privateLabel'},
        details: const <String, Object?>{
          'updateKind': 'invalid\n$privateLabel',
        },
      );

      await flushAppLogging();

      final renderedMemory = events.map((event) => event.message).join('\n');
      expect(renderedMemory, contains('Ignoring unmatched Test notification'));
      expect(renderedMemory, contains('future/method'));
      expect(
        renderedMemory,
        contains('reason=unsupported notification method'),
      );
      expect(renderedMemory, contains('count=1'));
      expect(renderedMemory, contains('threadId=present'));
      expect(renderedMemory, contains('itemId=present'));
      expect(renderedMemory, contains('itemType=fileChange'));
      expect(renderedMemory, contains('updateKind=file_change'));
      expect(renderedMemory, contains('<invalid>'));
      expect(renderedMemory, isNot(contains('raw=')));
      expect(renderedMemory, isNot(contains('privateDetail')));

      final logFile = await logDirectory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .single;
      final renderedDisk = await logFile.readAsString();
      for (final sentinel in const <String>[
        privatePatch,
        privatePath,
        privateDetail,
        privateRaw,
        privateLabel,
        'private-thread-id',
        'private-item-id',
      ]) {
        expect(renderedMemory, isNot(contains(sentinel)));
        expect(renderedDisk, isNot(contains(sentinel)));
      }
      expect(renderedDisk, isNot(contains('raw=')));
      expect(ignored.ignoredCounts, <String, int>{
        'future/method|unsupported notification method': 1,
        'future/method\n$privateLabel|invalid reason\n$privateLabel': 1,
      });
      expect(ignored.unmatchedCounts, <String, int>{'future/method': 1});
    });
  });
}
