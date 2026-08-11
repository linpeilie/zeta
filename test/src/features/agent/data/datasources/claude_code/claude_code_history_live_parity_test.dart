import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_event_mapper.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_session_history_reader.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_stream_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  const scope = AgentRuntimeScope(
    runtimeId: 'claude-history-parity',
    connectionEpoch: 1,
  );
  const fixturePath =
      'test/src/features/agent/data/datasources/claude_code/fixtures/hello_turn.jsonl';

  group('Claude Code history/live parity', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'zeta-claude-history-parity-',
      );
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test(
      'same fixture yields positionally equal canonical signatures',
      () async {
        final liveFrames = _loadFixture(fixturePath);
        final init = liveFrames.first;
        final sessionId = init['session_id']! as String;
        const turnId = 'turn-hello';
        final liveIdentity = ClaudeCodeStreamIdentity();
        final liveMapper = ClaudeCodeEventMapper(
          providerId: 'claude-code',
          identity: liveIdentity,
        );
        addTearDown(liveMapper.dispose);
        liveMapper.beginTurn(
          runtimeScope: scope,
          sessionId: sessionId,
          turnId: turnId,
        );

        final liveEvents = <AgentEvent>[];
        for (final frame in liveFrames) {
          liveEvents.addAll(
            liveMapper
                .mapFrame(
                  raw: frame,
                  runtimeScope: scope,
                  runningTurnId: turnId,
                )
                .events,
          );
          if (frame['type'] == 'system' && frame['subtype'] == 'init') {
            liveEvents.add(
              AgentTurnStartedEvent(
                AgentTurn(id: turnId, sessionId: sessionId),
              ),
            );
          }
        }
        final liveSnapshotBeforeHistory = liveIdentity.snapshot(
          runtimeScope: scope,
          sessionId: sessionId,
          turnId: turnId,
        );

        const projectPath = '/tmp/zeta-cc-fixture';
        final historyFile = await _writeHistoryFixture(
          tempRoot: tempRoot,
          projectPath: projectPath,
          sessionId: sessionId,
          liveFrames: liveFrames,
        );
        late ClaudeCodeStreamIdentity historyIdentity;
        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
          historyIdentityFactory: () {
            historyIdentity = ClaudeCodeStreamIdentity();
            return historyIdentity;
          },
          historyTurnIdFactory: (_, _, _) => turnId,
        );

        final history = await reader.readHistoryEvents(
          threadId: sessionId,
          providerId: 'claude-code',
          projectPath: projectPath,
          sessionPath: historyFile.path,
          runtimeScope: scope,
        );

        final historyProviderEvents = history.events.where(
          (event) =>
              event is! AgentMessageUpdatedEvent ||
              event.role != AgentMessageRole.user,
        );
        expect(
          historyProviderEvents.map(_canonicalSignature).toList(),
          liveEvents.map(_canonicalSignature).toList(),
        );
        expect(identical(historyIdentity, liveIdentity), isFalse);
        expect(
          liveIdentity
              .snapshot(
                runtimeScope: scope,
                sessionId: sessionId,
                turnId: turnId,
              )
              .toString(),
          liveSnapshotBeforeHistory.toString(),
        );
        expect(
          history.identitySnapshots[turnId].toString(),
          liveSnapshotBeforeHistory.toString(),
        );
        expect(history.snapshot.turns, hasLength(1));
        expect(
          history.snapshot.turns.single.status,
          AgentHistoryTurnStatus.completed,
        );
      },
    );

    test(
      'synthesizes terminal and aggregates usage for disk history',
      () async {
        const projectPath = '/workspace/history';
        const sessionId = 'history-session-redacted';
        final projectDirectory = Directory(
          '${tempRoot.path}${Platform.pathSeparator}projects'
          '${Platform.pathSeparator}'
          '${ClaudeCodeSessionHistoryReader.encodeProjectPath(projectPath)}',
        );
        await projectDirectory.create(recursive: true);
        final historyFile = File(
          '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
        );
        final frames = <Map<String, Object?>>[
          <String, Object?>{
            'type': 'user',
            'sessionId': sessionId,
            'uuid': 'history-user-1',
            'timestamp': '2026-08-10T01:00:00.000Z',
            'cwd': projectPath,
            'message': <String, Object?>{
              'role': 'user',
              'content': 'Inspect the history path',
            },
          },
          <String, Object?>{
            'type': 'assistant',
            'sessionId': sessionId,
            'uuid': 'history-assistant-tool',
            'timestamp': '2026-08-10T01:00:01.000Z',
            'message': <String, Object?>{
              'id': 'history-message-tool',
              'role': 'assistant',
              'model': 'claude-test-model',
              'stop_reason': 'tool_use',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'tool_use',
                  'id': 'history-tool-1',
                  'name': 'Read',
                  'input': <String, Object?>{'file_path': '[PATH_REDACTED]'},
                },
              ],
              'usage': <String, Object?>{'input_tokens': 5, 'output_tokens': 2},
            },
          },
          <String, Object?>{
            'type': 'user',
            'sessionId': sessionId,
            'uuid': 'history-tool-result',
            'timestamp': '2026-08-10T01:00:02.000Z',
            'message': <String, Object?>{
              'role': 'user',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'tool_result',
                  'tool_use_id': 'history-tool-1',
                  'content': '[TOOL_OUTPUT_REDACTED]',
                },
              ],
            },
          },
          <String, Object?>{
            'type': 'assistant',
            'sessionId': sessionId,
            'uuid': 'history-assistant-final',
            'timestamp': '2026-08-10T01:00:03.000Z',
            'message': <String, Object?>{
              'id': 'history-message-final',
              'role': 'assistant',
              'model': 'claude-test-model',
              'stop_reason': 'end_turn',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': '[RESPONSE_REDACTED]',
                },
              ],
              'usage': <String, Object?>{
                'input_tokens': 3,
                'output_tokens': 4,
                'cache_read_input_tokens': 7,
              },
            },
          },
        ];
        await historyFile.writeAsString(
          '${frames.map(jsonEncode).join('\n')}\n',
        );

        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
        );
        final snapshot = await reader.readThreadHistory(
          threadId: sessionId,
          providerId: 'claude-code',
          projectPath: projectPath,
          sessionPath: historyFile.path,
        );

        expect(snapshot.turns, hasLength(1));
        final turn = snapshot.turns.single;
        expect(turn.status, AgentHistoryTurnStatus.completed);
        expect(turn.startedAt, DateTime.utc(2026, 8, 10, 1));
        expect(turn.completedAt, DateTime.utc(2026, 8, 10, 1, 0, 3));
        expect(turn.duration, const Duration(seconds: 3));
        expect(turn.cwd, projectPath);
        expect(turn.model, 'claude-test-model');
        expect(turn.tokenUsageIsSessionCumulative, isFalse);
        expect(turn.tokenUsage?.inputTokens, 8);
        expect(turn.tokenUsage?.outputTokens, 6);
        expect(turn.tokenUsage?.cachedInputTokens, 7);
        expect(
          turn.entries.whereType<AgentHistoryMessageEntry>(),
          hasLength(2),
        );
        expect(turn.entries.whereType<AgentHistoryToolEntry>(), hasLength(1));
        final tool = turn.entries
            .whereType<AgentHistoryToolEntry>()
            .single
            .toolCall;
        expect(tool.title, 'Read');
        expect(tool.kind, AgentToolKind.read);
        expect(tool.status, AgentToolStatus.completed);
      },
    );
  });
}

List<Map<String, Object?>> _loadFixture(String path) {
  final frames = <Map<String, Object?>>[];
  for (final line in File(path).readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final decoded = jsonDecode(trimmed) as Map;
    frames.add(
      decoded.map((key, value) => MapEntry(key.toString(), value as Object?)),
    );
  }
  return frames;
}

Future<File> _writeHistoryFixture({
  required Directory tempRoot,
  required String projectPath,
  required String sessionId,
  required List<Map<String, Object?>> liveFrames,
}) async {
  final projectDirectory = Directory(
    '${tempRoot.path}${Platform.pathSeparator}projects'
    '${Platform.pathSeparator}'
    '${ClaudeCodeSessionHistoryReader.encodeProjectPath(projectPath)}',
  );
  await projectDirectory.create(recursive: true);
  final file = File(
    '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
  );
  final historyFrames = <Map<String, Object?>>[
    <String, Object?>{
      'type': 'user',
      'sessionId': sessionId,
      'uuid': 'history-user-parity',
      'timestamp': '2026-08-10T01:00:00.000Z',
      'cwd': projectPath,
      'message': <String, Object?>{
        'role': 'user',
        'content': '[USER_TEXT_REDACTED]',
      },
    },
    for (final frame in liveFrames)
      if (frame['type'] != 'system')
        <String, Object?>{
          ...frame,
          'sessionId': sessionId,
          'timestamp': frame['type'] == 'result'
              ? '2026-08-10T01:00:02.000Z'
              : '2026-08-10T01:00:01.000Z',
        }..remove('session_id'),
  ];
  await file.writeAsString('${historyFrames.map(jsonEncode).join('\n')}\n');
  return file;
}

String _canonicalSignature(AgentEvent event) {
  return switch (event) {
    AgentSessionStartedEvent(:final session) =>
      'AgentSessionStartedEvent|session=${session.id}',
    AgentThreadStatusChangedEvent(:final threadId, :final status) =>
      'AgentThreadStatusChangedEvent|thread=$threadId|status=${status.name}',
    AgentTurnStartedEvent(:final turn) =>
      'AgentTurnStartedEvent|turn=${turn.id}',
    AgentMessageUpdatedEvent(:final messageId, :final status, :final role) =>
      'AgentMessageUpdatedEvent|entry=$messageId|status=${status?.name ?? '-'}|role=${role?.name ?? '-'}',
    AgentReasoningDeltaEvent(:final itemId, :final kind) =>
      'AgentReasoningDeltaEvent|entry=$itemId|kind=${kind.name}',
    AgentToolCallEvent(:final toolCall) =>
      'AgentToolCallEvent|id=${toolCall.id}|status=${toolCall.status.name}|kind=${toolCall.kind.name}',
    AgentTokenUsageEvent(:final turnId, :final isSessionCumulative) =>
      'AgentTokenUsageEvent|turn=${turnId ?? '-'}|cumulative=$isSessionCumulative',
    AgentTurnCompletedEvent(:final turnId, :final status) =>
      'AgentTurnCompletedEvent|turn=$turnId|status=${status.name}',
    _ => 'UnknownEvent|${event.runtimeType}',
  };
}
