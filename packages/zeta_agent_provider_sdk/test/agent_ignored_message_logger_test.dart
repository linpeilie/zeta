import 'dart:io';

import 'package:test/test.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

void main() {
  group('AgentIgnoredMessageLogger', () {
    final events = <_RecordedLog>[];
    late Directory logDirectory;

    setUp(() async {
      events.clear();
      logDirectory = await Directory.systemTemp.createTemp(
        'zeta-ignored-message-logger-test-',
      );
      ZetaLogging.install(
        (_) => _FileRecordingLogger(
          events,
          File('${logDirectory.path}/provider.log'),
        ),
      );
    });

    tearDown(() async {
      ZetaLogging.reset();
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

      await Future<void>.value();

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

final class _RecordedLog {
  const _RecordedLog(this.message);

  final String message;
}

final class _FileRecordingLogger implements ZetaLogger {
  const _FileRecordingLogger(this.events, this.file);

  final List<_RecordedLog> events;
  final File file;

  void _record(String message) {
    events.add(_RecordedLog(message));
    file.writeAsStringSync('$message\n', mode: FileMode.append, flush: true);
  }

  @override
  void t(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void d(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void i(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void w(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void failure(
    String message, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) => _record(message);
}
