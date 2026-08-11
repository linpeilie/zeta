import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart'
    show ProcessStarter;
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('ClaudeCodeAgentProvider', () {
    test('hello turn maps init/text/result and usage', () async {
      final process = _FakeClaudeProcess();
      var idSeq = 0;
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        processStarter: _starter(process),
        whichLookup: (command) async => command,
        idFactory: () {
          idSeq += 1;
          return idSeq == 1
              ? '00000000-0000-4000-8000-000000000001'
              : 'turn-hello-1';
        },
      );
      addTearDown(provider.dispose);

      final events = <AgentEvent>[];
      provider.events.listen(events.add);

      await provider.initialize();
      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
      );
      expect(session.id, '00000000-0000-4000-8000-000000000001');

      // Process start should have been observed.
      await pumpEventQueue();
      process.emitInit(sessionId: session.id);
      await pumpEventQueue();

      final turn = await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        message: 'ping',
      );
      expect(turn.id, 'turn-hello-1');

      await pumpEventQueue();
      expect(process.receivedUserTexts, <String>['ping']);

      process.emitAssistantText(
        sessionId: session.id,
        messageId: 'msg_1',
        text: 'pong',
      );
      process.emitResultSuccess(sessionId: session.id);
      await pumpEventQueue(times: 5);

      expect(events.whereType<AgentSessionStartedEvent>(), isNotEmpty);
      expect(events.whereType<AgentTurnStartedEvent>(), hasLength(1));
      expect(events.whereType<AgentMessageUpdatedEvent>(), hasLength(1));
      final usage = events.whereType<AgentTokenUsageEvent>().single;
      expect(usage.isSessionCumulative, isFalse);
      expect(usage.turnId, 'turn-hello-1');
      final completed = events.whereType<AgentTurnCompletedEvent>().single;
      expect(completed.status, AgentHistoryTurnStatus.completed);
      expect(completed.turnId, 'turn-hello-1');
    });

    test(
      'can_use_tool emits permission event then control_response on decide',
      () async {
        final process = _FakeClaudeProcess();
        var idSeq = 0;
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _starter(process),
          whichLookup: (command) async => command,
          idFactory: () {
            idSeq += 1;
            return idSeq == 1 ? 'session-perm-1' : 'turn-perm-1';
          },
        );
        addTearDown(provider.dispose);

        final events = <AgentEvent>[];
        provider.events.listen(events.add);

        await provider.initialize();
        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        await pumpEventQueue();
        process.emitInit(sessionId: session.id);
        await pumpEventQueue();

        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'run tool',
        );
        await pumpEventQueue();

        process.emitControlRequest(requestId: 'req_1', toolName: 'Bash');
        await pumpEventQueue(times: 3);

        // 不立即 deny；等待用户决策。
        expect(provider.controlDeniedCount, 0);
        expect(provider.controlPendingCount, 1);
        expect(process.receivedControlResponses, isEmpty);
        final permission = events
            .whereType<AgentPermissionRequestedEvent>()
            .single;
        expect(permission.request.id, 'req_1');
        expect(permission.request.sessionId, 'session-perm-1');
        expect(permission.request.turnId, 'turn-perm-1');

        await provider.respondToPermission(
          const AgentPermissionDecision(
            requestId: 'req_1',
            approved: true,
            commandDecision: AgentCommandApprovalDecisionKind.accept,
          ),
        );
        await pumpEventQueue(times: 3);

        expect(provider.controlPendingCount, 0);
        expect(process.receivedControlResponses, hasLength(1));
        final response = process.receivedControlResponses.single;
        expect(response['type'], 'control_response');
        expect(response['request_id'], 'req_1');
        final body = response['response'] as Map<String, Object?>;
        expect(body['behavior'], 'allow');
        expect(body['updatedInput'], isA<Map>());
      },
    );

    test('unknown control_request type is still fail-closed denied', () async {
      final process = _FakeClaudeProcess();
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        processStarter: _starter(process),
        whichLookup: (command) async => command,
        idFactory: () => 'id-unknown-ctrl',
      );
      addTearDown(provider.dispose);

      final events = <AgentEvent>[];
      provider.events.listen(events.add);

      await provider.initialize();
      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
      );
      await pumpEventQueue();
      process.emitInit(sessionId: session.id);
      await pumpEventQueue();

      process.emitJson(<String, Object?>{
        'type': 'control_request',
        'request_id': 'req_x',
        'request': <String, Object?>{'type': 'not_a_tool'},
      });
      await pumpEventQueue(times: 3);

      expect(provider.controlDeniedCount, 1);
      expect(events.whereType<AgentPermissionRequestedEvent>(), isEmpty);
      expect(process.receivedControlResponses, hasLength(1));
      final body =
          process.receivedControlResponses.single['response']
              as Map<String, Object?>;
      expect(body['behavior'], 'deny');
    });

    test(
      'idle permission switch restarts peer by resuming same session',
      () async {
        final firstProcess = _FakeClaudeProcess();
        final secondProcess = _FakeClaudeProcess();
        final starts = <_RecordedProcessStart>[];
        final processes = <_FakeClaudeProcess>[firstProcess, secondProcess];
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _queueStarter(processes, starts),
          whichLookup: (command) async => command,
          idFactory: () => 'session-switch-1',
        );
        addTearDown(provider.dispose);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        final result = await provider.permissionPolicy.applyPermissionSelection(
          const AgentPermissionSelection(optionId: ':plan'),
        );

        expect(result.scope, AgentPermissionApplyScope.currentSession);
        expect(starts, hasLength(2));
        expect(
          starts.first.arguments,
          containsAllInOrder(<String>[
            '--session-id',
            session.id,
            '--permission-mode',
            'default',
          ]),
        );
        expect(
          starts.last.arguments,
          containsAllInOrder(<String>[
            '--resume',
            session.id,
            '--permission-mode',
            'plan',
          ]),
        );
      },
    );

    test('permission switch is rejected while a turn is running', () async {
      final process = _FakeClaudeProcess();
      final starts = <_RecordedProcessStart>[];
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        processStarter: _queueStarter(<_FakeClaudeProcess>[process], starts),
        whichLookup: (command) async => command,
        idFactory: _sequenceIds(<String>[
          'session-running-1',
          'turn-running-1',
        ]),
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
      );
      await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        message: 'still running',
      );

      await expectLater(
        provider.permissionPolicy.applyPermissionSelection(
          const AgentPermissionSelection(optionId: ':plan'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(starts, hasLength(1));
    });

    test(
      'allow always is persisted and auto-applied without another event',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'zeta-claude-provider-permission-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final cacheFile = File(
          '${directory.path}${Platform.pathSeparator}session.json',
        );
        final process = _FakeClaudeProcess();
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _starter(process),
          whichLookup: (command) async => command,
          sessionDecisionStoreFactory: (_) =>
              FileClaudeCodeSessionDecisionStore(file: cacheFile),
          idFactory: _sequenceIds(<String>['session-cache-1', 'turn-cache-1']),
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        provider.events.listen(events.add);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'run tools',
        );
        process.emitControlRequest(requestId: 'req_first', toolName: 'Bash');
        await pumpEventQueue(times: 3);
        await provider.respondToPermission(
          const AgentPermissionDecision(
            requestId: 'req_first',
            approved: true,
            commandDecision: AgentCommandApprovalDecisionKind.acceptForSession,
          ),
        );
        process.emitControlRequest(requestId: 'req_second', toolName: 'Bash');
        await pumpEventQueue(times: 5);

        expect(events.whereType<AgentPermissionRequestedEvent>(), hasLength(1));
        expect(provider.controlPendingCount, 0);
        expect(process.receivedControlResponses, hasLength(2));
        expect(
          process.receivedControlResponses.last['request_id'],
          'req_second',
        );
        final source = await cacheFile.readAsString();
        expect(source, contains('"toolName":"Bash"'));
        expect(source, contains('"decision":"allow"'));
        expect(source, isNot(contains('echo hi')));
        expect(source, isNot(contains('input')));
      },
    );

    test('source has no 尚未接入 failure branch', () {
      final source = File(
        'lib/src/features/agent/data/datasources/claude_code/'
        'claude_code_agent_provider.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('尚未接入')));
    });
  });
}

ProcessStarter _starter(_FakeClaudeProcess process) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    process.start();
    return process;
  };
}

ProcessStarter _queueStarter(
  List<_FakeClaudeProcess> processes,
  List<_RecordedProcessStart> starts,
) {
  var index = 0;
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (index >= processes.length) {
      throw StateError('No fake Claude process left');
    }
    starts.add(
      _RecordedProcessStart(
        executable: executable,
        arguments: List<String>.of(arguments),
        workingDirectory: workingDirectory,
      ),
    );
    final process = processes[index++];
    process.start();
    return process;
  };
}

String Function() _sequenceIds(List<String> ids) {
  var index = 0;
  return () {
    if (index >= ids.length) {
      throw StateError('No fake id left');
    }
    return ids[index++];
  };
}

final class _RecordedProcessStart {
  const _RecordedProcessStart({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class _FakeClaudeProcess implements Process {
  final StreamController<List<int>> _stdinBytes = StreamController<List<int>>();
  final StreamController<List<int>> _stdoutBytes =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrBytes =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();

  final List<String> receivedUserTexts = <String>[];
  final List<Map<String, Object?>> receivedControlResponses =
      <Map<String, Object?>>[];

  late final IOSink _stdin = IOSink(_FakeStdinConsumer(_stdinBytes));

  void start() {
    _stdinBytes.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleInputLine, onDone: () => _completeExit(0));
  }

  @override
  int get pid => 99;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdoutBytes.stream;

  @override
  Stream<List<int>> get stderr => _stderrBytes.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _completeExit(0);
    return true;
  }

  void emitInit({required String sessionId}) {
    _writeStdout(<String, Object?>{
      'type': 'system',
      'subtype': 'init',
      'session_id': sessionId,
      'cwd': r'C:\tmp\zeta-cc-test',
      'model': 'claude-haiku-4-5-20251001',
      'permissionMode': 'default',
      'claude_code_version': '2.1.220',
      'uuid': 'uuid-init',
    });
  }

  void emitAssistantText({
    required String sessionId,
    required String messageId,
    required String text,
  }) {
    _writeStdout(<String, Object?>{
      'type': 'assistant',
      'session_id': sessionId,
      'uuid': 'uuid-asst-1',
      'message': <String, Object?>{
        'id': messageId,
        'role': 'assistant',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
      },
    });
  }

  void emitResultSuccess({required String sessionId}) {
    _writeStdout(<String, Object?>{
      'type': 'result',
      'subtype': 'success',
      'session_id': sessionId,
      'uuid': 'uuid-result-1',
      'is_error': false,
      'num_turns': 1,
      'stop_reason': 'end_turn',
      'duration_ms': 100,
      'result': 'pong',
      'usage': <String, Object?>{
        'input_tokens': 10,
        'output_tokens': 4,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 0,
      },
    });
  }

  void emitControlRequest({
    required String requestId,
    required String toolName,
  }) {
    emitJson(<String, Object?>{
      'type': 'control_request',
      'request_id': requestId,
      'request': <String, Object?>{
        'type': 'can_use_tool',
        'tool_name': toolName,
        'input': <String, Object?>{'command': 'echo hi'},
      },
    });
  }

  void emitJson(Map<String, Object?> message) {
    _writeStdout(message);
  }

  void _writeStdout(Map<String, Object?> message) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.add(utf8.encode('${jsonEncode(message)}\n'));
    }
  }

  void _handleInputLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      return;
    }
    final map = <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    if (map['type'] == 'user') {
      final message = map['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is List && content.isNotEmpty) {
          final first = content.first;
          if (first is Map && first['text'] is String) {
            receivedUserTexts.add(first['text'] as String);
          }
        }
      }
    }
    if (map['type'] == 'control_response') {
      receivedControlResponses.add(map);
    }
  }

  void _completeExit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
    unawaited(_closeController(_stdoutBytes));
    unawaited(_closeController(_stderrBytes));
    unawaited(_closeController(_stdinBytes));
  }
}

class _FakeStdinConsumer implements StreamConsumer<List<int>> {
  const _FakeStdinConsumer(this._controller);

  final StreamController<List<int>> _controller;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return stream.listen(_controller.add).asFuture<void>();
  }

  @override
  Future<void> close() async {}
}

Future<void> _closeController(StreamController<List<int>> controller) async {
  if (!controller.isClosed) {
    await controller.close();
  }
}
