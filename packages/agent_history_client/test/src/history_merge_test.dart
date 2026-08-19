import 'dart:io';

import 'package:agent_history_client/agent_history_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('mergeHistoryInputs', () {
    test(
      'merges sources in order and replaces duplicate turns in place',
      () async {
        final result = await mergeHistoryInputs(<HistoryReplayInput>[
          _input(
            sourceId: 'local',
            contents:
                '{"id":"first","status":"running"}\n'
                '{"ignored":true}\n'
                '{"id":"second","status":"completed"}\n',
          ),
          _input(
            sourceId: 'remote',
            contents: '\n{"id":"first","status":"failed"}\n',
          ),
        ]);

        expect(result.turns.map((turn) => turn.id), <String>[
          'first',
          'second',
        ]);
        expect(result.turns.first.status, AgentHistoryTurnStatus.failed);
        expect(result.warnings, isEmpty);
        expect(() => result.turns.add(_turn('third')), throwsUnsupportedError);
        expect(
          () => result.warnings.add(
            const HistoryDecodeWarning(
              sourceId: 'fixture',
              lineNumber: 1,
              kind: HistoryDecodeWarningKind.malformedJson,
            ),
          ),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'skips malformed, non-object, and explicitly rejected records',
      () async {
        final input = HistoryReplayInput(
          sourceId: 'fixture',
          read: () async => 'not-json\n[1,2]\n{"corrupt":true}\n{"id":"ok"}\n',
          decode: (record) {
            if (record['corrupt'] == true) {
              throw const HistoryRecordDecodeException('missing-turn-id');
            }
            return _decodeTurn(record);
          },
        );

        final result = await mergeHistoryInputs(<HistoryReplayInput>[input]);

        expect(result.turns.single.id, 'ok');
        expect(
          result.warnings.map((warning) => warning.kind),
          <HistoryDecodeWarningKind>[
            HistoryDecodeWarningKind.malformedJson,
            HistoryDecodeWarningKind.nonObjectRecord,
            HistoryDecodeWarningKind.rejectedRecord,
          ],
        );
        expect(result.warnings.map((warning) => warning.lineNumber), <int>[
          1,
          2,
          3,
        ]);
        expect(result.warnings.last.sourceId, 'fixture');
        expect(result.warnings.last.decoderCode, 'missing-turn-id');
        expect(
          const HistoryRecordDecodeException('safe-code').toString(),
          'HistoryRecordDecodeException(safe-code)',
        );
      },
    );

    test('propagates whole-input IO failures', () async {
      const failure = FileSystemException(
        'fixture read failure',
        'history.jsonl',
      );
      final input = HistoryReplayInput(
        sourceId: 'io-failure',
        read: () async => throw failure,
        decode: _decodeTurn,
      );

      await expectLater(
        mergeHistoryInputs(<HistoryReplayInput>[input]),
        throwsA(same(failure)),
      );
    });

    test('propagates unexpected decoder failures', () async {
      final failure = StateError('decoder invariant');
      final input = HistoryReplayInput(
        sourceId: 'decoder-failure',
        read: () async => '{"id":"turn"}',
        decode: (_) => throw failure,
      );

      await expectLater(
        mergeHistoryInputs(<HistoryReplayInput>[input]),
        throwsA(same(failure)),
      );
    });

    test('accepts empty input collections and blank files', () async {
      final empty = await mergeHistoryInputs(const <HistoryReplayInput>[]);
      final blank = await mergeHistoryInputs(<HistoryReplayInput>[
        _input(sourceId: 'blank', contents: ' \n\n'),
      ]);

      expect(empty.turns, isEmpty);
      expect(empty.warnings, isEmpty);
      expect(blank.turns, isEmpty);
      expect(blank.warnings, isEmpty);
    });
  });
}

HistoryReplayInput _input({
  required String sourceId,
  required String contents,
}) {
  return HistoryReplayInput(
    sourceId: sourceId,
    read: () async => contents,
    decode: _decodeTurn,
  );
}

AgentHistoryTurn? _decodeTurn(Map<String, Object?> record) {
  final id = record['id'];
  if (id is! String) {
    return null;
  }
  final status = switch (record['status']) {
    'running' => AgentHistoryTurnStatus.running,
    'completed' => AgentHistoryTurnStatus.completed,
    'failed' => AgentHistoryTurnStatus.failed,
    _ => AgentHistoryTurnStatus.unknown,
  };
  return _turn(id, status: status);
}

AgentHistoryTurn _turn(
  String id, {
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.unknown,
}) {
  return AgentHistoryTurn(id: id, status: status);
}
