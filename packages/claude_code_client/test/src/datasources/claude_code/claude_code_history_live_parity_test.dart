import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_event_mapper.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_session_history_reader.dart';
import 'package:claude_code_client/src/mappers/claude_code_stream_identity.dart';
import 'package:test/test.dart';

import '../../../testing/agent_file_change_canonical.dart';

void main() {
  const scope = AgentRuntimeScope(
    runtimeId: 'claude-history-parity',
    connectionEpoch: 1,
  );
  const fixturePath =
      'test/src/datasources/claude_code/fixtures/hello_turn.jsonl';

  group('Claude Code history/live parity', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'zeta-claude-history-parity-',
      );
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
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
            return historyIdentity = ClaudeCodeStreamIdentity();
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
        expect(turn.modelId, 'claude-test-model');
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

    test('Edit and Write typed evidence match isolated live/history', () async {
      // Arrange
      final fixture = _jsonObject(
        'test/fixtures/agent_file_change_evidence/'
        'claude_code_edit_write_2_1_227.json',
      );
      final scenarios = (fixture['scenarios']! as List<Object?>)
          .map(_mapObject)
          .toList(growable: false);

      for (final scenario in scenarios) {
        final name = scenario['name']! as String;
        final frames = (scenario['frames']! as List<Object?>)
            .map(_mapObject)
            .toList(growable: false);
        final sessionId = frames.first['session_id']! as String;
        final turnId = 'turn-file-$name';
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

        // Act: live 与 history 使用不同 mapper/tracker 实例。
        final liveEvents = <AgentEvent>[];
        for (final frame in frames) {
          liveEvents.addAll(
            liveMapper
                .mapFrame(
                  raw: frame,
                  runtimeScope: scope,
                  runningTurnId: turnId,
                )
                .events,
          );
        }
        final historyFile = await _writeHistoryFixture(
          tempRoot: tempRoot,
          projectPath: '/tmp/zeta-cc-file-$name',
          sessionId: sessionId,
          liveFrames: frames,
        );
        final historyIdentities = <ClaudeCodeStreamIdentity>[];
        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
          historyIdentityFactory: () {
            final identity = ClaudeCodeStreamIdentity();
            historyIdentities.add(identity);
            return identity;
          },
          historyTurnIdFactory: (_, _, _) => turnId,
        );
        final history = await reader.readHistoryEvents(
          threadId: sessionId,
          providerId: 'claude-code',
          projectPath: '/tmp/zeta-cc-file-$name',
          sessionPath: historyFile.path,
          runtimeScope: scope,
        );
        final replay = await reader.readHistoryEvents(
          threadId: sessionId,
          providerId: 'claude-code',
          projectPath: '/tmp/zeta-cc-file-$name',
          sessionPath: historyFile.path,
          runtimeScope: scope,
        );

        // Assert
        final liveTool = liveEvents
            .whereType<AgentToolCallEvent>()
            .last
            .toolCall;
        final historyTool = history.events
            .whereType<AgentToolCallEvent>()
            .last
            .toolCall;
        final replayTool = replay.events
            .whereType<AgentToolCallEvent>()
            .last
            .toolCall;
        expect(historyTool.title, liveTool.title, reason: name);
        expect(historyTool.kind, liveTool.kind, reason: name);
        expect(historyTool.status, liveTool.status, reason: name);
        expect(historyTool.locations, liveTool.locations, reason: name);
        final liveEnvelope = canonicalFileChangeToolCall(liveTool);
        expect(
          canonicalFileChangeToolCall(historyTool).signature,
          liveEnvelope.signature,
          reason: name,
        );
        expect(
          canonicalFileChangeToolCall(replayTool).signature,
          liveEnvelope.signature,
          reason: name,
        );
        expect(historyIdentities, hasLength(2), reason: name);
        expect(
          identical(historyIdentities[0], liveIdentity),
          isFalse,
          reason: name,
        );
        expect(
          identical(historyIdentities[0], historyIdentities[1]),
          isFalse,
          reason: name,
        );
        expect(
          identical(liveTool.fileChanges, historyTool.fileChanges),
          isFalse,
          reason: name,
        );
        expect(
          identical(historyTool.fileChanges, replayTool.fileChanges),
          isFalse,
          reason: name,
        );
      }
    });
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
    AgentMessageDeltaEvent(:final messageId, :final status, :final role) =>
      'AgentMessageDeltaEvent|entry=$messageId|'
          'status=${status?.name ?? '-'}|role=${role.name}',
    AgentMessageUpdatedEvent(:final messageId, :final status, :final role) =>
      'AgentMessageUpdatedEvent|entry=$messageId|'
          'status=${status?.name ?? '-'}|role=${role?.name ?? '-'}',
    AgentReasoningDeltaEvent(:final itemId, :final kind) =>
      'AgentReasoningDeltaEvent|entry=$itemId|kind=${kind.name}',
    AgentToolCallEvent(:final toolCall) =>
      'AgentToolCallEvent|id=${toolCall.id}|'
          'status=${toolCall.status.name}|kind=${toolCall.kind.name}',
    AgentTokenUsageEvent(:final turnId, :final isSessionCumulative) =>
      'AgentTokenUsageEvent|turn=${turnId ?? '-'}|'
          'cumulative=$isSessionCumulative',
    AgentTurnCompletedEvent(:final turnId, :final status) =>
      'AgentTurnCompletedEvent|turn=$turnId|status=${status.name}',
    _ => 'UnknownEvent|${event.runtimeType}',
  };
}

Map<String, Object?> _jsonObject(String path) =>
    _mapObject(jsonDecode(File(path).readAsStringSync()));

Map<String, Object?> _mapObject(Object? value) => (value! as Map).map(
  (key, item) => MapEntry(key.toString(), item as Object?),
);
